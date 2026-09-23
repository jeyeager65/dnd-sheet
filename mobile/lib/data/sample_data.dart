import '../models/character.dart';

/// Jarson's data, seeded into Hive on first launch. This is a stand-in for
/// the real app's character-creation flow and SRD catalog, both still
/// unported - it exists so the sheet has real (not hardcoded-in-the-UI)
/// data to compute against from day one.
Character buildSampleJarson() {
  return Character(
    id: 'jarson',
    name: 'Jarson',
    speciesLabel: 'Red · Fire',
    speciesKey: 'srd-2024_dragonborn-species',
    speciesChoice: 'Red',
    backgroundLabel: 'Soldier',
    backgroundKey: 'srd-2024_soldier-background',
    classLabel: 'Dragonborn Fighter · Champion',
    classKey: 'srd-2024_fighter-class',
    subclassKey: 'srd-2024_champion-subclass',
    level: 9,
    abilityScores: const AbilityScores(
      str: 19,
      dex: 12,
      con: 14,
      intel: 10,
      wis: 12,
      cha: 8,
    ),
    maxHp: 76,
    currentHp: 76,
    // Half Plate + Shield: 15 + Dex modifier (max 2) [16] + 2 = 18,
    // matching his known real AC exactly - computed, not hardcoded.
    equippedArmor: EquippedArmor(
      name: 'Half Plate Armor',
      armorClassFormula: '15 + Dex modifier (max 2)',
      stealth: true,
      category: 'Medium',
    ),
    shieldEquipped: true,
    initiativeBonus: 0,
    speed: 30,
    hitDiceDie: 'd10',
    hitDiceTotal: 9,
    hitDiceSpent: 0,
    savingThrowProficiencies: const ['str', 'con'],
    skills: [
      SkillEntry(name: 'Athletics', ability: 'str', proficient: true),
      SkillEntry(name: 'Perception', ability: 'wis', proficient: true),
      SkillEntry(name: 'Survival', ability: 'wis', proficient: true),
      SkillEntry(name: 'Insight', ability: 'wis', proficient: false),
      SkillEntry(name: 'Intimidation', ability: 'cha', proficient: false),
    ],
    // Resource keys follow rules.dart's recalculateClassResources scheme
    // (`${classKey}_$name` / `${speciesKey}_$name`) so loading Jarson
    // through the repository (which recalculates on every load) never
    // creates a duplicate under the old ad hoc key.
    resources: [
      Resource(
        key: 'srd-2024_fighter-class_Action Surge',
        name: 'Action Surge',
        max: 1,
        used: 0,
        hint: 'Take one extra action this turn. Recharges on a Long Rest.',
        shortRestRecovery: 'none',
      ),
      Resource(
        // Verified against classes.json's Fighter level table: the
        // "Second Wind" column reads "3" at level 9, not 1 - Second Wind
        // scales with level (2 at 1-3, 3 at 4-9, 4 at 10+), it isn't a
        // flat single use the way it first looked from the mockup.
        key: 'srd-2024_fighter-class_Second Wind',
        name: 'Second Wind',
        max: 3,
        used: 0,
        hint: 'Bonus action: heal 1d10+9. Also spent by Tactical Mind to boost a failed ability check. Recharges on a Short or Long Rest.',
        shortRestRecovery: 'full',
      ),
      Resource(
        key: 'srd-2024_fighter-class_Indomitable',
        name: 'Indomitable',
        max: 1,
        used: 0,
        hint: 'Reroll one failed saving throw — you must use the new roll. Recharges on a Long Rest.',
        shortRestRecovery: 'none',
      ),
      Resource(
        // Species resources scale with Proficiency Bonus, not a flat
        // count - at level 9 that's +4 (2 + floor((9-1)/4)).
        key: 'srd-2024_dragonborn-species_Breath Weapon',
        name: 'Breath Weapon',
        max: 4,
        used: 0,
        hint: 'Recharges on a Long Rest.',
        shortRestRecovery: 'none',
      ),
    ],
    innateAttacks: [
      InnateAttack(
        // damageType/desc below are only a fallback for a species the app
        // can't resolve (homebrew, or not cataloged) - for a real
        // Dragonborn, character_sheet_screen.dart's _InnateAttackRow
        // computes the actual damage type (species choice) and shows the
        // verbatim SRD trait text instead of these; levelDice/saveDcFormula
        // below ARE the live source of truth either way (see
        // rules.dart's innateAttackInfo).
        name: 'Breath Weapon',
        levelDice: [
          LevelDiceBreakpoint(level: 1, diceCount: 1),
          LevelDiceBreakpoint(level: 5, diceCount: 2),
          LevelDiceBreakpoint(level: 11, diceCount: 3),
          LevelDiceBreakpoint(level: 17, diceCount: 4),
        ],
        dieType: 'd10',
        damageType: 'Fire',
        saveAbility: 'dex',
        saveDcFormula: '8 + Proficiency Bonus + Constitution modifier',
        desc: 'Replace an attack with a 15-ft Cone or 30-ft Line breath; each creature makes a Dexterity save or takes damage (half on success).',
        resourceKey: 'srd-2024_dragonborn-species_Breath Weapon',
      ),
    ],
    weapons: [
      Weapon(
        name: 'Greatsword',
        damageDice: '2d6',
        damageType: 'slashing',
        properties: const ['Heavy', 'Two-Handed'],
        mastery: 'Graze',
        masteryDesc: 'If your attack roll misses, you still deal damage to the target equal to your Strength modifier.',
        proficient: true,
        category: 'Martial Melee Weapons',
      ),
      Weapon(
        name: 'Sword of the Failed Dragon Slayer',
        damageDice: '2d6',
        damageType: 'slashing',
        properties: const ['Heavy', 'Two-Handed'],
        proficient: true,
        magicBonus: 2,
        category: 'Martial Melee Weapons',
        specialFeatures: const [
          'Mounting Fury — 2nd consecutive hit on a target: +1d6 fire. 3rd+: +2d6 fire. Resets on a miss or when you switch targets.',
        ],
      ),
    ],
    features: [
      GrantedFeature(
        name: 'Draconic Ancestry',
        source: 'species',
        desc: 'Your ancestry is Red. It sets the damage type of your Breath Weapon and the damage type you resist — both Fire.',
      ),
      GrantedFeature(
        name: 'Fighting Style: Great Weapon Fighting',
        source: 'class',
        desc: "When you roll damage for a Melee weapon you're holding with two hands, treat any 1 or 2 on a damage die as a 3. The weapon needs the Two-Handed or Versatile property.",
      ),
      GrantedFeature(
        name: 'Extra Attack',
        source: 'class',
        desc: 'You attack twice, instead of once, whenever you take the Attack action on your turn.',
      ),
      GrantedFeature(
        name: 'Remarkable Athlete',
        source: 'Champion',
        desc: "Add half your Proficiency Bonus (round up) to any Strength, Dexterity, or Constitution check that doesn't already use it. Your running long jump increases by that same bonus, in feet.",
      ),
      GrantedFeature(
        name: 'Improved Critical',
        source: 'Champion',
        desc: 'Your weapon attacks score a Critical Hit on a roll of 19 or 20.',
      ),
    ],
    feats: [
      // Great Weapon Master is a real 2024 PHB feat, not part of the free
      // SRD - its rules text isn't bundled here (see rules.dart's
      // liveFeatureEffects/_builtinFeatEffects doc comments for why), so
      // this grant has no `desc` snapshot. Add it as "My Homebrew" (kind
      // 'feat', source 'official') to restore its description and its
      // Heavy-weapon damage bonus - that's your own transcription of
      // content you already own, not something this app redistributes.
      GrantedFeature(name: 'Great Weapon Master', source: 'feat'),
      GrantedFeature(
        name: 'Alert',
        source: 'feat',
        desc: '• Initiative Proficiency — add your Proficiency Bonus to Initiative rolls\n• Initiative Swap — (Level 5+) trade Initiative with a willing ally you can see at the start of combat',
      ),
    ],
    inventory: [
      InventoryEntry(name: "Explorer's Pack", quantity: 1),
      InventoryEntry(name: 'Potion of Healing', quantity: 2),
      InventoryEntry(name: 'Grappling Hook', quantity: 1),
    ],
    currency: const Currency(cp: 12, sp: 4, gp: 86),
    // A level 9 Fighter's four Weapon Mastery kinds.
    weaponMasteries: const ['Greatsword', 'Longsword', 'Javelin', 'Longbow'],
  );
}
