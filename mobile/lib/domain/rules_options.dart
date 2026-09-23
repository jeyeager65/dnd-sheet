part of 'rules.dart';

// Features that make the player pick something - Expertise skills, Weapon
// Mastery weapons, a Divine Order, Eldritch Invocations, Metamagic, a
// Goliath's Giant Ancestry, Magic Initiate's spells, ... Each is an
// "option set": when it applies, how many picks it allows, what the
// options are, and what a pick does. Picks are recorded in
// Character.featureChoices (Weapon Mastery in Character.weaponMasteries)
// and surfaced as Pending Choices (kind 'option') when a level-up,
// creation, or change newly grants them.

/// One choosable option - [desc] is its rules text (SRD text where the SRD
/// has it). [minLevel]/[requires] are prerequisites (an Eldritch
/// Invocation's "Level 5+ Warlock" / "Pact of the Blade Invocation").
class FeatureOption {
  const FeatureOption(this.name, this.desc, {this.minLevel = 0, this.requires});
  final String name;
  final String desc;
  final int minLevel;
  final String? requires;
}

/// What a pick from a set does.
enum OptionKind {
  /// Adds each pick as its own feature (Eldritch Invocations, Metamagic).
  feature,

  /// Records a pick that specializes the trigger feature itself (Divine
  /// Order: Protector) - shown alongside that feature, and on the sheet.
  modifier,

  /// Skill proficiency (Primal Knowledge, Skillful, Keen Senses).
  skill,

  /// Skill or tool proficiency (Skilled).
  skillOrTool,

  /// Expertise in a proficient skill.
  expertise,

  /// A language.
  language,

  /// Weapon Mastery kinds (stored in Character.weaponMasteries).
  weaponMastery,

  /// Spells granted by the pick (rules.syncGrantedSpells adds them).
  spells,

  /// The spellcasting ability for granted spells (Int, Wis, or Cha).
  ability,
}

class FeatureOptionSet {
  const FeatureOptionSet({
    required this.name,
    required this.kind,
    required this.label,
    this.feature,
    this.changeable = false,
  });

  /// The key picks are stored under in Character.featureChoices.
  final String name;
  final OptionKind kind;

  /// What the choice asks, e.g. "Choose 2 skills for Expertise".
  final String label;

  /// The feature/trait/feat this set belongs to (shown with it on the
  /// Features tab) - usually [name] itself.
  final String? feature;

  /// Picks can be swapped later (Weapon Mastery after a Long Rest, Hunter's
  /// Prey after a rest, Circle of the Land's land each Long Rest...).
  final bool changeable;

  String get featureName => feature ?? name;
}

const _abilityOptions = [
  FeatureOption('Intelligence', ''),
  FeatureOption('Wisdom', ''),
  FeatureOption('Charisma', ''),
];

const _landOptions = [
  FeatureOption('Arid', 'Resistance: Fire.'),
  FeatureOption('Polar', 'Resistance: Cold.'),
  FeatureOption('Temperate', 'Resistance: Lightning.'),
  FeatureOption('Tropical', 'Resistance: Poison.'),
];

/// Species option sets' names - cleared when the species changes.
const _speciesOptionSets = {
  'Giant Ancestry',
  'Gnomish Lineage',
  'Lineage Spellcasting Ability',
  'Keen Senses',
  'Skillful',
};

bool _has(Character c, String feature) =>
    c.features.any((f) => f.name == feature);

/// Every option set that applies to [c] right now.
List<FeatureOptionSet> featureOptionSetsFor(Character c) => [
  for (final name in _allOptionSetNames(c))
    if (featureOptionSet(c, name) case final set?)
      if (optionCount(c, set) > 0) set,
];

Iterable<String> _allOptionSetNames(Character c) sync* {
  yield* const [
    'Weapon Mastery',
    'Expertise',
    'Deft Explorer',
    'Deft Explorer Languages',
    'Scholar',
    "Thieves' Cant",
    'Primal Knowledge',
    'Bonus Proficiencies',
    'Divine Order',
    'Primal Order',
    'Blessed Strikes',
    'Elemental Fury',
    "Hunter's Prey",
    'Defensive Tactics',
    'Elemental Affinity',
    'Circle of the Land Spells',
    'Fiendish Resilience',
    'Eldritch Invocations',
    'Metamagic',
    'Mystic Arcanum',
    'Spell Mastery',
    'Signature Spells',
    'Magical Discoveries',
    ..._speciesOptionSets,
  ];
  for (final feat in c.feats) {
    final base = baseFeatName(feat.name);
    if (base == 'Magic Initiate') {
      if (featNameChoice(feat.name) == null) {
        yield '${feat.name} List';
      } else {
        yield '${feat.name} Cantrips';
        yield '${feat.name} Spell';
        yield '${feat.name} Ability';
      }
    } else if (base == 'Skilled') {
      yield 'Skilled';
    }
  }
}

