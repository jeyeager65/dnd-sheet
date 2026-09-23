import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dnd_sheet/data/homebrew_repository.dart';
import 'package:dnd_sheet/data/local_official_content.dart';
import 'package:dnd_sheet/models/effect.dart';
import 'package:dnd_sheet/models/homebrew.dart';

void main() {
  // Needed for loadLocalOfficialContent's rootBundle.loadString call
  // below - same as srdCatalog.init() elsewhere in this test suite.
  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  // These tests never call init() (needs Hive/path_provider plugin
  // channels the widget-test environment doesn't provide) - create()
  // still works, it just skips persisting, same pattern as
  // CharacterRepository's tests.
  setUp(() {
    homebrewRepo.entries.clear();
  });

  test('create adds a new entry and byKind filters by kind', () {
    homebrewRepo.create('feat', 'Draconic Resilience');
    homebrewRepo.create('spell', 'Ember Lance');
    homebrewRepo.create('feat', 'Iron Will');

    final feats = homebrewRepo.byKind('feat');
    expect(
      feats.map((e) => e.name),
      containsAll(['Draconic Resilience', 'Iron Will']),
    );
    expect(feats.length, 2);
    expect(homebrewRepo.byKind('spell').length, 1);
    expect(homebrewRepo.byKind('armor'), isEmpty);
  });

  test('create reuses an existing entry of the same kind+name (case-insensitive), not a duplicate', () {
    final first = homebrewRepo.create('feat', 'Draconic Resilience');
    final second = homebrewRepo.create('feat', 'draconic resilience');

    expect(second.id, first.id);
    expect(homebrewRepo.byKind('feat').length, 1);
  });

  test('a homebrew id is always prefixed "homebrew_"', () {
    final entry = homebrewRepo.create('gear', "Alchemist's Kit");
    expect(entry.id, startsWith('homebrew_'));
  });

  test('exportAll round-trips the whole catalog, including effects/category/prerequisite, through importEntry', () {
    homebrewRepo.create('feat', 'Test Official Feat');
    homebrewRepo.update(
      HomebrewEntry(
        id: homebrewRepo.byKind('feat').single.id,
        kind: 'feat',
        name: 'Test Official Feat',
        source: 'official',
        effects: const [
          Effect(
            target: 'damageRoll',
            formula: 'Proficiency Bonus',
            condition: 'heavyWeapon',
          ),
        ],
        category: 'General Feat',
        prerequisite: 'Level 4+',
      ),
    );
    final json = homebrewRepo.exportAll();

    homebrewRepo.entries.clear();
    for (final entry in parseLocalOfficialContent(json)) {
      homebrewRepo.importEntry(entry);
    }

    final restored = homebrewRepo.byKind('feat').single;
    expect(restored.name, 'Test Official Feat');
    expect(restored.source, 'official');
    expect(restored.effects.single.formula, 'Proficiency Bonus');
    expect(restored.effects.single.condition, 'heavyWeapon');
    expect(restored.category, 'General Feat');
    expect(restored.prerequisite, 'Level 4+');
  });

  test('HomebrewEntry.fromJson defaults category and prerequisite to null for pre-existing data that never had those fields', () {
    final entry = HomebrewEntry.fromJson({
      'id': 'homebrew_1',
      'kind': 'feat',
      'name': 'Old Entry',
    });
    expect(entry.category, isNull);
    expect(entry.prerequisite, isNull);
  });

  test('exportAll produces an empty JSON array when the catalog is empty', () {
    expect(homebrewRepo.exportAll(), jsonEncode(const []));
  });

  test('parseLocalOfficialContent returns entries for a valid array, and [] for anything malformed', () {
    final valid = parseLocalOfficialContent(
      jsonEncode([
        {'id': 'homebrew_a', 'kind': 'feat', 'name': 'Test Feat'},
      ]),
    );
    expect(valid, hasLength(1));
    expect(valid.first.name, 'Test Feat');

    expect(parseLocalOfficialContent('not json at all'), isEmpty);
    expect(parseLocalOfficialContent(jsonEncode({'not': 'a list'})), isEmpty);
    expect(parseLocalOfficialContent(jsonEncode([1, 2, 3])), isEmpty);
    expect(parseLocalOfficialContent(''), isEmpty);
  });

  test('loadLocalOfficialContent does nothing (and never throws) when assets/official/content.json is absent - the shared/public build case', () async {
    homebrewRepo.entries.clear();
    await loadLocalOfficialContent();
    expect(homebrewRepo.entries, isEmpty);
  });
}
