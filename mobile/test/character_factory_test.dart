import 'package:flutter_test/flutter_test.dart';

import 'package:dnd_sheet/data/character_factory.dart';
import 'package:dnd_sheet/data/srd_catalog.dart';
import 'package:dnd_sheet/domain/rules.dart' as rules;
import 'package:dnd_sheet/models/character.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await srdCatalog.init();
  });

  test(
    'buildNewCharacter computes a level-1 Fighter correctly from real SRD data',
    () {
      final fighter = srdCatalog.classOptions.firstWhere(
        (c) => c.name == 'Fighter',
      );
      final dragonborn = srdCatalog.species.firstWhere(
        (s) => s.name == 'Dragonborn',
      );
      final soldier = srdCatalog.backgroundOptions.firstWhere(
        (b) => b.name == 'Soldier',
      );

      final character = buildNewCharacter(
        name: 'Test Fighter',
        species: dragonborn,
        background: soldier,
        srdClass: fighter,
        abilityScores: const AbilityScores(
          str: 16,
          dex: 12,
          con: 14,
          intel: 10,
          wis: 10,
          cha: 8,
        ),
        chosenClassSkills: const ['Acrobatics', 'Perception'],
      );

      expect(character.level, 1);
      expect(
        character.hitDiceDie,
        'd10',
      ); // parsed from "D10 per Fighter level"
      expect(character.hitDiceTotal, 1);
      // Level 1: max die roll (10) + Con modifier (+2).
      expect(character.maxHp, 12);
      expect(character.currentHp, 12);
      expect(
        rules.armorClassFor(character),
        11,
      ); // unarmored: 10 + Dex modifier (+1)
      expect(character.savingThrowProficiencies, containsAll(['str', 'con']));
      expect(character.savingThrowProficiencies.length, 2);
      expect(character.backgroundLabel, 'Soldier');
      expect(character.backgroundKey, soldier.key);

      // Level-1 Fighter features (Second Wind's rules text, Weapon
      // Mastery, ...) get granted from classes.json, but Fighting Style
      // is a choice - it should show up as a Pending Choice instead.
      expect(
        character.features.map((f) => f.name),
        containsAll(['Second Wind', 'Weapon Mastery']),
      );
      expect(
        character.features.any((f) => f.name == 'Fighting Style'),
        isFalse,
      );
      // Fighting Style (a feat pick) and Weapon Mastery (3 weapon kinds).
      expect(character.pendingChoices.length, 2);
      expect(character.pendingChoices.first.label, 'Level 1: Fighting Style');
      expect(character.pendingChoices.last.optionSet, 'Weapon Mastery');
      expect(character.pendingChoices.last.count, 3);
      expect(
        character.pendingChoices.first.featCategory,
        'Fighting Style Feat',
      );

      // Soldier grants Athletics + Intimidation outright; the player also
      // chose Acrobatics + Perception as their 2 Fighter class skills -
      // all 4 should end up proficient, no more, no less.
      final skillNames = character.skills.map((s) => s.name).toSet();
      expect(skillNames, {
        'Athletics',
        'Intimidation',
        'Acrobatics',
        'Perception',
      });
      expect(character.skills.every((s) => s.proficient), isTrue);

      // Starting ability scores get their own baseline history entry, so
      // later edits/ASIs have something to diff against.
      expect(character.history, hasLength(1));
      expect(character.history.first.label, 'Character created');
      expect(character.history.first.detail, contains('STR 16'));
      expect(character.history.first.detail, contains('DEX 12'));
      expect(
        character.skills.firstWhere((s) => s.name == 'Athletics').ability,
        'str',
      );
      expect(
        character.skills.firstWhere((s) => s.name == 'Perception').ability,
        'wis',
      );

      // Soldier also grants the Savage Attacker feat outright.
      expect(
        character.feats.any(
          (f) => f.name == 'Savage Attacker' && f.source == 'background',
        ),
        isTrue,
      );

      // Fighter gets 2 uses of Second Wind at level 1 (verified against the
      // real level table, not the flat "1" the earliest mockup assumed).
      final secondWind = character.resources.firstWhere(
        (r) => r.key == 'srd-2024_fighter-class_Second Wind',
      );
      expect(secondWind.max, 2);
      expect(secondWind.used, 0);
      // Action Surge/Indomitable aren't granted until level 2/9.
      expect(
        character.resources.where(
          (r) => r.key == 'srd-2024_fighter-class_Action Surge',
        ),
        isEmpty,
      );
      // Dragonborn's Breath Weapon: Proficiency Bonus uses at level 1 (+2).
      final breathWeapon = character.resources.firstWhere(
        (r) => r.key == 'srd-2024_dragonborn-species_Breath Weapon',
      );
      expect(breathWeapon.max, 2);
    },
  );

  test('buildNewCharacter grants option A starting equipment: Chain Mail, Greatsword, Flail, 8 Javelins, and 4 GP', () {
    final fighter = srdCatalog.classOptions.firstWhere(
      (c) => c.name == 'Fighter',
    );
    final dragonborn = srdCatalog.species.firstWhere(
      (s) => s.name == 'Dragonborn',
    );
    final soldier = srdCatalog.backgroundOptions.firstWhere(
      (b) => b.name == 'Soldier',
    );

    final character = buildNewCharacter(
      name: 'Option A Fighter',
      species: dragonborn,
      background: soldier,
      srdClass: fighter,
      abilityScores: const AbilityScores(
        str: 16,
        dex: 12,
        con: 14,
        intel: 10,
        wis: 10,
        cha: 8,
      ),
      chosenClassSkills: const ['Acrobatics', 'Perception'],
      classEquipmentOption: 'A',
    );

    expect(character.equippedArmor?.name, 'Chain Mail');
    // Needed for Heavy-armor-gated effects (e.g. Heavy Armor Master) to
    // actually detect it - see rules.dart's 'heavyArmor' condition.
    expect(character.equippedArmor?.category, 'Heavy');
    expect(
      character.weapons.map((w) => w.name),
      containsAll(['Greatsword', 'Flail', 'Javelin']),
    );
    expect(
      character.inventory.any((i) => i.name == 'Javelin' && i.quantity == 8),
      isTrue,
    );
    expect(character.currency.gp, 4);
  });

  test('buildNewCharacter grants option B starting equipment: Studded Leather, Scimitar/Shortsword/Longbow, and 11 GP', () {
    final fighter = srdCatalog.classOptions.firstWhere(
      (c) => c.name == 'Fighter',
    );
    final dragonborn = srdCatalog.species.firstWhere(
      (s) => s.name == 'Dragonborn',
    );
    final soldier = srdCatalog.backgroundOptions.firstWhere(
      (b) => b.name == 'Soldier',
    );

    final character = buildNewCharacter(
      name: 'Option B Fighter',
      species: dragonborn,
      background: soldier,
      srdClass: fighter,
      abilityScores: const AbilityScores(
        str: 10,
        dex: 16,
        con: 14,
        intel: 10,
        wis: 10,
        cha: 8,
      ),
      chosenClassSkills: const ['Acrobatics', 'Perception'],
      classEquipmentOption: 'B',
    );

    expect(character.equippedArmor?.name, 'Studded Leather Armor');
    expect(character.equippedArmor?.category, 'Light');
    expect(
      character.weapons.map((w) => w.name),
      containsAll(['Scimitar', 'Shortsword', 'Longbow']),
    );
    // Scimitar/Shortsword are Finesse - the sheet's own "+ Add Weapon"
    // picker leaves this unset, but starting equipment should get it right.
    expect(
      character.weapons.firstWhere((w) => w.name == 'Scimitar').finesse,
      isTrue,
    );
    expect(character.currency.gp, 11);
  });

  test('buildNewCharacter grants option C as just 155 GP, no gear', () {
    final fighter = srdCatalog.classOptions.firstWhere(
      (c) => c.name == 'Fighter',
    );
    final dragonborn = srdCatalog.species.firstWhere(
      (s) => s.name == 'Dragonborn',
    );
    final soldier = srdCatalog.backgroundOptions.firstWhere(
      (b) => b.name == 'Soldier',
    );

    final character = buildNewCharacter(
      name: 'Option C Fighter',
      species: dragonborn,
      background: soldier,
      srdClass: fighter,
      abilityScores: const AbilityScores(
        str: 16,
        dex: 12,
        con: 14,
        intel: 10,
        wis: 10,
        cha: 8,
      ),
      chosenClassSkills: const ['Acrobatics', 'Perception'],
      classEquipmentOption: 'C',
    );

    expect(character.equippedArmor, isNull);
    expect(character.weapons, isEmpty);
    expect(character.currency.gp, 155);
  });

  test('buildNewCharacter leaves resources empty for a class without special-cased handling', () {
    final wizard = srdCatalog.classOptions.where((c) => c.name == 'Wizard');
    if (wizard.isEmpty) {
      return; // only guaranteed if Wizard is in the ported SRD class list
    }
    final human = srdCatalog.species.firstWhere((s) => s.name == 'Human');
    final sage = srdCatalog.backgroundOptions.firstWhere(
      (b) => b.name == 'Sage',
    );

    final character = buildNewCharacter(
      name: 'Test Wizard',
      species: human,
      background: sage,
      srdClass: wizard.first,
      abilityScores: const AbilityScores(
        str: 8,
        dex: 12,
        con: 14,
        intel: 16,
        wis: 10,
        cha: 10,
      ),
      chosenClassSkills: const [
        'Arcana',
        'History',
      ], // overlaps Sage's own grants - shouldn't duplicate
    );

    expect(character.resources, isEmpty);
    // Sage already grants Arcana + History; picking them again as class
    // skills shouldn't produce two SkillEntry rows for the same skill.
    expect(character.skills.where((s) => s.name == 'Arcana').length, 1);
    expect(character.skills.length, 2);

    // Wizard is a spellcasting class - buildNewCharacter should turn
    // spellcasting on automatically with the right ability and level-1 slots.
    expect(character.spellcasting, isNotNull);
    expect(character.spellcasting!.ability, 'int');
    expect(character.spellcasting!.slots[1]?.max, 2);
  });

  test(
    'buildNewCharacter leaves spellcasting off for a non-caster (Fighter)',
    () {
      final fighter = srdCatalog.classOptions.firstWhere(
        (c) => c.name == 'Fighter',
      );
      final dragonborn = srdCatalog.species.firstWhere(
        (s) => s.name == 'Dragonborn',
      );
      final soldier = srdCatalog.backgroundOptions.firstWhere(
        (b) => b.name == 'Soldier',
      );

      final character = buildNewCharacter(
        name: 'Test Fighter 2',
        species: dragonborn,
        background: soldier,
        srdClass: fighter,
        abilityScores: const AbilityScores(
          str: 16,
          dex: 12,
          con: 14,
          intel: 10,
          wis: 10,
          cha: 8,
        ),
        chosenClassSkills: const ['Acrobatics', 'Perception'],
      );

      expect(character.spellcasting, isNull);
    },
  );

  test('skillChoiceFor parses both "Choose N: list" and Bard\'s "Choose any N" shapes', () {
    final fighter = srdCatalog.classOptions.firstWhere(
      (c) => c.name == 'Fighter',
    );
    final fighterChoice = srdCatalog.skillChoiceFor(fighter.key)!;
    expect(fighterChoice.count, 2);
    expect(fighterChoice.choices, contains('Athletics'));
    expect(fighterChoice.choices, contains('Perception'));
    expect(fighterChoice.choices!.length, 9);

    final bard = srdCatalog.classOptions.where((c) => c.name == 'Bard');
    if (bard.isNotEmpty) {
      final bardChoice = srdCatalog.skillChoiceFor(bard.first.key)!;
      expect(bardChoice.count, 3);
      expect(bardChoice.choices, isNull); // any of the 18 skills
    }
  });

  test('standardArrayByClass matches the 2024 PHB\'s Standard Array by Class table for every SRD class, each using the same 6 numbers (15/14/13/12/10/8)', () {
    const expected = {
      'Barbarian': (15, 13, 14, 10, 12, 8),
      'Bard': (8, 14, 12, 13, 10, 15),
      'Cleric': (14, 8, 13, 10, 15, 12),
      'Druid': (8, 12, 14, 13, 15, 10),
      'Fighter': (15, 14, 13, 8, 10, 12),
      'Monk': (12, 15, 13, 10, 14, 8),
      'Paladin': (15, 10, 13, 8, 12, 14),
      'Ranger': (12, 15, 13, 8, 14, 10),
      'Rogue': (12, 15, 13, 14, 10, 8),
      'Sorcerer': (10, 13, 14, 8, 12, 15),
      'Warlock': (8, 14, 13, 12, 10, 15),
      'Wizard': (8, 12, 13, 15, 14, 10),
    };
    expect(standardArrayByClass.keys.toSet(), expected.keys.toSet());
    for (final entry in expected.entries) {
      final (str, dex, con, intel, wis, cha) = entry.value;
      final scores = standardArrayByClass[entry.key]!;
      expect(scores.str, str, reason: '${entry.key} Str');
      expect(scores.dex, dex, reason: '${entry.key} Dex');
      expect(scores.con, con, reason: '${entry.key} Con');
      expect(scores.intel, intel, reason: '${entry.key} Int');
      expect(scores.wis, wis, reason: '${entry.key} Wis');
      expect(scores.cha, cha, reason: '${entry.key} Cha');
      // Same 6 numbers every time, just reassigned - the Standard Array
      // itself never changes per class, only where its scores go.
      expect([str, dex, con, intel, wis, cha]..sort(), [
        8,
        10,
        12,
        13,
        14,
        15,
      ], reason: '${entry.key} uses the Standard Array');
    }
  });

  test('a Dragonborn made through New Character gets Breath Weapon as an attack (not just its uses), with the Draconic Ancestry damage type', () {
    SrdRefItem pick(List<SrdRefItem> items, String name) =>
        items.firstWhere((i) => i.name == name);
    final character = buildNewCharacter(
      name: 'Test Dragonborn',
      species: pick(srdCatalog.species, 'Dragonborn'),
      background: pick(srdCatalog.backgroundOptions, 'Soldier'),
      srdClass: pick(srdCatalog.classOptions, 'Fighter'),
      abilityScores: const AbilityScores(
        str: 16,
        dex: 12,
        con: 14,
        intel: 10,
        wis: 10,
        cha: 8,
      ),
      chosenClassSkills: const [],
    );

    final breath = character.innateAttacks.singleWhere(
      (a) => a.name == 'Breath Weapon',
    );
    expect(character.resources.any((r) => r.key == breath.resourceKey), isTrue);
    final info = rules.innateAttackInfo(character, breath);
    expect(info.diceCount, 1);
    expect(info.saveDc, 12); // 8 + Con +2 + PB +2

    character.speciesChoice = 'Blue';
    expect(rules.innateAttackDamageType(character, breath), 'Lightning');

    // Recalculating again (every app load does) never duplicates it.
    rules.recalculateClassResources(character);
    expect(
      character.innateAttacks.where((a) => a.name == 'Breath Weapon'),
      hasLength(1),
    );
  });

  test(
    'a non-Dragonborn gets no Breath Weapon, and a leftover one is dropped',
    () {
      SrdRefItem pick(List<SrdRefItem> items, String name) =>
          items.firstWhere((i) => i.name == name);
      final character = buildNewCharacter(
        name: 'Test Human',
        species: pick(srdCatalog.species, 'Human'),
        background: pick(srdCatalog.backgroundOptions, 'Soldier'),
        srdClass: pick(srdCatalog.classOptions, 'Fighter'),
        abilityScores: const AbilityScores(
          str: 16,
          dex: 12,
          con: 14,
          intel: 10,
          wis: 10,
          cha: 8,
        ),
        chosenClassSkills: const [],
      );
      expect(character.innateAttacks, isEmpty);

      character.innateAttacks = [
        InnateAttack(
          name: 'Breath Weapon',
          damageType: 'Fire',
          saveAbility: 'dex',
          desc: '',
          resourceKey: 'srd-2024_dragonborn-species_Breath Weapon',
        ),
      ];
      rules.recalculateClassResources(character);
      expect(character.innateAttacks, isEmpty);
    },
  );
}