/// The set named [name] as it applies to [c], or null if [c] doesn't have
/// what grants it.
FeatureOptionSet? featureOptionSet(Character c, String name) {
  FeatureOptionSet set(
    OptionKind kind,
    String label, {
    String? feature,
    bool changeable = false,
  }) => FeatureOptionSet(
    name: name,
    kind: kind,
    label: label,
    feature: feature,
    changeable: changeable,
  );

  if (name.startsWith('Magic Initiate')) {
    final featName = name.replaceFirst(
      RegExp(r' (List|Cantrips|Spell|Ability)$'),
      '',
    );
    if (!c.feats.any((f) => f.name == featName)) return null;
    final list = featNameChoice(featName) ?? 'a class';
    return switch (name.substring(featName.length + 1)) {
      'List' => set(
        OptionKind.modifier,
        'Magic Initiate: choose a spell list',
        feature: featName,
      ),
      'Cantrips' => set(
        OptionKind.spells,
        'Magic Initiate: choose 2 $list cantrips',
        feature: featName,
        changeable: true,
      ),
      'Spell' => set(
        OptionKind.spells,
        'Magic Initiate: choose a level 1 $list spell',
        feature: featName,
        changeable: true,
      ),
      _ => set(
        OptionKind.ability,
        'Magic Initiate: spellcasting ability',
        feature: featName,
      ),
    };
  }

  switch (name) {
    case 'Weapon Mastery':
      return _has(c, name)
          ? set(
              OptionKind.weaponMastery,
              'Weapon Mastery: choose weapon kinds',
              changeable: true,
            )
          : null;
    case 'Expertise':
      return _has(c, name)
          ? set(OptionKind.expertise, 'Expertise: choose skills')
          : null;
    case 'Deft Explorer':
      return _has(c, name)
          ? set(
              OptionKind.expertise,
              'Deft Explorer: choose a skill for Expertise',
            )
          : null;
    case 'Deft Explorer Languages':
      return _has(c, 'Deft Explorer')
          ? set(
              OptionKind.language,
              'Deft Explorer: choose 2 languages',
              feature: 'Deft Explorer',
            )
          : null;
    case 'Scholar':
      return _has(c, name)
          ? set(OptionKind.expertise, 'Scholar: choose a skill for Expertise')
          : null;
    case "Thieves' Cant":
      return _has(c, name)
          ? set(OptionKind.language, "Thieves' Cant: choose one other language")
          : null;
    case 'Primal Knowledge':
      return _has(c, name)
          ? set(OptionKind.skill, 'Primal Knowledge: choose a Barbarian skill')
          : null;
    case 'Bonus Proficiencies':
      return _has(c, name)
          ? set(OptionKind.skill, 'Bonus Proficiencies: choose 3 skills')
          : null;
    case 'Divine Order':
    case 'Primal Order':
    case 'Blessed Strikes':
    case 'Elemental Fury':
    case 'Elemental Affinity':
      return _has(c, name)
          ? set(OptionKind.modifier, '$name: choose one')
          : null;
    case "Hunter's Prey":
    case 'Defensive Tactics':
    case 'Fiendish Resilience':
      return _has(c, name)
          ? set(OptionKind.modifier, '$name: choose one', changeable: true)
          : null;
    case 'Circle of the Land Spells':
      return _has(c, name)
          ? set(
              OptionKind.modifier,
              'Circle of the Land: choose your land (changes after a Long Rest)',
              changeable: true,
            )
          : null;
    case 'Eldritch Invocations':
      return _has(c, name)
          ? set(OptionKind.feature, 'Eldritch Invocations', changeable: true)
          : null;
    case 'Metamagic':
      return _has(c, name)
          ? set(OptionKind.feature, 'Metamagic options', changeable: true)
          : null;
    case 'Mystic Arcanum':
      return _has(c, name)
          ? set(
              OptionKind.spells,
              'Mystic Arcanum: one Warlock spell of each arcanum level',
              changeable: true,
            )
          : null;
    case 'Spell Mastery':
      return _has(c, name)
          ? set(
              OptionKind.spells,
              'Spell Mastery: a level 1 and a level 2 spellbook spell',
              changeable: true,
            )
          : null;
    case 'Signature Spells':
      return _has(c, name)
          ? set(
              OptionKind.spells,
              'Signature Spells: two level 3 spellbook spells',
              changeable: true,
            )
          : null;
    case 'Magical Discoveries':
      return _has(c, name)
          ? set(
              OptionKind.spells,
              'Magical Discoveries: 2 Cleric, Druid, or Wizard spells',
              changeable: true,
            )
          : null;
    case 'Giant Ancestry':
      return c.speciesKey == 'srd-2024_goliath-species'
          ? set(OptionKind.modifier, 'Giant Ancestry: choose your boon')
          : null;
    case 'Gnomish Lineage':
      return c.speciesKey == 'srd-2024_gnome-species'
          ? set(OptionKind.modifier, 'Gnomish Lineage: choose one')
          : null;
    case 'Lineage Spellcasting Ability':
      final trait = switch (c.speciesKey) {
        'srd-2024_elf-species' => 'Elven Lineage',
        'srd-2024_gnome-species' => 'Gnomish Lineage',
        'srd-2024_tiefling-species' => 'Fiendish Legacy',
        _ => null,
      };
      return trait == null
          ? null
          : set(
              OptionKind.ability,
              '$trait: spellcasting ability for its spells',
              feature: trait,
            );
    case 'Keen Senses':
      return c.speciesKey == 'srd-2024_elf-species'
          ? set(OptionKind.skill, 'Keen Senses: choose a skill')
          : null;
    case 'Skillful':
      return c.speciesKey == 'srd-2024_human-species'
          ? set(OptionKind.skill, 'Skillful: choose a skill')
          : null;
    case 'Skilled':
      return c.feats.any((f) => baseFeatName(f.name) == 'Skilled')
          ? set(OptionKind.skillOrTool, 'Skilled: choose 3 skills or tools')
          : null;
  }
  return null;
}

