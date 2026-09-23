import 'package:flutter_test/flutter_test.dart';

import 'package:dnd_sheet/data/character_factory.dart';
import 'package:dnd_sheet/data/homebrew_catalog.dart';
import 'package:dnd_sheet/data/homebrew_repository.dart';
import 'package:dnd_sheet/data/srd_catalog.dart';
import 'package:dnd_sheet/data/starting_equipment.dart';
import 'package:dnd_sheet/domain/rules.dart' as rules;
import 'package:dnd_sheet/models/character.dart';

SrdRefItem _pick(List<SrdRefItem> items, String name) =>
    items.firstWhere((i) => i.name == name);

Character _make({
  String cls = 'Fighter',
  String species = 'Human',
  String background = 'Soldier',
  Map<String, int> increases = const {'str': 2, 'con': 1},
  String? classEquipment,
  String? backgroundEquipment,
  int level = 1,
}) {
  final c = buildNewCharacter(
    name: 'Test',
    species: _pick(srdCatalog.species, species),
    background: _pick(srdCatalog.backgroundOptions, background),
    srdClass: _pick(srdCatalog.classOptions, cls),
    abilityScores: const AbilityScores(
      str: 14,
      dex: 14,
      con: 14,
      intel: 14,
      wis: 14,
      cha: 14,
    ),
    chosenClassSkills: const [],
    backgroundAbilityIncreases: increases,
    classEquipmentOption: classEquipment,
    backgroundEquipmentOption: backgroundEquipment,
  );
  while (c.level < level) {
    rules.levelUpOneLevel(c);
  }
  return c;
}

