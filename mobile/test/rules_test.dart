import 'package:flutter_test/flutter_test.dart';

import 'package:dnd_sheet/data/homebrew_repository.dart';
import 'package:dnd_sheet/data/sample_data.dart';
import 'package:dnd_sheet/data/sheet_text_repository.dart';
import 'package:dnd_sheet/data/srd_catalog.dart';
import 'package:dnd_sheet/domain/rules.dart' as rules;
import 'package:dnd_sheet/models/character.dart';
import 'package:dnd_sheet/models/effect.dart';
import 'package:dnd_sheet/models/homebrew.dart';

/// Grants Heavy Armor Master to [c] and backs it with a homebrew "official"
/// entry carrying its effect - it's a real 2024 PHB feat NOT in the free
/// SRD (see rules.dart's _builtinFeatEffects doc comment), so unlike
/// Alert, the app never ships its mechanics; this is what a real player
/// has to do once, themselves, to make it work (the same as this test
/// simulates).
void _grantHeavyArmorMaster(
  Character c, {
  String formula = 'Proficiency Bonus',
}) {
  c.feats.add(GrantedFeature(name: 'Heavy Armor Master', source: 'feat'));
  final entry = homebrewRepo.create('feat', 'Heavy Armor Master');
  homebrewRepo.update(
    HomebrewEntry(
      id: entry.id,
      kind: entry.kind,
      name: entry.name,
      source: 'official',
      effects: [
        Effect(
          target: 'damageReduction:physical',
          formula: formula,
          condition: 'heavyArmor',
        ),
      ],
    ),
  );
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await srdCatalog.init();
  });

  // homebrewRepo is a global singleton - tests that add entries to it
  // (the override/Effect tests below) must not leak into other tests.
  setUp(() {
    homebrewRepo.entries.clear();
  });

  test('AbilityScores.increase applies deltas and clamps at 20', () {
    const scores = AbilityScores(
      str: 19,
      dex: 12,
      con: 14,
      intel: 10,
      wis: 12,
      cha: 8,
    );
    final single = scores.increase({'str': 2});
    expect(single.str, 20); // 19 + 2 clamped to 20, not 21
    final double_ = scores.increase({'dex': 1, 'con': 1});
    expect(double_.dex, 13);
    expect(double_.con, 15);
    expect(double_.str, 19); // untouched
  });

  test('pendingChoicesForLevelUp surfaces ASI choices crossed, matching the real Fighter table (4, 6, 8, 12, 14, 16)', () {
    final jarson = buildSampleJarson();
    jarson.level = 3;
    jarson.pendingChoices = [];

    final crossing5 = rules.pendingChoicesForLevelUp(jarson, 3, 5);
    expect(crossing5.length, 1);
    expect(crossing5.first.label, contains('Level 4'));
    // kind: 'asi' routes it to its own "ASI or a General Feat?" choice
    // up front, instead of sending the player into the full feat picker
    // to search for "Ability Score Improvement" by name.
    expect(crossing5.first.kind, 'asi');

    final crossingNone = rules.pendingChoicesForLevelUp(jarson, 9, 10);
    expect(crossingNone, isEmpty);

    final crossingTwo = rules.pendingChoicesForLevelUp(jarson, 3, 7);
    expect(
      crossingTwo.map((c) => c.label),
      containsAll([contains('Level 4'), contains('Level 6')]),
    );
  });

  test('pendingChoicesForLevelUp never returns a choice already present (no duplicates)', () {
    final jarson = buildSampleJarson();
    final already = rules.pendingChoicesForLevelUp(jarson, 3, 5).first;
    jarson.pendingChoices = [already];
    final again = rules.pendingChoicesForLevelUp(jarson, 3, 5);
    expect(again, isEmpty);
  });

  test('classFeaturesForLevelUp grants Extra Attack at 5 and Indomitable at 9, skipping choice-driven entries', () {
    final jarson = buildSampleJarson();
    jarson.level = 3;
    jarson.features = [];

    final crossing5 = rules.classFeaturesForLevelUp(jarson, 3, 5);
    expect(
      crossing5.map((f) => f.name),
      containsAll(['Extra Attack', 'Tactical Shift']),
    );
    // Ability Score Improvement (level 4) and Fighter Subclass (level 3)
    // are choice-driven, not plain features - never auto-granted here.
    expect(
      crossing5.any((f) => f.name == 'Ability Score Improvement'),
      isFalse,
    );
    expect(crossing5.any((f) => f.name == 'Fighter Subclass'), isFalse);

    jarson.features = crossing5;
    final crossing9 = rules.classFeaturesForLevelUp(jarson, 5, 9);
    expect(
      crossing9.map((f) => f.name),
      containsAll(['Indomitable', 'Tactical Master']),
    );
  });

  test('classFeaturesForLevelUp never re-grants a feature already present', () {
    final jarson = buildSampleJarson(); // already has Extra Attack at level 9
    final regranted = rules.classFeaturesForLevelUp(jarson, 3, 9);
    expect(regranted.any((f) => f.name == 'Extra Attack'), isFalse);
  });

  test('resolvePendingChoice removes the choice, grants the feat, and applies ability deltas', () {
    final jarson = buildSampleJarson();
    final choice = PendingChoice(
      id: 'test-1',
      label: 'Level 4: Ability Score Improvement',
    );
    jarson.pendingChoices = [choice];
    final beforeCon = jarson.abilityScores.con;

    rules.resolvePendingChoice(
      jarson,
      'test-1',
      GrantedFeature(name: 'Ability Score Improvement', source: 'feat'),
      abilityScoreDeltas: {'con': 2},
    );

    expect(jarson.pendingChoices, isEmpty);
    expect(
      jarson.feats.any((f) => f.name == 'Ability Score Improvement'),
      isTrue,
    );
    expect(jarson.abilityScores.con, beforeCon + 2);
    expect(jarson.history, hasLength(1));
    expect(jarson.history.first.label, contains('Ability Score Improvement'));
    expect(jarson.history.first.detail, contains('CON'));
    expect(
      jarson.history.first.detail,
      contains('$beforeCon → ${beforeCon + 2}'),
    );
  });

  test('grantFeat logs a history entry even without ability score deltas', () {
    final jarson = buildSampleJarson();
    rules.grantFeat(jarson, GrantedFeature(name: 'Alert', source: 'feat'));
    expect(jarson.feats.any((f) => f.name == 'Alert'), isTrue);
    expect(jarson.history, hasLength(1));
    expect(jarson.history.first.label, 'Feat: Alert (Level ${jarson.level})');
    expect(jarson.history.first.detail, isNull);
  });

  test(
    'setAbilityScores updates the scores and logs only what actually changed',
    () {
      final jarson = buildSampleJarson();
      final before = jarson.abilityScores;
      rules.setAbilityScores(
        jarson,
        AbilityScores(
          str: before.str,
          dex: before.dex + 2,
          con: before.con,
          intel: before.intel,
          wis: before.wis,
          cha: before.cha,
        ),
        label: 'Belt of Giant Strength',
      );
      expect(jarson.abilityScores.dex, before.dex + 2);
      expect(jarson.history, hasLength(1));
      expect(jarson.history.first.label, 'Belt of Giant Strength');
      expect(
        jarson.history.first.detail,
        '${'DEX'} ${before.dex} → ${before.dex + 2}',
      );
    },
  );

  test('setAbilityScores logs nothing when nothing actually changed', () {
    final jarson = buildSampleJarson();
    rules.setAbilityScores(jarson, jarson.abilityScores);
    expect(jarson.history, isEmpty);
  });

  test('logHistory appends oldest-first', () {
    final jarson = buildSampleJarson();
    rules.logHistory(jarson, 'First');
    rules.logHistory(jarson, 'Second');
    expect(jarson.history.map((h) => h.label), ['First', 'Second']);
  });

  test('liveFeatureText prefers the real SRD text over a stale stored desc (Remarkable Athlete)', () {
    final jarson = buildSampleJarson();
    final stale = jarson.features.firstWhere(
      (f) => f.name == 'Remarkable Athlete',
    );
    // Jarson's sample data still carries the pre-port, 2014-style desc.
    expect(stale.desc, contains('half your Proficiency Bonus'));

    final live = rules.liveFeatureText(jarson, stale);
    expect(live, isNot(contains('half your Proficiency Bonus')));
    expect(live, contains('Advantage on Initiative rolls'));
  });

  test('liveFeatureText falls back to the stored desc for an uncataloged/homebrew feature', () {
    final jarson = buildSampleJarson();
    final homebrew = GrantedFeature(
      name: 'Definitely Not A Real Feature',
      source: 'homebrew',
      desc: 'Custom text.',
    );
    expect(rules.liveFeatureText(jarson, homebrew), 'Custom text.');
  });

  test('armorClassFromFormula handles light (uncapped Dex), medium (capped), and heavy (flat) armor', () {
    expect(
      rules.armorClassFromFormula('11 + Dex modifier', 3),
      14,
    ); // light: full Dex
    expect(
      rules.armorClassFromFormula('11 + Dex modifier', -1),
      10,
    ); // light: negative Dex too
    expect(
      rules.armorClassFromFormula('15 + Dex modifier (max 2)', 3),
      17,
    ); // medium: Dex capped at 2
    expect(
      rules.armorClassFromFormula('15 + Dex modifier (max 2)', 1),
      16,
    ); // medium: under the cap, uses actual Dex
    expect(
      rules.armorClassFromFormula('18', 5),
      18,
    ); // heavy: Dex ignored entirely
  });

  test(
    "armorClassFor matches Jarson's known AC of 18 from Half Plate + Shield",
    () {
      final jarson = buildSampleJarson();
      // Half Plate: 15 + Dex modifier (max 2). Jarson's Dex is 12 (+1 mod),
      // under the cap, so 15 + 1 = 16, plus the Shield's flat +2 = 18.
      expect(rules.armorClassFor(jarson), 18);
      // Medium, not Heavy - matters for Heavy-armor-gated effects like
      // Heavy Armor Master, which shouldn't apply to him while wearing it.
      expect(jarson.equippedArmor?.category, 'Medium');
    },
  );

  test('armorClassOverride wins over the computed value when set', () {
    final jarson = buildSampleJarson();
    jarson.armorClassOverride = 25;
    expect(rules.armorClassFor(jarson), 25);
  });

  const secondWindKey = 'srd-2024_fighter-class_Second Wind';
  const actionSurgeKey = 'srd-2024_fighter-class_Action Surge';
  const indomitableKey = 'srd-2024_fighter-class_Indomitable';
  const breathWeaponKey = 'srd-2024_dragonborn-species_Breath Weapon';

  test('recalculateClassResources matches the real Fighter level table (classes.json)', () {
    final jarson = buildSampleJarson();

    // Second Wind scales: 2 uses at 1-3, 3 at 4-9, 4 at 10+ - not the flat
    // "1" the very first mockup assumed.
    for (final (level, expectedSecondWind) in [
      (1, 2),
      (3, 2),
      (4, 3),
      (9, 3),
      (10, 4),
    ]) {
      jarson.level = level;
      rules.recalculateClassResources(jarson);
      final secondWind = jarson.resources.firstWhere(
        (r) => r.key == secondWindKey,
      );
      expect(
        secondWind.max,
        expectedSecondWind,
        reason: 'Second Wind at level $level',
      );
    }

    // Action Surge isn't unlocked at all below level 2 (matches the web
    // app: an un-unlocked threshold resource is omitted, not shown as
    // 0/0), then 1 use at 2-16, 2 uses at 17+.
    jarson.level = 1;
    rules.recalculateClassResources(jarson);
    expect(jarson.resources.where((r) => r.key == actionSurgeKey), isEmpty);
    for (final (level, expected) in [(2, 1), (9, 1), (17, 2)]) {
      jarson.level = level;
      rules.recalculateClassResources(jarson);
      final actionSurge = jarson.resources.firstWhere(
        (r) => r.key == actionSurgeKey,
      );
      expect(actionSurge.max, expected, reason: 'Action Surge at level $level');
    }

    // Indomitable: not unlocked below 9, 1 at 9-12, 2 at 13-16, 3 at 17+.
    jarson.level = 8;
    rules.recalculateClassResources(jarson);
    expect(jarson.resources.where((r) => r.key == indomitableKey), isEmpty);
    for (final (level, expected) in [(9, 1), (13, 2), (17, 3)]) {
      jarson.level = level;
      rules.recalculateClassResources(jarson);
      final indomitable = jarson.resources.firstWhere(
        (r) => r.key == indomitableKey,
      );
      expect(indomitable.max, expected, reason: 'Indomitable at level $level');
    }
  });

  test('recalculateClassResources also scales the Dragonborn species resource (Breath Weapon) with Proficiency Bonus', () {
    final jarson = buildSampleJarson();
    for (final (level, expectedMax) in [(1, 2), (5, 3), (9, 4), (17, 6)]) {
      jarson.level = level;
      rules.recalculateClassResources(jarson);
      final breathWeapon = jarson.resources.firstWhere(
        (r) => r.key == breathWeaponKey,
      );
      expect(
        breathWeapon.max,
        expectedMax,
        reason: 'Breath Weapon at level $level',
      );
    }
  });

  test('recalculateClassResources clamps used-but-now-invalid uses down to the new max', () {
    final jarson = buildSampleJarson();
    jarson.resources.firstWhere((r) => r.key == secondWindKey).used = 3;

    jarson.level = 1; // Second Wind max drops from 3 to 2 at level 1
    rules.recalculateClassResources(jarson);

    final secondWind = jarson.resources.firstWhere(
      (r) => r.key == secondWindKey,
    );
    expect(secondWind.max, 2);
    expect(secondWind.used, 2); // was 3, clamped down
  });

  test('recalculateClassResources drops an unlocked-then-un-unlocked resource rather than leaving it stale', () {
    final jarson = buildSampleJarson();
    jarson.level = 17; // Action Surge and Indomitable both unlocked here
    rules.recalculateClassResources(jarson);
    expect(jarson.resources.where((r) => r.key == actionSurgeKey), isNotEmpty);

    jarson.level = 1; // level corrected back down below their thresholds
    rules.recalculateClassResources(jarson);
    expect(jarson.resources.where((r) => r.key == actionSurgeKey), isEmpty);
    expect(jarson.resources.where((r) => r.key == indomitableKey), isEmpty);
  });

  test(
    'maxHpForLevel matches Jarson\'s real numbers (d10, Con +2, level 9 -> 76)',
    () {
      expect(rules.maxHpForLevel(die: 'd10', conModifier: 2, level: 9), 76);
    },
  );

  test('recalculateHp is idempotent and clamps current HP/Hit Dice to the new totals', () {
    final jarson = buildSampleJarson();
    jarson.currentHp = 10;
    jarson.hitDiceSpent = 9;

    jarson.level = 5;
    rules.recalculateHp(jarson);

    expect(
      jarson.maxHp,
      rules.maxHpForLevel(die: 'd10', conModifier: 2, level: 5),
    );
    expect(jarson.hitDiceTotal, 5);
    expect(jarson.currentHp, 10); // below the new max, so untouched
    expect(jarson.hitDiceSpent, 5); // was 9, clamped down to the new total

    final before = jarson.maxHp;
    rules.recalculateHp(jarson);
    expect(
      jarson.maxHp,
      before,
    ); // calling it again at the same level changes nothing
  });

  test('subclassPendingChoices does nothing before level 3', () {
    final jarson = buildSampleJarson();
    jarson.subclassKey = null;
    jarson.pendingChoices = [];

    expect(rules.subclassPendingChoices(jarson, 1, 2), isEmpty);
  });

  test('subclassPendingChoices surfaces a choice on crossing level 3, never auto-assigning', () {
    final jarson = buildSampleJarson();
    jarson.subclassKey = null;
    jarson.classLabel = 'Lv.3 Dragonborn Fighter';
    jarson.features = [];
    jarson.pendingChoices = [];

    final choices = rules.subclassPendingChoices(jarson, 2, 3);

    expect(choices.length, 1);
    expect(choices.first.label, contains('Level 3'));
    expect(choices.first.kind, 'subclass');
    // Nothing is assigned or granted just from surfacing the choice.
    expect(jarson.subclassKey, isNull);
    expect(jarson.features, isEmpty);
  });

  test('subclassPendingChoices never duplicates an already-pending choice, and never fires once resolved', () {
    final jarson = buildSampleJarson();
    jarson.subclassKey = null;
    jarson.pendingChoices = [];

    final first = rules.subclassPendingChoices(jarson, 2, 3);
    jarson.pendingChoices = first;
    expect(rules.subclassPendingChoices(jarson, 2, 3), isEmpty);

    jarson.subclassKey = 'srd-2024_champion-subclass'; // now resolved
    expect(rules.subclassPendingChoices(jarson, 2, 3), isEmpty);
  });

  test('resolveSubclassChoice assigns Champion, updates classLabel, and grants reached features only', () {
    final jarson = buildSampleJarson();
    jarson.level = 3;
    jarson.subclassKey = null;
    jarson.classLabel = 'Lv.3 Dragonborn Fighter';
    jarson.features = [];
    jarson.pendingChoices = [
      PendingChoice(
        id: 'sub-1',
        label: 'Level 3: Fighter Subclass',
        kind: 'subclass',
      ),
    ];

    rules.resolveSubclassChoice(jarson, 'sub-1', 'srd-2024_champion-subclass');

    expect(jarson.pendingChoices, isEmpty);
    expect(jarson.subclassKey, 'srd-2024_champion-subclass');
    expect(jarson.classLabel, contains('Champion'));
    expect(
      jarson.features.map((f) => f.name),
      containsAll(['Improved Critical', 'Remarkable Athlete']),
    );
    expect(jarson.features.every((f) => f.source == 'subclass'), isTrue);
    // Level 7's Additional Fighting Style hasn't been reached yet.
    expect(
      jarson.features.any((f) => f.name == 'Additional Fighting Style'),
      isFalse,
    );
    expect(jarson.history.last.label, contains('Subclass chosen: Champion'));
    expect(jarson.history.last.detail, contains('New features:'));
    expect(jarson.history.last.detail, contains('Improved Critical'));
    expect(jarson.history.last.detail, contains('Remarkable Athlete'));
  });

  test('resolveSubclassChoice backfills every reached subclass feature on a big level jump, surfacing choice-driven ones as a Pending Choice instead of auto-granting them', () {
    final jarson = buildSampleJarson();
    jarson.level = 10;
    jarson.subclassKey = null;
    jarson.features = [];
    jarson.pendingChoices = [
      PendingChoice(
        id: 'sub-1',
        label: 'Level 3: Fighter Subclass',
        kind: 'subclass',
      ),
    ];

    rules.resolveSubclassChoice(jarson, 'sub-1', 'srd-2024_champion-subclass');

    expect(
      jarson.features.map((f) => f.name),
      containsAll([
        'Improved Critical',
        'Remarkable Athlete',
        'Heroic Warrior',
      ]),
    );
    // Additional Fighting Style (level 7) is choice-driven - never silently
    // auto-granted, even on a big backfilling jump like this one.
    expect(
      jarson.features.any((f) => f.name == 'Additional Fighting Style'),
      isFalse,
    );
    expect(
      jarson.pendingChoices.map((p) => p.label),
      contains('Level 7: Additional Fighting Style'),
    );
    expect(
      jarson.pendingChoices
          .firstWhere((p) => p.label == 'Level 7: Additional Fighting Style')
          .featCategory,
      'Fighting Style Feat',
    );
    expect(jarson.history.last.detail, contains('New choices to make:'));
    expect(
      jarson.history.last.detail,
      contains('Level 7: Additional Fighting Style'),
    );
  });

  test('levelUpOneLevel crossing Champion\'s level 7 surfaces Additional Fighting Style as a Pending Choice, not a silently-granted feature', () {
    final jarson = buildSampleJarson();
    // Champion's subclass key is already set on the sample data - rewind
    // to level 6 (just below the level 7 feature) to exercise an ordinary
    // one-level-at-a-time advance, the normal "Level Up" button's path.
    jarson.level = 6;

    final summary = rules.levelUpOneLevel(jarson);

    expect(summary.newLevel, 7);
    expect(
      jarson.features.any((f) => f.name == 'Additional Fighting Style'),
      isFalse,
    );
    expect(
      jarson.pendingChoices.map((p) => p.label),
      contains('Level 7: Additional Fighting Style'),
    );
    expect(
      summary.newPendingChoices.map((p) => p.label),
      contains('Level 7: Additional Fighting Style'),
    );
  });

  test('repairMissingFeatChoices converts an already-granted inert Additional Fighting Style feature (from before the level-up fix) into a resolvable Pending Choice', () {
    final jarson = buildSampleJarson();
    // Reproduces exactly what the old buggy subclassFeaturesForLevelUp did:
    // auto-granted the choice-driven feature as a plain inert feature, with
    // no Pending Choice ever created for it.
    jarson.features = [
      ...jarson.features,
      GrantedFeature(
        name: 'Additional Fighting Style',
        source: 'subclass',
        desc: 'stale desc',
      ),
    ];

    rules.repairMissingFeatChoices(jarson);

    expect(
      jarson.features.any((f) => f.name == 'Additional Fighting Style'),
      isFalse,
    );
    expect(
      jarson.pendingChoices.map((p) => p.label),
      contains('Level 7: Additional Fighting Style'),
    );
    expect(jarson.history.last.label, contains('Data repair'));

    // Idempotent - calling it again (e.g. every app load) does nothing more.
    final historyLengthAfterFirstRepair = jarson.history.length;
    rules.repairMissingFeatChoices(jarson);
    expect(jarson.history.length, historyLengthAfterFirstRepair);
  });

  test('repairMissingFeatChoices does nothing for a character with no stale inert choice feature', () {
    final jarson = buildSampleJarson();
    final before = jarson.history.length;

    rules.repairMissingFeatChoices(jarson);

    expect(jarson.history.length, before);
  });

  test('subclassFeaturesForLevelUp does nothing until a subclass is actually chosen', () {
    final jarson = buildSampleJarson();
    jarson.subclassKey = null;
    jarson.features = [];

    rules.subclassFeaturesForLevelUp(jarson, 9, 10);

    expect(jarson.features, isEmpty); // never auto-assigns, even at level 10
  });

  test('subclassFeaturesForLevelUp only grants newly-crossed features once already chosen, never re-granting', () {
    final jarson = buildSampleJarson(); // already Champion, level 9
    final beforeCount = jarson.features.length;

    rules.subclassFeaturesForLevelUp(jarson, 9, 10);
    expect(jarson.features.length, beforeCount + 1); // just Heroic Warrior
    expect(jarson.features.last.name, 'Heroic Warrior');

    rules.subclassFeaturesForLevelUp(jarson, 10, 15);
    expect(jarson.features.any((f) => f.name == 'Superior Critical'), isTrue);
    // Re-running an already-crossed range never duplicates.
    final countAt15 = jarson.features.length;
    rules.subclassFeaturesForLevelUp(jarson, 9, 15);
    expect(jarson.features.length, countAt15);
  });

  test('featChoicePendingChoices surfaces Fighting Style at level 1, but not Ability Score Improvement (handled separately)', () {
    final jarson = buildSampleJarson();
    jarson.pendingChoices = [];

    final choices = rules.featChoicePendingChoices(jarson, 0, 1);

    expect(choices.length, 1);
    expect(choices.first.label, 'Level 1: Fighting Style');
    expect(choices.first.featCategory, 'Fighting Style Feat');
  });

  test('feat ability score increases: read from SRD feat text, or set '
      "on a homebrew feat, and capped at the feat's maximum", () {
    final grappler = rules.featAbilityIncrease('Grappler')!;
    expect(grappler.abilities, ['str', 'dex']);
    expect((grappler.amount, grappler.max), (1, 20));
    final boon = rules.featAbilityIncrease('Boon of Combat Prowess')!;
    expect(boon.abilities, hasLength(6));
    expect(boon.max, 30);
    expect(rules.featAbilityIncrease('Boon of Spell Recall')!.abilities, [
      'int',
      'wis',
      'cha',
    ]);
    expect(rules.featAbilityIncrease('Ability Score Improvement'), isNull);
    expect(rules.featAbilityIncrease('Alert'), isNull);

    final entry = homebrewRepo.create('feat', 'Great Weapon Master');
    homebrewRepo.update(
      HomebrewEntry(
        id: entry.id,
        kind: entry.kind,
        name: entry.name,
        source: 'official',
        data: const {
          'abilityIncrease': ['str'],
        },
      ),
    );
    final gwm = rules.featAbilityIncrease('Great Weapon Master')!;
    expect(gwm.abilities, ['str']);
    expect((gwm.amount, gwm.max), (1, 20));

    final jarson = buildSampleJarson();
    jarson.feats.removeWhere((f) => f.name == 'Great Weapon Master');
    jarson.abilityScores = const AbilityScores(
      str: 20,
      dex: 12,
      con: 14,
      intel: 10,
      wis: 10,
      cha: 10,
    );
    rules.grantFeat(
      jarson,
      GrantedFeature(name: 'Great Weapon Master', source: 'feat'),
      abilityScoreDeltas: {'str': 1},
    );
    expect(jarson.abilityScores.str, 20); // already at the maximum

    rules.grantFeat(
      jarson,
      GrantedFeature(name: 'Boon of Combat Prowess', source: 'feat'),
      abilityScoreDeltas: {'str': 1},
    );
    expect(jarson.abilityScores.str, 21); // an Epic Boon goes to 30
  });

  test('Great Weapon Master (a homebrew "official" entry, since it\'s a '
      'real 2024 feat NOT in the free SRD - see _builtinFeatEffects\' doc '
      'comment) only adds its Proficiency Bonus damage with a Heavy '
      'weapon', () {
    final jarson = buildSampleJarson();
    final entry = homebrewRepo.create('feat', 'Great Weapon Master');
    homebrewRepo.update(
      HomebrewEntry(
        id: entry.id,
        kind: entry.kind,
        name: entry.name,
        source: 'official',
        effects: const [
          Effect(
            target: 'damageRoll',
            formula: 'Proficiency Bonus',
            condition: 'heavyWeapon',
          ),
        ],
      ),
    );
    final greatsword = jarson.weapons.firstWhere((w) => w.name == 'Greatsword');
    final prof = rules.proficiencyBonusForLevel(jarson.level);

    final withFeat = rules.damageFor(jarson, greatsword);
    expect(withFeat.breakdown, contains('Great Weapon Master'));
    expect(
      withFeat.breakdown,
      contains('Great Weapon Master ${rules.formatModifier(prof)}'),
    );

    // Non-Heavy weapon: the feat's effect is conditioned on 'heavyWeapon'
    // and shouldn't fire even though the feat is still on the sheet.
    // Jarson's seed weapons (Greatsword, Sword of the Failed Dragon
    // Slayer) are both Heavy, so build a light one directly.
    final dagger = Weapon(
      name: 'Dagger',
      damageDice: '1d4',
      damageType: 'piercing',
      properties: const ['Finesse', 'Light', 'Thrown'],
      proficient: true,
      finesse: true,
    );
    expect(dagger.isHeavy, isFalse);
    expect(
      rules.damageFor(jarson, dagger).breakdown,
      isNot(contains('Great Weapon Master')),
    );

    jarson.feats.removeWhere((f) => f.name == 'Great Weapon Master');
    expect(
      rules.damageFor(jarson, greatsword).breakdown,
      isNot(contains('Great Weapon Master')),
    );
  });

  test('isSpellcastingClass/spellcastingAbilityForClass recognize the 8 SRD casters and reject Fighter', () {
    expect(rules.isSpellcastingClass('srd-2024_wizard-class'), isTrue);
    expect(rules.spellcastingAbilityForClass('srd-2024_wizard-class'), 'int');
    expect(rules.spellcastingAbilityForClass('srd-2024_cleric-class'), 'wis');
    expect(rules.isSpellcastingClass('srd-2024_fighter-class'), isFalse);
    expect(rules.spellcastingAbilityForClass('srd-2024_fighter-class'), isNull);
  });

  test(
    'enableSpellcasting sets the right ability and level-1 slots for a Wizard',
    () {
      final wizard = buildSampleJarson();
      wizard.classKey = 'srd-2024_wizard-class';
      wizard.level = 1;
      wizard.spellcasting = null;

      rules.enableSpellcasting(wizard);

      expect(wizard.spellcasting, isNotNull);
      expect(wizard.spellcasting!.ability, 'int');
      expect(wizard.spellcasting!.slots[1]?.max, 2);
      expect(wizard.spellcasting!.slots[1]?.used, 0);
    },
  );

  test('recalculateSpellSlots grows/shrinks slots with level and clamps used down, for both full-caster and Pact Magic shapes', () {
    final wizard = buildSampleJarson();
    wizard.classKey = 'srd-2024_wizard-class';
    wizard.level = 1;
    rules.enableSpellcasting(wizard);
    wizard.spellcasting!.slots[1]!.used = 2; // both level-1 slots spent

    wizard.level = 5;
    rules.recalculateSpellSlots(wizard);
    expect(wizard.spellcasting!.slots.keys.toSet(), {1, 2, 3});
    expect(wizard.spellcasting!.slots[1]!.max, 4);
    expect(wizard.spellcasting!.slots[1]!.used, 2); // carried over, not reset
    expect(wizard.spellcasting!.slots[3]!.used, 0); // newly unlocked

    final warlock = buildSampleJarson();
    warlock.classKey = 'srd-2024_warlock-class';
    warlock.level = 1;
    rules.enableSpellcasting(warlock);
    expect(warlock.spellcasting!.ability, 'cha');
    expect(warlock.spellcasting!.slots.keys.toSet(), {1});
    expect(warlock.spellcasting!.slots[1]!.max, 1);

    warlock.spellcasting!.slots[1]!.used = 1;
    warlock.level = 5; // Pact Magic slots become 2 level-3 slots, not level-1
    rules.recalculateSpellSlots(warlock);
    expect(warlock.spellcasting!.slots.containsKey(1), isFalse);
    expect(warlock.spellcasting!.slots[3]!.max, 2);
    expect(warlock.spellcasting!.slots[3]!.used, 0);
  });

  test(
    'applyLongRest fully restores spell slots, matching every other resource',
    () {
      final wizard = buildSampleJarson();
      wizard.classKey = 'srd-2024_wizard-class';
      wizard.level = 5;
      rules.enableSpellcasting(wizard);
      for (final slot in wizard.spellcasting!.slots.values) {
        slot.used = slot.max;
      }

      rules.applyLongRest(wizard);

      expect(
        wizard.spellcasting!.slots.values.every((s) => s.used == 0),
        isTrue,
      );
    },
  );

  test('setTempHp replaces rather than adds, and clamps at 0', () {
    final jarson = buildSampleJarson();
    rules.setTempHp(jarson, 10);
    expect(jarson.tempHp, 10);

    // A second grant replaces, it never stacks on top (SRD: "They Don't
    // Stack") - even a smaller amount overwrites, since the UI is what
    // surfaces the current value for the player to decide against.
    rules.setTempHp(jarson, 4);
    expect(jarson.tempHp, 4);

    rules.setTempHp(jarson, -5);
    expect(jarson.tempHp, 0);
  });

  test('applyDamageOrHeal spends Temporary HP before real HP, carrying leftover damage over', () {
    final jarson = buildSampleJarson();
    jarson.currentHp = jarson.maxHp;
    rules.setTempHp(jarson, 5);

    // 3 damage - fully absorbed by tempHp, real HP untouched.
    rules.applyDamageOrHeal(jarson, -3);
    expect(jarson.tempHp, 2);
    expect(jarson.currentHp, jarson.maxHp);

    // 7 more damage - depletes the remaining 2 tempHp, 5 carries over to
    // real HP.
    rules.applyDamageOrHeal(jarson, -7);
    expect(jarson.tempHp, 0);
    expect(jarson.currentHp, jarson.maxHp - 5);
  });

  test('restPreview lists what each rest would recover, without changing '
      'the character', () {
    final jarson = buildSampleJarson();
    for (final r in jarson.resources) {
      r.used = 0;
    }
    jarson.currentHp = jarson.maxHp;
    jarson.tempHp = 0;
    jarson.hitDiceSpent = 0;
    jarson.exhaustionLevel = 0;
    expect(rules.restPreview(jarson, longRest: true), isEmpty);

    final secondWind = jarson.resources.firstWhere(
      (r) => r.name == 'Second Wind',
    );
    final actionSurge = jarson.resources.firstWhere(
      (r) => r.name == 'Action Surge',
    );
    secondWind.used = 1;
    actionSurge.used = 1;
    jarson.currentHp = jarson.maxHp - 10;

    final short = rules.restPreview(jarson, longRest: false);
    expect(short, [
      'Second Wind: ${secondWind.max - 1} → ${secondWind.max} of '
          '${secondWind.max} left',
    ]);

    final long = rules.restPreview(jarson, longRest: true);
    expect(
      long,
      contains(
        'HP: ${jarson.maxHp - 10} → ${jarson.maxHp} of '
        '${jarson.maxHp}',
      ),
    );
    expect(long.any((l) => l.startsWith('Action Surge: 0 → 1')), isTrue);
    expect(long.any((l) => l.startsWith('Second Wind')), isTrue);

    // Just a preview - nothing was actually recovered.
    expect(secondWind.used, 1);
    expect(jarson.currentHp, jarson.maxHp - 10);
  });

  test('applyLongRest clears Temporary HP', () {
    final jarson = buildSampleJarson();
    rules.setTempHp(jarson, 8);
    rules.applyLongRest(jarson);
    expect(jarson.tempHp, 0);
  });

  test('innateAttackInfo scales Breath Weapon dice count with level exactly '
      'at the real thresholds (1d10/2d10/3d10/4d10 at 1/5/11/17), never '
      'stale, via the generalized levelDice breakpoints', () {
    final jarson = buildSampleJarson();
    final breathWeapon = jarson.innateAttacks.firstWhere(
      (a) => a.name == 'Breath Weapon',
    );
    for (final (level, expectedDice) in [
      (1, 1),
      (4, 1),
      (5, 2),
      (9, 2), // level 9 - must stay 2d10, not "go stale" at 3d10
      (10, 2),
      (11, 3),
      (16, 3),
      (17, 4),
      (20, 4),
    ]) {
      jarson.level = level;
      final info = rules.innateAttackInfo(jarson, breathWeapon);
      expect(
        info.diceCount,
        expectedDice,
        reason: 'Breath Weapon dice at level $level',
      );
      expect(info.dieType, 'd10');
    }
  });

  test("innateAttackInfo computes Breath Weapon's save DC from its formula "
      '(8 + Proficiency Bonus + Constitution modifier)', () {
    final jarson = buildSampleJarson(); // level 9, Con 14 (+2 mod)
    final breathWeapon = jarson.innateAttacks.firstWhere(
      (a) => a.name == 'Breath Weapon',
    );
    final info = rules.innateAttackInfo(jarson, breathWeapon);
    final prof = rules.proficiencyBonusForLevel(jarson.level);
    expect(info.saveDc, 8 + prof + 2);
  });

  test('evaluateFormula: literal int, Proficiency Bonus, an ability modifier, a real two-term DC formula, subtraction, a bare negative, and an unrecognized term', () {
    final jarson = buildSampleJarson(); // level 9 (Prof +4), Con 14 (+2)
    expect(rules.evaluateFormula('3', jarson), 3);
    expect(
      rules.evaluateFormula('Proficiency Bonus', jarson),
      rules.proficiencyBonusForLevel(jarson.level),
    );
    expect(rules.evaluateFormula('Constitution modifier', jarson), 2);
    expect(
      rules.evaluateFormula(
        '8 + Proficiency Bonus + Constitution modifier',
        jarson,
      ),
      8 + rules.proficiencyBonusForLevel(jarson.level) + 2,
    );
    expect(rules.evaluateFormula('8 - 1', jarson), 7);
    // A cursed item's penalty - never exercised by a real example above,
    // worth its own assertion.
    expect(rules.evaluateFormula('-1', jarson), -1);
    expect(rules.evaluateFormula('not a real formula', jarson), 0);
  });

  test(
    'sumEffects reproduces the old hardcoded Alert initiative bonus exactly',
    () {
      // Jarson already has Alert granted (sample_data.dart) - don't add a
      // second one, that would double-count the effect.
      final jarson = buildSampleJarson();
      expect(jarson.feats.where((f) => f.name == 'Alert').length, 1);
      final withAlert = rules.initiativeModifier(jarson);

      jarson.feats.removeWhere((f) => f.name == 'Alert');
      final withoutAlert = rules.initiativeModifier(jarson);

      expect(
        withAlert - withoutAlert,
        rules.proficiencyBonusForLevel(jarson.level),
      );
    },
  );

  test('a homebrew feat Effect on a saving throw actually moves savingThrowModifier', () {
    final jarson = buildSampleJarson();
    homebrewRepo.entries.add(
      HomebrewEntry(
        id: 'homebrew_test-wis-feat',
        kind: 'feat',
        name: 'Test Wisdom Ward',
        effects: const [Effect(target: 'save:wis', formula: '2')],
      ),
    );
    jarson.feats.add(GrantedFeature(name: 'Test Wisdom Ward', source: 'feat'));

    final withFeat = rules.savingThrowModifier(jarson, 'wis');
    jarson.feats.removeWhere((f) => f.name == 'Test Wisdom Ward');
    final withoutFeat = rules.savingThrowModifier(jarson, 'wis');

    expect(withFeat - withoutFeat, 2);
  });

  test('a homebrew magicItem Effect only applies while the item is attuned, and tiers add rather than replace (Bloodied Boots)', () {
    final jarson = buildSampleJarson();
    jarson.currentHp = jarson.maxHp;
    homebrewRepo.entries.add(
      HomebrewEntry(
        id: 'homebrew_test-boots',
        kind: 'magicItem',
        name: 'Test Bloodied Boots',
        effects: const [
          Effect(target: 'damageRoll', formula: '1', condition: 'anyDamage'),
          Effect(target: 'damageRoll', formula: '1', condition: 'bloodied'),
        ],
      ),
    );
    final boots = InventoryEntry(name: 'Test Bloodied Boots', quantity: 1);
    jarson.inventory = [...jarson.inventory, boots];
    final greatsword = jarson.weapons.firstWhere((w) => w.name == 'Greatsword');

    // Not attuned yet - no effect at all, even below max HP.
    jarson.currentHp = jarson.maxHp - 1;
    expect(
      rules.damageFor(jarson, greatsword).breakdown,
      isNot(contains('Test Bloodied Boots')),
    );

    boots.attuned = true;

    // Full HP: attuned, but neither tier's condition is met.
    jarson.currentHp = jarson.maxHp;
    expect(
      rules.damageFor(jarson, greatsword).breakdown,
      isNot(contains('Test Bloodied Boots')),
    );

    // Hurt but not Bloodied: +1.
    jarson.currentHp = jarson.maxHp - 1;
    var breakdown = rules.damageFor(jarson, greatsword).breakdown;
    expect(breakdown, contains('Test Bloodied Boots +1'));

    // Exactly half HP - Bloodied per the Rules Glossary ("half its Hit
    // Points or fewer") - both tiers fire, summing to +2.
    jarson.currentHp = (jarson.maxHp / 2).floor();
    final total = rules
        .matchingEffects(jarson, 'damageRoll', weapon: greatsword)
        .where((e) => e.$1 == 'Test Bloodied Boots')
        .fold(0, (a, e) => a + e.$2);
    expect(total, 2);

    // Un-attuning drops it back to nothing, even while Bloodied.
    boots.attuned = false;
    expect(
      rules.damageFor(jarson, greatsword).breakdown,
      isNot(contains('Test Bloodied Boots')),
    );
  });

  test('a homebrew magic weapon\'s effects need attunement only if it requires it, and its attack/damage effects only count for that weapon', () {
    final jarson = buildSampleJarson();
    homebrewRepo.entries.add(
      HomebrewEntry(
        id: 'homebrew_test-sword',
        kind: 'weapon',
        name: 'Sword of the Failed Dragon Slayer',
        effects: const [
          Effect(target: 'damageRoll', formula: '1'),
          Effect(target: 'initiative', formula: '2'),
        ],
        data: const {'damageDice': '2d6', 'requiresAttunement': true},
      ),
    );
    final carried = InventoryEntry(
      name: 'Sword of the Failed Dragon Slayer',
      quantity: 1,
    );
    jarson.inventory = [...jarson.inventory, carried];
    final sword = jarson.weapons.firstWhere(
      (w) => w.name == 'Sword of the Failed Dragon Slayer',
    );
    final greatsword = jarson.weapons.firstWhere((w) => w.name == 'Greatsword');

    // Requires attunement, not attuned - nothing.
    expect(rules.sumEffects(jarson, 'damageRoll', weapon: sword), 0);
    expect(
      rules.matchingEffects(jarson, 'initiative').map((e) => e.$1),
      isNot(contains('Sword of the Failed Dragon Slayer')),
    );

    carried.attuned = true;
    expect(rules.sumEffects(jarson, 'damageRoll', weapon: sword), 1);
    // The damage bonus is the sword's own, not every weapon's...
    expect(rules.sumEffects(jarson, 'damageRoll', weapon: greatsword), 0);
    // ...but a non-attack effect applies to the character as usual.
    expect(
      rules.matchingEffects(jarson, 'initiative').map((e) => e.$1),
      contains('Sword of the Failed Dragon Slayer'),
    );

    // One that doesn't require attunement works just by being carried.
    homebrewRepo.entries.removeWhere((e) => e.id == 'homebrew_test-sword');
    homebrewRepo.entries.add(
      HomebrewEntry(
        id: 'homebrew_test-sword',
        kind: 'weapon',
        name: 'Sword of the Failed Dragon Slayer',
        effects: const [Effect(target: 'damageRoll', formula: '1')],
        data: const {'damageDice': '2d6'},
      ),
    );
    carried.attuned = false;
    expect(rules.sumEffects(jarson, 'damageRoll', weapon: sword), 1);
  });

  test('a homebrew feat named exactly like a built-in one overrides it, rather than being shadowed', () {
    // Jarson already has Alert granted (sample_data.dart) - don't add a
    // second one, that would double-count the effect.
    final jarson = buildSampleJarson();
    expect(jarson.feats.where((f) => f.name == 'Alert').length, 1);
    homebrewRepo.entries.add(
      HomebrewEntry(
        id: 'homebrew_test-alert-override',
        kind: 'feat',
        name: 'Alert',
        effects: const [Effect(target: 'save:wis', formula: '3')],
      ),
    );

    // The homebrew version's save:wis effect applies...
    final baseWis = rules.abilityModifier(jarson.abilityScores.wis);
    expect(rules.savingThrowModifier(jarson, 'wis'), baseWis + 3);
    // ...and the built-in initiative bonus does NOT (homebrew replaces,
    // not adds to, the built-in entry for the same name).
    final baseDex = rules.abilityModifier(jarson.abilityScores.dex);
    expect(rules.initiativeModifier(jarson), baseDex + jarson.initiativeBonus);
  });

  test('liveFeatureText overrides real SRD feat text with a same-named homebrew entry\'s desc', () {
    final jarson = buildSampleJarson();
    homebrewRepo.entries.add(
      HomebrewEntry(
        id: 'homebrew_test-alert-text',
        kind: 'feat',
        name: 'Alert',
        desc: 'A custom house-ruled version of Alert.',
      ),
    );
    final alert = GrantedFeature(name: 'Alert', source: 'feat');
    expect(
      rules.liveFeatureText(jarson, alert),
      'A custom house-ruled version of Alert.',
    );
  });

  test('liveFeatureText falls back to a same-named homebrew feat\'s desc for an uncataloged feat name', () {
    final jarson = buildSampleJarson();
    homebrewRepo.entries.add(
      HomebrewEntry(
        id: 'homebrew_test-custom-feat',
        kind: 'feat',
        name: 'Totally Custom Feat',
        desc: 'A completely homebrew feat with real text.',
      ),
    );
    final feat = GrantedFeature(name: 'Totally Custom Feat', source: 'feat');
    expect(
      rules.liveFeatureText(jarson, feat),
      'A completely homebrew feat with real text.',
    );
  });

  test('InnateAttack.fromJson migrates legacy flat damageDice data', () {
    // Legacy shape (pre-generalization): no levelDice/dieType/saveDcFormula
    // at all, just a flat "2d10" string - Breath Weapon's real old data.
    final breathWeapon = InnateAttack.fromJson({
      'name': 'Breath Weapon',
      'damageDice': '2d10',
      'damageType': 'Fire',
      'saveAbility': 'dex',
      'desc': 'Some desc.',
      'resourceKey': 'test-key',
    });
    expect(breathWeapon.levelDice, [
      const LevelDiceBreakpoint(level: 1, diceCount: 2),
    ]);
    expect(breathWeapon.dieType, 'd10');
    // The one legacy name this repo actually has real saved data for gets
    // the real formula default.
    expect(
      breathWeapon.saveDcFormula,
      '8 + Proficiency Bonus + Constitution modifier',
    );

    final unrelated = InnateAttack.fromJson({
      'name': 'Some Other Attack',
      'damageDice': '1d6',
      'damageType': 'Cold',
      'saveAbility': 'con',
      'desc': 'Some desc.',
      'resourceKey': 'test-key-2',
    });
    expect(unrelated.levelDice, [
      const LevelDiceBreakpoint(level: 1, diceCount: 1),
    ]);
    expect(unrelated.dieType, 'd6');
    // Any other/unknown legacy name gets '' (DC 0, visibly wrong) rather
    // than a guessed formula.
    expect(unrelated.saveDcFormula, '');
  });

  test('HomebrewEntry.toJson/fromJson round-trips desc/source/effects, and old-shape JSON loads with documented defaults', () {
    const entry = HomebrewEntry(
      id: 'homebrew_test-roundtrip',
      kind: 'feat',
      name: 'Round Trip Feat',
      desc: 'Some real text.',
      source: 'official',
      effects: [
        Effect(
          target: 'damageRoll',
          formula: 'Proficiency Bonus',
          condition: 'heavyWeapon',
        ),
      ],
    );
    final restored = HomebrewEntry.fromJson(entry.toJson());
    expect(restored.id, entry.id);
    expect(restored.kind, entry.kind);
    expect(restored.name, entry.name);
    expect(restored.desc, entry.desc);
    expect(restored.source, entry.source);
    expect(restored.effects.length, 1);
    expect(restored.effects.first.target, 'damageRoll');
    expect(restored.effects.first.formula, 'Proficiency Bonus');
    expect(restored.effects.first.condition, 'heavyWeapon');

    // Old shape: no desc/source/effects keys at all.
    final legacy = HomebrewEntry.fromJson({
      'id': 'homebrew_test-legacy',
      'kind': 'weapon',
      'name': 'Legacy Weapon',
    });
    expect(legacy.desc, '');
    expect(legacy.source, 'homebrew');
    expect(legacy.effects, isEmpty);
  });

  test('liveSpeciesResistances derives Draconic Resistance from speciesChoice - Jarson is Red, so Fire', () {
    final jarson = buildSampleJarson();
    final effects = rules.liveSpeciesResistances(jarson);

    expect(effects, hasLength(1));
    expect(effects.first.target, 'damageResistance:fire');
  });

  test('liveSpeciesResistances is empty for a non-Dragonborn or an unset ancestry choice', () {
    final jarson = buildSampleJarson();
    jarson.speciesKey = 'srd-2024_human-species';
    expect(rules.liveSpeciesResistances(jarson), isEmpty);

    jarson.speciesKey = 'srd-2024_dragonborn-species';
    jarson.speciesChoice = null;
    expect(rules.liveSpeciesResistances(jarson), isEmpty);
  });

  test('computeDamageTaken passes an unrelated damage type straight through unchanged', () {
    final jarson = buildSampleJarson();
    final result = rules.computeDamageTaken(jarson, 20, 'cold', magical: false);
    expect(result.finalAmount, 20);
    expect(result.steps, ['Raw damage: 20']);
  });

  test("computeDamageTaken halves Fire damage via Jarson's Draconic Resistance, rounded down", () {
    final jarson = buildSampleJarson();
    final result = rules.computeDamageTaken(jarson, 19, 'fire', magical: false);
    expect(result.finalAmount, 9); // (19 / 2).floor()
    expect(result.steps.last, contains('Draconic Resistance'));
    expect(result.steps.last, contains('9'));
  });

  test(
    'halfOnSave halves the raw damage as its own step, before resistance',
    () {
      final jarson = buildSampleJarson();
      // Cold: no resistance, so this isolates halfOnSave's own effect.
      final result = rules.computeDamageTaken(
        jarson,
        13,
        'cold',
        magical: false,
        halfOnSave: true,
      );
      expect(result.finalAmount, 6); // (13 / 2).floor()
      expect(result.steps, ['Raw damage: 13', 'Passed a save: half → 6']);
    },
  );

  test('halfOnSave stacks with resistance as two separate, independently-rounded halvings (order-independent)', () {
    final jarson = buildSampleJarson();
    // Fire: Jarson is resistant (Draconic Resistance) - a successful save
    // against a fire effect he's also resistant to should quarter it, not
    // just halve it once.
    final result = rules.computeDamageTaken(
      jarson,
      19,
      'fire',
      magical: false,
      halfOnSave: true,
    );
    // (19/2).floor() = 9, then (9/2).floor() = 4 - matches floor(19/4) = 4,
    // confirming the two halvings commute despite being applied as
    // separate rounded-down steps rather than one combined /4.
    expect(result.finalAmount, 4);
    expect(result.steps, [
      'Raw damage: 19',
      'Passed a save: half → 9',
      'Draconic Resistance: Resistant, half → 4',
    ]);
  });

  test("Heavy Armor Master (a homebrew official entry - it's not in the free SRD either) reduces nonmagical Bludgeoning/Piercing/Slashing damage by Proficiency Bonus while wearing Heavy armor - Jarson's is 4", () {
    final jarson = buildSampleJarson();
    _grantHeavyArmorMaster(jarson);
    jarson.equippedArmor = EquippedArmor(
      name: 'Plate Armor',
      armorClassFormula: '18',
      category: 'Heavy',
    );

    final result = rules.computeDamageTaken(
      jarson,
      10,
      'bludgeoning',
      magical: false,
    );
    expect(result.finalAmount, 6); // 10 - Proficiency Bonus (4)
    expect(result.steps.last, contains('Heavy Armor Master'));
    expect(result.steps.last, contains('-4'));

    // Magical damage bypasses it entirely.
    final magicalResult = rules.computeDamageTaken(
      jarson,
      10,
      'bludgeoning',
      magical: true,
    );
    expect(magicalResult.finalAmount, 10);

    // A damage type outside Bludgeoning/Piercing/Slashing is unaffected.
    final fireResult = rules.computeDamageTaken(
      jarson,
      10,
      'fire',
      magical: false,
    );
    // Still gets Draconic Resistance (half), just not Heavy Armor Master.
    expect(fireResult.finalAmount, 5);
    expect(
      fireResult.steps.any((s) => s.contains('Heavy Armor Master')),
      isFalse,
    );
  });

  test(
    'Heavy Armor Master does nothing without Heavy armor actually equipped',
    () {
      final jarson = buildSampleJarson();
      _grantHeavyArmorMaster(jarson);
      jarson.equippedArmor = EquippedArmor(
        name: 'Studded Leather',
        armorClassFormula: '12 + Dex modifier',
        category: 'Light',
      );

      final result = rules.computeDamageTaken(
        jarson,
        10,
        'bludgeoning',
        magical: false,
      );
      expect(result.finalAmount, 10);
    },
  );

  test('computeDamageTaken never goes negative even if reduction exceeds the (possibly already-halved) amount', () {
    final jarson = buildSampleJarson();
    _grantHeavyArmorMaster(jarson);
    jarson.equippedArmor = EquippedArmor(
      name: 'Plate Armor',
      armorClassFormula: '18',
      category: 'Heavy',
    );

    final result = rules.computeDamageTaken(
      jarson,
      2,
      'bludgeoning',
      magical: false,
    );
    expect(result.finalAmount, 0); // 2 - 4, floored at 0
  });

  test('resistance applies before reduction, matching how 5e resolves both together', () {
    final jarson = buildSampleJarson();
    _grantHeavyArmorMaster(jarson);
    jarson.equippedArmor = EquippedArmor(
      name: 'Plate Armor',
      armorClassFormula: '18',
      category: 'Heavy',
    );
    // A homebrew magic item granting resistance to Bludgeoning too, so
    // this hits both a resistance and a reduction on the same type.
    final entry = homebrewRepo.create('magicItem', 'Stoneskin Amulet');
    homebrewRepo.update(
      HomebrewEntry(
        id: entry.id,
        kind: entry.kind,
        name: entry.name,
        effects: const [
          Effect(target: 'damageResistance:bludgeoning', formula: ''),
        ],
      ),
    );
    jarson.inventory.add(
      InventoryEntry(name: 'Stoneskin Amulet', quantity: 1, attuned: true),
    );

    final result = rules.computeDamageTaken(
      jarson,
      20,
      'bludgeoning',
      magical: false,
    );
    // 20 -> half (10, resistance) -> -4 (Heavy Armor Master) -> 6.
    expect(result.finalAmount, 6);
    expect(result.steps, hasLength(3));
    expect(result.steps[1], contains('half'));
    expect(result.steps[2], contains('Heavy Armor Master'));
  });

  test('a homebrew Heavy Armor Master entry\'s formula is respected as typed, not fixed at Proficiency Bonus', () {
    final jarson = buildSampleJarson();
    _grantHeavyArmorMaster(jarson, formula: '99'); // house-ruled amount
    jarson.equippedArmor = EquippedArmor(
      name: 'Plate Armor',
      armorClassFormula: '18',
      category: 'Heavy',
    );

    final result = rules.computeDamageTaken(
      jarson,
      50,
      'piercing',
      magical: false,
    );
    expect(result.finalAmount, 0); // 50 - 99, floored at 0
  });

  test('parseToolChoice resolves Soldier\'s real "Choose one kind of Gaming Set" text to a structured requirement', () {
    final soldier = srdCatalog.backgroundsByKey.values.firstWhere(
      (b) => b.name == 'Soldier',
    );
    final req = rules.parseToolChoice(soldier.toolProficiency);
    expect(req, isNotNull);
    expect(req!.count, 1);
    expect(req.tool.name, 'Gaming Set');
    expect(req.tool.variants, contains('Dice'));
  });

  test(
    'parseToolChoice resolves Bard\'s real "Choose 3 Musical Instruments" text',
    () {
      final bard = srdCatalog.classesByKey.values.firstWhere(
        (c) => c.name == 'Bard',
      );
      final req = rules.parseToolChoice(bard.traits['Tool Proficiencies']);
      expect(req, isNotNull);
      expect(req!.count, 3);
      expect(req.tool.name, 'Musical Instrument');
      // The bundled SRD data's own casing is inconsistent here (only
      // "Bagpipes" is capitalized; the rest, including "lute", aren't) -
      // matching the real data as-is rather than a cleaned-up guess.
      expect(req.tool.variants, contains('lute'));
    },
  );

  test('parseToolChoice returns null for a fixed tool proficiency (no choice at all)', () {
    final criminal = srdCatalog.backgroundsByKey.values.firstWhere(
      (b) => b.name == 'Criminal',
    );
    expect(criminal.toolProficiency, "Thieves' Tools");
    expect(rules.parseToolChoice(criminal.toolProficiency), isNull);
  });

  test('parseToolChoice returns null (rather than a wrong answer) for a choice it can\'t cleanly resolve to one variant-bearing tool', () {
    final rogue = srdCatalog.classesByKey.values.firstWhere(
      (c) => c.name == 'Rogue',
    );
    // "Choose one type of Artisan's Tools or Musical Instrument" names
    // two different things at once - Artisan's Tools isn't itself a
    // single SrdToolRef with variants, it's many separate top-level
    // tools (Smith's Tools, Carpenter's Tools, ...). This should fall
    // back to free text in the UI rather than silently picking one.
    expect(rules.parseToolChoice(rogue.traits['Tool Proficiencies']), isNull);
  });

  test('parseToolChoice returns null for null input', () {
    expect(rules.parseToolChoice(null), isNull);
  });

  test('toolChoiceRequirementsFor gathers both a Soldier background\'s and a Bard class\'s tool choices together', () {
    final jarson = buildSampleJarson();
    final soldier = srdCatalog.backgroundsByKey.values.firstWhere(
      (b) => b.name == 'Soldier',
    );
    final bard = srdCatalog.classesByKey.values.firstWhere(
      (c) => c.name == 'Bard',
    );
    jarson.backgroundKey = soldier.key;
    jarson.classKey = bard.key;

    final requirements = rules.toolChoiceRequirementsFor(jarson);

    expect(requirements, hasLength(2));
    expect(requirements[0].tool.name, 'Gaming Set');
    expect(requirements[1].tool.name, 'Musical Instrument');
  });

  test('toolChoiceRequirementsFor is empty for a background/class combination with no tool choice at all', () {
    final jarson = buildSampleJarson();
    final criminal = srdCatalog.backgroundsByKey.values.firstWhere(
      (b) => b.name == 'Criminal',
    );
    // Fixed Thieves' Tools (no choice), and Fighter has no Tool
    // Proficiencies trait at all - Jarson's own real backgroundKey
    // (Soldier) does have a choice, which is exactly why this test
    // swaps it out first.
    jarson.backgroundKey = criminal.key;
    expect(rules.toolChoiceRequirementsFor(jarson), isEmpty);
  });

  group('spellcasting', () {
    Character wizard({int level = 5}) {
      final c = buildSampleJarson();
      c.classKey = 'srd-2024_wizard-class';
      c.level = level;
      c.abilityScores = const AbilityScores(
        str: 10,
        dex: 14,
        con: 14,
        intel: 16,
        wis: 12,
        cha: 8,
      );
      rules.enableSpellcasting(c);
      return c;
    }

    SrdSpellRef spell(String name) =>
        srdCatalog.spells.firstWhere((s) => s.name == name);

    test('save DC and spell attack use the casting ability + Proficiency Bonus, plus spellSaveDc/spellAttack Effects', () {
      final c = wizard(); // Int 16 (+3), level 5 (PB +3)
      expect(rules.spellcastingModifier(c), 3);
      expect(rules.spellSaveDc(c), 14);
      expect(rules.spellAttackBonus(c), 6);

      c.inventory.add(
        InventoryEntry(
          name: 'Wand of the War Mage',
          quantity: 1,
          attuned: true,
        ),
      );
      final entry = homebrewRepo.create('magicItem', 'Wand of the War Mage');
      homebrewRepo.update(
        HomebrewEntry(
          id: entry.id,
          kind: entry.kind,
          name: entry.name,
          effects: const [
            Effect(target: 'spellAttack', formula: '1'),
            Effect(target: 'spellSaveDc', formula: '1'),
          ],
        ),
      );
      expect(rules.spellAttackBonus(c), 7);
      expect(rules.spellSaveDc(c), 15);
    });

    test('cantrip/prepared limits come from the class table, null where the class has no such column', () {
      expect(rules.cantripLimit(wizard()), 4);
      expect(rules.preparedSpellLimit(wizard()), 9);

      final paladin = buildSampleJarson()
        ..classKey = 'srd-2024_paladin-class'
        ..level = 5;
      rules.enableSpellcasting(paladin);
      expect(rules.cantripLimit(paladin), isNull);
      expect(rules.preparedSpellLimit(paladin), 6);
    });

    test('always-prepared spells do not count toward the prepared limit', () {
      final c = wizard();
      c.spellcasting!.spells = [
        KnownSpell(spellKey: spell('Shield').key),
        KnownSpell(spellKey: spell('Bless').key, alwaysPrepared: true),
        KnownSpell(spellKey: spell('Fireball').key, prepared: false),
      ];
      expect(rules.preparedSpellCount(c), 1);
    });

    test('castSpell spends the chosen slot and castableSlotLevels only offers levels with slots left', () {
      final c = wizard();
      expect(rules.castableSlotLevels(c, 2), [2, 3]);
      rules.castSpell(c, spell('Misty Step'), slotLevel: 3);
      rules.castSpell(c, spell('Misty Step'), slotLevel: 3);
      expect(c.spellcasting!.slots[3]!.used, 2);
      expect(rules.castableSlotLevels(c, 2), [2]);
      expect(rules.castableSlotLevels(c, 0), isEmpty); // cantrip: no slot
      expect(
        () => rules.castSpell(c, spell('Fireball'), slotLevel: 3),
        throwsStateError,
      );
    });

    test('a Concentration spell replaces the one already held, and says which it ended', () {
      final c = wizard();
      final bless = spell('Bless');
      expect(rules.castSpell(c, bless, slotLevel: 1), isNull);
      expect(c.spellcasting!.concentratingOn, bless.key);

      // Not a Concentration spell - leaves Bless up.
      rules.castSpell(c, spell('Magic Missile'), slotLevel: 1);
      expect(c.spellcasting!.concentratingOn, bless.key);

      final ended = rules.castSpell(c, spell('Haste'), slotLevel: 3);
      expect(ended, bless.key);
      expect(c.spellcasting!.concentratingOn, spell('Haste').key);
    });

    test('a Ritual casting (no slot level) spends nothing', () {
      final c = wizard();
      rules.castSpell(c, spell('Detect Magic'));
      expect(c.spellcasting!.slots.values.every((s) => s.used == 0), isTrue);
    });

    test('dropping to 0 HP and a Long Rest both end Concentration', () {
      final c = wizard();
      rules.castSpell(c, spell('Bless'), slotLevel: 1);
      rules.applyDamageOrHeal(c, -(c.currentHp - 1));
      expect(c.spellcasting!.concentratingOn, isNotNull); // still up at 1 HP
      rules.applyDamageOrHeal(c, -5);
      expect(c.spellcasting!.concentratingOn, isNull);

      rules.castSpell(c, spell('Bless'), slotLevel: 1);
      rules.applyLongRest(c);
      expect(c.spellcasting!.concentratingOn, isNull);
    });

    test('concentrationSaveDc is 10 or half the damage, capped at 30', () {
      expect(rules.concentrationSaveDc(5), 10);
      expect(rules.concentrationSaveDc(31), 15);
      expect(rules.concentrationSaveDc(200), 30);
    });

    test("a Short Rest restores Pact Magic slots but not a Wizard's", () {
      final warlock = buildSampleJarson()
        ..classKey = 'srd-2024_warlock-class'
        ..level = 5;
      rules.enableSpellcasting(warlock);
      expect(rules.usesPactMagic(warlock), isTrue);
      warlock.spellcasting!.slots[3]!.used = 2;
      rules.applyShortRest(warlock);
      expect(warlock.spellcasting!.slots[3]!.used, 0);

      final c = wizard();
      expect(rules.usesPactMagic(c), isFalse);
      c.spellcasting!.slots[1]!.used = 2;
      rules.applyShortRest(c);
      expect(c.spellcasting!.slots[1]!.used, 2);
    });

    test('spellDamageInfo reads attack/save and damage out of the SRD text, scaling cantrips by character level', () {
      final fireBolt = spell('Fire Bolt');
      expect(rules.spellDamageInfo(fireBolt, 1).dice, '1d10');
      expect(rules.spellDamageInfo(fireBolt, 5).dice, '2d10');
      expect(rules.spellDamageInfo(fireBolt, 17).dice, '4d10');
      expect(rules.spellDamageInfo(fireBolt, 1).isAttack, isTrue);
      expect(rules.spellDamageInfo(fireBolt, 1).damageType, 'Fire');

      final blast = rules.spellDamageInfo(spell('Eldritch Blast'), 11);
      expect(blast.dice, '1d10');
      expect(blast.beams, 3);
      expect(rules.spellDamageText(blast), '1d10 Force ×3');

      final fireball = rules.spellDamageInfo(spell('Fireball'), 5);
      expect(fireball.saveAbility, 'dex');
      expect(fireball.dice, '8d6');
      expect(rules.spellDamageInfo(spell('Magic Missile'), 1).dice, '1d4 + 1');

      // "Advantage on Dexterity saving throws" is a buff, not a save DC.
      expect(rules.spellDamageInfo(spell('Haste'), 5).isEmpty, isTrue);
    });

    test(
      "spellSummary combines the character's own to-hit/DC with the damage",
      () {
        final c = wizard();
        expect(
          rules.spellSummary(c, spell('Fire Bolt')),
          '+6 to hit · 2d10 Fire',
        );
        expect(
          rules.spellSummary(c, spell('Fireball')),
          'DC 14 Dex · 8d6 Fire',
        );
        expect(rules.spellSummary(c, spell('Mage Hand')), '');
      },
    );

    test(
      'spellRefFor resolves a homebrew spell by id, at the level it was given',
      () {
        final entry = homebrewRepo.create('spell', 'Ember Lance');
        final ref = rules.spellRefFor(entry.id, homebrewLevel: 2)!;
        expect(ref.name, 'Ember Lance');
        expect(ref.level, 2);
        expect(rules.spellRefFor('homebrew_gone'), isNull);
      },
    );

    test('levelUpOneLevel reports what changed about spellcasting', () {
      final c = wizard(level: 4);
      final summary = rules.levelUpOneLevel(c);
      expect(summary.spellcastingNotes, contains('Prepared Spells: 7 → 9'));
      expect(summary.spellcastingNotes, contains('New spell slot level: 3'));
      // Wizard cantrips don't change 4 -> 5.
      expect(
        summary.spellcastingNotes.any((n) => n.startsWith('Cantrips')),
        isFalse,
      );
      expect(c.history.last.detail, contains('Prepared Spells: 7 → 9'));
    });

    test(
      "concentration and a homebrew spell's level survive a JSON round trip",
      () {
        final c = wizard();
        c.spellcasting!.spells = [KnownSpell(spellKey: 'homebrew_x', level: 4)];
        c.spellcasting!.concentratingOn = spell('Bless').key;
        final copy = Character.fromJson(c.toJson());
        expect(copy.spellcasting!.concentratingOn, spell('Bless').key);
        expect(copy.spellcasting!.spells.single.level, 4);
      },
    );
  });

  group('sheet text', () {
    setUp(() => sheetTextRepo.overrides.clear());

    Character wizard() => buildSampleJarson()
      ..classKey = 'srd-2024_wizard-class'
      ..subclassKey = null
      ..features = [];

    test('every SRD class/subclass feature, species trait, and feat a character can be granted has bundled sheet text', () {
      const choiceDriven = {
        'Fighting Style',
        'Additional Fighting Style',
        'Ability Score Improvement',
        'Epic Boon',
      };
      final missing = <String>[];
      void check(String scope, Iterable<String> names) {
        for (final name in names) {
          if (choiceDriven.contains(name) || name.endsWith(' Subclass')) {
            continue;
          }
          final text = srdCatalog.sheetText[scope]?[name];
          if (text == null || text.isEmpty) missing.add('$scope|$name');
        }
      }

      for (final cls in srdCatalog.classesByKey.values) {
        check(cls.key, cls.features.map((f) => f.name));
        if (cls.subclass != null) {
          check(cls.subclass!.key, cls.subclass!.features.map((f) => f.name));
        }
      }
      for (final species in srdCatalog.speciesByKey.values) {
        check(species.key, species.traits.map((t) => t.name));
      }
      check('feats', srdCatalog.featsByKey.values.map((f) => f.name));
      expect(missing, isEmpty);
    });

    test(
      "a feature name shared across classes resolves to its own class's text",
      () {
        final spellcasting = GrantedFeature(
          name: 'Spellcasting',
          source: 'class',
        );
        final w = wizard();
        final cleric = wizard()..classKey = 'srd-2024_cleric-class';
        expect(rules.sheetText(w, spellcasting), startsWith('Int-based'));
        expect(rules.sheetText(cleric, spellcasting), startsWith('Wis-based'));
        expect(
          rules.sheetTextKey(w, spellcasting),
          'srd-2024_wizard-class|Spellcasting',
        );
      },
    );

    test(
      "a player's edit wins over the default, and resetting restores it",
      () {
        final w = wizard();
        final recovery = GrantedFeature(
          name: 'Arcane Recovery',
          source: 'class',
        );
        final defaultText = rules.defaultSheetText(w, recovery)!;
        expect(rules.sheetText(w, recovery), defaultText);

        sheetTextRepo.set(rules.sheetTextKey(w, recovery), 'My own wording.');
        expect(rules.sheetText(w, recovery), 'My own wording.');
        // Applies to any character with the same feature, not just this one.
        expect(rules.sheetText(wizard(), recovery), 'My own wording.');

        sheetTextRepo.set(rules.sheetTextKey(w, recovery), '   ');
        expect(rules.sheetText(w, recovery), defaultText);
      },
    );

    test("a homebrew feat uses its own sheet text, falling back to its description", () {
      final entry = homebrewRepo.create('feat', 'Tavern Brawler Plus');
      final feat = GrantedFeature(name: 'Tavern Brawler Plus', source: 'feat');
      final c = wizard();
      homebrewRepo.update(
        HomebrewEntry(
          id: entry.id,
          kind: 'feat',
          name: entry.name,
          desc: 'A long description of the feat.',
        ),
      );
      expect(rules.sheetTextScope(c, feat), 'homebrew');
      expect(rules.sheetText(c, feat), 'A long description of the feat.');

      homebrewRepo.update(
        HomebrewEntry(
          id: entry.id,
          kind: 'feat',
          name: entry.name,
          desc: 'A long description of the feat.',
          shortDesc: 'Short version.',
        ),
      );
      expect(rules.sheetText(c, feat), 'Short version.');
    });

    test('a hand-added feature falls back to its own stored description', () {
      final custom = GrantedFeature(
        name: 'Blessing of the Harvest',
        source: 'custom',
        desc: 'Once a day, find food.',
      );
      final c = wizard();
      expect(rules.sheetTextKey(c, custom), 'custom|Blessing of the Harvest');
      expect(rules.sheetText(c, custom), 'Once a day, find food.');
    });

    test('speciesTraitFeatures reads the species itself, even with nothing stored on the character', () {
      final c = wizard()..speciesKey = 'srd-2024_dragonborn-species';
      final names = rules.speciesTraitFeatures(c).map((f) => f.name);
      expect(names, containsAll(['Breath Weapon', 'Darkvision']));
    });
  });

  group('derived stats', () {
    Character hero(
      String classKey, {
      int level = 5,
      AbilityScores? scores,
      String? speciesKey,
    }) {
      final c = buildSampleJarson()
        ..classKey = classKey
        ..subclassKey = null
        ..level = level
        ..equippedArmor = null
        ..shieldEquipped = false
        ..feats = []
        ..weapons = []
        ..speciesKey = speciesKey ?? 'srd-2024_human-species'
        ..speed = 30
        ..abilityScores =
            scores ??
            const AbilityScores(
              str: 10,
              dex: 16,
              con: 14,
              intel: 10,
              wis: 14,
              cha: 10,
            );
      c.features = rules.classFeaturesForLevelUp(c..features = [], 0, level);
      return c;
    }

    SrdWeaponRef weapon(String name) =>
        srdCatalog.weaponsByKey.values.firstWhere((w) => w.name == name);

    test('ranged weapons attack with Dex, Finesse weapons with the better of Str/Dex', () {
      final c = hero('srd-2024_fighter-class');
      final longbow = rules.weaponFromSrd(c, weapon('Longbow'));
      final rapier = rules.weaponFromSrd(c, weapon('Rapier'));
      final greataxe = rules.weaponFromSrd(c, weapon('Greataxe'));
      expect(rapier.finesse, isTrue);
      expect(longbow.category, 'Martial Ranged Weapons');
      expect(rules.weaponAbility(c, longbow), ('Dex', 3));
      expect(rules.weaponAbility(c, rapier), ('Dex', 3));
      expect(rules.weaponAbility(c, greataxe), ('Str', 0));
      // A weapon saved before categories were stored still resolves by name.
      longbow.category = null;
      expect(rules.isRangedWeapon(longbow), isTrue);
    });

    test('weapon proficiency follows the class text', () {
      final wizard = hero('srd-2024_wizard-class');
      expect(rules.weaponFromSrd(wizard, weapon('Dagger')).proficient, isTrue);
      expect(
        rules.weaponFromSrd(wizard, weapon('Longsword')).proficient,
        isFalse,
      );
      final rogue = hero('srd-2024_rogue-class');
      expect(rules.weaponFromSrd(rogue, weapon('Rapier')).proficient, isTrue);
      expect(
        rules.weaponFromSrd(rogue, weapon('Longsword')).proficient,
        isFalse,
      );
      wizard.extraWeaponProficiencies = ['Martial weapons'];
      expect(
        rules.weaponFromSrd(wizard, weapon('Longsword')).proficient,
        isTrue,
      );
    });

    test('Martial Arts: Dex and the Martial Arts die for Monk weapons, only while unarmored', () {
      final monk = hero(
        'srd-2024_monk-class',
        scores: const AbilityScores(
          str: 10,
          dex: 16,
          con: 12,
          intel: 10,
          wis: 14,
          cha: 8,
        ),
      );
      final staff = rules.weaponFromSrd(monk, weapon('Quarterstaff'));
      expect(rules.weaponAbility(monk, staff), ('Dex', 3));
      expect(rules.weaponDamageDice(monk, staff), '1d8'); // level 5 die
      expect(rules.damageFor(monk, staff).text, startsWith('1d8+3'));
      monk.shieldEquipped = true;
      expect(rules.weaponAbility(monk, staff), ('Str', 0));
      expect(rules.weaponDamageDice(monk, staff), '1d6');
    });

    test('a mastery only applies to a picked weapon kind; untracked (legacy) characters keep all', () {
      final c = hero('srd-2024_fighter-class')..weaponMasteries = ['Longsword'];
      final longsword = rules.weaponFromSrd(c, weapon('Longsword'));
      final magic = rules.weaponFromSrd(c, weapon('Longsword'));
      final axe = rules.weaponFromSrd(c, weapon('Greataxe'));
      expect(rules.masteryApplies(c, longsword), isTrue);
      expect(
        rules.masteryApplies(
          c,
          Weapon(
            name: 'Longsword +1',
            damageDice: magic.damageDice,
            damageType: magic.damageType,
            properties: magic.properties,
            mastery: magic.mastery,
            proficient: true,
          ),
        ),
        isTrue,
      );
      expect(rules.masteryApplies(c, axe), isFalse);
      c.weaponMasteries = ['*'];
      expect(rules.masteryApplies(c, axe), isTrue);
      expect(rules.weaponMasteryLimit(c), 4);
    });

    test(
      'AC: Barbarian/Monk Unarmored Defense and the Defense fighting style',
      () {
        final barbarian = hero('srd-2024_barbarian-class'); // Dex +3, Con +2
        expect(rules.armorClassFor(barbarian), 15);
        barbarian.shieldEquipped = true;
        expect(rules.armorClassFor(barbarian), 17);

        final monk = hero('srd-2024_monk-class'); // Dex +3, Wis +2
        expect(rules.armorClassFor(monk), 15);
        monk.shieldEquipped = true; // Monk's version doesn't allow a Shield
        expect(rules.armorClassFor(monk), 15);

        final fighter = hero('srd-2024_fighter-class')
          ..equippedArmor = EquippedArmor(
            name: 'Chain Mail',
            armorClassFormula: '16',
            category: 'Heavy',
          );
        expect(rules.armorClassFor(fighter), 16);
        fighter.feats = [GrantedFeature(name: 'Defense', source: 'feat')];
        expect(rules.armorClassFor(fighter), 17);
      },
    );

    test('Archery adds +2 to ranged attacks only', () {
      final c = hero('srd-2024_fighter-class')
        ..feats = [GrantedFeature(name: 'Archery', source: 'feat')];
      final bow = rules.weaponFromSrd(c, weapon('Longbow'));
      final sword = rules.weaponFromSrd(c, weapon('Longsword'));
      expect(rules.attackFor(c, bow).bonus, 3 + 3 + 2);
      expect(rules.attackFor(c, sword).bonus, 0 + 3);
    });

    test('Speed: species base plus Fast Movement / Unarmored Movement', () {
      expect(rules.speciesBaseSpeed('srd-2024_goliath-species'), 35);
      final barbarian = hero('srd-2024_barbarian-class');
      expect(rules.speedFor(barbarian), 40);
      barbarian.equippedArmor = EquippedArmor(
        name: 'Plate Armor',
        armorClassFormula: '18',
        category: 'Heavy',
      );
      expect(rules.speedFor(barbarian), 30);
      final monk = hero('srd-2024_monk-class', level: 6);
      expect(rules.speedFor(monk), 45); // +15 ft at level 6
    });

    test('Max HP includes Dwarven Toughness and Draconic Resilience', () {
      final dwarf = hero(
        'srd-2024_fighter-class',
        speciesKey: 'srd-2024_dwarf-species',
      );
      rules.recalculateHp(dwarf);
      final human = hero('srd-2024_fighter-class');
      rules.recalculateHp(human);
      expect(dwarf.maxHp - human.maxHp, 5);
      expect(rules.maxHpBonus(dwarf), 5);
    });

    test('a background feat with a parenthetical ("Magic Initiate (Cleric)") resolves to the SRD feat', () {
      final c = hero('srd-2024_cleric-class');
      final feat = GrantedFeature(
        name: 'Magic Initiate (Cleric)',
        source: 'background',
      );
      expect(rules.baseFeatName(feat.name), 'Magic Initiate');
      expect(rules.featNameChoice(feat.name), 'Cleric');
      expect(rules.sheetTextScope(c, feat), 'feats');
      expect(rules.sheetText(c, feat), startsWith('Two cantrips'));
      expect(rules.liveFeatureText(c, feat), contains('Two Cantrips'));
    });
  });
}