/// How many picks [set] allows [c] at their current level.
int optionCount(Character c, FeatureOptionSet set) {
  final level = c.level;
  int table(String column) =>
      int.tryParse(_classData(c)?.levelValue(level, column) ?? '') ?? 0;
  if (set.name.startsWith('Magic Initiate')) {
    return set.name.endsWith('Cantrips') ? 2 : 1;
  }
  return switch (set.name) {
    'Weapon Mastery' => weaponMasteryLimit(c) ?? 0,
    'Expertise' => switch (c.classKey) {
      'srd-2024_bard-class' => level >= 9 ? 4 : 2,
      'srd-2024_rogue-class' => level >= 6 ? 4 : 2,
      _ => 2, // Ranger's level 9 Expertise: two skills
    },
    'Deft Explorer Languages' => 2,
    'Bonus Proficiencies' => 3,
    'Eldritch Invocations' => table('Eldritch Invocations'),
    'Metamagic' => level >= 17 ? 6 : (level >= 10 ? 4 : 2),
    'Mystic Arcanum' =>
      level >= 17 ? 4 : (level >= 15 ? 3 : (level >= 13 ? 2 : 1)),
    'Spell Mastery' || 'Signature Spells' || 'Magical Discoveries' => 2,
    'Skilled' =>
      3 * c.feats.where((f) => baseFeatName(f.name) == 'Skilled').length,
    _ => 1,
  };
}

/// What [c] has picked for [set] so far.
List<String> optionPicks(Character c, FeatureOptionSet set) =>
    set.kind == OptionKind.weaponMastery
    ? c.weaponMasteries.where((m) => m != '*').toList()
    : c.featureChoices[set.name] ?? const [];

/// [c]'s single pick for [setName], or null.
String? optionPick(Character c, String setName) {
  final picks = c.featureChoices[setName];
  return picks == null || picks.isEmpty ? null : picks.first;
}

