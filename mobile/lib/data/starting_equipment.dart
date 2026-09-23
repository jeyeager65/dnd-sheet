import '../domain/rules.dart' as rules;
import '../models/character.dart';
import 'srd_catalog.dart';

/// One lettered starting-equipment package from a class's or background's
/// SRD text - "(A) Greataxe, 4 Handaxes, Explorer's Pack, and 15 GP".
class EquipmentOption {
  const EquipmentOption({
    required this.id,
    required this.summary,
    required this.items,
    required this.gp,
  });
  final String id; // 'A', 'B', 'C'
  final String summary; // verbatim, shown to the player
  final List<(String name, int quantity)> items;
  final int gp;
}

/// Parses "Choose A or B: (A) Greataxe, 4 Handaxes, Explorer's Pack, and
/// 15 GP; or (B) 75 GP" - the phrasing every SRD class and background uses
/// - into its lettered packages. Plural quantities ("4 Handaxes", "20
/// Arrows", "2 Pouches") are singularized so they match catalog names.
List<EquipmentOption> parseEquipmentOptions(String? text) {
  if (text == null) return const [];
  final clean = text.replaceAll('_', '');
  final result = <EquipmentOption>[];
  for (final m in RegExp(
    r'\(([A-Z])\)\s*(.+?)(?=;\s*(?:or\s*)?\([A-Z]\)|$)',
  ).allMatches(clean)) {
    final summary = m.group(2)!.trim();
    final items = <(String, int)>[];
    var gp = 0;
    for (var part in summary.split(RegExp(r',\s*'))) {
      part = part.replaceFirst(RegExp(r'^and\s+'), '').trim();
      if (part.isEmpty) continue;
      final coins = RegExp(r'^(\d+)\s*GP$').firstMatch(part);
      if (coins != null) {
        gp += int.parse(coins.group(1)!);
        continue;
      }
      final counted = RegExp(r'^(\d+)\s+(.+)$').firstMatch(part);
      if (counted != null) {
        items.add((_singular(counted.group(2)!), int.parse(counted.group(1)!)));
      } else {
        items.add((part, 1));
      }
    }
    result.add(
      EquipmentOption(id: m.group(1)!, summary: summary, items: items, gp: gp),
    );
  }
  return result;
}

String _singular(String name) {
  if (_known(name)) return name;
  for (final (suffix, replacement) in [
    ('ches', 'ch'),
    ('es', 'e'),
    ('s', ''),
  ]) {
    if (name.endsWith(suffix)) {
      final candidate =
          name.substring(0, name.length - suffix.length) + replacement;
      if (_known(candidate) || suffix == 's') return candidate;
    }
  }
  return name;
}

bool _known(String name) =>
    srdCatalog.weaponsByKey.values.any((w) => w.name == name) ||
    srdCatalog.armorByKey.values.any((a) => a.name == name) ||
    srdCatalog.gearByKey.values.any((g) => g.name == name);

/// The class's starting-equipment packages.
List<EquipmentOption> classEquipmentOptions(String? classKey) =>
    parseEquipmentOptions(
      classKey != null
          ? srdCatalog.byKey(classKey)?.traits['Starting Equipment']
          : null,
    );

/// The background's starting-equipment packages.
List<EquipmentOption> backgroundEquipmentOptions(String? backgroundKey) =>
    parseEquipmentOptions(
      backgroundKey != null
          ? srdCatalog.backgroundsByKey[backgroundKey]?.equipment
          : null,
    );

/// Gives [c] everything in [option]: weapons go on the Weapons list (one
/// entry; a stack of them, like 8 Javelins, is also tracked as inventory
/// so the count is there), armor is equipped (a Shield raised), and
/// everything else is carried. A focus named after a weapon ("Druidic
/// Focus (Quarterstaff)") is both the weapon and the focus. Coins are
/// added.
void applyEquipmentOption(Character c, EquipmentOption option) {
  for (final (name, quantity) in option.items) {
    final inner = RegExp(r'\(([^)]+)\)$').firstMatch(name)?.group(1);
    final weapon = _weaponNamed(name) ?? _weaponNamed(inner);
    if (weapon != null && !c.weapons.any((w) => w.name == weapon.name)) {
      c.weapons = [...c.weapons, rules.weaponFromSrd(c, weapon)];
      if (quantity > 1) {
        c.inventory = [
          ...c.inventory,
          InventoryEntry(name: weapon.name, quantity: quantity),
        ];
      }
      if (_weaponNamed(name) != null) continue;
    }
    if (name == 'Shield') {
      c.shieldEquipped = true;
      continue;
    }
    final armor = srdCatalog.armorByKey.values
        .where((a) => a.name == name)
        .firstOrNull;
    if (armor != null) {
      c.equippedArmor = EquippedArmor(
        name: armor.name,
        armorClassFormula: armor.armorClass,
        strengthRequirement: armor.strength,
        stealth: armor.stealth,
        category: armor.simpleCategory,
      );
      continue;
    }
    c.inventory = [
      ...c.inventory,
      InventoryEntry(name: name, quantity: quantity),
    ];
  }
  c.currency = Currency(
    cp: c.currency.cp,
    sp: c.currency.sp,
    ep: c.currency.ep,
    gp: c.currency.gp + option.gp,
    pp: c.currency.pp,
  );
}

SrdWeaponRef? _weaponNamed(String? name) => name == null
    ? null
    : srdCatalog.weaponsByKey.values.where((w) => w.name == name).firstOrNull;
