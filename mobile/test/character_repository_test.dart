import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:dnd_sheet/data/character_repository.dart';
import 'package:dnd_sheet/data/homebrew_repository.dart';
import 'package:dnd_sheet/data/sample_data.dart';
import 'package:dnd_sheet/data/srd_catalog.dart';
import 'package:dnd_sheet/domain/rules.dart' as rules;
import 'package:dnd_sheet/models/character.dart';
import 'package:dnd_sheet/models/effect.dart';
import 'package:dnd_sheet/models/homebrew.dart';

void main() {
  // Needed for anything that reads real class/species data mid-test
  // (levelUpCharacter's classFeaturesForLevelUp, recalculateClassResources,
  // ...) - without this, srdCatalog.classesByKey stays empty when this
  // file runs on its own, and those lookups silently return nothing
  // rather than erroring, which is exactly what let this go unnoticed for
  // a while. Same pattern as every other test file's setUpAll.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await srdCatalog.init();
  });

  // These tests never call charactersRepo.init() (needs Hive/path_provider
  // plugin channels the widget-test environment doesn't provide) and seed
  // `characters` directly instead - save/levelUpCharacter/etc. still
  // work, they just skip persisting to Hive, same pattern as
  // widget_test.dart.
  setUp(() {
    charactersRepo.characters
      ..clear()
      ..add(buildSampleCharacter());
    homebrewRepo.entries.clear();
  });

  test(
    'a freshly-seeded character is its own family (familyId == id) and current',
    () {
      final torvek = charactersRepo.byId('torvek');
      expect(torvek.familyId, 'torvek');
      expect(torvek.isCurrent, isTrue);
      expect(charactersRepo.listFamilies(), [
        [torvek],
      ]);
    },
  );

  test('levelUpCharacter advances the character in place by one level and leaves an automatic, non-current backup of the pre-level-up state', () async {
    final torvek = charactersRepo.byId('torvek');
    final beforeMaxHp = torvek.maxHp;
    expect(torvek.level, 9);

    final summary = await charactersRepo.levelUpCharacter('torvek');

    // The same id/object advances forward - still current, same family.
    expect(torvek.id, 'torvek');
    expect(torvek.level, 10);
    expect(torvek.isCurrent, isTrue);
    expect(summary.oldLevel, 9);
    expect(summary.newLevel, 10);
    expect(summary.oldMaxHp, beforeMaxHp);
    expect(summary.newMaxHp, torvek.maxHp);

    // A new, non-current backup exists at the OLD level, sharing no
    // mutable state with the (now leveled-up) original.
    final families = charactersRepo.listFamilies();
    expect(families.length, 1);
    expect(families.first.length, 2);
    final backup = families.first.firstWhere((c) => c.id != 'torvek');
    expect(backup.familyId, 'torvek');
    expect(backup.isCurrent, isFalse);
    expect(backup.level, 9);
    expect(backup.name, torvek.name);
    backup.weapons = [];
    expect(torvek.weapons, isNotEmpty);
  });

  test('levelUpCharacter logs a History entry naming the new features and Pending Choices gained at that level, not just Max HP', () async {
    final torvek = charactersRepo.byId('torvek');
    // Level 4 -> 5 crosses Extra Attack/Tactical Shift (real class
    // features) with no Pending Choice; level 3 -> 4 crosses Ability
    // Score Improvement (a Pending Choice) with no new feature - between
    // them this exercises both halves of the enriched detail string.
    // Cleared first: Torvek's own seed data already has every feature up
    // to his real level 9 granted, so classFeaturesForLevelUp would
    // (correctly) find nothing "new" to grant without this.
    torvek.features = [];
    torvek.level = 4;
    final atFive = await charactersRepo.levelUpCharacter('torvek');
    expect(torvek.history.last.label, 'Leveled up: 4 → 5');
    expect(torvek.history.last.detail, contains('Max HP:'));
    expect(torvek.history.last.detail, contains('New features:'));
    for (final name in atFive.newFeatureNames) {
      expect(torvek.history.last.detail, contains(name));
    }
    expect(torvek.history.last.detail, isNot(contains('New choices')));
    // Level 4 -> 5 also crosses a Proficiency Bonus threshold (+2 -> +3),
    // which moves every proficient weapon's attack bonus too - both should
    // show up in the same detail string.
    expect(torvek.history.last.detail, contains('Proficiency Bonus: +2 → +3.'));
    expect(torvek.history.last.detail, contains('Weapons:'));

    torvek.level = 3;
    final atFour = await charactersRepo.levelUpCharacter('torvek');
    expect(torvek.history.last.detail, contains('New choices to make:'));
    for (final choice in atFour.newPendingChoices) {
      expect(torvek.history.last.detail, contains(choice.label));
    }
  });

  test(
    'promoteToCurrent makes the target current and demotes every sibling',
    () async {
      await charactersRepo.levelUpCharacter('torvek');
      final backup = charactersRepo.characters.firstWhere(
        (c) => c.familyId == 'torvek' && c.id != 'torvek',
      );

      await charactersRepo.promoteToCurrent(backup.id);

      expect(charactersRepo.byId(backup.id).isCurrent, isTrue);
      expect(charactersRepo.byId('torvek').isCurrent, isFalse);
    },
  );

  test('snapshotStatusLabel reflects the real level of a demoted character, not a stale label', () async {
    final torvek = charactersRepo.byId('torvek');
    expect(torvek.level, 9);

    await charactersRepo.levelUpCharacter('torvek');
    final backup = charactersRepo.characters.firstWhere(
      (c) => c.familyId == 'torvek' && c.id != 'torvek',
    );
    expect(backup.snapshotStatusLabel, 'Level 9 (previous)');
    expect(torvek.level, 10); // the live character actually advanced

    await charactersRepo.promoteToCurrent(backup.id);

    // Demoted, but his real level (10, from the level-up above) hasn't
    // changed just because he's no longer current.
    expect(torvek.isCurrent, isFalse);
    expect(torvek.snapshotStatusLabel, 'Level 10 (previous)');
  });

  test('duplicateAsNewCharacter creates a fully independent character in its own new family', () async {
    final duplicate = await charactersRepo.duplicateAsNewCharacter(
      'torvek',
      'Torvek (copy)',
    );

    expect(duplicate.id, isNot('torvek'));
    expect(duplicate.familyId, duplicate.id); // its own family, not Torvek's
    expect(duplicate.name, 'Torvek (copy)');
    expect(duplicate.isCurrent, isTrue);
    expect(charactersRepo.listFamilies().length, 2);
  });

  test('deleting the current snapshot promotes a remaining sibling, never leaving a family with zero current snapshots', () async {
    await charactersRepo.levelUpCharacter('torvek');
    final backup = charactersRepo.characters.firstWhere(
      (c) => c.familyId == 'torvek' && c.id != 'torvek',
    );
    expect(charactersRepo.byId('torvek').isCurrent, isTrue);

    await charactersRepo.delete('torvek');

    expect(charactersRepo.characters.any((c) => c.id == 'torvek'), isFalse);
    expect(charactersRepo.byId(backup.id).isCurrent, isTrue);
  });

  test(
    'deleting a non-current snapshot leaves the current one untouched',
    () async {
      await charactersRepo.levelUpCharacter('torvek');
      final backup = charactersRepo.characters.firstWhere(
        (c) => c.familyId == 'torvek' && c.id != 'torvek',
      );

      await charactersRepo.delete(backup.id);

      expect(charactersRepo.characters.any((c) => c.id == backup.id), isFalse);
      expect(charactersRepo.byId('torvek').isCurrent, isTrue);
    },
  );

  test('exportFamily includes every snapshot in the family, importFromJson adds them back with fresh ids but the same family link', () async {
    await charactersRepo.levelUpCharacter('torvek');
    final backup = charactersRepo.characters.firstWhere(
      (c) => c.familyId == 'torvek' && c.id != 'torvek',
    );
    final json = charactersRepo.exportFamily('torvek');

    final imported = await charactersRepo.importFromJson(json);

    expect(imported, hasLength(2));
    // Fresh ids, never colliding with the originals.
    expect(imported.map((c) => c.id), isNot(contains('torvek')));
    expect(imported.map((c) => c.id), isNot(contains(backup.id)));
    // But still linked to each other as one family, distinct from the
    // original family's id.
    final familyIds = imported.map((c) => c.familyId).toSet();
    expect(familyIds, hasLength(1));
    expect(familyIds.single, isNot('torvek'));
    // Names carried over correctly, at their own (different) levels.
    expect(imported.map((c) => c.name), everyElement('Torvek'));
    expect(imported.map((c) => c.level), containsAll([9, 10]));
    // Additive - the originals are still there too.
    expect(charactersRepo.characters, hasLength(4));
  });

  test('exportAll covers every character across every family', () async {
    await charactersRepo.levelUpCharacter('torvek');
    await charactersRepo.duplicateAsNewCharacter('torvek', 'Torvek (copy)');

    final json = charactersRepo.exportAll();
    final imported = await charactersRepo.importFromJson(json);

    expect(imported, hasLength(3));
    expect(charactersRepo.characters, hasLength(6));
  });

  test(
    "importFromJson rejects anything that isn't a current export file",
    () async {
      final single = charactersRepo.byId('torvek').toJson();
      await expectLater(
        charactersRepo.importFromJson(jsonEncode(single)),
        throwsFormatException,
      );
      await expectLater(
        charactersRepo.importFromJson(jsonEncode([single])),
        throwsFormatException,
      );
      expect(charactersRepo.characters, hasLength(1));
    },
  );

  test('familyId round-trips through Character.toJson/fromJson', () {
    final torvek = charactersRepo.byId('torvek');
    final restored = Character.fromJson(torvek.toJson());
    expect(restored.familyId, torvek.familyId);
    expect(restored.isCurrent, torvek.isCurrent);
  });

  test('backgroundLabel/backgroundKey round-trip through Character.toJson/fromJson', () {
    final torvek = charactersRepo.byId('torvek');
    expect(torvek.backgroundLabel, 'Soldier');
    expect(torvek.backgroundKey, 'srd-2024_soldier-background');

    final restored = Character.fromJson(torvek.toJson());
    expect(restored.backgroundLabel, 'Soldier');
    expect(restored.backgroundKey, 'srd-2024_soldier-background');
  });

  test('history entries round-trip through Character.toJson/fromJson', () {
    final torvek = charactersRepo.byId('torvek');
    torvek.history = [
      HistoryEntry(
        id: 'h1',
        timestamp: DateTime.utc(2026, 9, 19, 12, 0),
        label: 'Ability scores edited',
        detail: 'DEX 12 → 14',
      ),
    ];
    final restored = Character.fromJson(torvek.toJson());

    expect(restored.history, hasLength(1));
    expect(restored.history.first.id, 'h1');
    expect(restored.history.first.label, 'Ability scores edited');
    expect(restored.history.first.detail, 'DEX 12 → 14');
    expect(restored.history.first.timestamp, DateTime.utc(2026, 9, 19, 12, 0));
  });

  test(
    'a character with no history round-trips to an empty list, not a crash',
    () {
      final torvek = charactersRepo.byId('torvek');
      expect(torvek.history, isEmpty);
      final restored = Character.fromJson(torvek.toJson());
      expect(restored.history, isEmpty);
    },
  );

  test('a Mount defaults currentHp to maxHp and round-trips through JSON', () {
    final torvek = charactersRepo.byId('torvek');
    torvek.mounts = [
      Mount(name: 'Warhorse', armorClass: 11, maxHp: 19, speed: 60),
    ];
    expect(torvek.mounts.first.currentHp, 19); // defaults to full

    torvek.mounts.first.currentHp = 12;
    torvek.mounts.first.active = true;
    final restored = Character.fromJson(torvek.toJson());

    expect(restored.mounts.length, 1);
    expect(restored.mounts.first.name, 'Warhorse');
    expect(restored.mounts.first.armorClass, 11);
    expect(restored.mounts.first.maxHp, 19);
    expect(restored.mounts.first.currentHp, 12);
    expect(restored.mounts.first.speed, 60);
    expect(restored.mounts.first.active, isTrue);
  });

  test('a Weapon\'s damage dice/type can be edited after being added, not just at creation', () {
    final torvek = charactersRepo.byId('torvek');
    final greatsword = torvek.weapons.firstWhere((w) => w.name == 'Greatsword');

    greatsword
      ..damageDice = '3d6'
      ..damageType = 'Fire'
      ..proficient = false
      ..finesse = true
      ..magicBonus = 2;

    expect(greatsword.damageDice, '3d6');
    expect(greatsword.damageType, 'Fire');
    expect(greatsword.proficient, isFalse);
    expect(greatsword.finesse, isTrue);
    expect(greatsword.magicBonus, 2);
  });

  test(
    'an InventoryEntry\'s name and caption can be edited after being added',
    () {
      final torvek = charactersRepo.byId('torvek');
      final item = InventoryEntry(name: 'Torch', quantity: 3);
      torvek.inventory = [item];

      item
        ..name = 'Everburning Torch'
        ..caption = 'Never goes out'
        ..quantity = 1;

      expect(torvek.inventory.first.name, 'Everburning Torch');
      expect(torvek.inventory.first.caption, 'Never goes out');
      expect(torvek.inventory.first.quantity, 1);

      // Round-trips too, not just in-memory.
      final restored = Character.fromJson(torvek.toJson());
      expect(restored.inventory.first.name, 'Everburning Torch');
      expect(restored.inventory.first.caption, 'Never goes out');
    },
  );

  test('an InnateAttack using the new levelDice shape round-trips through Character.fromJson(c.toJson())', () {
    final torvek = charactersRepo.byId('torvek');
    final restored = Character.fromJson(torvek.toJson());

    final original = torvek.innateAttacks.firstWhere(
      (a) => a.name == 'Breath Weapon',
    );
    final restoredAttack = restored.innateAttacks.firstWhere(
      (a) => a.name == 'Breath Weapon',
    );

    expect(restoredAttack.levelDice, original.levelDice);
    expect(restoredAttack.dieType, original.dieType);
    expect(restoredAttack.saveDcFormula, original.saveDcFormula);
    expect(restoredAttack.saveAbility, original.saveAbility);
  });

  test('exporting a character with a homebrew feat carrying an Effect bundles that entry in homebrew', () {
    final entry = homebrewRepo.create('feat', 'Test Homebrew Feat');
    homebrewRepo.update(
      HomebrewEntry(
        id: entry.id,
        kind: entry.kind,
        name: entry.name,
        desc: 'Grants a bonus to Wisdom saves.',
        effects: const [
          Effect(target: 'save:wis', formula: 'Proficiency Bonus'),
        ],
      ),
    );
    final torvek = charactersRepo.byId('torvek');
    torvek.feats.add(
      GrantedFeature(name: 'Test Homebrew Feat', source: 'homebrew'),
    );

    final json = charactersRepo.exportFamily('torvek');
    final decoded = jsonDecode(json) as Map<String, dynamic>;

    expect(decoded['homebrew'], hasLength(1));
    final bundled = decoded['homebrew'][0] as Map<String, dynamic>;
    expect(bundled['name'], 'Test Homebrew Feat');
    expect(bundled['effects'], hasLength(1));
  });

  test('exporting a character with no homebrew feat/attuned magic item bundles an empty homebrew list', () {
    // Torvek's seed data has no homebrew feats or attuned magic items,
    // and any unrelated homebrew catalog entries shouldn't leak in.
    homebrewRepo.create('feat', 'Unrelated Homebrew Feat');

    final json = charactersRepo.exportFamily('torvek');
    final decoded = jsonDecode(json) as Map<String, dynamic>;

    expect(decoded['homebrew'], isEmpty);
  });

  test('importFromJson on a homebrew-bundled export restores the character and the effect actually applies', () async {
    final entry = homebrewRepo.create('feat', 'Test Homebrew Feat');
    homebrewRepo.update(
      HomebrewEntry(
        id: entry.id,
        kind: entry.kind,
        name: entry.name,
        effects: const [
          Effect(target: 'save:wis', formula: 'Proficiency Bonus'),
        ],
      ),
    );
    final torvek = charactersRepo.byId('torvek');
    torvek.feats.add(
      GrantedFeature(name: 'Test Homebrew Feat', source: 'homebrew'),
    );
    final beforeSave = rules.savingThrowModifier(torvek, 'wis');

    final json = charactersRepo.exportFamily('torvek');

    // Simulate a fresh install: no local homebrew catalog at all.
    homebrewRepo.entries.clear();

    final imported = await charactersRepo.importFromJson(json);

    expect(imported, hasLength(1));
    expect(
      homebrewRepo.byKind('feat').map((e) => e.name),
      contains('Test Homebrew Feat'),
    );
    final importedSave = rules.savingThrowModifier(imported.first, 'wis');
    expect(importedSave, beforeSave);
  });

  test('re-importing the same homebrew-bundled export twice does not duplicate the homebrew entry', () async {
    final entry = homebrewRepo.create('feat', 'Test Homebrew Feat');
    homebrewRepo.update(
      HomebrewEntry(
        id: entry.id,
        kind: entry.kind,
        name: entry.name,
        effects: const [
          Effect(target: 'save:wis', formula: 'Proficiency Bonus'),
        ],
      ),
    );
    final torvek = charactersRepo.byId('torvek');
    torvek.feats.add(
      GrantedFeature(name: 'Test Homebrew Feat', source: 'homebrew'),
    );
    final json = charactersRepo.exportFamily('torvek');

    await charactersRepo.importFromJson(json);
    await charactersRepo.importFromJson(json);

    expect(
      homebrewRepo.entries.where((e) => e.name == 'Test Homebrew Feat'),
      hasLength(1),
    );
  });

  test('importing a bundle whose homebrew entry name collides with a different local entry leaves the local one untouched', () async {
    final entry = homebrewRepo.create('feat', 'Test Homebrew Feat');
    homebrewRepo.update(
      HomebrewEntry(
        id: entry.id,
        kind: entry.kind,
        name: entry.name,
        effects: const [
          Effect(target: 'save:wis', formula: 'Proficiency Bonus'),
        ],
      ),
    );
    final torvek = charactersRepo.byId('torvek');
    torvek.feats.add(
      GrantedFeature(name: 'Test Homebrew Feat', source: 'homebrew'),
    );
    final json = charactersRepo.exportFamily('torvek');

    // Local entry with the same kind+name but a different effect -
    // simulates the importing device having already tuned its own
    // version locally.
    homebrewRepo.entries.clear();
    final local = homebrewRepo.create('feat', 'Test Homebrew Feat');
    homebrewRepo.update(
      HomebrewEntry(
        id: local.id,
        kind: local.kind,
        name: local.name,
        effects: const [Effect(target: 'save:wis', formula: '99')],
      ),
    );

    await charactersRepo.importFromJson(json);

    final stillLocal = homebrewRepo.entries.singleWhere(
      (e) => e.name == 'Test Homebrew Feat',
    );
    expect(stillLocal.effects.single.formula, '99');
  });

  test("EquippedArmor.category round-trips through Character.toJson/fromJson, and legacy armor with no category loads as null", () {
    final torvek = charactersRepo.byId('torvek');
    torvek.equippedArmor = EquippedArmor(
      name: 'Plate Armor',
      armorClassFormula: '18',
      category: 'Heavy',
    );
    final restored = Character.fromJson(torvek.toJson());
    expect(restored.equippedArmor?.category, 'Heavy');

    final legacy = EquippedArmor.fromJson({
      'name': 'Plate Armor',
      'armorClassFormula': '18',
    });
    expect(legacy.category, isNull);
  });
}