/// The options [set] offers [c] - every option, including ones already
/// picked; [optionAvailable] says which can be picked now.
List<FeatureOption> optionsFor(Character c, FeatureOptionSet set) {
  List<FeatureOption> skills(Iterable<String> names) => [
    for (final n in names) FeatureOption(n, ''),
  ];
  final allSkills = srdCatalog.skillsByName.keys.toList()..sort();
  final proficient = {
    for (final s in c.skills)
      if (s.proficient) s.name,
  };
  List<FeatureOption> spellsWhere(bool Function(SrdSpellRef s) test) => [
    for (final s in srdCatalog.spells)
      if (test(s))
        FeatureOption(
          s.name,
          s.level == 0
              ? 'Cantrip · ${s.school}'
              : 'Level ${s.level} ${s.school}',
        ),
  ];

  if (set.name.startsWith('Magic Initiate')) {
    final list = featNameChoice(set.featureName);
    return switch (set.name.substring(set.featureName.length + 1)) {
      'List' => const [
        FeatureOption('Cleric', ''),
        FeatureOption('Druid', ''),
        FeatureOption('Wizard', ''),
      ],
      'Cantrips' => spellsWhere(
        (s) => s.level == 0 && s.classes.contains(list),
      ),
      'Spell' => spellsWhere((s) => s.level == 1 && s.classes.contains(list)),
      _ => _abilityOptions,
    };
  }

  switch (set.name) {
    case 'Weapon Mastery':
      final meleeOnly = c.classKey == 'srd-2024_barbarian-class';
      return [
        for (final w in srdCatalog.weaponsByKey.values)
          if (w.mastery != null &&
              (!meleeOnly || w.category.contains('Melee')) &&
              isProficientWithWeapon(c, w.name, w.category, w.properties))
            FeatureOption(
              w.name,
              '${w.mastery}: '
              '${srdCatalog.weaponPropertiesByName[w.mastery]?.desc ?? ''}',
            ),
      ];
    case 'Expertise':
    case 'Deft Explorer':
      return skills(allSkills.where(proficient.contains));
    case 'Scholar':
      return skills(
        const [
          'Arcana',
          'History',
          'Investigation',
          'Medicine',
          'Nature',
          'Religion',
        ].where(proficient.contains),
      );
    case 'Deft Explorer Languages':
    case "Thieves' Cant":
      return [
        for (final l in srdCatalog.languages)
          if (l.name != "Thieves' Cant") FeatureOption(l.name, ''),
      ];
    case 'Primal Knowledge':
      return skills(
        srdCatalog.skillChoiceFor(c.classKey ?? '')?.choices ?? allSkills,
      );
    case 'Bonus Proficiencies':
    case 'Skillful':
      return skills(allSkills);
    case 'Keen Senses':
      return skills(const ['Insight', 'Perception', 'Survival']);
    case 'Skilled':
      return [
        ...skills(allSkills),
        for (final t in srdCatalog.tools) FeatureOption(t.name, 'Tool'),
      ];
    case 'Divine Order':
      return const [
        FeatureOption(
          'Protector',
          'Proficiency with Martial weapons and training with Heavy armor.',
        ),
        FeatureOption(
          'Thaumaturge',
          'One extra Cleric cantrip; add your Wisdom modifier (minimum +1) '
              'to Intelligence (Arcana or Religion) checks.',
        ),
      ];
    case 'Primal Order':
      return const [
        FeatureOption(
          'Magician',
          'One extra Druid cantrip; add your Wisdom modifier (minimum +1) '
              'to Intelligence (Arcana or Nature) checks.',
        ),
        FeatureOption(
          'Warden',
          'Proficiency with Martial weapons and training with Medium armor.',
        ),
      ];
    case 'Blessed Strikes':
      return const [
        FeatureOption(
          'Divine Strike',
          'Once on each of your turns when you hit with a weapon attack, '
              'deal an extra 1d8 Necrotic or Radiant damage.',
        ),
        FeatureOption(
          'Potent Spellcasting',
          'Add your Wisdom modifier to the damage of any Cleric cantrip.',
        ),
      ];
    case 'Elemental Fury':
      return const [
        FeatureOption(
          'Potent Spellcasting',
          'Add your Wisdom modifier to the damage of any Druid cantrip.',
        ),
        FeatureOption(
          'Primal Strike',
          'Once on each of your turns when you hit with a weapon or Beast '
              'form attack, deal an extra 1d8 Cold, Fire, Lightning, or '
              'Thunder damage.',
        ),
      ];
    case "Hunter's Prey":
      return const [
        FeatureOption(
          'Colossus Slayer',
          'Once per turn, a weapon hit deals an extra 1d8 damage to a '
              'target missing any of its Hit Points.',
        ),
        FeatureOption(
          'Horde Breaker',
          'Once per turn, make another attack with the same weapon '
              'against a different creature within 5 feet of the original '
              'target.',
        ),
      ];
    case 'Defensive Tactics':
      return const [
        FeatureOption(
          'Escape the Horde',
          'Opportunity Attacks have Disadvantage against you.',
        ),
        FeatureOption(
          'Multiattack Defense',
          'When a creature hits you, it has Disadvantage on all other '
              'attack rolls against you this turn.',
        ),
      ];
    case 'Elemental Affinity':
      return const [
        FeatureOption('Acid', ''),
        FeatureOption('Cold', ''),
        FeatureOption('Fire', ''),
        FeatureOption('Lightning', ''),
        FeatureOption('Poison', ''),
      ];
    case 'Circle of the Land Spells':
      return _landOptions;
    case 'Fiendish Resilience':
      return [
        for (final dt in srdCatalog.damageTypes)
          if (dt.name != 'Force') FeatureOption(dt.name, ''),
      ];
    case 'Eldritch Invocations':
      return _classOptionSections(
        'srd-2024_warlock-class',
        '### Eldritch Invocation Options',
      );
    case 'Metamagic':
      return _classOptionSections(
        'srd-2024_sorcerer-class',
        '### Metamagic Options',
      );
    case 'Mystic Arcanum':
      final maxLevel = 5 + optionCount(c, set);
      return spellsWhere(
        (s) =>
            s.classes.contains('Warlock') &&
            s.level >= 6 &&
            s.level <= maxLevel,
      );
    case 'Spell Mastery':
      final known = _knownSpellNames(c);
      return spellsWhere(
        (s) =>
            (s.level == 1 || s.level == 2) &&
            s.castingTime.startsWith('Action') &&
            known.contains(s.name),
      );
    case 'Signature Spells':
      final known = _knownSpellNames(c);
      return spellsWhere((s) => s.level == 3 && known.contains(s.name));
    case 'Magical Discoveries':
      final maxLevel = highestSlotLevel(c);
      return spellsWhere(
        (s) =>
            s.level <= maxLevel &&
            (s.classes.contains('Cleric') ||
                s.classes.contains('Druid') ||
                s.classes.contains('Wizard')),
      );
    case 'Giant Ancestry':
      return _traitBoldSections('srd-2024_goliath-species', 'Giant Ancestry');
    case 'Gnomish Lineage':
      return _traitBoldSections('srd-2024_gnome-species', 'Gnomish Lineage');
    case 'Lineage Spellcasting Ability':
      return _abilityOptions;
  }
  return const [];
}

