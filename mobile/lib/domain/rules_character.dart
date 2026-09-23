part of 'rules.dart';

// Character-level edits that touch many derived things at once: changing
// species, class, or background after creation; size; and the
// proficiency lists the sheet's Equipment Training box shows.

/// The size categories a species offers, in the order its SRD text lists
/// them - ["Medium"], or ["Medium", "Small"] for Human and Tiefling
/// ("Medium (...) or Small (...), chosen when you select this species").
List<String> speciesSizeOptions(String? speciesKey) {
  final raw = speciesKey != null
      ? srdCatalog.speciesByKey[speciesKey]?.size
      : null;
  if (raw == null) return const [];
  return [
    for (final m in RegExp(
      r'\b(Tiny|Small|Medium|Large|Huge|Gargantuan)\b',
    ).allMatches(raw))
      m.group(1)!,
  ];
}

/// [c]'s size: their pick if it's one the species offers, else the first.
String sizeFor(Character c) {
  final options = speciesSizeOptions(c.speciesKey);
  if (options.isEmpty) return c.sizeChoice ?? '';
  return options.contains(c.sizeChoice) ? c.sizeChoice! : options.first;
}

/// Armor categories [c] is trained in: the class's Armor Training text
/// ("Light, Medium, and Heavy armor and Shields") plus
/// Character.extraArmorTraining. Values: Light, Medium, Heavy, Shields.
Set<String> armorTraining(Character c) => {
  ...classArmorTraining(c),
  ...c.extraArmorTraining,
};

Set<String> classArmorTraining(Character c) {
  final text = _classData(c)?.traits['Armor Training'] ?? '';
  return {
    for (final category in ['Light', 'Medium', 'Heavy'])
      if (text.contains(category)) category,
    if (text.contains('Shield')) 'Shields',
  };
}

/// Weapon proficiencies as text for the sheet: the class's own wording
/// plus any extras.
String weaponProficiencyText(Character c) => [
  if ((_classData(c)?.traits['Weapon Proficiencies'] ?? '').isNotEmpty)
    _classData(c)!.traits['Weapon Proficiencies']!,
  ...c.extraWeaponProficiencies,
].join('; ');

/// Tool proficiencies: the resolved background/class choices (or, with
/// none recorded, the background's and class's own tool text), plus
/// extras.
List<String> toolProficiencies(Character c) {
  final background = c.backgroundKey != null
      ? srdCatalog.backgroundsByKey[c.backgroundKey]
      : null;
  final base = c.toolProficiencyChoices.isNotEmpty
      ? c.toolProficiencyChoices
      : [
          _classData(c)?.traits['Tool Proficiencies'],
          background?.toolProficiency,
        ].nonNulls.where((s) => s.isNotEmpty && s != 'None').toList();
  return [...base, ...c.extraToolProficiencies];
}

/// Re-reads every weapon's proficiency after the character's proficiencies
/// changed (a new class, a Protector pick, a hand-added proficiency). A
/// weapon with no category (older homebrew) is left as it was.
void refreshWeaponProficiency(Character c) {
  for (final w in c.weapons) {
    final category = weaponCategory(w);
    if (category == null) continue;
    w.proficient = isProficientWithWeapon(c, w.name, category, w.properties);
  }
}

/// Changes [c]'s species after creation: base Speed, size, and species
/// choice reset to the new species', species-sourced features and attacks
/// (Breath Weapon) are rebuilt, and Max HP moves by any change in species
/// HP bonus (Dwarven Toughness).
void changeSpecies(Character c, String? speciesKey, String label) {
  if (speciesKey == c.speciesKey && label == c.speciesLabel) return;
  final oldLabel = c.speciesLabel;
  c.speciesKey = speciesKey;
  c.speciesLabel = label;
  c.speciesChoice = null;
  c.sizeChoice = null;
  c.speed = speciesBaseSpeed(speciesKey) ?? c.speed;
  c.features = c.features.where((f) => f.source != 'species').toList();
  c.pendingChoices = c.pendingChoices
      .where((p) => !p.id.startsWith('species:'))
      .toList();
  c.featureChoices = {
    for (final e in c.featureChoices.entries)
      if (!_speciesOptionSets.contains(e.key)) e.key: e.value,
  };
  recalculateClassResources(c);
  refreshMaxHp(c);
  c.pendingChoices = [...c.pendingChoices, ...speciesPendingChoices(c)];
  syncGrantedSpells(c);
  logHistory(c, 'Species changed: $oldLabel → $label');
}

