import 'package:flutter_test/flutter_test.dart';

import 'package:dnd_sheet/data/character_factory.dart';
import 'package:dnd_sheet/data/homebrew_catalog.dart';
import 'package:dnd_sheet/data/homebrew_repository.dart';
import 'package:dnd_sheet/data/srd_catalog.dart';
import 'package:dnd_sheet/domain/rules.dart' as rules;
import 'package:dnd_sheet/models/character.dart';
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
}