Set<String> _knownSpellNames(Character c) => {
  for (final s in c.spellcasting?.spells ?? const <KnownSpell>[])
    if (s.source == null) ?knownSpellRef(s)?.name,
};

/// Whether [option] can be picked for [set] now: prerequisites met, not
/// already picked, and (for Expertise) not already an Expertise skill.
bool optionAvailable(Character c, FeatureOptionSet set, FeatureOption option) {
  if (c.level < option.minLevel) return false;
  final picks = optionPicks(c, set);
  if (option.requires != null &&
      !_allOptionPicks(c).contains(option.requires)) {
    return false;
  }
  if (set.kind == OptionKind.expertise) {
    return !c.skills.any((s) => s.name == option.name && s.expertise);
  }
  if (set.kind == OptionKind.skill || set.kind == OptionKind.skillOrTool) {
    return !c.skills.any((s) => s.name == option.name && s.proficient) &&
        !c.extraToolProficiencies.contains(option.name);
  }
  if (set.kind == OptionKind.language) {
    return !c.languages.contains(option.name);
  }
  return !picks.contains(option.name);
}

Set<String> _allOptionPicks(Character c) => {
  for (final picks in c.featureChoices.values) ...picks,
};

/// Parses a class's own "#### Option" sections (Eldritch Invocations,
/// Metamagic) out of its last feature's text, which carries them as an
/// appendix. A "Prerequisite: Level N+ Warlock" line becomes minLevel, and
/// a "..., X Invocation" prerequisite becomes [FeatureOption.requires].
List<FeatureOption> _classOptionSections(String classKey, String marker) {
  final classData = srdCatalog.byKey(classKey);
  if (classData == null) return const [];
  final text = classData.features
      .map((f) => f.desc)
      .firstWhere((d) => d.contains(marker), orElse: () => '');
  if (text.isEmpty) return const [];
  final body = text.substring(text.indexOf(marker) + marker.length);
  final result = <FeatureOption>[];
  for (final section in body.split('\n#### ').skip(1)) {
    final newline = section.indexOf('\n');
    if (newline < 0) continue;
    final name = section.substring(0, newline).trim();
    if (name.startsWith('Cantrips')) break;
    var desc = section.substring(newline + 1);
    final nextHeading = desc.indexOf('\n### ');
    if (nextHeading >= 0) desc = desc.substring(0, nextHeading);
    desc = desc.trim();
    final prereq = RegExp(r'_Prerequisite: ([^_]+)_').firstMatch(desc);
    final level = RegExp(r'Level (\d+)\+').firstMatch(prereq?.group(1) ?? '');
    final requires = RegExp(r'([A-Z][\w\s]+?) Invocation')
        .firstMatch(prereq?.group(1) ?? '');
    result.add(
      FeatureOption(
        name,
        desc,
        minLevel: level != null ? int.parse(level.group(1)!) : 0,
        requires: requires?.group(1)?.trim(),
      ),
    );
  }
  return result;
}

