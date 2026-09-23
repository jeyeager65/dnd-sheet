part of 'rules.dart';

// Character-level edits that touch many derived things at once: changing
// species, class, or background after creation; XP; size; and the
// proficiency lists the sheet's Equipment Training box shows.

/// 2024 Character Advancement table: the XP needed to reach each level
/// (index 0 = level 1).
const xpThresholds = [
  0,
  300,
  900,
  2700,
  6500,
  14000,
  23000,
  34000,
  48000,
  64000,
  85000,
  100000,
  120000,
  140000,
  165000,
  195000,
  225000,
  265000,
  305000,
  355000,
];

/// XP needed to reach [c]'s next level - null at level 20.
int? xpForNextLevel(Character c) => c.level < 20 ? xpThresholds[c.level] : null;

/// Enough XP for the next level (the Level Up button can go ahead).
bool readyToLevelUp(Character c) {
  final next = xpForNextLevel(c);
  return next != null && c.experiencePoints >= next;
}

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
  final hpBefore = maxHpBonus(c);
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
  applyMaxHpBonusChange(c, hpBefore);
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
    c.feats = [
      ...c.feats,
      GrantedFeature(name: next!.feat!, source: 'background'),
    ];
  }
  applyBackgroundAbilityIncreases(c, abilityIncreases);
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
