import 'package:flutter_test/flutter_test.dart';

import 'package:dnd_sheet/data/srd_catalog.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await srdCatalog.init();
  });

  test('loads feats, including the ones already granted to Torvek', () {
    expect(srdCatalog.featsByKey.length, greaterThan(15));
    final alert = srdCatalog.featsByKey.values.firstWhere(
      (f) => f.name == 'Alert',
    );
    // Alert's own `desc` is just an intro line - the real mechanics live
    // in `benefits`, which is exactly the bug fixed for Torvek earlier.
    expect(alert.fullDescription, contains('Initiative Proficiency'));
    expect(alert.fullDescription, contains('Initiative Swap'));
  });

  test('loads weapons with correct Heavy/Finesse property detection', () {
    final greatsword = srdCatalog.weaponsByKey.values.firstWhere(
      (w) => w.name == 'Greatsword',
    );
    expect(greatsword.isHeavy, isTrue);
    expect(greatsword.splitDamage, ('2d6', 'Slashing'));
    expect(greatsword.mastery, 'Graze');

    final dagger = srdCatalog.weaponsByKey.values.firstWhere(
      (w) => w.name == 'Dagger',
    );
    expect(dagger.isFinesse, isTrue);
  });

  test('loads weapon mastery descriptions keyed by name', () {
    final graze = srdCatalog.weaponPropertiesByName['Graze'];
    expect(graze, isNotNull);
    expect(graze!.isMastery, isTrue);
    expect(graze.desc, contains('miss'));
  });

  test('loads armor with AC formula text', () {
    final padded = srdCatalog.armorByKey.values.firstWhere(
      (a) => a.name == 'Padded Armor',
    );
    expect(padded.armorClass, contains('Dex modifier'));
    expect(padded.stealth, isTrue);
  });

  test('SrdArmorRef.simpleCategory boils the verbose category text down to Light/Medium/Heavy', () {
    String simpleCategoryOf(String name) => srdCatalog.armorByKey.values
        .firstWhere((a) => a.name == name)
        .simpleCategory!;

    expect(simpleCategoryOf('Padded Armor'), 'Light');
    expect(simpleCategoryOf('Half Plate Armor'), 'Medium');
    expect(simpleCategoryOf('Chain Mail'), 'Heavy');
  });

  test('loads spells', () {
    expect(srdCatalog.spells.length, greaterThan(300));
    expect(
      srdCatalog.spells.any((s) => s.name == 'Fireball' && s.level == 3),
      isTrue,
    );
  });

  test('loads species traits and the Draconic Ancestry choice table', () {
    final dragonborn = srdCatalog.speciesByKey.values.firstWhere(
      (s) => s.name == 'Dragonborn',
    );
    expect(dragonborn.traits.any((t) => t.name == 'Breath Weapon'), isTrue);
    expect(dragonborn.tables.length, 1);
    expect(dragonborn.tables.first.caption, 'Draconic Ancestors');
  });

  test('flattenSpeciesTableOptions splits Dragonborn\'s paired-column table into 10 options', () {
    final dragonborn = srdCatalog.speciesByKey.values.firstWhere(
      (s) => s.name == 'Dragonborn',
    );
    final options = flattenSpeciesTableOptions(dragonborn.tables.first);
    expect(options.length, 10);
    final red = options.firstWhere((o) => o.name == 'Red');
    expect(red.detail, 'Fire');
    final black = options.firstWhere((o) => o.name == 'Black');
    expect(black.detail, 'Acid');
  });

  test('loads gear, tools, magic items, and languages catalogs, including full rules text', () {
    expect(srdCatalog.gear.any((g) => g.name == 'Acid'), isTrue);
    final acid = srdCatalog.gearByKey.values.firstWhere(
      (g) => g.name == 'Acid',
    );
    expect(acid.desc, contains('Dexterity saving throw'));
    expect(acid.cost, '25 GP');

    expect(
      srdCatalog.tools.any((t) => t.name == "Alchemist's Supplies"),
      isTrue,
    );
    final alchemist = srdCatalog.toolsByKey.values.firstWhere(
      (t) => t.name == "Alchemist's Supplies",
    );
    expect(alchemist.ability, 'Intelligence');
    expect(alchemist.utilize, contains('Identify a substance'));

    expect(
      srdCatalog.magicItems.any((m) => m.name == 'Adamantine Armor'),
      isTrue,
    );
    final adamantine = srdCatalog.magicItemsByKey.values.firstWhere(
      (m) => m.name == 'Adamantine Armor',
    );
    expect(adamantine.rarity, 'Uncommon');
    expect(adamantine.desc, contains('Critical Hit'));

    expect(srdCatalog.languages.any((l) => l.name == 'Common'), isTrue);
  });

  test('loads full 2024 spell rules text (Fireball), not just key/name/level/school', () {
    final fireball = srdCatalog.spells.firstWhere((s) => s.name == 'Fireball');
    expect(fireball.castingTime, 'Action');
    expect(fireball.range, '150 feet');
    expect(fireball.components, contains('V, S, M'));
    expect(fireball.concentration, isFalse);
    expect(fireball.duration, 'Instantaneous');
    expect(fireball.desc, contains('20-foot-radius Sphere'));
    expect(fireball.higherLevel, contains('1d6'));
    expect(fireball.classes, containsAll(['Sorcerer', 'Wizard']));
  });

  test('loads the reference glossary (abilities, alignments, damage types, spell schools, sizes) from the SRD 5.2.1 tables', () {
    expect(srdCatalog.abilityGlossary.length, 6);
    final cha = srdCatalog.abilityGlossary.firstWhere(
      (a) => a.name == 'Charisma',
    );
    expect(cha.key, 'cha');
    expect(cha.desc, 'Confidence, poise, and charm');

    expect(srdCatalog.alignments.length, 9);
    final ce = srdCatalog.alignments.firstWhere((a) => a.shortName == 'CE');
    expect(ce.name, 'Chaotic Evil');
    expect(ce.desc, contains('Chaotic Evil creatures'));

    expect(srdCatalog.damageTypes.length, 13);
    expect(srdCatalog.damageTypes.any((d) => d.name == 'Fire'), isTrue);

    expect(srdCatalog.spellSchools.length, 8);
    final abjuration = srdCatalog.spellSchools.firstWhere(
      (s) => s.name == 'Abjuration',
    );
    expect(abjuration.desc, 'Prevents or reverses harmful effects');

    expect(srdCatalog.sizes.length, 6);
    final medium = srdCatalog.sizes.firstWhere((s) => s.name == 'Medium');
    expect(medium.space, '5 by 5 feet');
    expect(medium.squares, '1 square');
  });

  test('skillsByName carries the full 2024 skill description, not just name/ability', () {
    final acrobatics = srdCatalog.skillsByName['Acrobatics']!;
    expect(acrobatics.ability, 'dex');
    expect(acrobatics.desc, contains('acrobatic stunt'));
  });

  test('backgroundsByKey carries ability score options, tool proficiency, and starting equipment text', () {
    final soldier = srdCatalog.backgroundsByKey['srd-2024_soldier-background']!;
    expect(
      soldier.abilityScores,
      containsAll(['Strength', 'Dexterity', 'Constitution']),
    );
    expect(soldier.toolProficiency, contains('Gaming Set'));
    expect(soldier.equipment, contains('Spear'));
  });

  test('loads verbatim SRD condition text, excluding Exhaustion (tracked separately)', () {
    expect(srdCatalog.conditionDescriptions['Blinded'], contains('Advantage'));
    expect(srdCatalog.conditionNames, isNot(contains('Exhaustion')));
    expect(srdCatalog.conditionNames.length, 14);
  });

  test("parses Wizard's full-caster spellSlots table (2 level-1 slots at level 1, 4/3/2 at level 5)", () {
    final wizard = srdCatalog.classesByKey.values.firstWhere(
      (c) => c.name == 'Wizard',
    );
    expect(wizard.spellSlotsAtLevel(1), {1: 2});
    expect(wizard.spellSlotsAtLevel(5), {1: 4, 2: 3, 3: 2});
  });

  test("parses Warlock's flat Pact Magic slots (1 level-1 slot at level 1, 2 level-3 slots at level 5)", () {
    final warlock = srdCatalog.classesByKey.values.firstWhere(
      (c) => c.name == 'Warlock',
    );
    expect(warlock.spellSlotsAtLevel(1), {1: 1});
    expect(warlock.spellSlotsAtLevel(5), {3: 2});
  });

  test('spellSlotsAtLevel is empty for a non-caster (Fighter)', () {
    final fighter = srdCatalog.byKey('srd-2024_fighter-class')!;
    expect(fighter.spellSlotsAtLevel(5), isEmpty);
  });

  test('loads the full Rules Glossary (154 terms), including its bracketed family tag', () {
    expect(srdCatalog.rulesGlossary.length, 154);
    final advantage = srdCatalog.rulesGlossary.firstWhere(
      (t) => t.name == 'Advantage',
    );
    expect(advantage.tag, isNull);
    expect(advantage.desc, contains('roll two d20s'));

    final unconscious = srdCatalog.rulesGlossary.firstWhere(
      (t) => t.name == 'Unconscious',
    );
    expect(unconscious.tag, 'Condition');
    expect(unconscious.desc, contains('Incapacitated'));
  });

  test('loads the Playing the Game chapter as one entry per top-level section, in chapter order', () {
    expect(srdCatalog.playingTheGame.map((s) => s.name), [
      'Rhythm of Play',
      'The Six Abilities',
      'D20 Tests',
      'Proficiency',
      'Actions',
      'Social Interaction',
      'Exploration',
      'Combat',
      'Damage and Healing',
    ]);
    final combat = srdCatalog.playingTheGame.firstWhere(
      (s) => s.name == 'Combat',
    );
    expect(combat.desc, contains('Order of Combat'));
    expect(combat.desc, contains('Opportunity Attacks'));
  });

  test('loads the Gameplay Toolbox chapter, including Traps and Poison', () {
    expect(
      srdCatalog.gameplayToolbox.map((s) => s.name),
      containsAll(['Traps', 'Poison', 'Combat Encounters']),
    );
    final traps = srdCatalog.gameplayToolbox.firstWhere(
      (s) => s.name == 'Traps',
    );
    expect(traps.desc, contains('Collapsing Roof'));
  });

  test('loads the Character Creation chapter, including Multiclassing and Level Advancement', () {
    expect(
      srdCatalog.characterCreationChapters.map((s) => s.name),
      containsAll(['Multiclassing', 'Level Advancement', 'Trinkets']),
    );
    final multiclassing = srdCatalog.characterCreationChapters.firstWhere(
      (s) => s.name == 'Multiclassing',
    );
    expect(multiclassing.desc, contains('Prerequisites'));
  });

  test(
    'loads mounts, large vehicles, and tack as one combined name+desc list',
    () {
      expect(srdCatalog.mountsAndVehicles.length, 25); // 8 + 7 + 10
      final camel = srdCatalog.mountsAndVehicles.firstWhere(
        (m) => m.name == 'Camel',
      );
      expect(camel.desc, contains('Carrying Capacity: 450 lb.'));
      final airship = srdCatalog.mountsAndVehicles.firstWhere(
        (m) => m.name == 'Airship',
      );
      expect(airship.desc, contains('AC: 13'));
      expect(airship.desc, contains('HP: 300'));
    },
  );
}
