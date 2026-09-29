import 'package:flutter_test/flutter_test.dart';

import 'package:dnd_sheet/data/character_factory.dart';
import 'package:dnd_sheet/data/homebrew_catalog.dart';
import 'package:dnd_sheet/data/homebrew_repository.dart';
import 'package:dnd_sheet/data/srd_catalog.dart';
import 'package:dnd_sheet/domain/rules.dart' as rules;
import 'package:dnd_sheet/models/character.dart';
import 'package:dnd_sheet/models/effect.dart';
import 'package:dnd_sheet/models/homebrew.dart';

/// Creates a homebrew entry with [data] and registers it the way the app
/// does after every save.
HomebrewEntry _entry(
  String kind,
  String name,
  Map<String, dynamic> data, {
  String desc = '',
}) {
  final e = homebrewRepo.create(kind, name);
  homebrewRepo.update(e.copyWith(data: data, desc: desc, source: 'official'));
  registerHomebrewInCatalog();
  return homebrewRepo.entries.firstWhere((x) => x.id == e.id);
}

SrdRefItem _srd(List<SrdRefItem> items, String name) =>
    items.firstWhere((i) => i.name == name);

Character _build({
  required SrdRefItem species,
  required SrdRefItem cls,
  SrdRefItem? background,
}) => buildNewCharacter(
  name: 'Brew',
  species: species,
  background: background ?? _srd(srdCatalog.backgroundOptions, 'Soldier'),
  srdClass: cls,
  abilityScores: const AbilityScores(
    str: 10,
    dex: 14,
    con: 14,
    intel: 16,
    wis: 10,
    cha: 10,
  ),
  chosenClassSkills: const [],
);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await srdCatalog.init();
  });

  setUp(() {
    homebrewRepo.entries.clear();
    registerHomebrewInCatalog();
  });

  test(
    'a homebrew species: speed, traits with sheet text, and resistances',
    () {
      final e = _entry('species', 'Frostkin', {
        'size': 'Medium',
        'speed': 40,
        'resistances': ['Cold'],
        'traits': [
          {
            'name': 'Rimeblood',
            'desc': 'Long rules text about cold.',
            'shortDesc': 'Resistance to Cold.',
          },
        ],
      });
      final c = _build(
        species: SrdRefItem(key: e.id, name: e.name, isHomebrew: true),
        cls: _srd(srdCatalog.classOptions, 'Fighter'),
      );
      expect(c.speed, 40);
      final trait = rules.speciesTraitFeatures(c).single;
      expect(trait.name, 'Rimeblood');
      expect(rules.sheetText(c, trait), 'Resistance to Cold.');
      expect(
        rules.computeDamageTaken(c, 10, 'cold', magical: false).finalAmount,
        5,
      );
    },
  );

  test('a homebrew full-caster class: hit die, saves, slots, features, ASI and subclass choices', () {
    final e = _entry('class', 'Runescribe', {
      'hitDie': 'd8',
      'saves': ['int', 'wis'],
      'casterType': 'full',
      'spellAbility': 'int',
      'armorTraining': ['Light'],
      'features': [
        {
          'level': 1,
          'name': 'Runic Script',
          'desc': 'Write runes.',
          'shortDesc': 'Runes!',
        },
        {'level': 2, 'name': 'Glyph Ward', 'desc': 'Ward yourself.'},
      ],
    });
    final c = _build(
      species: _srd(srdCatalog.species, 'Human'),
      cls: SrdRefItem(key: e.id, name: e.name, isHomebrew: true),
    );
    expect(c.hitDiceDie, 'd8');
    expect(c.savingThrowProficiencies.toSet(), {'int', 'wis'});
    expect(c.features.map((f) => f.name), ['Runic Script']);
    expect(c.spellcasting?.ability, 'int');
    expect(c.spellcasting?.slots[1]?.max, 2);
    expect(rules.sheetText(c, c.features.single), 'Runes!');
    expect(rules.armorTraining(c), {'Light'});

    while (c.level < 4) {
      rules.levelUpOneLevel(c);
    }
    expect(c.features.map((f) => f.name), contains('Glyph Ward'));
    final kinds = c.pendingChoices.map((p) => p.kind ?? p.label).toList();
    expect(kinds, contains('subclass'));
    expect(kinds, contains('asi'));
  });

  test('a homebrew subclass for an SRD class: offered, and grants features and spells', () {
    final e = _entry('subclass', 'Battle Master', {
      'parentClass': 'srd-2024_fighter-class',
      'features': [
        {'level': 3, 'name': 'Combat Superiority', 'desc': 'Maneuvers.'},
        {'level': 7, 'name': 'Know Your Enemy', 'desc': 'Study a foe.'},
      ],
      'spells': [
        {
          'level': 3,
          'spells': ['Shield'],
        },
      ],
    });
    final c = _build(
      species: _srd(srdCatalog.species, 'Human'),
      cls: _srd(srdCatalog.classOptions, 'Fighter'),
    );
    while (c.level < 3) {
      rules.levelUpOneLevel(c);
    }
    expect(
      rules.subclassOptionsFor(c).map((s) => s.name),
      containsAll(['Champion', 'Battle Master']),
    );
    final choice = c.pendingChoices.firstWhere((p) => p.kind == 'subclass');
    rules.resolveSubclassChoice(c, choice.id, e.id);
    expect(c.subclassKey, e.id);
    expect(c.features.map((f) => f.name), contains('Combat Superiority'));
    expect(c.features.map((f) => f.name), isNot(contains('Know Your Enemy')));
    expect(
      c.spellcasting!.spells.map((s) => rules.knownSpellRef(s)!.name),
      contains('Shield'),
    );
    rules.levelUpOneLevel(c);
    rules.levelUpOneLevel(c);
    rules.levelUpOneLevel(c);
    rules.levelUpOneLevel(c);
    expect(c.features.map((f) => f.name), contains('Know Your Enemy'));
  });

  test('a homebrew background: abilities, skills, feat', () {
    final e = _entry('background', 'Sailor', {
      'abilityScores': ['Strength', 'Dexterity', 'Wisdom'],
      'skills': ['Athletics', 'Perception'],
      'tool': "Navigator's Tools",
      'feat': 'Tough',
    });
    expect(rules.backgroundAbilityOptions(e.id), ['str', 'dex', 'wis']);
    final c = _build(
      species: _srd(srdCatalog.species, 'Human'),
      cls: _srd(srdCatalog.classOptions, 'Fighter'),
      background: SrdRefItem(key: e.id, name: e.name, isHomebrew: true),
    );
    expect(
      c.skills.map((s) => s.name),
      containsAll(['Athletics', 'Perception']),
    );
    expect(c.feats.map((f) => f.name), contains('Tough'));
  });

  test("a homebrew spell's stat block drives the Spells tab", () {
    final e = _entry('spell', 'Frost Lance', {
      'level': 2,
      'school': 'Evocation',
      'castingTime': 'Action',
      'range': '90 feet',
      'components': 'V, S',
      'duration': 'Instantaneous',
      'classes': ['Wizard'],
    }, desc: 'Make a ranged spell attack. On a hit, 3d8 Cold damage.');
    final ref = rules.spellRefFor(e.id)!;
    expect(ref.level, 2);
    expect(ref.school, 'Evocation');
    expect(rules.spellDamageInfo(ref, 5).dice, '3d8');
  });

  test('a homebrew magic weapon carries its bonus and special features onto the weapon', () {
    final e = _entry('weapon', 'Flame Tongue Test', {
      'damageDice': '2d6',
      'damageType': 'Slashing',
      'category': 'Martial Melee Weapons',
      'properties': ['Heavy', 'Two-Handed'],
      'rarity': 'Very Rare',
      'requiresAttunement': true,
      'magicBonus': 2,
      'specialFeatures': ['Kindling: extra fire on consecutive hits.'],
    });
    final weapon = WeaponStats.fromData(e.data)!
        .toWeapon(e.name, proficient: true);
    expect(weapon.magicBonus, 2);
    expect(weapon.specialFeatures, [
      'Kindling: extra fire on consecutive hits.',
    ]);
    final info = rules.itemInfo('Flame Tongue Test')!;
    expect(info.rarity, 'Very Rare');
    expect(info.requiresAttunement, isTrue);

    // With no base weapon, the name says nothing about its kind...
    final c = _build(
      species: _srd(srdCatalog.species, 'Human'),
      cls: _srd(srdCatalog.classOptions, 'Fighter'),
    );
    c.weaponMasteries = ['Greatsword'];
    weapon.mastery = 'Graze';
    expect(rules.masteryApplies(c, weapon), isFalse);
    // ...with one, a Greatsword mastery pick covers it.
    final based = WeaponStats.fromData({
      ...e.data,
      'baseWeapon': 'Greatsword',
      'mastery': 'Graze',
    })!.toWeapon(e.name, proficient: true);
    expect(based.baseWeapon, 'Greatsword');
    expect(rules.masteryApplies(c, based), isTrue);
    expect(Weapon.fromJson(based.toJson()).baseWeapon, 'Greatsword');

    // An entry saved before these fields existed still reads as mundane.
    final plain = WeaponStats.fromData({'damageDice': '1d8'})!;
    expect(plain.magicBonus, 0);
    expect(plain.specialFeatures, isEmpty);
  });

  test('a carried magic item with charges gets a resource', () {
    _entry('magicItem', 'Wand of Sparks', {
      'itemCategory': 'Wand',
      'rarity': 'Uncommon',
      'charges': 7,
      'recharge': 'dawn',
    });
    final c = _build(
      species: _srd(srdCatalog.species, 'Human'),
      cls: _srd(srdCatalog.classOptions, 'Fighter'),
    );
    c.inventory = [InventoryEntry(name: 'Wand of Sparks', quantity: 1)];
    rules.recalculateClassResources(c);
    final r = c.resources.firstWhere((r) => r.name == 'Wand of Sparks charges');
    expect(r.max, 7);
    expect(rules.isCustomResource(c, r), isFalse);
    expect(rules.itemInfo('Wand of Sparks')?.rarity, 'Uncommon');
    c.inventory = [];
    rules.recalculateClassResources(c);
    expect(c.resources.any((r) => r.name == 'Wand of Sparks charges'), isFalse);
  });

  group('set scores, Pact of the Tome, Lessons, homebrew grants', () {
    test(
      'a Belt of Giant Strength sets Strength while attuned, only if higher',
      () {
        _entry('magicItem', 'Belt of Giant Strength', {'rarity': 'Rare'});
        final belt = homebrewRepo.entries.firstWhere(
          (e) => e.kind == 'magicItem',
        );
        homebrewRepo.update(
          belt.copyWith(
            effects: const [Effect(target: 'setScore:str', formula: '21')],
          ),
        );
        final c = _build(
          species: _srd(srdCatalog.species, 'Human'),
          cls: _srd(srdCatalog.classOptions, 'Fighter'),
        );
        final item = InventoryEntry(
          name: 'Belt of Giant Strength',
          quantity: 1,
        );
        c.inventory = [item];
        expect(rules.effectiveScores(c).str, 10); // not attuned
        item.attuned = true;
        expect(rules.effectiveScores(c).str, 21);
        expect(rules.modifierOf(c, 'str'), 5);
        expect(c.abilityScores.str, 10); // the character's own is unchanged
        final greataxe = rules.weaponFromSrd(
          c,
          srdCatalog.weaponsByKey.values.firstWhere(
            (w) => w.name == 'Greataxe',
          ),
        );
        expect(rules.attackFor(c, greataxe).bonus, 5 + 2);
        c.abilityScores = const AbilityScores(
          str: 22,
          dex: 10,
          con: 10,
          intel: 10,
          wis: 10,
          cha: 10,
        );
        expect(rules.effectiveScores(c).str, 22);
      },
    );

    test(
      'Pact of the Tome asks for its Book of Shadows spells and grants them',
      () {
        final c = _build(
          species: _srd(srdCatalog.species, 'Human'),
          cls: _srd(srdCatalog.classOptions, 'Warlock'),
        );
        rules.chooseOptions(
          c,
          rules.featureOptionSet(c, 'Eldritch Invocations')!,
          ['Pact of the Tome'],
        );
        expect(
          c.pendingChoices.map((p) => p.optionSet),
          containsAll(['Book of Shadows Cantrips', 'Book of Shadows Rituals']),
        );
        final rituals = rules.featureOptionSet(c, 'Book of Shadows Rituals')!;
        final options = rules.optionsFor(c, rituals).map((o) => o.name);
        expect(options, contains('Detect Magic'));
        expect(options, isNot(contains('Magic Missile'))); // not a Ritual
        rules.chooseOptions(c, rituals, ['Detect Magic', 'Find Familiar']);
        rules.chooseOptions(
          c,
          rules.featureOptionSet(c, 'Book of Shadows Cantrips')!,
          ['Guidance', 'Light', 'Fire Bolt'],
        );
        final tome = c.spellcasting!.spells.where(
          (s) => s.source == 'Pact of the Tome',
        );
        expect(tome, hasLength(5));
      },
    );

    test('Lessons of the First Ones asks for an Origin feat', () {
      final c = _build(
        species: _srd(srdCatalog.species, 'Human'),
        cls: _srd(srdCatalog.classOptions, 'Warlock'),
      );
      rules.levelUpOneLevel(c);
      rules.chooseOptions(
        c,
        rules.featureOptionSet(c, 'Eldritch Invocations')!,
        ['Lessons of the First Ones'],
      );
      final choice = c.pendingChoices.firstWhere(
        (p) => p.label.startsWith('Lessons of the First Ones'),
      );
      expect(choice.featCategory, 'Origin Feat');
    });

    test('a homebrew feat can grant spells and a feat pick', () {
      _entry('feat', 'Fey Touched', {
        'featChoice': 'Origin Feat',
        'grantedSpells': [
          {
            'name': 'Misty Step',
            'freeCasts': 1,
            'recovery': 'long',
            'ability': 'cha',
          },
        ],
      });
      final c = _build(
        species: _srd(srdCatalog.species, 'Human'),
        cls: _srd(srdCatalog.classOptions, 'Fighter'),
      );
      rules.grantFeat(c, GrantedFeature(name: 'Fey Touched', source: 'feat'));
      final misty = c.spellcasting!.spells.single;
      expect(misty.source, 'Fey Touched');
      expect(misty.freeCasts, 1);
      expect(misty.abilityOverride, 'cha');
      expect(
        c.pendingChoices.any(
          (p) =>
              p.label == 'Fey Touched: choose a feat' &&
              p.featCategory == 'Origin Feat',
        ),
        isTrue,
      );
    });

    test(
      'a homebrew species grants spells by level, including homebrew spells',
      () {
        _entry('spell', 'Moonbeam Whisper', {'level': 1, 'school': 'Illusion'});
        final e = _entry('species', 'Moonkin', {
          'speed': 30,
          'featChoice': 'any',
          'grantedSpells': [
            {'name': 'Light', 'level': 1},
            {'name': 'Moonbeam Whisper', 'level': 3, 'freeCasts': 1},
          ],
        });
        final c = _build(
          species: SrdRefItem(key: e.id, name: e.name, isHomebrew: true),
          cls: _srd(srdCatalog.classOptions, 'Fighter'),
        );
        Iterable<String> names() => c.spellcasting!.spells
            .where((s) => s.source == 'Moonkin')
            .map((s) => rules.knownSpellRef(s)!.name);
        expect(names(), ['Light']);
        expect(
          c.pendingChoices.map((p) => p.id),
          contains('species:featChoice'),
        );
        rules.levelUpOneLevel(c);
        rules.levelUpOneLevel(c);
        expect(names(), containsAll(['Light', 'Moonbeam Whisper']));
      },
    );
  });
}
