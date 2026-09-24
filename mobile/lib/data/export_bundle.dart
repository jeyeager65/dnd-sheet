import 'dart:convert';

import '../domain/rules.dart' as rules;
import '../models/character.dart';
import '../models/homebrew.dart';
import 'homebrew_repository.dart';
import 'sheet_text_repository.dart';

// The character export file:
//
//   {
//     "format": "dnd-sheet-characters",
//     "version": 1,
//     "exportedAt": "2026-09-23T20:15:00.000",
//     "characters": [ ...Character.toJson(), grouped ... ],
//     "homebrew": [ ...every homebrew entry the characters depend on... ],
//     "sheetText": { "<scope>|<feature name>": "<the player's PDF wording>" }
//   }
//
// Rules text the app can look up again (an SRD class feature, species
// trait, or feat) isn't copied into the characters' feature lists; text
// only the file knows (a hand-added feature, an Eldritch Invocation's
// text) is kept.

const exportFormat = 'dnd-sheet-characters';
const exportVersion = 1;

// My Homebrew's own export file (also what assets/official/content.json
// holds - see assets/official/README.md):
//
//   {
//     "format": "dnd-sheet-homebrew",
//     "version": 1,
//     "exportedAt": "...",
//     "homebrew": [ ...HomebrewEntry.toJson()... ]
//   }
const homebrewExportFormat = 'dnd-sheet-homebrew';
const homebrewExportVersion = 1;

/// The My Homebrew export file for [entries], sorted by kind then name.
String buildHomebrewBundle(List<HomebrewEntry> entries) {
  final sorted = [...entries]
    ..sort(
      (a, b) => a.kind != b.kind
          ? a.kind.compareTo(b.kind)
          : a.name.toLowerCase().compareTo(b.name.toLowerCase()),
    );
  return const JsonEncoder.withIndent('  ').convert({
    'format': homebrewExportFormat,
    'version': homebrewExportVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'homebrew': [for (final e in sorted) e.toJson()],
  });
}

/// Reads a My Homebrew export file - throwing a FormatException for
/// anything else.
List<HomebrewEntry> parseHomebrewBundle(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map ||
      decoded['format'] != homebrewExportFormat ||
      decoded['version'] != homebrewExportVersion) {
    throw const FormatException(
      "This isn't a homebrew export from this version of the app.",
    );
  }
  return [
    for (final e in decoded['homebrew'] as List? ?? const [])
      HomebrewEntry.fromJson((e as Map).cast<String, dynamic>()),
  ];
}

/// Builds the export file for [chars]. [allSheetText] includes every
/// sheet-text edit (a full backup) instead of just the ones [chars] use.
String buildExportBundle(List<Character> chars, {bool allSheetText = false}) {
  final homebrew = homebrewDependenciesOf(chars);
  final sheetText = allSheetText
      ? {...sheetTextRepo.overrides}
      : {
          for (final c in chars)
            for (final f in [
              ...c.features,
              ...c.feats,
              ...rules.speciesTraitFeatures(c),
            ])
              rules.sheetTextKey(c, f):
                  ?sheetTextRepo[rules.sheetTextKey(c, f)],
        };
  return const JsonEncoder.withIndent('  ').convert({
    'format': exportFormat,
    'version': exportVersion,
    'exportedAt': DateTime.now().toIso8601String(),
    'characters': [for (final c in chars) _exportCharacter(c)],
    'homebrew': [for (final e in homebrew) e.toJson()],
    'sheetText': sheetText,
  });
}

/// [c]'s JSON with the rules text of catalog-resolvable features and feats
/// dropped - the importing app reads it from the SRD (or the bundled
/// homebrew) itself.
Map<String, dynamic> _exportCharacter(Character c) {
  final json = c.toJson();
  List<dynamic> slim(List<GrantedFeature> features) => [
    for (final f in features)
      {...f.toJson(), if (_textIsLookedUp(c, f)) 'desc': null},
  ];
  json['features'] = slim(c.features);
  json['feats'] = slim(c.feats);
  return json;
}

bool _textIsLookedUp(Character c, GrantedFeature f) {
  final scope = rules.sheetTextScope(c, f);
  return scope != 'custom' && !scope.startsWith('option:');
}

