import 'package:uuid/uuid.dart';

import '../domain/rules.dart' as rules;
import '../models/character.dart';
import 'srd_catalog.dart';

const _uuid = Uuid();
const fighterClassKey = 'srd-2024_fighter-class';

/// One of Fighter's three "Choose A, B, or C" starting equipment
/// packages - hardcoded verbatim from classes.json's Starting Equipment
/// trait text rather than parsed at runtime, since the free SRD only
/// phrases this consistently enough to parse automatically for a single
/// class, and Fighter is the only one in scope so far.
class FighterEquipmentOption {
  const FighterEquipmentOption({required this.id, required this.summary});
  final String id; // 'A' | 'B' | 'C'
  final String summary; // shown to the player, verbatim from the SRD
}

const fighterStartingEquipmentOptions = [
  FighterEquipmentOption(
    id: 'A',
    summary: "Chain Mail, Greatsword, Flail, 8 Javelins, Dungeoneer's Pack, and 4 GP",
  ),
  FighterEquipmentOption(
    id: 'B',
    summary: "Studded Leather Armor, Scimitar, Shortsword, Longbow, 20 Arrows, Quiver, Dungeoneer's Pack, and 11 GP",
  ),
  FighterEquipmentOption(id: 'C', summary: '155 GP'),
];

/// The 2024 PHB's "Standard Array by Class" table (Character Creation,
/// Step 3) - a suggested Str/Dex/Con/Int/Wis/Cha assignment of the
/// Standard Array (15, 14, 13, 12, 10, 8) per class, putting the highest
/// scores in that class's main abilities. Hardcoded verbatim from
/// assets/srd/reference/character-creation.json's own table (bundled,
/// freely-licensed SRD content) rather than parsed at runtime, since nothing
/// else needs to read that chapter's prose as structured data. Purely a
/// starting suggestion, same as the real table - New Character's ability
/// score fields stay freely editable either way.
const standardArrayByClass = {
  'Barbarian': AbilityScores(
    str: 15,
    dex: 13,
    con: 14,
    intel: 10,
    wis: 12,
    cha: 8,
  ),
  'Bard': AbilityScores(str: 8, dex: 14, con: 12, intel: 13, wis: 10, cha: 15),
  'Cleric': AbilityScores(
    str: 14,
    dex: 8,
    con: 13,
    intel: 10,
    wis: 15,
    cha: 12,
  ),
  'Druid': AbilityScores(str: 8, dex: 12, con: 14, intel: 13, wis: 15, cha: 10),
  'Fighter': AbilityScores(
    str: 15,
    dex: 14,
    con: 13,
    intel: 8,
    wis: 10,
    cha: 12,
  ),
  'Monk': AbilityScores(str: 12, dex: 15, con: 13, intel: 10, wis: 14, cha: 8),
  'Paladin': AbilityScores(
    str: 15,
    dex: 10,
    con: 13,
    intel: 8,
    wis: 12,
    cha: 14,
  ),
  'Ranger': AbilityScores(
    str: 12,
    dex: 15,
    con: 13,
    intel: 8,
    wis: 14,
    cha: 10,
  ),
  'Rogue': AbilityScores(str: 12, dex: 15, con: 13, intel: 14, wis: 10, cha: 8),
  'Sorcerer': AbilityScores(
    str: 10,
    dex: 13,
    con: 14,
    intel: 8,
    wis: 12,
    cha: 15,
  ),
  'Warlock': AbilityScores(
    str: 8,
    dex: 14,
    con: 13,
    intel: 12,
    wis: 10,
    cha: 15,
  ),
  'Wizard': AbilityScores(
    str: 8,
    dex: 12,
    con: 13,
    intel: 15,
    wis: 14,
    cha: 10,
  ),
};