/// Changes [c]'s background after creation: the old background's skill
/// proficiencies, Origin feat, and ability score increases come off, and
/// the new one's go on ([abilityIncreases]: the +2/+1 or +1/+1/+1 picked
/// for it). Tool choices reset, since the new background has its own.
void changeBackground(
  Character c,
  String? backgroundKey,
  String label,
  Map<String, int> abilityIncreases,
) {
  final old = c.backgroundKey != null
      ? srdCatalog.backgroundsByKey[c.backgroundKey]
      : null;
  final next = backgroundKey != null
      ? srdCatalog.backgroundsByKey[backgroundKey]
      : null;
  final oldLabel = c.backgroundLabel;
  final before = c.abilityScores;

  final oldSkills = old?.skillProficiencies.toSet() ?? const <String>{};
  c.skills = c.skills.where((s) => !oldSkills.contains(s.name)).toList();
  c.feats = c.feats.where((f) => f.source != 'background').toList();
  c.abilityScores = before.increase({
    for (final e in c.backgroundAbilityIncreases.entries) e.key: -e.value,
  });

  c.backgroundKey = backgroundKey;
  c.backgroundLabel = label;
  c.toolProficiencyChoices = const [];
  for (final name in next?.skillProficiencies ?? const <String>[]) {
    final ref = srdCatalog.skillsByName[name];
    if (ref == null) continue;
    c.skills = [
      ...c.skills.where((s) => s.name != name),
      SkillEntry(name: ref.name, ability: ref.ability, proficient: true),
    ];
  }
  if (next?.feat != null) {
    final feat = GrantedFeature(name: next!.feat!, source: 'background');
    c.feats = [...c.feats, feat];
    c.pendingChoices = [
      ...c.pendingChoices.where((p) => !p.id.startsWith('feat:')),
      ...featPendingChoices(c, feat),
    ];
  }
  applyBackgroundAbilityIncreases(c, abilityIncreases);
  refreshMaxHp(c);
  syncGrantedSpells(c);
  final diff = _abilityScoreDiff(before, c.abilityScores);
  logHistory(
    c,
    'Background changed: ${oldLabel ?? 'none'} → $label',
    detail: diff.isEmpty ? null : diff.join(', '),
  );
}

/// Adds a background's +2/+1 or +1/+1/+1 to [c]'s scores (capped at 20,
/// as the rules say) and records what was actually added, so a later
/// background change can take exactly that back out.
void applyBackgroundAbilityIncreases(Character c, Map<String, int> increases) {
  final before = c.abilityScores;
  c.abilityScores = before.increase(increases);
  c.backgroundAbilityIncreases = {
    for (final key in increases.keys)
      if (c.abilityScores.of(key) - before.of(key) > 0)
        key: c.abilityScores.of(key) - before.of(key),
  };
}

/// The abilities a background lets you raise, as ability keys - e.g.
/// Acolyte's ["int", "wis", "cha"]. Empty for an uncataloged background.
List<String> backgroundAbilityOptions(String? backgroundKey) {
  final info = backgroundKey != null
      ? srdCatalog.backgroundsByKey[backgroundKey]
      : null;
  return [
    for (final name in info?.abilityScores ?? const <String>[])
      ?_abilityNameToKeyLower[name.toLowerCase()],
  ];
}

/// Changes [c]'s class after creation - a rebuild for their current level:
/// Hit Die, saving throws, class and subclass features, resources, spell
/// slots, and Max HP all come from the new class; the subclass, Weapon
/// Mastery picks, feature option picks, and class Pending Choices are
/// cleared and re-offered. Feats, skills, and inventory stay as they are.
void changeClass(Character c, String classKey, String label) {
  if (classKey == c.classKey) return;
  final classData = srdCatalog.byKey(classKey);
  final oldLabel = c.classLabel;
  c.classKey = classKey;
  c.classLabel = label;
  c.subclassKey = null;
  if (classData != null) {
    c.hitDiceDie = parseHitDie(classData.traits['Hit Point Die']) ?? 'd8';
    c.savingThrowProficiencies = parseSavingThrows(
      classData.traits['Saving Throw Proficiencies'],
    );
  }
  c.hitPointRolls = const {};
  c.features = [
    ...c.features.where((f) => f.source == 'species'),
    ...classFeaturesForLevelUp(c..features = [], 0, c.level),
  ];
  c.weaponMasteries = const [];
  c.featureChoices = {
    for (final e in c.featureChoices.entries)
      if (_speciesOptionSets.contains(e.key)) e.key: e.value,
  };
  c.extraArmorTraining = const [];
  c.extraWeaponProficiencies = const [];
  c.pendingChoices = [
    ...c.pendingChoices.where((p) => p.id.startsWith('species:')),
    ...pendingChoicesForLevelUp(c, 0, c.level),
    ...featChoicePendingChoices(c, 0, c.level),
    ...subclassPendingChoices(c, 0, c.level),
    ...featureOptionPendingChoices(c, 0, c.level),
  ];
  if (isSpellcastingClass(classKey)) {
    final old = c.spellcasting;
    c.spellcasting = Spellcasting(
      ability: spellcastingAbilityForClass(classKey)!,
      spells: [...?old?.spells.where((s) => s.source != null)],
    );
  } else if (c.spellcasting != null) {
    final granted = c.spellcasting!.spells
        .where((s) => s.source != null)
        .toList();
    c.spellcasting = granted.isEmpty
        ? null
        : Spellcasting(ability: c.spellcasting!.ability, spells: granted);
  }
  recalculateSpellSlots(c);
  recalculateClassResources(c);
  recalculateHp(c);
  c.currentHp = c.maxHp;
  refreshWeaponProficiency(c);
  syncGrantedSpells(c);
  logHistory(c, 'Class changed: $oldLabel → $label');
}

