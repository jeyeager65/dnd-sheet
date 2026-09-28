import '../models/character.dart';
import '../models/homebrew.dart';
import 'homebrew_repository.dart';
import 'srd_catalog.dart';

// Structured rules data for homebrew/official entries (HomebrewEntry.data),
// and turning it into the same shapes the SRD catalog uses - so a
// homebrew spell, weapon, species, background, class, or subclass works
// everywhere an SRD one does. Keys are documented on each type below.

/// A weapon's stats. data keys: damageDice, damageType, category,
/// properties (list), mastery, baseWeapon (an SRD weapon name, for a
/// weapon whose name doesn't say what kind it is) - plus, for a magic
/// weapon, magicBonus
/// (int) and specialFeatures (list of text), copied onto the character's
/// weapon when it's added. (rarity/requiresAttunement live in the same
/// data map but aren't weapon stats - see rules.itemInfo.)
class WeaponStats {
  WeaponStats({
    this.damageDice = '1d6',
    this.damageType = 'Slashing',
    this.category = 'Simple Melee Weapons',
    List<String>? properties,
    this.mastery,
    this.magicBonus = 0,
    List<String>? specialFeatures,
    this.baseWeapon,
  }) : properties = properties ?? [],
       specialFeatures = specialFeatures ?? [];

  String damageDice;
  String damageType;
  String category;
  List<String> properties;
  String? mastery;
  int magicBonus;
  List<String> specialFeatures;
  String? baseWeapon;

  static WeaponStats? fromData(Map<String, dynamic> data) {
    if (data['damageDice'] == null) return null;
    return WeaponStats(
      damageDice: data['damageDice'] as String,
      damageType: data['damageType'] as String? ?? '',
      category: data['category'] as String? ?? 'Simple Melee Weapons',
      properties: (data['properties'] as List?)?.cast<String>() ?? [],
      mastery: data['mastery'] as String?,
      magicBonus: data['magicBonus'] as int? ?? 0,
      specialFeatures: (data['specialFeatures'] as List?)?.cast<String>() ?? [],
      baseWeapon: data['baseWeapon'] as String?,
    );
  }

  Map<String, dynamic> toData() => {
    'damageDice': damageDice,
    'damageType': damageType,
    'category': category,
    'properties': properties,
    'mastery': mastery,
    'magicBonus': magicBonus,
    'specialFeatures': specialFeatures,
    'baseWeapon': baseWeapon,
  };

  Weapon toWeapon(String name, {required bool proficient}) => Weapon(
    name: name,
    damageDice: damageDice,
    damageType: damageType,
    properties: properties,
    mastery: mastery,
    masteryDesc: mastery != null
        ? srdCatalog.weaponPropertiesByName[mastery]?.desc
        : null,
    proficient: proficient,
    finesse: properties.contains('Finesse'),
    category: category,
    magicBonus: magicBonus,
    specialFeatures: [...specialFeatures],
    baseWeapon: baseWeapon,
  );
}

/// An armor's stats. data keys: armorCategory (Light/Medium/Heavy/Shield),
/// baseAc, dexMode ('full' | 'max2' | 'none'), strength ("Str 13"),
/// stealth (bool).
class ArmorStats {
  ArmorStats({
    this.category = 'Light',
    this.baseAc = 11,
    this.dexMode = 'full',
    this.strength,
    this.stealth = false,
  });

  String category;
  int baseAc;
  String dexMode;
  String? strength;
  bool stealth;

  bool get isShield => category == 'Shield';

  /// The SRD-style formula text rules.armorClassFromFormula reads -
  /// "11 + Dex modifier", "14 + Dex modifier (max 2)", "16".
  String get formula => switch (dexMode) {
    'full' => '$baseAc + Dex modifier',
    'max2' => '$baseAc + Dex modifier (max 2)',
    _ => '$baseAc',
  };

  static ArmorStats fromFormula(
    String formula, {
    String? category,
    String? strength,
    bool stealth = false,
  }) => ArmorStats(
    category: category ?? 'Light',
    baseAc: int.tryParse(RegExp(r'\d+').stringMatch(formula) ?? '') ?? 10,
    dexMode: formula.contains('max 2')
        ? 'max2'
        : formula.contains('Dex')
        ? 'full'
        : 'none',
    strength: strength,
    stealth: stealth,
  );

