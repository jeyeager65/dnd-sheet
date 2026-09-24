import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dnd_sheet/data/export_bundle.dart';
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

  test('the homebrew export round-trips the whole catalog, including effects/category/prerequisite/data', () {
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
        data: const {
          'grantedSpells': [
            {'name': 'Shield'},
          ],
        },
      ),
    );
    final json = buildHomebrewBundle(homebrewRepo.entries);
    expect((jsonDecode(json) as Map)['format'], homebrewExportFormat);

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
    expect(restored.data['grantedSpells'], hasLength(1));
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

  test('an empty catalog exports an empty list, and entry JSON leaves out empty fields', () {
    expect(parseHomebrewBundle(buildHomebrewBundle(const [])), isEmpty);
    final bare = homebrewRepo.create('gear', 'Rope of Plenty').toJson();
    expect(bare.keys.toSet(), {'id', 'kind', 'name', 'source'});
  });

  test('parseLocalOfficialContent reads a homebrew export file, and returns [] for anything else', () {
    final valid = parseLocalOfficialContent(
      jsonEncode({
        'format': homebrewExportFormat,
        'version': homebrewExportVersion,
        'homebrew': [
          {'id': 'homebrew_a', 'kind': 'feat', 'name': 'Test Feat'},
        ],
      }),
    );
    expect(valid, hasLength(1));
    expect(valid.first.name, 'Test Feat');

    expect(parseLocalOfficialContent('not json at all'), isEmpty);
    // A bare array (the old shape) is no longer read.
    expect(
      parseLocalOfficialContent(
        jsonEncode([
          {'id': 'homebrew_a', 'kind': 'feat', 'name': 'Test Feat'},
        ]),
      ),
      isEmpty,
    );
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
