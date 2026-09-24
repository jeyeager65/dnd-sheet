import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dnd_sheet/data/character_factory.dart';
import 'package:dnd_sheet/data/character_repository.dart';
import 'package:dnd_sheet/data/export_bundle.dart';
import 'package:dnd_sheet/data/homebrew_catalog.dart';
import 'package:dnd_sheet/data/homebrew_repository.dart';
import 'package:dnd_sheet/data/sheet_text_repository.dart';
import 'package:dnd_sheet/data/srd_catalog.dart';
import 'package:dnd_sheet/domain/rules.dart' as rules;
import 'package:dnd_sheet/models/character.dart';
import 'package:dnd_sheet/models/homebrew.dart';

HomebrewEntry _hb(
  String kind,
  String name,
  Map<String, dynamic> data, {
  String desc = '',
}) {
  final e = homebrewRepo.create(kind, name);
  homebrewRepo.update(e.copyWith(data: data, desc: desc));
  registerHomebrewInCatalog();
  return homebrewRepo.entries.firstWhere((x) => x.id == e.id);
}

void _wipe() {
  charactersRepo.characters.clear();
  homebrewRepo.entries.clear();
  sheetTextRepo.overrides.clear();
  registerHomebrewInCatalog();
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await srdCatalog.init();
  });

  setUp(_wipe);

  test('a heavily customized character with homebrew of every kind survives export and import into a fresh app, even with a same-named homebrew conflict', () async {
    // --- Build it ---
    final spell = _hb('spell', 'Rune Bolt', {
      'level': 1,
      'school': 'Evocation',
      'castingTime': 'Action',
      'range': '60 feet',
      'classes': ['Runescribe'],
    }, desc: 'Make a ranged spell attack. On a hit, 2d8 Force damage.');
    _hb('spell', 'Glyph Glow', {'level': 0});
    final species = _hb('species', 'Stoneborn', {
      'speed': 25,
      'traits': [
        {'name': 'Stone Skin', 'desc': 'Tough.', 'shortDesc': 'Tough.'},
      ],
    });
    final cls = _hb('class', 'Runescribe', {
      'hitDie': 'd8',
      'saves': ['int', 'wis'],
      'casterType': 'full',
      'spellAbility': 'int',
      'features': [
        {'level': 1, 'name': 'Runic Script', 'desc': 'Write runes.'},
      ],
    });
    final subclass = _hb('subclass', 'Circle of Glyphs', {
      'parentClass': cls.id,
      'features': [
        {'level': 3, 'name': 'Glyph Mastery', 'desc': 'Master glyphs.'},
      ],
    });
    final background = _hb('background', 'Scribe', {
      'abilityScores': ['Intelligence', 'Wisdom', 'Charisma'],
      'skills': ['Arcana', 'History'],
      'feat': 'Glyph Adept',
    });
    _hb('feat', 'Glyph Adept', {
      'grantedSpells': [
        {'name': 'Glyph Glow'},
      ],
    });
    _hb('magicItem', 'Rune Wand', {'charges': 5, 'recharge': 'long'});
    _hb('armor', 'Runed Coat', {
      'armorCategory': 'Light',
      'baseAc': 12,
      'dexMode': 'full',
    });
    _hb('tool', "Glyphwright's Tools", const {});
    _hb('language', 'Runic', const {});
    _hb('feat', 'Unrelated Feat', const {}); // shouldn't be exported

    final c = buildNewCharacter(
      name: 'Rhea',
      species: SrdRefItem(
        key: species.id,
        name: species.name,
        isHomebrew: true,
      ),
      background: SrdRefItem(
        key: background.id,
        name: background.name,
        isHomebrew: true,
      ),
      srdClass: SrdRefItem(key: cls.id, name: cls.name, isHomebrew: true),
      abilityScores: const AbilityScores(
        str: 8,
        dex: 14,
        con: 14,
        intel: 15,
        wis: 12,
        cha: 10,
      ),
      chosenClassSkills: const [],
      backgroundAbilityIncreases: const {'int': 2, 'wis': 1},
    );
    rules.levelUpOneLevel(c, hpRoll: 7);
    rules.levelUpOneLevel(c);
    rules.resolveSubclassChoice(
      c,
      c.pendingChoices.firstWhere((p) => p.kind == 'subclass').id,
      subclass.id,
    );
    c.spellcasting!.spells = [
      ...c.spellcasting!.spells,
      KnownSpell(spellKey: spell.id),
    ];
    c.spellcasting!.concentratingOn = spell.id;
    c.inventory = [
      InventoryEntry(name: 'Rune Wand', quantity: 1, attuned: true),
    ];
    c.equippedArmor = ArmorStats(baseAc: 12).toArmor('Runed Coat');
    c.extraToolProficiencies = ["Glyphwright's Tools"];
    c.languages = ['Common', 'Runic'];
    c.maxHpAdjustment = 3;
    rules.recalculateClassResources(c);
    rules.refreshMaxHp(c);
    charactersRepo.characters.add(c);
    final glyphFeature = c.features.firstWhere(
      (f) => f.name == 'Glyph Mastery',
    );
    sheetTextRepo.set(rules.sheetTextKey(c, glyphFeature), 'My glyph words.');
    final before = c.toJson();
    final beforeAc = rules.armorClassFor(c);

    // --- Export ---
    final file = charactersRepo.exportFamily(c.familyId);
    final decoded = jsonDecode(file) as Map<String, dynamic>;
    expect(decoded['format'], exportFormat);
    expect(decoded['version'], exportVersion);
    final names = [
      for (final e in decoded['homebrew'] as List) (e as Map)['name'],
    ];
    expect(names.toSet(), {
      'Rune Bolt',
      'Glyph Glow',
      'Stoneborn',
      'Runescribe',
      'Circle of Glyphs',
      'Scribe',
      'Glyph Adept',
      'Rune Wand',
      'Runed Coat',
      "Glyphwright's Tools",
      'Runic',
    });
    expect(decoded['sheetText'], hasLength(1));
    final exported = (decoded['characters'] as List).single as Map;
    // Homebrew text still travels (with the homebrew); nothing SRD here.
    expect(
      (exported['features'] as List).every((f) => (f as Map)['desc'] == null),
      isTrue,
    );

    // --- A fresh app that already has its own "Runescribe" ---
    _wipe();
    final localCls = _hb('class', 'Runescribe', {
      'hitDie': 'd8',
      'saves': ['int', 'wis'],
      'casterType': 'full',
      'spellAbility': 'int',
      'features': [
        {'level': 1, 'name': 'Runic Script', 'desc': 'Local wording.'},
      ],
    });
    expect(localCls.id, isNot(cls.id));

    final imported = (await charactersRepo.importFromJson(file)).single;

    // References resolve - the class to the local one that already existed.
    expect(imported.classKey, localCls.id);
    expect(srdCatalog.byKey(imported.classKey!)?.name, 'Runescribe');
    expect(srdCatalog.speciesByKey[imported.speciesKey]?.name, 'Stoneborn');
    expect(srdCatalog.backgroundsByKey[imported.backgroundKey]?.name, 'Scribe');
    // The subclass's parent was re-pointed at the local class too.
    expect(rules.chosenSubclass(imported)?.name, 'Circle of Glyphs');
    expect(
      rules.spellRefFor(imported.spellcasting!.concentratingOn!)?.name,
      'Rune Bolt',
    );
    expect(
      imported.spellcasting!.spells
          .map((s) => rules.knownSpellRef(s)?.name)
          .toSet(),
      containsAll(['Rune Bolt', 'Glyph Glow']),
    );
    expect(
      imported.resources.any((r) => r.name == 'Rune Wand charges'),
      isTrue,
    );
    expect(rules.armorClassFor(imported), beforeAc);
    expect(rules.itemInfo('Rune Wand'), isNotNull);
    expect(
      rules.sheetText(
        imported,
        imported.features.firstWhere((f) => f.name == 'Glyph Mastery'),
      ),
      'My glyph words.',
    );
    expect(
      rules.liveFeatureText(
        imported,
        imported.features.firstWhere((f) => f.name == 'Glyph Mastery'),
      ),
      'Master glyphs.',
    );
    // Only one Runescribe class - the local one wasn't duplicated.
    expect(homebrewRepo.byKind('class'), hasLength(1));

    // Everything else matches the original.
    final after = imported.toJson();
    for (final key in [
      'name',
      'level',
      'abilityScores',
      'maxHp',
      'currentHp',
      'hitPointRolls',
      'maxHpAdjustment',
      'backgroundAbilityIncreases',
      'languages',
      'extraToolProficiencies',
      'inventory',
      'equippedArmor',
      'skills',
      'savingThrowProficiencies',
      'featureChoices',
      'weaponMasteries',
      'speed',
      'hitDiceDie',
    ]) {
      expect(jsonEncode(after[key]), jsonEncode(before[key]), reason: key);
    }
  });

  test('a local sheet-text edit is never overwritten by an import', () async {
    final c = buildNewCharacter(
      name: 'Tess',
      species: srdCatalog.species.firstWhere((s) => s.name == 'Human'),
      background: srdCatalog.backgroundOptions.firstWhere(
        (b) => b.name == 'Soldier',
      ),
      srdClass: srdCatalog.classOptions.firstWhere((x) => x.name == 'Fighter'),
      abilityScores: const AbilityScores(
        str: 15,
        dex: 14,
        con: 13,
        intel: 10,
        wis: 12,
        cha: 8,
      ),
      chosenClassSkills: const [],
    );
    charactersRepo.characters.add(c);
    final key = rules.sheetTextKey(c, c.features.first);
    sheetTextRepo.set(key, 'From the file.');
    final file = charactersRepo.exportAll();
    sheetTextRepo.set(key, 'Mine.');
    await charactersRepo.importFromJson(file);
    expect(sheetTextRepo[key], 'Mine.');
  });
}