/// What the app knows about a carried item, from the SRD or homebrew:
/// kind ("Gear", "Tool", "Wondrous Item", "Weapon", ...), rules text,
/// weight, cost, rarity, and whether it needs attunement.
class ItemInfo {
  const ItemInfo({
    required this.kind,
    required this.desc,
    this.weight,
    this.cost,
    this.rarity,
    this.requiresAttunement = false,
  });
  final String kind;
  final String desc;
  final String? weight;
  final String? cost;
  final String? rarity;
  final bool requiresAttunement;
}

/// Looks [name] up in the gear, tool, magic item, weapon, and armor
/// catalogs, then homebrew - exact name first, then without a trailing
/// parenthetical ("Druidic Focus (Quarterstaff)" -> "Druidic Focus").
/// Null for an item nothing describes.
ItemInfo? itemInfo(String name) {
  ItemInfo? find(String n) {
    final lower = n.toLowerCase();
    bool same(String other) => other.toLowerCase() == lower;
    for (final g in srdCatalog.gearByKey.values) {
      if (same(g.name)) {
        return ItemInfo(
          kind: 'Gear',
          desc: g.desc,
          weight: g.weight,
          cost: g.cost,
        );
      }
    }
    for (final t in srdCatalog.toolsByKey.values) {
      if (same(t.name)) {
        return ItemInfo(
          kind: 'Tool',
          desc: [
            if (t.ability != null) 'Ability: ${t.ability}.',
            if (t.utilize.isNotEmpty) 'Utilize: ${t.utilize}',
            if (t.craft.isNotEmpty) 'Craft: ${t.craft}',
          ].join('\n\n'),
          cost: t.cost,
        );
      }
    }
    for (final m in srdCatalog.magicItemsByKey.values) {
      if (same(m.name)) {
        return ItemInfo(
          kind: m.category,
          desc: m.desc,
          rarity: m.rarity.replaceAll(RegExp(r'\s*\(.*\)'), ''),
          requiresAttunement: m.rarity.contains('Attunement'),
        );
      }
    }
    for (final w in srdCatalog.weaponsByKey.values) {
      if (same(w.name)) {
        return ItemInfo(
          kind: w.category,
          desc:
              '${w.damage}. ${w.properties.join(', ')}'
              '${w.mastery != null ? '. Mastery: ${w.mastery}' : ''}.',
        );
      }
    }
    for (final a in srdCatalog.armorByKey.values) {
      if (same(a.name)) {
        return ItemInfo(
          kind: '${a.category} Armor',
          desc:
              'AC ${a.armorClass}'
              '${a.strength != null ? '. Strength ${a.strength}' : ''}'
              '${a.stealth ? '. Disadvantage on Stealth' : ''}.',
        );
      }
    }
    for (final e in homebrewRepo.entries) {
      if (same(e.name) &&
          const [
            'gear',
            'tool',
            'magicItem',
            'weapon',
            'armor',
          ].contains(e.kind)) {
        return ItemInfo(
          kind: e.source == 'official' ? 'Official content' : 'Homebrew',
          desc: e.desc,
          rarity: e.data['rarity'] as String?,
          requiresAttunement: e.data['requiresAttunement'] as bool? ?? false,
        );
      }
    }
    return null;
  }

  return find(name) ?? find(name.replaceFirst(RegExp(r'\s*\([^)]*\)$'), ''));
}

/// How many magic items [c] can be attuned to at once - 3, or 4 with the
/// Thief's Use Magic Device.
int attunementLimit(Character c) =>
    c.features.any((f) => f.name == 'Use Magic Device') ? 4 : 3;

int attunedCount(Character c) => c.inventory.where((i) => i.attuned).length;