/// Parses a species trait's "**Name (Detail).** text" option paragraphs -
/// Giant Ancestry's six boons, Gnomish Lineage's two lineages. The option
/// name is the bold name without its parenthetical.
List<FeatureOption> _traitBoldSections(String speciesKey, String traitName) {
  final trait = srdCatalog.speciesByKey[speciesKey]?.traits.where(
    (t) => t.name == traitName,
  );
  if (trait == null || trait.isEmpty) return const [];
  return [
    for (final m in RegExp(
      r'\*\*(.+?)\.\*\*\s*(.+?)(?=\n\s*\n\*\*|$)',
      dotAll: true,
    ).allMatches(trait.first.desc))
      FeatureOption(
        m.group(1)!.replaceFirst(RegExp(r'\s*\(.*\)$'), ''),
        m.group(2)!.trim(),
      ),
  ];
}

/// Records [picks] for [set], replacing earlier picks for a changeable set
/// ([replace]) or adding to them, and applies what they do: proficiency,
/// Expertise, languages, masteries, extra training (Protector, Warden),
/// features (Invocations, Metamagic), and granted spells.
void chooseOptions(
  Character c,
  FeatureOptionSet set,
  List<String> picks, {
  bool replace = false,
}) {
  final before = replace ? const <String>[] : optionPicks(c, set);
  final all = [...before, ...picks];
  final options = {for (final o in optionsFor(c, set)) o.name: o};

  switch (set.kind) {
    case OptionKind.weaponMastery:
      c.weaponMasteries = all;
    case OptionKind.skill:
    case OptionKind.expertise:
    case OptionKind.skillOrTool:
      for (final name in picks) {
        final ref = srdCatalog.skillsByName[name];
        if (ref == null) {
          c.extraToolProficiencies = {
            ...c.extraToolProficiencies,
            name,
          }.toList();
          continue;
        }
        final existing = c.skills.where((s) => s.name == name);
        final entry = existing.isNotEmpty
            ? existing.first
            : SkillEntry(
                name: ref.name,
                ability: ref.ability,
                proficient: true,
              );
        entry.proficient = true;
        if (set.kind == OptionKind.expertise) entry.expertise = true;
        c.skills = [...c.skills.where((s) => s.name != name), entry];
      }
    case OptionKind.language:
      c.languages = {
        ...c.languages,
        if (set.name == "Thieves' Cant") "Thieves' Cant",
        ...picks,
      }.toList();
    case OptionKind.feature:
      if (replace) {
        c.features = c.features.where((f) => f.source != set.name).toList();
      }
      c.features = [
        ...c.features,
        for (final name in picks)
          GrantedFeature(
            name: name,
            source: set.name,
            desc: options[name]?.desc,
          ),
      ];
    case OptionKind.modifier:
    case OptionKind.spells:
    case OptionKind.ability:
      break;
  }
  if (set.kind != OptionKind.weaponMastery) {
    c.featureChoices = {...c.featureChoices, set.name: all};
  }

  // Picks that grant training.
  if (set.name == 'Divine Order' && all.contains('Protector')) {
    _addTraining(c, armor: 'Heavy', weapons: 'Martial weapons');
  }
  if (set.name == 'Primal Order' && all.contains('Warden')) {
    _addTraining(c, armor: 'Medium', weapons: 'Martial weapons');
  }
  // Magic Initiate with no list: the pick names the feat's list, then its
  // spells are chosen from that list.
  if (set.name.endsWith(' List') && set.name.startsWith('Magic Initiate')) {
    final newName = '${set.featureName} (${all.first})';
    c.feats = [
      for (final f in c.feats)
        f.name == set.featureName
            ? GrantedFeature(name: newName, source: f.source, desc: f.desc)
            : f,
    ];
    c.featureChoices = {...c.featureChoices}..remove(set.name);
    c.pendingChoices = [
      ...c.pendingChoices,
      ..._pendingFor(c, 'feat:', [
        '$newName Cantrips',
        '$newName Spell',
        '$newName Ability',
      ]),
    ];
  }
  c.pendingChoices = c.pendingChoices
      .where(
        (p) =>
            !(p.kind == 'option' &&
                p.optionSet == set.name &&
                optionPicks(c, set).length >= optionCount(c, set)),
      )
      .toList();
  syncGrantedSpells(c);
  logHistory(c, '${set.featureName}: ${picks.join(', ')}');
}