  static ArmorStats? fromData(Map<String, dynamic> data) {
    if (data['armorCategory'] == null) return null;
    return ArmorStats(
      category: data['armorCategory'] as String,
      baseAc: data['baseAc'] as int? ?? 10,
      dexMode: data['dexMode'] as String? ?? 'full',
      strength: data['strength'] as String?,
      stealth: data['stealth'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toData() => {
    'armorCategory': category,
    'baseAc': baseAc,
    'dexMode': dexMode,
    'strength': strength,
    'stealth': stealth,
  };

  EquippedArmor toArmor(String name) => EquippedArmor(
    name: name,
    armorClassFormula: formula,
    strengthRequirement: strength,
    stealth: stealth,
    category: category,
  );
}

/// Common damage dice, for the weapon dice dropdown.
const commonDamageDice = [
  '1',
  '1d4',
  '1d6',
  '1d8',
  '1d10',
  '1d12',
  '2d4',
  '2d6',
  '2d8',
  '2d10',
  '2d12',
];

const weaponCategories = [
  'Simple Melee Weapons',
  'Simple Ranged Weapons',
  'Martial Melee Weapons',
  'Martial Ranged Weapons',
];

/// The weapon properties (not masteries), as the SRD names them -
/// "Ammunition", "Finesse", "Heavy", ...
List<String> get weaponPropertyNames => [
  for (final p in srdCatalog.weaponPropertiesByName.values)
    if (!p.isMastery) p.name,
];

List<String> get weaponMasteryNames => [
  for (final p in srdCatalog.weaponPropertiesByName.values)
    if (p.isMastery) p.name,
];

/// Saves [data] onto the homebrew entry with [id] (merging into what's
/// there) - how a homebrew weapon/armor remembers its stats after the
/// first time they're entered.
void saveHomebrewData(String id, Map<String, dynamic> data) {
  final entry = homebrewRepo.entries.where((e) => e.id == id).firstOrNull;
  if (entry == null) return;
  homebrewRepo.update(entry.copyWith(data: {...entry.data, ...data}));
}

HomebrewEntry? homebrewById(String id) =>
    homebrewRepo.entries.where((e) => e.id == id).firstOrNull;

// ---------------------------------------------------------------------------
// Homebrew species / backgrounds / classes / subclasses in the catalog.
//
// data keys:
//  species:    size ("Medium" | "Small" | "Small or Medium"), speed (int),
//              traits [{name, desc, shortDesc}], resistances [damage type]
//  background: abilityScores [3 ability names], skills [2 skill names],
//              tool (text), feat (feat name), equipment (text)
//  class:      hitDie ("d8"), primaryAbility, saves [2 ability keys],
//              skillCount (int), skillChoices [skill names],
//              armorTraining [Light/Medium/Heavy/Shields],
//              weaponProficiencies (text), toolProficiencies (text),
//              casterType ("none" | "full" | "half" | "pact"),
//              spellAbility (ability key), subclassLevel (int),
//              standardFeatLevels (bool, default true: ASI at 4/8/12/16 and
//              Epic Boon at 19), features [{level, name, desc, shortDesc}],
//              equipment (text)
//  subclass:   parentClass (class key), features [{level, name, desc,
//              shortDesc}], spells [{level, spells: [names]}]
//  spell:      level, school, castingTime, range, components, duration,
//              concentration, ritual, classes [names], higherLevel
//  weapon:     see WeaponStats; a magic weapon also rarity,
//              requiresAttunement, and effects (on the entry itself)
//  magicItem:  itemCategory, rarity, requiresAttunement, charges (int),
//              recharge ("dawn" | "long" | "short" | "none")
//  feat, species, class (also): grantedSpells [{name, level (character/
//              class level it arrives at), freeCasts (0 none, -1 at will),
//              recovery ("long" | "short"), ability (key)}]
//  feat, species (also): featChoice (feat category, "any", or empty) - a
//              feat pick it grants, like Human's Versatile
// ---------------------------------------------------------------------------

final _registered = <String>{};

const _abilityNames = {
  'str': 'Strength',
  'dex': 'Dexterity',
  'con': 'Constitution',
  'int': 'Intelligence',
  'wis': 'Wisdom',
  'cha': 'Charisma',
};

List<Map<String, dynamic>> _maps(Object? list) => [
  for (final item in (list as List?) ?? const [])
    (item as Map).cast<String, dynamic>(),
];

List<SrdClassFeature> _features(Object? list) => [
  for (final f in _maps(list))
    SrdClassFeature(
      level: f['level'] as int? ?? 1,
      name: f['name'] as String? ?? '',
      desc: f['desc'] as String? ?? '',
    ),
];

Map<String, String> _shortTexts(Object? list) => {
  for (final f in _maps(list))
    if ((f['shortDesc'] as String? ?? '').isNotEmpty)
      f['name'] as String: f['shortDesc'] as String,
};

/// Puts every homebrew species, background, class, and subclass into the
/// SRD catalog's own maps (keyed by the homebrew id), replacing what an
/// earlier call put there - so pickers, rules, the sheet, and the PDF
/// treat them exactly like SRD entries. Safe to call repeatedly.
void registerHomebrewInCatalog() {
  for (final id in _registered) {
    srdCatalog.speciesByKey.remove(id);
    srdCatalog.backgroundsByKey.remove(id);
    srdCatalog.classesByKey.remove(id);
    srdCatalog.sheetText.remove(id);
  }
  _registered.clear();
  srdCatalog.homebrewSubclasses.clear();

  for (final e in homebrewRepo.entries) {
    final d = e.data;
    switch (e.kind) {
      case 'species':
        srdCatalog.speciesByKey[e.id] = SrdSpeciesInfo(
          key: e.id,
          name: e.name,
          size: d['size'] as String? ?? 'Medium',
          speed: '${d['speed'] ?? 30} feet',
          traits: [
            for (final t in _maps(d['traits']))
              SrdSpeciesTrait(
                name: t['name'] as String? ?? '',
                desc: t['desc'] as String? ?? '',
              ),
          ],
          tables: const [],
        );
        srdCatalog.sheetText[e.id] = _shortTexts(d['traits']);
      case 'background':
        srdCatalog.backgroundsByKey[e.id] = SrdBackgroundInfo(
          key: e.id,
          name: e.name,
          skillProficiencies:
              (d['skills'] as List?)?.cast<String>() ?? const [],
          feat: d['feat'] as String?,
          abilityScores:
              (d['abilityScores'] as List?)?.cast<String>() ?? const [],
          toolProficiency: d['tool'] as String?,
          equipment: d['equipment'] as String?,
        );
      case 'class':
        srdCatalog.classesByKey[e.id] = _homebrewClass(e);
        srdCatalog.sheetText[e.id] = _shortTexts(d['features']);
      case 'subclass':
        final parent = d['parentClass'] as String?;
        if (parent == null) continue;
        srdCatalog.homebrewSubclasses
            .putIfAbsent(parent, () => [])
            .add(
              SrdSubclass(
                key: e.id,
                name: e.name,
                features: _features(d['features']),
                spellsByLevel: {
                  for (final row in _maps(d['spells']))
                    row['level'] as int? ?? 3:
                        (row['spells'] as List?)?.cast<String>() ?? const [],
                },
              ),
            );
        srdCatalog.sheetText[e.id] = _shortTexts(d['features']);
      default:
        continue;
    }
    _registered.add(e.id);
  }
}

SrdClass _homebrewClass(HomebrewEntry e) {
  final d = e.data;
  final features = _features(d['features']);
  final subclassLevel = d['subclassLevel'] as int? ?? 3;
  final standardFeats = d['standardFeatLevels'] as bool? ?? true;
  final allFeatures = [
    ...features,
    SrdClassFeature(
      level: subclassLevel,
      name: '${e.name} Subclass',
      desc: 'Choose a ${e.name} subclass.',
    ),
    if (standardFeats) ...[
      for (final level in const [4, 8, 12, 16])
        SrdClassFeature(
          level: level,
          name: 'Ability Score Improvement',
          desc: 'Gain the Ability Score Improvement feat or another feat.',
        ),
      const SrdClassFeature(
        level: 19,
        name: 'Epic Boon',
        desc: 'Gain an Epic Boon feat or another feat.',
      ),
    ],
  ]..sort((a, b) => a.level.compareTo(b.level));

  // Spell progression borrowed from the SRD caster of the same kind.
  final casterType = d['casterType'] as String? ?? 'none';
  final reference = switch (casterType) {
    'full' => srdCatalog.byKey('srd-2024_wizard-class'),
    'half' => srdCatalog.byKey('srd-2024_paladin-class'),
    'pact' => srdCatalog.byKey('srd-2024_warlock-class'),
    _ => null,
  };

  final levels = <SrdLevelRow>[
    for (var level = 1; level <= 20; level++)
      {
        'Level': '$level',
        'Proficiency Bonus': '+${((level - 1) ~/ 4) + 2}',
        'Class Features': [
          for (final f in allFeatures)
            if (f.level == level) f.name,
        ].join(', '),
        if (reference != null) ...{
          for (final column in const [
            'Cantrips',
            'Prepared Spells',
            'Spell Slots',
            'Slot Level',
          ])
            column: ?reference.levelValue(level, column),
        },
      },
  ];
  final saves = (d['saves'] as List?)?.cast<String>() ?? const [];
  final skills = (d['skillChoices'] as List?)?.cast<String>() ?? const [];
  final armor = (d['armorTraining'] as List?)?.cast<String>() ?? const [];
  return SrdClass(
    key: e.id,
    name: e.name,
    traits: {
      'Primary Ability': _abilityNames[d['primaryAbility']] ?? '',
      'Hit Point Die':
          '${(d['hitDie'] as String? ?? 'd8').toUpperCase()} '
          'per ${e.name} level',
      'Saving Throw Proficiencies': saves
          .map((k) => _abilityNames[k] ?? k)
          .join(' and '),
      'Skill Proficiencies': skills.isEmpty
          ? 'Choose any ${d['skillCount'] ?? 2} skills'
          : 'Choose ${d['skillCount'] ?? 2}: ${skills.join(', ')}',
      'Weapon Proficiencies':
          d['weaponProficiencies'] as String? ?? 'Simple weapons',
      'Armor Training': armor.isEmpty
          ? 'None'
          : '${armor.where((a) => a != 'Shields').join(', ')} armor'
                '${armor.contains('Shields') ? ' and Shields' : ''}',
      'Tool Proficiencies': d['toolProficiencies'] as String? ?? 'None',
      'Starting Equipment': d['equipment'] as String? ?? '',
      if (casterType != 'none' && d['spellAbility'] != null)
        'Spellcasting Ability': d['spellAbility'] as String,
    },
    levels: levels,
    features: allFeatures,
    spellSlotsByLevel: reference?.spellSlotsByLevel ?? const {},
  );
}

/// A homebrew spell as the SRD spell shape, from its entry's data - null
/// if the entry has no spell data yet (a quick-added name only).
SrdSpellRef? homebrewSpellRef(HomebrewEntry e, {int? fallbackLevel}) {
  final d = e.data;
  if (d['level'] == null && fallbackLevel == null) return null;
  return SrdSpellRef(
    key: e.id,
    name: e.name,
    level: d['level'] as int? ?? fallbackLevel ?? 1,
    school: d['school'] as String? ?? 'Homebrew',
    classes: (d['classes'] as List?)?.cast<String>() ?? const [],
    ritual: d['ritual'] as bool? ?? false,
    castingTime: d['castingTime'] as String? ?? '',
    range: d['range'] as String? ?? '',
    components: d['components'] as String? ?? '',
    concentration: d['concentration'] as bool? ?? false,
    duration: d['duration'] as String? ?? '',
    desc: e.desc,
    higherLevel: (d['higherLevel'] as String?)?.isEmpty ?? true
        ? null
        : d['higherLevel'] as String,
  );
}