rules.FeatureOptionSet _set(Character c, String name) =>
    rules.featureOptionSet(c, name)!;

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await srdCatalog.init();
  });

  setUp(() => homebrewRepo.entries.clear());

  group('creation', () {
    test('background ability increases are applied and recorded', () {
      final c = _make(increases: const {'str': 2, 'con': 1});
      expect(c.abilityScores.str, 16);
      expect(c.abilityScores.con, 15);
      expect(c.backgroundAbilityIncreases, {'str': 2, 'con': 1});
      expect(rules.backgroundAbilityOptions(c.backgroundKey), [
        'str',
        'dex',
        'con',
      ]);
    });

    test(
      'every SRD class and background parses into lettered equipment packages',
      () {
        for (final cls in srdCatalog.classesByKey.values) {
          final options = classEquipmentOptions(cls.key);
          expect(options.length, greaterThanOrEqualTo(2), reason: cls.name);
          expect(options.last.items, isEmpty, reason: '${cls.name}: gold only');
        }
        for (final bg in srdCatalog.backgroundsByKey.values) {
          expect(backgroundEquipmentOptions(bg.key), hasLength(2));
        }
      },
    );

    test("starting equipment: weapons, armor, Shield, stacks, and coins", () {
      final barbarian = _make(
        cls: 'Barbarian',
        classEquipment: 'A',
        backgroundEquipment: 'A',
      );
      expect(
        barbarian.weapons.map((w) => w.name),
        containsAll(['Greataxe', 'Handaxe', 'Spear', 'Shortbow']),
      );
      expect(
        barbarian.inventory.any((i) => i.name == 'Handaxe' && i.quantity == 4),
        isTrue,
      );
      expect(barbarian.currency.gp, 15 + 14);

      final cleric = _make(
        cls: 'Cleric',
        background: 'Acolyte',
        increases: const {'wis': 2, 'cha': 1},
        classEquipment: 'A',
        backgroundEquipment: 'A',
      );
      expect(cleric.equippedArmor?.name, 'Chain Shirt');
      // Both packages include a Holy Symbol - one line, quantity 2.
      expect(
        cleric.inventory.where((i) => i.name == 'Holy Symbol').single.quantity,
        2,
      );
      expect(cleric.shieldEquipped, isTrue);

      // A focus named after a weapon is also that weapon.
      final druid = _make(cls: 'Druid', classEquipment: 'A');
      expect(druid.weapons.map((w) => w.name), contains('Quarterstaff'));
      expect(
        druid.inventory.map((i) => i.name),
        contains('Druidic Focus (Quarterstaff)'),
      );
    });

    test('a Human is asked for Skillful and a Versatile Origin feat', () {
      final c = _make();
      final ids = c.pendingChoices.map((p) => p.id);
      expect(ids, containsAll(['species:Skillful', 'species:Versatile']));
    });

    test("Acolyte's Magic Initiate (Cleric) asks for its cantrips, spell, and ability, and grants them", () {
      final c = _make(
        cls: 'Fighter',
        background: 'Acolyte',
        increases: const {'int': 1, 'wis': 1, 'cha': 1},
      );
      final sets = c.pendingChoices
          .where((p) => p.kind == 'option')
          .map((p) => p.optionSet);
      expect(
        sets,
        containsAll([
          'Magic Initiate (Cleric) Cantrips',
          'Magic Initiate (Cleric) Spell',
          'Magic Initiate (Cleric) Ability',
        ]),
      );
      final cantrips = _set(c, 'Magic Initiate (Cleric) Cantrips');
      expect(
        rules.optionsFor(c, cantrips).map((o) => o.name),
        contains('Sacred Flame'),
      );
      rules.chooseOptions(c, cantrips, ['Sacred Flame', 'Guidance']);
      rules.chooseOptions(c, _set(c, 'Magic Initiate (Cleric) Spell'), [
        'Bless',
      ]);
      rules.chooseOptions(c, _set(c, 'Magic Initiate (Cleric) Ability'), [
        'Wisdom',
      ]);
      final granted = c.spellcasting!.spells.where(
        (s) => s.source == 'Magic Initiate (Cleric)',
      );
      expect(granted, hasLength(3));
      final bless = granted.firstWhere(
        (s) => rules.knownSpellRef(s)!.name == 'Bless',
      );
      expect(bless.freeCasts, 1);
      expect(bless.abilityOverride, 'wis');
      expect(
        c.pendingChoices.where(
          (p) => p.optionSet?.startsWith('Magic') ?? false,
        ),
        isEmpty,
      );
    });
  });

  group('changing species, class, background', () {
    test('changing class rebuilds hit die, saves, features, spellcasting, and weapon proficiency', () {
      final c = _make(cls: 'Fighter', classEquipment: 'A', level: 5);
      expect(
        c.weapons.firstWhere((w) => w.name == 'Greatsword').proficient,
        isTrue,
      );
      rules.changeClass(c, 'srd-2024_wizard-class', 'Wizard');
      expect(c.hitDiceDie, 'd6');
      expect(c.savingThrowProficiencies.toSet(), {'int', 'wis'});
      expect(c.features.map((f) => f.name), contains('Arcane Recovery'));
      expect(c.features.map((f) => f.name), isNot(contains('Second Wind')));
      expect(c.spellcasting?.slots[3]?.max, 2);
      expect(
        c.weapons.firstWhere((w) => w.name == 'Greatsword').proficient,
        isFalse,
      );
      expect(c.weaponMasteries, isEmpty);
      expect(c.maxHp, c.currentHp);
    });

    test('changing species updates speed, species options, and HP bonus', () {
      final c = _make();
      rules.changeSpecies(c, 'srd-2024_goliath-species', 'Goliath');
      expect(c.speed, 35);
      expect(
        c.pendingChoices.map((p) => p.id),
        contains('species:Giant Ancestry'),
      );
      expect(
        c.pendingChoices.map((p) => p.id),
        isNot(contains('species:Skillful')),
      );
      final hp = c.maxHp;
      rules.changeSpecies(c, 'srd-2024_dwarf-species', 'Dwarf');
      expect(c.maxHp, hp + 1); // Dwarven Toughness at level 1
    });

    test(
      'changing background swaps its skills, feat, and ability increases',
      () {
        final c = _make(increases: const {'str': 2, 'con': 1});
        expect(
          c.skills.map((s) => s.name),
          containsAll(['Athletics', 'Intimidation']),
        );
        rules.changeBackground(c, 'srd-2024_sage-background', 'Sage', const {
          'int': 2,
          'wis': 1,
        });
        expect(c.abilityScores.str, 14);
        expect(c.abilityScores.con, 14);
        expect(c.abilityScores.intel, 16);
        expect(c.skills.map((s) => s.name), isNot(contains('Athletics')));
        expect(c.skills.map((s) => s.name), containsAll(['Arcana', 'History']));
        expect(c.feats.map((f) => f.name), contains('Magic Initiate (Wizard)'));
        expect(
          c.pendingChoices.map((p) => p.optionSet),
          contains('Magic Initiate (Wizard) Cantrips'),
        );
      },
    );
  });

  group('feature options', () {
    test('Eldritch Invocations: parsed from the SRD, counted by the table, gated by level and prerequisites', () {
      final c = _make(cls: 'Warlock', increases: const {'cha': 2, 'con': 1});
      final set = _set(c, 'Eldritch Invocations');
      final options = rules.optionsFor(c, set);
      expect(options, hasLength(28));
      expect(rules.optionCount(c, set), 1);
      final thirsting = options.firstWhere((o) => o.name == 'Thirsting Blade');
      expect(thirsting.minLevel, 5);
      expect(thirsting.requires, 'Pact of the Blade');
      expect(rules.optionAvailable(c, set, thirsting), isFalse);

      rules.chooseOptions(c, set, ['Armor of Shadows']);
      expect(c.features.map((f) => f.name), contains('Armor of Shadows'));
      // Its at-will Mage Armor is granted.
      final mageArmor = c.spellcasting!.spells.firstWhere(
        (s) => s.source == 'Armor of Shadows',
      );
      expect(mageArmor.freeCasts, rules.atWill);

      rules.levelUpOneLevel(c); // level 2: 3 invocations
      final pending = c.pendingChoices.where(
        (p) => p.optionSet == 'Eldritch Invocations',
      );
      expect(pending.single.count, 2);
    });

    test('Divine Order: Protector adds Heavy armor and Martial weapons; Thaumaturge adds a cantrip and skill bonus', () {
      final protector = _make(
        cls: 'Cleric',
        increases: const {'wis': 2, 'con': 1},
      );
      rules.chooseOptions(protector, _set(protector, 'Divine Order'), [
        'Protector',
      ]);
      expect(rules.armorTraining(protector), contains('Heavy'));
      expect(
        rules.isProficientWithWeapon(
          protector,
          'Longsword',
          'Martial Melee Weapons',
          const [],
        ),
        isTrue,
      );
      expect(
        rules.sheetText(
          protector,
          GrantedFeature(name: 'Divine Order', source: 'class'),
        ),
        startsWith('Protector: '),
      );

      final thaum = _make(cls: 'Cleric', increases: const {'wis': 2, 'con': 1});
      final before = rules.cantripLimit(thaum)!;
      rules.chooseOptions(thaum, _set(thaum, 'Divine Order'), ['Thaumaturge']);
      expect(rules.cantripLimit(thaum), before + 1);
      final arcana = SkillEntry(
        name: 'Arcana',
        ability: 'int',
        proficient: false,
      );
      expect(rules.skillModifier(thaum, arcana), 2 + 3); // Int +2, Wis +3
    });

    test(
      'Expertise picks set the skill; Weapon Mastery picks limit masteries',
      () {
        final rogue = _make(
          cls: 'Rogue',
          increases: const {'dex': 2, 'con': 1},
        );
        rogue.skills = [
          SkillEntry(name: 'Stealth', ability: 'dex', proficient: true),
          SkillEntry(name: 'Perception', ability: 'wis', proficient: true),
        ];
        rules.chooseOptions(rogue, _set(rogue, 'Expertise'), ['Stealth']);
        expect(
          rogue.skills.firstWhere((s) => s.name == 'Stealth').expertise,
          isTrue,
        );

        final fighter = _make();
        final mastery = _set(fighter, 'Weapon Mastery');
        expect(rules.optionCount(fighter, mastery), 3);
        rules.chooseOptions(fighter, mastery, [
          'Longsword',
          'Longbow',
          'Greataxe',
        ]);
        expect(fighter.weaponMasteries, ['Longsword', 'Longbow', 'Greataxe']);
      },
    );

    test(
      'Giant Ancestry and Gnomish Lineage options come from the trait text',
      () {
        final goliath = _make(species: 'Goliath');
        final boons = rules.optionsFor(
          goliath,
          _set(goliath, 'Giant Ancestry'),
        );
        expect(boons, hasLength(6));
        expect(boons.first.name, startsWith('Cloud'));
        final gnome = _make(species: 'Gnome');
        expect(
          rules
              .optionsFor(gnome, _set(gnome, 'Gnomish Lineage'))
              .map((o) => o.name),
          ['Forest Gnome', 'Rock Gnome'],
        );
      },
    );

    test('species and option resistances reach Take Damage', () {
      final dwarf = _make(species: 'Dwarf');
      expect(
        rules
            .computeDamageTaken(dwarf, 10, 'poison', magical: false)
            .finalAmount,
        5,
      );
      final tiefling = _make(species: 'Tiefling')..speciesChoice = 'Infernal';
      expect(
        rules
            .computeDamageTaken(tiefling, 10, 'fire', magical: false)
            .finalAmount,
        5,
      );
      expect(
        rules
            .computeDamageTaken(tiefling, 10, 'cold', magical: false)
            .finalAmount,
        10,
      );
    });
  });

  group('granted spells', () {
    test(
      "Paladin's Smite grants Divine Smite with one free cast per Long Rest",
      () {
        final c = _make(
          cls: 'Paladin',
          level: 2,
          increases: const {'str': 2, 'con': 1},
        );
        final smite = c.spellcasting!.spells.firstWhere(
          (s) => s.source == "Paladin's Smite",
        );
        expect(rules.knownSpellRef(smite)!.name, 'Divine Smite');
        rules.castSpell(c, rules.knownSpellRef(smite)!, freeCastFrom: smite);
        expect(rules.freeCastsLeft(smite), 0);
        rules.applyShortRest(c);
        expect(rules.freeCastsLeft(smite), 0);
        rules.applyLongRest(c);
        expect(rules.freeCastsLeft(smite), 1);
      },
    );

    test('a Life Domain Cleric gets their domain spells by level', () {
      final c = _make(
        cls: 'Cleric',
        level: 5,
        increases: const {'wis': 2, 'con': 1},
      );
      final choice = c.pendingChoices.firstWhere((p) => p.kind == 'subclass');
      rules.resolveSubclassChoice(
        c,
        choice.id,
        'srd-2024_life-domain-subclass',
      );
      final names = c.spellcasting!.spells
          .where((s) => s.source == 'Life Domain Spells')
          .map((s) => rules.knownSpellRef(s)!.name)
          .toSet();
      expect(
        names,
        containsAll(['Aid', 'Bless', 'Revivify', 'Mass Healing Word']),
      );
      expect(names, isNot(contains('Death Ward'))); // level 7
    });

    test("a High Elf Fighter gets lineage spells at 1, 3, and 5 with the chosen ability", () {
      final c = _make(species: 'Elf')..speciesChoice = 'High Elf';
      rules.chooseOptions(c, _set(c, 'Lineage Spellcasting Ability'), [
        'Intelligence',
      ]);
      while (c.level < 5) {
        rules.levelUpOneLevel(c);
      }
      final lineage = {
        for (final s in c.spellcasting!.spells.where(
          (s) => s.source == 'Elven Lineage',
        ))
          rules.knownSpellRef(s)!.name: s,
      };
      expect(
        lineage.keys,
        containsAll(['Prestidigitation', 'Detect Magic', 'Misty Step']),
      );
      expect(lineage['Misty Step']!.abilityOverride, 'int');
      expect(lineage['Misty Step']!.freeCasts, 1);
      // A Fighter still gets no class spellcasting - just these.
      expect(c.spellcasting!.slots, isEmpty);
    });

    test(
      'syncGrantedSpells is idempotent and drops spells whose source is gone',
      () {
        final c = _make(
          cls: 'Paladin',
          level: 2,
          increases: const {'str': 2, 'con': 1},
        );
        final count = c.spellcasting!.spells.length;
        rules.syncGrantedSpells(c);
        rules.syncGrantedSpells(c);
        expect(c.spellcasting!.spells.length, count);
        c.features = c.features
            .where((f) => f.name != "Paladin's Smite")
            .toList();
        rules.syncGrantedSpells(c);
        expect(
          c.spellcasting!.spells.any((s) => s.source == "Paladin's Smite"),
          isFalse,
        );
      },
    );
  });

  test('XP thresholds, size options', () {
    final c = _make()..experiencePoints = 250;
    expect(rules.xpForNextLevel(c), 300);
    expect(rules.readyToLevelUp(c), isFalse);
    c.experiencePoints = 300;
    expect(rules.readyToLevelUp(c), isTrue);
    expect(rules.speciesSizeOptions('srd-2024_human-species'), [
      'Medium',
      'Small',
    ]);
    c.sizeChoice = 'Small';
    expect(rules.sizeFor(c), 'Small');
    expect(rules.speciesSizeOptions('srd-2024_gnome-species'), ['Small']);
  });

  group('items, unarmed strike, homebrew stats', () {
    test(
      'itemInfo finds gear, tools, magic items (with attunement), and weapons',
      () {
        expect(rules.itemInfo("Explorer's Pack")?.kind, 'Gear');
        expect(rules.itemInfo("Thieves' Tools")?.kind, 'Tool');
        final amulet = rules.itemInfo('Amulet of the Planes')!;
        expect(amulet.requiresAttunement, isTrue);
        expect(amulet.rarity, 'Very Rare');
        expect(rules.itemInfo('Longsword')?.desc, contains('Slashing'));
        expect(rules.itemInfo('Druidic Focus (Quarterstaff)'), isNotNull);
        expect(rules.itemInfo('A Very Specific Rock'), isNull);
      },
    );

    test('attunement limit is 3, or 4 with Use Magic Device', () {
      final c = _make();
      expect(rules.attunementLimit(c), 3);
      c.features = [
        ...c.features,
        GrantedFeature(name: 'Use Magic Device', source: 'Thief'),
      ];
      expect(rules.attunementLimit(c), 4);
    });

    test(
      'Unarmed Strike: 1 + Str normally; Martial Arts die and Dex for a Monk',
      () {
        final fighter = _make(increases: const {'str': 2, 'con': 1}); // Str 16
        final u = rules.unarmedStrike(fighter);
        expect(u.attack, 3 + 2);
        expect(u.damage, '4 Bludgeoning');
        expect(u.grappleDc, 8 + 3 + 2);
        final monk = _make(cls: 'Monk', increases: const {'dex': 2, 'wis': 1});
        final m = rules.unarmedStrike(monk);
        expect(m.ability, 'Dex');
        expect(m.damage, '1d6+3 Bludgeoning');
      },
    );

    test(
      'homebrew weapon and armor stats round-trip through the entry data',
      () {
        final stats = WeaponStats(
          damageDice: '1d10',
          damageType: 'Force',
          category: 'Martial Ranged Weapons',
          properties: ['Ammunition', 'Heavy'],
          mastery: 'Slow',
        );
        final back = WeaponStats.fromData(stats.toData())!;
        final w = back.toWeapon('Arc Caster', proficient: true);
        expect(rules.isRangedWeapon(w), isTrue);
        expect(w.masteryDesc, isNotNull);

        final armor = ArmorStats(
          category: 'Medium',
          baseAc: 14,
          dexMode: 'max2',
        );
        expect(armor.formula, '14 + Dex modifier (max 2)');
        final parsed = ArmorStats.fromFormula('15 + Dex modifier (max 2)');
        expect(parsed.baseAc, 15);
        expect(parsed.dexMode, 'max2');
      },
    );

    test(
      'pdfAttackRowCount counts weapons, innate attacks, and damage cantrips',
      () {
        final c = _make(cls: 'Wizard', increases: const {'int': 2, 'con': 1});
        String key(String n) =>
            srdCatalog.spells.firstWhere((s) => s.name == n).key;
        c.spellcasting!.cantripsKnown = [key('Fire Bolt'), key('Light')];
        expect(rules.pdfAttackRowCount(c), c.weapons.length + 1);
      },
    );
  });
}
