import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../domain/rules.dart' as rules;
import '../models/character.dart';
import '../models/homebrew.dart';
import 'homebrew_repository.dart';
import 'sample_data.dart';

const _uuid = Uuid();

/// Local persistence, one Hive box holding each character as a JSON
/// string keyed by id. Deliberately avoids Hive's codegen'd TypeAdapters
/// (and the build_runner step that comes with them) - a schema this small
/// and still-evolving isn't worth that ceremony yet; plain JSON via
/// Character.toJson/fromJson is enough, same spirit as the web app's
/// schemaless IndexedDB + normalize-on-read approach.
class CharacterRepository extends ChangeNotifier {
  static const _boxName = 'characters';
  // Nullable rather than `late`: widget tests seed `characters` directly
  // and never call init() (Hive needs the path_provider plugin channel,
  // which the test environment doesn't provide) - save/delete still work
  // there, they just skip persisting, which is fine since those tests are
  // about UI behavior, not Hive itself.
  Box<String>? _box;
  final List<Character> characters = [];

  Future<void> init() async {
    // Deliberately not Hive.initFlutter(), which defaults to
    // getApplicationDocumentsDirectory() - on Windows that's often the
    // user's OneDrive-redirected Documents folder, and OneDrive's own
    // sync process transiently locks files it's watching, which collides
    // with Hive's exclusive file lock and throws a PathAccessException on
    // launch. Application support isn't synced/backed up by OneDrive,
    // and is the more correct place for a local database file anyway -
    // not somewhere a user browses to or expects to find app internals.
    final supportDir = await getApplicationSupportDirectory();
    Hive.init(supportDir.path);
    final box = await Hive.openBox<String>(_boxName);
    _box = box;

    if (box.isEmpty) {
      final jarson = buildSampleJarson();
      await box.put(jarson.id, jsonEncode(jarson.toJson()));
    }

    characters.clear();
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      final character = Character.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      // Keeps class/species resource maximums (Action Surge/Second Wind/
      // Indomitable, Rages, Breath Weapon, ...) in sync with the real SRD
      // level tables on every load, so the SRD data - not a value
      // hand-typed into sample_data.dart - stays the single source of
      // truth.
      rules.recalculateClassResources(character);
      // One-time repair for data saved before a choice-driven feature
      // (e.g. Champion's Additional Fighting Style) was correctly turned
      // into a Pending Choice on level-up instead of silently granted as
      // an inert feature - see rules.dart's repairMissingFeatChoices doc.
      rules.repairMissingFeatChoices(character);
      characters.add(character);
    }
    notifyListeners();
  }

  Character byId(String id) => characters.firstWhere((c) => c.id == id);

  /// All characters, grouped by familyId - one group per family, in
  /// first-seen order within each. What the character list screen renders
  /// (one card per family, with its snapshots underneath).
  List<List<Character>> listFamilies() {
    final byFamily = <String, List<Character>>{};
    for (final c in characters) {
      (byFamily[c.familyId] ??= []).add(c);
    }
    return byFamily.values.toList();
  }

  /// Deep-clones [source] via its own JSON round-trip (same idea as the
  /// web app's structuredClone) so the clone shares no mutable state -
  /// editing one snapshot's weapons list, say, never touches another's -
  /// with [overrides] applied to the decoded JSON before rebuilding, for
  /// the fields that must differ on the clone (id, at minimum).
  Character _cloneWith(Character source, Map<String, dynamic> overrides) {
    final json =
        jsonDecode(jsonEncode(source.toJson())) as Map<String, dynamic>;
    json.addAll(overrides);
    return Character.fromJson(json);
  }

  /// Clones [source] as a new, non-current snapshot in the same family -
  /// an automatic backup, not something offered as its own action (see
  /// levelUpCharacter, the only caller).
  Future<Character> _snapshotBackup(Character source) async {
    final backup = _cloneWith(source, {'id': _uuid.v4(), 'isCurrent': false});
    await save(backup);
    return backup;
  }

  /// Marks one snapshot as the in-play character, demoting every other
  /// snapshot in the same family - never deleting them, so an old level
  /// (however it got there - usually levelUpCharacter's automatic backup)
  /// is always available to promote back to if a level-up needs undoing.
  Future<void> promoteToCurrent(String id) async {
    final target = byId(id);
    for (final sibling in characters.where(
      (c) => c.familyId == target.familyId,
    )) {
      sibling.isCurrent = sibling.id == id;
      await _box?.put(sibling.id, jsonEncode(sibling.toJson()));
    }
    notifyListeners();
  }

  /// Levels up the character at [currentId] by exactly one level (see
  /// rules.levelUpOneLevel for everything that touches: HP, class/species
  /// resource maximums, newly-reached features, new Pending Choices).
  /// First snapshots its pre-level-up state as an automatic backup in the
  /// same family - not current, never auto-promoted - so a level-up is
  /// always reversible (Promote the backup back) rather than a one-way
  /// mutation; this replaces the old manual "Create Snapshot" step, which
  /// this app no longer offers on its own.
  Future<rules.LevelUpSummary> levelUpCharacter(String currentId) async {
    final current = byId(currentId);
    await _snapshotBackup(current);
    final summary = rules.levelUpOneLevel(current);
    await save(current);
    return summary;
  }

  /// Fully independent copy, in a new family of its own - "Save As" rather
  /// than a level-up snapshot.
  Future<Character> duplicateAsNewCharacter(
    String sourceId,
    String name,
  ) async {
    final source = byId(sourceId);
    final newId = _uuid.v4();
    final duplicate = _cloneWith(source, {
      'id': newId,
      'familyId': newId,
      'label': 'Level ${source.level}',
      'isCurrent': true,
      'name': name,
    });
    await save(duplicate);
    return duplicate;
  }

  /// Persists a character (new or existing) and notifies listeners so
  /// every screen showing it (list, sheet) rebuilds. For an existing
  /// character, callers mutate it in place (e.g. `resource.used++`) and
  /// then call this to save + broadcast; for a new one (from New
  /// Character), it's added to the in-memory list too.
  Future<void> save(Character c) async {
    await _box?.put(c.id, jsonEncode(c.toJson()));
    if (!characters.any((existing) => existing.id == c.id)) {
      characters.add(c);
    }
    notifyListeners();
  }

  /// The kind+name pairs of homebrew content [chars] actually depend on to
  /// keep working after export/import: their feats' names, and their
  /// *attuned* inventory items' names (the two sources
  /// rules.matchingEffects reads) - not the player's entire unrelated
  /// homebrew catalog.
  Set<(String, String)> _homebrewDependenciesOf(List<Character> chars) {
    final deps = <(String, String)>{};
    for (final c in chars) {
      for (final f in c.feats) {
        deps.add(('feat', f.name.toLowerCase()));
      }
      for (final i in c.inventory) {
        if (i.attuned) deps.add(('magicItem', i.name.toLowerCase()));
      }
    }
    return deps;
  }

  /// Pretty-printed `{characters, homebrew}` JSON for [chars], bundling
  /// whichever homebrew entries they actually depend on - without this,
  /// a homebrew feat/magic item's `Effect`s (matched live by name against
  /// homebrewRepo, never stored on the character itself) would silently
  /// stop applying on import, since nothing here travels with the
  /// character JSON alone.
  String _exportBundle(List<Character> chars) {
    final deps = _homebrewDependenciesOf(chars);
    final homebrew = homebrewRepo.entries.where(
      (e) => deps.contains((e.kind, e.name.toLowerCase())),
    );
    return const JsonEncoder.withIndent('  ').convert({
      'characters': chars.map((c) => c.toJson()).toList(),
      'homebrew': homebrew.map((e) => e.toJson()).toList(),
    });
  }

  /// JSON for every snapshot in [familyId]'s family - the counterpart to
  /// importFromJson.
  String exportFamily(String familyId) {
    final family = characters.where((c) => c.familyId == familyId).toList();
    return _exportBundle(family);
  }

  /// JSON for every character - a full backup, e.g. before reinstalling
  /// the app or moving to a new phone.
  String exportAll() => _exportBundle(characters);

  /// Every character (by name) that currently references [entry] via a
  /// granted feat or an attuned inventory item - used to warn before a
  /// destructive delete, since Effects/text are matched by name alone
  /// (see rules.liveFeatureEffects/liveItemEffects), not id.
  List<String> charactersReferencing(HomebrewEntry entry) {
    final names = <String>[];
    for (final c in characters) {
      final usesIt =
          (entry.kind == 'feat' &&
              c.feats.any(
                (f) => f.name.toLowerCase() == entry.name.toLowerCase(),
              )) ||
          (entry.kind == 'magicItem' &&
              c.inventory.any(
                (i) =>
                    i.attuned &&
                    i.name.toLowerCase() == entry.name.toLowerCase(),
              ));
      if (usesIt) names.add(c.name);
    }
    return names;
  }

  /// Parses [raw] - either the current `{characters: [...], homebrew:
  /// [...]}` shape, or the legacy bare array/object of characters only
  /// (from before homebrew bundling existed, or a hand-built file) - and
  /// adds the characters as new ones, always with freshly generated ids,
  /// never overwriting anything already saved, so importing is safe to
  /// run more than once and can never silently clobber existing data.
  /// familyId references within the imported batch are remapped to the
  /// new ids too, so snapshot relationships ("Level 5, current" / "Level
  /// 8, planned") survive the round trip; a familyId pointing outside the
  /// batch (not possible from a real export, but possible from a
  /// hand-edited file) falls back to the character's own new id, making
  /// it its own standalone family rather than risking a collision with an
  /// unrelated local family that happens to reuse that id string. Any
  /// bundled homebrew entries are merged into homebrewRepo first (see
  /// HomebrewRepository.importEntry), so the characters' Effects still
  /// apply once they land.
  Future<List<Character>> importFromJson(String raw) async {
    final decoded = jsonDecode(raw);
    final List<dynamic> rawList;
    final List<dynamic> homebrewMaps;
    if (decoded is Map && decoded.containsKey('characters')) {
      rawList = decoded['characters'] as List;
      homebrewMaps = decoded['homebrew'] as List? ?? const [];
    } else {
      rawList = decoded is List ? decoded : [decoded];
      homebrewMaps = const [];
    }

    for (final hb in homebrewMaps) {
      homebrewRepo.importEntry(
        HomebrewEntry.fromJson(hb as Map<String, dynamic>),
      );
    }

    final maps = [
      for (final item in rawList) Map<String, dynamic>.from(item as Map),
    ];

    final idMap = <String, String>{
      for (final json in maps) json['id'] as String: _uuid.v4(),
    };

    final imported = <Character>[];
    for (final json in maps) {
      final oldId = json['id'] as String;
      final oldFamilyId = json['familyId'] as String? ?? oldId;
      json['id'] = idMap[oldId];
      json['familyId'] = idMap[oldFamilyId] ?? idMap[oldId]!;
      final character = Character.fromJson(json);
      rules.recalculateClassResources(character);
      imported.add(character);
    }
    for (final character in imported) {
      await save(character);
    }
    return imported;
  }

  /// Permanently removes a character. Irreversible - callers should
  /// confirm with the player first (see CharacterListScreen's delete flow).
  /// If it was its family's current snapshot and others remain, promotes
  /// one of them, so a family never briefly has zero current snapshots.
  Future<void> delete(String id) async {
    final target = characters.where((c) => c.id == id);
    final familyId = target.isEmpty ? null : target.first.familyId;
    final wasCurrent = target.isEmpty ? false : target.first.isCurrent;

    await _box?.delete(id);
    characters.removeWhere((c) => c.id == id);

    if (wasCurrent && familyId != null) {
      final remaining = characters.where((c) => c.familyId == familyId);
      if (remaining.isNotEmpty) {
        remaining.first.isCurrent = true;
        await _box?.put(
          remaining.first.id,
          jsonEncode(remaining.first.toJson()),
        );
      }
    }
    notifyListeners();
  }
}

/// A single shared instance. Simple app, simple DI - a full provider/
/// riverpod setup isn't earning its keep yet for one repository.
final charactersRepo = CharacterRepository();