void _addTraining(
  Character c, {
  required String armor,
  required String weapons,
}) {
  c.extraArmorTraining = {...c.extraArmorTraining, armor}.toList();
  c.extraWeaponProficiencies = {
    ...c.extraWeaponProficiencies,
    weapons,
  }.toList();
  refreshWeaponProficiency(c);
}

List<PendingChoice> _pendingFor(
  Character c,
  String prefix,
  Iterable<String> setNames,
) {
  final existing = c.pendingChoices.map((p) => p.id).toSet();
  return [
    for (final name in setNames)
      if (featureOptionSet(c, name) case final set?)
        if (optionCount(c, set) - optionPicks(c, set).length case final missing
            when missing > 0 && !existing.contains('$prefix$name'))
          PendingChoice(
            id: '$prefix$name',
            label: set.label,
            kind: 'option',
            optionSet: name,
            count: missing,
          ),
  ];
}

/// Pending Choices for class and subclass option sets that [c] gained, or
/// gained more picks in, between [oldLevel] and their current level. The
/// counts are read at both levels, so a Warlock going from 4 to 5 gets
/// asked for exactly the invocations the table added.
List<PendingChoice> featureOptionPendingChoices(
  Character c,
  int oldLevel,
  int newLevel,
) {
  final result = <PendingChoice>[];
  final existing = c.pendingChoices.map((p) => p.id).toSet();
  final pendingSets = {
    for (final p in c.pendingChoices)
      if (p.kind == 'option') p.optionSet,
  };
  for (final set in featureOptionSetsFor(c)) {
    if (_speciesOptionSets.contains(set.name) ||
        set.name.startsWith('Magic Initiate') ||
        set.name == 'Skilled' ||
        pendingSets.contains(set.name)) {
      continue;
    }
    final now = optionCount(c, set);
    final picked = optionPicks(c, set).length;
    // A pre-existing character that never used these picks (Expertise
    // toggled by hand on the Overview tab) counts as having made them.
    final already = set.kind == OptionKind.expertise
        ? c.skills.where((s) => s.expertise).length
        : picked;
    final missing = now - already;
    final id = 'option:${set.name}:$newLevel';
    if (missing > 0 && !existing.contains(id)) {
      result.add(
        PendingChoice(
          id: id,
          label: 'Level $newLevel: ${set.label}',
          kind: 'option',
          optionSet: set.name,
          count: missing,
        ),
      );
    }
  }
  return result;
}

/// Pending Choices for [c]'s species options (Giant Ancestry, Skillful,
/// Keen Senses, a lineage's spellcasting ability) and Human Versatile's
/// Origin feat - asked at creation and when the species changes.
List<PendingChoice> speciesPendingChoices(Character c) => [
  ..._pendingFor(c, 'species:', _speciesOptionSets),
  if (c.speciesKey == 'srd-2024_human-species' &&
      !c.pendingChoices.any((p) => p.id == 'species:Versatile'))
    PendingChoice(
      id: 'species:Versatile',
      label: 'Versatile: choose an Origin feat',
      featCategory: 'Origin Feat',
    ),
];