/// Builds a fresh level-1 Character from New Character's picks. Deliberately
/// modest: no species traits granted (beyond a resource, if the species
/// grants one - see below), no subclass (real classes don't grant one
/// until level 3 anyway) - just what can be computed honestly from the
/// SRD data actually ported: Hit Point Die, Saving Throw Proficiencies,
/// skill proficiencies from the background plus the player's class skill
/// picks, level-1 resources (class + species) and class features, Pending
/// Choices for any level-1 choice-driven feature (Fighting Style, ...),
/// and - if [fighterEquipmentOption] is given on a Fighter - real starting
/// gear. Everything else is left for the player to fill in on the sheet
/// afterward, the same as this app already lets you do for Jarson.
Character buildNewCharacter({
  required String name,
  required SrdRefItem species,
  required SrdRefItem background,
  required SrdRefItem srdClass,
  required AbilityScores abilityScores,
  required List<String> chosenClassSkills,
  String? fighterEquipmentOption,
}) {
  final classInfo = srdCatalog.byKey(srdClass.key);
  final hitDie = rules.parseHitDie(classInfo?.traits['Hit Point Die']) ?? 'd8';
  final savingThrows = rules.parseSavingThrows(
    classInfo?.traits['Saving Throw Proficiencies'],
  );
  final conMod = rules.abilityModifier(abilityScores.con);
  final maxHp = rules.maxHpForLevel(die: hitDie, conModifier: conMod, level: 1);

  final backgroundInfo = srdCatalog.backgroundsByKey[background.key];
  final skillNames = {
    ...?backgroundInfo?.skillProficiencies,
    ...chosenClassSkills,
  };
  final skills = skillNames
      .map((skillName) {
        final ref = srdCatalog.skillsByName[skillName];
        if (ref == null) return null;
        return SkillEntry(
          name: ref.name,
          ability: ref.ability,
          proficient: true,
        );
      })
      .whereType<SkillEntry>()
      .toList();

  final feats = <GrantedFeature>[
    if (backgroundInfo?.feat != null)
      GrantedFeature(name: backgroundInfo!.feat!, source: 'background'),
  ];

  final character = Character(
    id: _uuid.v4(),
    name: name,
    speciesLabel: species.name,
    speciesKey: species.key,
    backgroundLabel: background.name,
    backgroundKey: background.key,
    classLabel: srdClass.name,
    classKey: srdClass.key,
    level: 1,
    abilityScores: abilityScores,
    maxHp: maxHp,
    currentHp: maxHp,
    // Unarmored (equippedArmor null, no shield) - AC computes to 10 + Dex
    // modifier automatically, see domain/rules.dart's armorClassFor.
    hitDiceDie: hitDie,
    hitDiceTotal: 1,
    savingThrowProficiencies: savingThrows,
    skills: skills,
    resources: const [],
    pendingChoices: const [],
    weapons: const [],
    features: const [],
    feats: feats,
    inventory: const [],
    currency: const Currency(),
  );

  // Level-1 resources (class - Second Wind, Rages, ... - and species -
  // Breath Weapon, ... - whichever apply) and class features (Weapon
  // Mastery, Tactical Mind, ...), read from the real classes.json/
  // species.json data - works for any ported class/species, not just
  // Fighter/Dragonborn.
  rules.recalculateClassResources(character);
  character.features = rules.classFeaturesForLevelUp(character, 0, 1);
  // Pending Choices for any level-1 choice-driven feature (Fighting
  // Style, ...), resolved the same way as an Ability Score Improvement
  // (through the feat picker, restricted to the category).
  character.pendingChoices = rules.featChoicePendingChoices(character, 0, 1);

  // Turns on spellcasting automatically for one of the 8 SRD casting
  // classes, with level-1 cantrips/slots computed from the real class
  // level table - the player fills in cantrips/spells known afterward.
  if (rules.isSpellcastingClass(srdClass.key)) {
    rules.enableSpellcasting(character);
  }

  if (srdClass.key == fighterClassKey && fighterEquipmentOption != null) {
    _grantFighterStartingEquipment(character, fighterEquipmentOption);
  }

  final armorSource = character.equippedArmor?.name ?? 'Unarmored';
  final startingFeatureNames = [
    ...character.features.map((f) => f.name),
    ...character.feats.map((f) => f.name),
  ];
  rules.logHistory(
    character,
    'Character created',
    detail:
        'STR ${abilityScores.str}, DEX ${abilityScores.dex}, '
        'CON ${abilityScores.con}, INT ${abilityScores.intel}, '
        'WIS ${abilityScores.wis}, CHA ${abilityScores.cha}. '
        'AC ${rules.armorClassFor(character)} ($armorSource'
        '${character.shieldEquipped ? ' + Shield' : ''}).'
        '${startingFeatureNames.isEmpty ? '' : ' Starting features/feats: ${startingFeatureNames.join(', ')}.'}',
  );

  return character;
}

/// Applies one of [fighterStartingEquipmentOptions] to a freshly built
/// Fighter: equips armor, adds weapons (built the same way the sheet's own
/// "+ Add Weapon" picker does), stacks any non-weapon gear as inventory,
/// and sets starting coin. Pack contents (a Dungeoneer's Pack's dozen-odd
/// items) aren't exploded out - there's no general item catalog ported yet,
/// so it's tracked as a single named entry, same as this app already does
/// for anything outside weapons/armor/feats/spells.
void _grantFighterStartingEquipment(Character c, String optionId) {
  Weapon weaponNamed(String name) {
    final ref = srdCatalog.weaponsByKey.values.firstWhere(
      (w) => w.name == name,
    );
    final (dice, type) = ref.splitDamage;
    return Weapon(
      name: ref.name,
      damageDice: dice,
      damageType: type,
      properties: ref.properties,
      mastery: ref.mastery,
      masteryDesc: ref.mastery != null
          ? srdCatalog.weaponPropertiesByName[ref.mastery]?.desc
          : null,
      proficient: true,
      finesse: ref.isFinesse,
    );
  }

  EquippedArmor armorNamed(String name) {
    final ref = srdCatalog.armorByKey.values.firstWhere((a) => a.name == name);
    return EquippedArmor(
      name: ref.name,
      armorClassFormula: ref.armorClass,
      strengthRequirement: ref.strength,
      stealth: ref.stealth,
      category: ref.simpleCategory,
    );
  }

  switch (optionId) {
    case 'A':
      c.equippedArmor = armorNamed('Chain Mail');
      c.weapons = [
        ...c.weapons,
        weaponNamed('Greatsword'),
        weaponNamed('Flail'),
        weaponNamed('Javelin'),
      ];
      c.inventory = [
        ...c.inventory,
        InventoryEntry(name: 'Javelin', quantity: 8),
        InventoryEntry(name: "Dungeoneer's Pack", quantity: 1),
      ];
      c.currency = const Currency(gp: 4);
    case 'B':
      c.equippedArmor = armorNamed('Studded Leather Armor');
      c.weapons = [
        ...c.weapons,
        weaponNamed('Scimitar'),
        weaponNamed('Shortsword'),
        weaponNamed('Longbow'),
      ];
      c.inventory = [
        ...c.inventory,
        InventoryEntry(name: 'Arrow', quantity: 20),
        InventoryEntry(name: 'Quiver', quantity: 1),
        InventoryEntry(name: "Dungeoneer's Pack", quantity: 1),
      ];
      c.currency = const Currency(gp: 11);
    case 'C':
      c.currency = const Currency(gp: 155);
  }
}
