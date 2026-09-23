import '../models/character.dart';
import '../models/homebrew.dart';
import 'homebrew_repository.dart';
import 'srd_catalog.dart';

// Structured rules data for homebrew/official entries (HomebrewEntry.data),
// and turning it into the same shapes the SRD catalog uses - so a
// homebrew spell, weapon, species, background, class, or subclass works
// everywhere an SRD one does. Keys are documented on each type below.

/// A weapon's stats. data keys: damageDice, damageType, category,
/// properties (list), mastery.
class WeaponStats {
  WeaponStats({
    this.damageDice = '1d6',
    this.damageType = 'Slashing',
    this.category = 'Simple Melee Weapons',
    List<String>? properties,
    this.mastery,
  }) : properties = properties ?? [];

  String damageDice;
  String damageType;
  String category;
  List<String> properties;
  String? mastery;

  static WeaponStats? fromData(Map<String, dynamic> data) {
    if (data['damageDice'] == null) return null;
    return WeaponStats(
      damageDice: data['damageDice'] as String,
      damageType: data['damageType'] as String? ?? '',
      category: data['category'] as String? ?? 'Simple Melee Weapons',
      properties: (data['properties'] as List?)?.cast<String>() ?? [],
      mastery: data['mastery'] as String?,
    );
  }

  Map<String, dynamic> toData() => {
    'damageDice': damageDice,
    'damageType': damageType,
    'category': category,
    'properties': properties,
    'mastery': mastery,
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