/// Pending Choices for a newly granted feat's own options (Magic
/// Initiate's list/spells/ability, Skilled's proficiencies).
List<PendingChoice> featPendingChoices(Character c, GrantedFeature feat) {
  final base = baseFeatName(feat.name);
  if (base == 'Magic Initiate') {
    return _pendingFor(
      c,
      'feat:',
      featNameChoice(feat.name) == null
          ? ['${feat.name} List']
          : [
              '${feat.name} Cantrips',
              '${feat.name} Spell',
              '${feat.name} Ability',
            ],
    );
  }
  if (base == 'Skilled') {
    final set = featureOptionSet(c, 'Skilled')!;
    return [
      PendingChoice(
        id: 'feat:Skilled:${c.feats.length}',
        label: set.label,
        kind: 'option',
        optionSet: 'Skilled',
        count: 3,
      ),
    ];
  }
  return const [];
}

/// The pick-dependent short line the sheet shows for a feature whose
/// option set is a single modifier pick - "Protector: Martial weapons and
/// Heavy armor." - or null.
String? optionSheetText(Character c, GrantedFeature feature) {
  for (final set in featureOptionSetsFor(c)) {
    if (set.kind != OptionKind.modifier || set.featureName != feature.name) {
      continue;
    }
    final pick = optionPick(c, set.name);
    if (pick == null) return null;
    final short =
        srdCatalog.sheetText['options']?['${set.name}|$pick'] ??
        optionsFor(c, set).where((o) => o.name == pick).firstOrNull?.desc;
    return short == null || short.isEmpty ? pick : '$pick: $short';
  }
  return null;
}

/// Effects that come from species traits and option picks rather than a
/// feat or item: Dwarven Resilience (Poison resistance), a Tiefling
/// legacy's resistance, Wood Elf's 35 ft Speed, Elemental Affinity,
/// Circle of the Land's Nature's Ward, Fiendish Resilience, and a Cleric
/// Thaumaturge's / Druid Magician's skill bonus.
List<(String, Effect)> featureEffects(Character c) {
  final result = <(String, Effect)>[];
  void resist(String label, String type) => result.add((
    label,
    Effect(target: 'damageResistance:${type.toLowerCase()}', formula: ''),
  ));
  switch (c.speciesKey) {
    case 'srd-2024_dwarf-species':
      resist('Dwarven Resilience', 'poison');
    case 'srd-2024_tiefling-species':
      final type = switch (c.speciesChoice) {
        'Abyssal' => 'poison',
        'Chthonic' => 'necrotic',
        'Infernal' => 'fire',
        _ => null,
      };
      if (type != null) resist('Fiendish Legacy', type);
    case 'srd-2024_elf-species':
      if (c.speciesChoice == 'Wood Elf') {
        result.add(('Wood Elf', const Effect(target: 'speed', formula: '5')));
      }
  }
  final affinity = optionPick(c, 'Elemental Affinity');
  if (affinity != null && _has(c, 'Elemental Affinity')) {
    resist('Elemental Affinity', affinity);
  }
  final land = optionPick(c, 'Circle of the Land Spells');
  if (land != null && _has(c, "Nature's Ward")) {
    final type = {
      'Arid': 'fire',
      'Polar': 'cold',
      'Temperate': 'lightning',
      'Tropical': 'poison',
    }[land];
    if (type != null) resist("Nature's Ward", type);
  }
  final fiendish = optionPick(c, 'Fiendish Resilience');
  if (fiendish != null && _has(c, 'Fiendish Resilience')) {
    resist('Fiendish Resilience', fiendish);
  }
  final order = optionPick(c, 'Divine Order') ?? optionPick(c, 'Primal Order');
  if (order == 'Thaumaturge' || order == 'Magician') {
    final wis = abilityModifier(c.abilityScores.wis);
    final bonus = '${wis < 1 ? 1 : wis}';
    for (final skill in [
      'Arcana',
      order == 'Thaumaturge' ? 'Religion' : 'Nature',
    ]) {
      result.add((order!, Effect(target: 'skill:$skill', formula: bonus)));
    }
  }
  return result;
}
