import 'package:flutter/material.dart';

import '../data/homebrew_catalog.dart';
import '../data/srd_catalog.dart';

/// The shared weapon-stats form - damage dice, damage type, category,
/// properties, and mastery, each picked from the SRD's own lists rather
/// than typed - used to enter a homebrew weapon and to edit any weapon.
List<Widget> weaponStatsFields(
  WeaponStats stats,
  void Function(void Function()) setState,
) {
  final dice = {...commonDamageDice, stats.damageDice}.toList();
  final types = [for (final dt in srdCatalog.damageTypes) dt.name];
  final type = types.firstWhere(
    (t) => t.toLowerCase() == stats.damageType.toLowerCase(),
    orElse: () => stats.damageType,
  );
  return [
    Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: stats.damageDice,
            decoration: const InputDecoration(labelText: 'Damage dice'),
            items: [
              for (final d in dice) DropdownMenuItem(value: d, child: Text(d)),
            ],
            onChanged: (v) => setState(() => stats.damageDice = v!),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: DropdownButtonFormField<String>(
            initialValue: types.contains(type) ? type : null,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Damage type'),
            items: [
              for (final t in types) DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (v) => setState(() => stats.damageType = v!),
          ),
        ),
      ],
    ),
    DropdownButtonFormField<String>(
      initialValue: weaponCategories.contains(stats.category)
          ? stats.category
          : null,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'Category'),
      items: [
        for (final c in weaponCategories)
          DropdownMenuItem(value: c, child: Text(c)),
      ],
      onChanged: (v) => setState(() => stats.category = v!),
    ),
    const SizedBox(height: 8),
    const Text('Properties', style: TextStyle(fontSize: 12)),
    Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final prop in weaponPropertyNames)
          FilterChip(
            label: Text(prop, style: const TextStyle(fontSize: 12)),
            selected: stats.properties.any((x) => x.startsWith(prop)),
            onSelected: (v) => setState(() {
              stats.properties = v
                  ? [...stats.properties, prop]
                  : stats.properties.where((x) => !x.startsWith(prop)).toList();
            }),
          ),
      ],
    ),
    DropdownButtonFormField<String?>(
      initialValue: weaponMasteryNames.contains(stats.mastery)
          ? stats.mastery
          : null,
      decoration: const InputDecoration(labelText: 'Mastery'),
      items: [
        const DropdownMenuItem(value: null, child: Text('None')),
        for (final m in weaponMasteryNames)
          DropdownMenuItem(value: m, child: Text(m)),
      ],
      onChanged: (v) => setState(() => stats.mastery = v),
    ),
  ];
}