/// Every homebrew entry [chars] depend on, followed transitively (a
/// homebrew subclass's homebrew parent class; the spells a homebrew feat,
/// species, or class grants): their species, class, subclass, background,
/// feats, spells, weapons, armor, carried items, tools, and languages.
List<HomebrewEntry> homebrewDependenciesOf(List<Character> chars) {
  final byId = {for (final e in homebrewRepo.entries) e.id: e};
  final byName = <(String, String), HomebrewEntry>{
    for (final e in homebrewRepo.entries) (e.kind, e.name.toLowerCase()): e,
  };
  final found = <String, HomebrewEntry>{};
  void addId(String? id) {
    final e = id == null ? null : byId[id];
    if (e != null) found[e.id] = e;
  }

  void addName(String kind, String? name) {
    final e = name == null ? null : byName[(kind, name.toLowerCase())];
    if (e != null) found[e.id] = e;
  }

  for (final c in chars) {
    addId(c.speciesKey);
    addId(c.classKey);
    addId(c.subclassKey);
    addId(c.backgroundKey);
    for (final key in c.spellcasting?.cantripsKnown ?? const <String>[]) {
      addId(key);
    }
    for (final s in c.spellcasting?.spells ?? const <KnownSpell>[]) {
      addId(s.spellKey);
    }
    for (final f in c.feats) {
      addName('feat', f.name);
    }
    for (final w in c.weapons) {
      addName('weapon', w.name);
    }
    addName('armor', c.equippedArmor?.name);
    for (final i in c.inventory) {
      for (final kind in const [
        'magicItem',
        'gear',
        'tool',
        'weapon',
        'armor',
      ]) {
        addName(kind, i.name);
      }
    }
    for (final t in [
      ...c.toolProficiencyChoices,
      ...c.extraToolProficiencies,
    ]) {
      addName('tool', t);
    }
    for (final l in c.languages) {
      addName('language', l);
    }
  }
  // What the found entries themselves point at.
  var before = -1;
  while (found.length != before) {
    before = found.length;
    for (final e in [...found.values]) {
      addId(e.data['parentClass'] as String?);
      addName('feat', e.data['feat'] as String?);
      for (final row in (e.data['grantedSpells'] as List?) ?? const []) {
        addName('spell', (row as Map)['name'] as String?);
      }
    }
  }
  return found.values.toList();
}

/// Reads an export file into homebrew entries, characters (JSON, ids not
/// yet reassigned), and sheet text - throwing a FormatException for
/// anything that isn't this app's current export format.
({
  List<HomebrewEntry> homebrew,
  List<Map<String, dynamic>> characters,
  Map<String, String> sheetText,
})
parseExportBundle(String raw) {
  final decoded = jsonDecode(raw);
  if (decoded is! Map ||
      decoded['format'] != exportFormat ||
      decoded['version'] != exportVersion) {
    throw const FormatException(
      "This isn't a character export from this version of the app.",
    );
  }
  return (
    homebrew: [
      for (final e in decoded['homebrew'] as List? ?? const [])
        HomebrewEntry.fromJson((e as Map).cast<String, dynamic>()),
    ],
    characters: [
      for (final c in decoded['characters'] as List? ?? const [])
        Map<String, dynamic>.from(c as Map),
    ],
    sheetText: {
      for (final e in (decoded['sheetText'] as Map? ?? const {}).entries)
        e.key as String: e.value as String,
    },
  );
}

/// Merges [incoming] homebrew into the local catalog and returns the id
/// changes to apply to the characters and sheet text: an entry the device
/// already has (same kind and name) keeps the local one - never
/// overwritten - and the incoming id maps to it; a new entry is added
/// as-is, with any reference it holds to another remapped entry (a
/// subclass's parent class) fixed up.
Map<String, String> mergeHomebrew(List<HomebrewEntry> incoming) {
  final remap = <String, String>{};
  for (final e in incoming) {
    final local = homebrewRepo.entries
        .where(
          (x) =>
              x.kind == e.kind && x.name.toLowerCase() == e.name.toLowerCase(),
        )
        .firstOrNull;
    if (local != null && local.id != e.id) remap[e.id] = local.id;
  }
  for (final e in incoming) {
    if (remap.containsKey(e.id)) continue;
    final parent = e.data['parentClass'] as String?;
    homebrewRepo.importEntry(
      parent != null && remap.containsKey(parent)
          ? e.copyWith(data: {...e.data, 'parentClass': remap[parent]})
          : e,
    );
  }
  return remap;
}

/// Points a character's homebrew references (species, class, subclass,
/// background, spells, concentration, item-charge resources) at [remap]'s
/// ids.
void remapCharacterJson(Map<String, dynamic> json, Map<String, String> remap) {
  if (remap.isEmpty) return;
  String? map(Object? id) => id is String ? remap[id] ?? id : id as String?;
  for (final key in const [
    'speciesKey',
    'classKey',
    'subclassKey',
    'backgroundKey',
  ]) {
    json[key] = map(json[key]);
  }
  final sc = json['spellcasting'] as Map<String, dynamic>?;
  if (sc != null) {
    sc['cantripsKnown'] = [
      for (final k in sc['cantripsKnown'] as List? ?? const []) map(k),
    ];
    sc['spells'] = [
      for (final s in sc['spells'] as List? ?? const [])
        {...(s as Map).cast<String, dynamic>(), 'spellKey': map(s['spellKey'])},
    ];
    sc['concentratingOn'] = map(sc['concentratingOn']);
  }
  json['resources'] = [
    for (final r in json['resources'] as List? ?? const [])
      {
        ...(r as Map).cast<String, dynamic>(),
        if ((r['key'] as String).startsWith('item:'))
          'key': 'item:${map((r['key'] as String).substring(5))}',
      },
  ];
}

/// Sheet-text keys ("scope|name") with a remapped homebrew scope.
String remapSheetTextKey(String key, Map<String, String> remap) {
  final bar = key.indexOf('|');
  if (bar < 0) return key;
  final scope = key.substring(0, bar);
  return '${remap[scope] ?? scope}${key.substring(bar)}';
}
