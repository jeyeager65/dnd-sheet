import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

/// A class's level table row - e.g. `{"Level": "9", "Second Wind": "3",
/// "Class Features": "Indomitable (one use), Tactical Master", ...}` -
/// straight from classes.json, values kept as strings since columns mix
/// numbers ("3"), bonuses ("+4"), and prose.
typedef SrdLevelRow = Map<String, String?>;

/// A class feature's rules text - e.g. {level: 5, name: "Extra Attack",
/// desc: "You can attack twice instead of once..."}. Distinct from the
/// level table's "Class Features" column, which is just a name summary;
/// this is where the actual description lives.
class SrdClassFeature {
  const SrdClassFeature({
    required this.level,
    required this.name,
    required this.desc,
  });
  final int level;
  final String name;
  final String desc;
}

/// A class's subclass, as the free SRD has it: exactly one per class (the
/// "starter" subclass - Champion for Fighter, Evoker for Wizard, ...).
/// Battle Master/Eldritch Knight/other PHB-only subclasses aren't in this
/// data at all, so there's no real "choice" to model here yet - a class
/// with SRD data has one subclass, auto-assigned once its level is
/// reached (see rules.dart's resolveSubclassChoice).
class SrdSubclass {
  const SrdSubclass({
    required this.key,
    required this.name,
    required this.features,
    this.spellsByLevel = const {},
  });
  final String key;
  final String name;
  final List<SrdClassFeature> features;

  /// Always-prepared spells by class level - a homebrew subclass's own
  /// list. (An SRD subclass keeps its list in a "... Spells" feature's
  /// table instead; see rules_granted_spells.dart.)
  final Map<int, List<String>> spellsByLevel;
}

class SrdClass {
  SrdClass({
    required this.key,
    required this.name,
    required this.traits,
    required this.levels,
    required this.features,
    this.subclass,
    this.spellSlotsByLevel = const {},
  });
  final String key;
  final String name;
  final Map<String, String> traits;
  final List<SrdLevelRow> levels;
  final List<SrdClassFeature> features;
  final SrdSubclass? subclass;

  /// Character level -> {spell level: slot count} for a full caster's
  /// level table (Wizard, Cleric, ...) - the level table's `spellSlots`
  /// column is a nested object, unlike every other column, so it's parsed
  /// separately rather than through the flat string-keyed [levels] rows.
  /// Empty for a non-caster or a Pact Magic caster (Warlock), whose flat
  /// "Spell Slots"/"Slot Level" columns are read straight from [levels]
  /// instead - see rules.dart's spellSlotsAtLevel.
  final Map<int, Map<int, int>> spellSlotsByLevel;

  /// The value of [column] at exactly [level] - e.g. `levelValue(9, 'Second
  /// Wind')` on Fighter returns `'3'`. Returns null if the level or column
  /// isn't present (some columns are blank at levels that don't change them).
  String? levelValue(int level, String column) {
    for (final row in levels) {
      if (row['Level'] == '$level') return row[column];
    }
    return null;
  }

  /// Spell slot counts (spell level -> how many) at a given character
  /// level - {} for a non-caster or a level with no slots yet. Handles
  /// both shapes the SRD data uses: a full caster's per-spell-level
  /// spellSlotsByLevel table, and Warlock's flat "Spell Slots" (a count) +
  /// "Slot Level" (the single level all of them are) columns instead,
  /// since every Warlock slot is the same level.
  Map<int, int> spellSlotsAtLevel(int level) {
    final nested = spellSlotsByLevel[level];
    if (nested != null && nested.isNotEmpty) return nested;
    final row = levelValue(level, 'Spell Slots');
    final slotLevel = levelValue(level, 'Slot Level');
    final count = row != null ? int.tryParse(row) : null;
    final sLevel = slotLevel != null ? int.tryParse(slotLevel) : null;
    if (count != null && count > 0 && sLevel != null && sLevel > 0) {
      return {sLevel: count};
    }
    return const {};
  }

  /// True for a Pact Magic caster (Warlock) - its level table has the
  /// flat "Slot Level" column instead of the per-spell-level spellSlots
  /// one. Pact Magic slots come back on a Short Rest too, not just a Long
  /// Rest (see rules.applyShortRest).
  bool get hasPactMagic => levels.any((row) => row.containsKey('Slot Level'));

  /// The level table's "Cantrips" / "Prepared Spells" count at [level] -
  /// null for a class whose table has no such column (Paladin and Ranger
  /// learn no cantrips; a non-caster has neither).
  int? cantripsAtLevel(int level) =>
      int.tryParse(levelValue(level, 'Cantrips') ?? '');
  int? preparedSpellsAtLevel(int level) =>
      int.tryParse(levelValue(level, 'Prepared Spells') ?? '');

  /// The level at which this class's level table first offers a subclass
  /// choice - always phrased "[Class Name] Subclass" in the "Class
  /// Features" column (verified against every SRD class: always level 3).
  /// Later levels say "Subclass feature" instead (more of an already-
  /// chosen subclass's features), which this deliberately excludes.
  int? get subclassChoiceLevel {
    for (final row in levels) {
      final text = row['Class Features'] ?? '';
      if (RegExp(r'\bSubclass\b').hasMatch(text) &&
          !text.contains('Subclass feature')) {
        return int.parse(row['Level']!);
      }
    }
    return null;
  }
}

/// A bare key+name catalog entry - enough to list and pick from, without
/// carrying the full SRD record (traits, tables, ...) into the picker UI.
class SrdRefItem {
  const SrdRefItem({
    required this.key,
    required this.name,
    this.isHomebrew = false,
    this.detail,
  });
  final String key;
  final String name;

  /// True for an entry resolved from homebrewRepo rather than the bundled
  /// SRD catalog - shown as a "Homebrew" badge in picker UIs.
  final bool isHomebrew;

  /// An optional one-line caption under the name in picker UIs (e.g. a
  /// spell's "Level 3 Evocation") - null for most catalogs, where the
  /// name alone is enough to pick by.
  final String? detail;
}

class SrdFeatBenefit {
  const SrdFeatBenefit(this.name, this.desc);
  final String name;
  final String desc;
}

class SrdFeat {
  SrdFeat({
    required this.key,
    required this.name,
    required this.category,
    required this.prerequisite,
    required this.desc,
    required this.benefits,
  });
  final String key;
  final String name;
  final String category;
  final String? prerequisite;
  final String desc;
  final List<SrdFeatBenefit> benefits;

  /// Full description including benefits, formatted for display. Some
  /// feats' `desc` is just an intro line ("You gain the following
  /// benefits.") with the actual mechanics living in `benefits` - mirrors
  /// the web app's formatFeatDescription, which this was ported from.
  String get fullDescription {
    final parts = <String>[if (desc.isNotEmpty) desc];
    for (final b in benefits) {
      parts.add('${b.name}: ${b.desc}');
    }
    return parts.join(' ');
  }
}

class SrdWeaponRef {
  SrdWeaponRef({
    required this.key,
    required this.name,
    required this.category,
    required this.damage,
    required this.properties,
    this.mastery,
  });
  final String key;
  final String name;
  final String category;
  final String damage; // e.g. "2d6 Slashing"
  final List<String> properties; // e.g. ["Heavy", "Two-Handed"]
  final String? mastery;

  bool get isHeavy => properties.contains('Heavy');
  bool get isFinesse => properties.contains('Finesse');

  /// Splits "2d6 Slashing" into dice ("2d6") and damage type ("Slashing").
  (String dice, String type) get splitDamage {
    final parts = damage.split(' ');
    return (
      parts.isNotEmpty ? parts.first : '',
      parts.length > 1 ? parts.sublist(1).join(' ') : '',
    );
  }
}

class SrdArmorRef {
  SrdArmorRef({
    required this.key,
    required this.name,
    required this.category,
    required this.armorClass,
    this.strength,
    required this.stealth,
  });
  final String key;
  final String name;
  final String
  category; // e.g. "Heavy Armor (10 Minutes to Don and 5 Minutes to Doff)"
  final String armorClass; // formula text, e.g. "11 + Dex modifier"
  final String? strength;
  final bool stealth; // true = Disadvantage on Stealth checks

  /// [category] boiled down to 'Light' | 'Medium' | 'Heavy' | null -
  /// matches EquippedArmor.category's vocabulary (models/character.dart),
  /// which drives conditions like Heavy Armor Master's damage reduction.
  String? get simpleCategory => category.contains('Heavy')
      ? 'Heavy'
      : category.contains('Medium')
      ? 'Medium'
      : category.contains('Light')
      ? 'Light'
      : null;
}

class SrdGearRef {
  const SrdGearRef({
    required this.key,
    required this.name,
    this.desc = '',
    this.weight,
    this.cost,
  });
  final String key;
  final String name;
  final String desc;
  final String? weight;
  final String? cost;
}

class SrdToolRef {
  const SrdToolRef({
    required this.key,
    required this.name,
    this.ability,
    this.utilize = '',
    this.craft = '',
    this.cost,
    this.variants = const [],
  });
  final String key;
  final String name;
  final String? ability; // governing ability for checks, e.g. "Intelligence"
  final String utilize; // what a check with this tool can accomplish
  final String craft; // items craftable with this tool
  final String? cost;

  /// Specific kinds this tool comes in, e.g. "Gaming Set" -> [Dice,
  /// dragonchess, playing cards, three-dragon ante] - empty for a tool
  /// that's just itself (most of them). Drives rules.parseToolChoice's
  /// picker when a background/class grants "Choose N `<this tool>`".
  final List<String> variants;
}

class SrdMagicItemRef {
  const SrdMagicItemRef({
    required this.key,
    required this.name,
    required this.category,
    required this.rarity,
    this.desc = '',
  });
  final String key;
  final String name;
  final String category;
  final String rarity;
  final String desc;
}

/// A weapon property or mastery's rules text (Finesse, Heavy, Graze,
/// Cleave, ...) - keyed by name, since that's how a Weapon record
/// references it (`mastery: "Graze"`, `properties: ["Heavy", ...]`).
class SrdWeaponPropertyRef {
  const SrdWeaponPropertyRef({
    required this.name,
    required this.desc,
    required this.isMastery,
  });
  final String name;
  final String desc;
  final bool isMastery;
}

class SrdSpellRef {
  const SrdSpellRef({
    required this.key,
    required this.name,
    required this.level,
    required this.school,
    this.classes = const [],
    this.ritual = false,
    this.castingTime = '',
    this.range = '',
    this.components = '',
    this.concentration = false,
    this.duration = '',
    this.desc = '',
    this.higherLevel,
  });
  final String key;
  final String name;
  final int level; // 0 = cantrip
  final String school;
  final List<String> classes; // which class lists it appears on
  final bool ritual;
  final String castingTime;
  final String range;
  final String components; // e.g. "V, S, M (a ball of bat guano and sulfur)"
  final bool concentration;
  final String duration;
  final String desc;

  /// "At Higher Levels" text - null for a spell with no scaling effect.
  final String? higherLevel;
}

/// One trait line from a species entry (e.g. Dragonborn's "Breath Weapon").
class SrdSpeciesTrait {
  const SrdSpeciesTrait({required this.name, required this.desc});
  final String name;
  final String desc;
}

/// An embedded choice table from a species entry - Dragonborn's "Draconic
/// Ancestors," Elf's "Elven Lineages," Tiefling's "Fiendish Legacies."
class SrdSpeciesTable {
  const SrdSpeciesTable({
    required this.caption,
    required this.headers,
    required this.rows,
  });
  final String caption;
  final List<String> headers;
  final List<List<String>> rows;
}

class SrdSpeciesInfo {
  SrdSpeciesInfo({
    required this.key,
    required this.name,
    required this.size,
    required this.speed,
    required this.traits,
    required this.tables,
  });
  final String key;
  final String name;
  final String size; // e.g. "Medium (about 5-7 feet tall)"
  final String speed; // e.g. "30 feet"
  final List<SrdSpeciesTrait> traits;
  final List<SrdSpeciesTable> tables;
}

/// One option from a flattened species choice table - e.g. {name: "Red",
/// detail: "Fire"} for Dragonborn's Draconic Ancestry.
class SpeciesChoiceOption {
  const SpeciesChoiceOption({required this.name, required this.detail});
  final String name;
  final String detail;
}

/// Flattens a species's embedded choice table into a flat option list. The
/// source data comes in two layouts:
///  - Dragonborn's repeats its 2 columns twice per row (two dragons per
///    row, since the original book table was two side-by-side
///    mini-tables) - detected by the header list's first half exactly
///    equaling its second half - and each half becomes its own option.
///  - Elf/Tiefling's is one option per row: first column is the name, the
///    rest are detail columns joined together for display.
/// Ported from the web app's rules.ts flattenSpeciesTableOptions.
List<SpeciesChoiceOption> flattenSpeciesTableOptions(SrdSpeciesTable table) {
  final headers = table.headers;
  final isEven = headers.length % 2 == 0;
  final half = headers.length ~/ 2;
  final isPaired =
      isEven &&
      half > 0 &&
      _sameStrings(headers.sublist(0, half), headers.sublist(half));

  if (isPaired) {
    final options = <SpeciesChoiceOption>[];
    for (final row in table.rows) {
      if (row.isNotEmpty && row[0].isNotEmpty) {
        options.add(
          SpeciesChoiceOption(
            name: row[0],
            detail: row.length > 1 ? row[1] : '',
          ),
        );
      }
      if (row.length > half && row[half].isNotEmpty) {
        options.add(
          SpeciesChoiceOption(
            name: row[half],
            detail: row.length > half + 1 ? row[half + 1] : '',
          ),
        );
      }
    }
    return options;
  }

  return [
    for (final row in table.rows)
      SpeciesChoiceOption(
        name: row.isNotEmpty ? row[0] : '',
        detail: row.skip(1).where((c) => c.isNotEmpty).join(' / '),
      ),
  ];
}

bool _sameStrings(List<String> a, List<String> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// A background's fixed grants - skills and a feat are given outright
/// (not a choice), unlike a class's skill proficiencies below. [equipment]
/// is the verbatim "Choose A or B" starting-gear text (same shape as
/// Fighter's Starting Equipment, just not parsed into structured options
/// the way starting_equipment.dart's packages are -
/// backgrounds aren't in that scope yet).
class SrdBackgroundInfo {
  SrdBackgroundInfo({
    required this.key,
    required this.name,
    required this.skillProficiencies,
    this.feat,
    this.abilityScores = const [],
    this.toolProficiency,
    this.equipment,
  });
  final String key;
  final String name;
  final List<String> skillProficiencies;
  final String? feat;
  final List<String> abilityScores;
  final String? toolProficiency;
  final String? equipment;
}

/// One of the 18 skills and the ability it's checked against - e.g.
/// {name: "Athletics", ability: "str"}, plus the 2024 rules-glossary
/// description of what the skill covers.
class SrdSkillRef {
  const SrdSkillRef({
    required this.name,
    required this.ability,
    this.desc = '',
  });
  final String name;
  final String ability;
  final String desc;
}

/// Picks the SRD 2024 entry out of a reference file's multi-gamesystem
/// `descriptions` array (each bundled reference file also carries 2014 and
/// third-party "a5e" text for other Open5e consumers - this app only ever
/// wants the 2024 one). Returns '' if the 2024 entry is missing rather
/// than falling back to a different ruleset's text.
String _srd2024Desc(List<dynamic>? descriptions) {
  if (descriptions == null) return '';
  for (final d in descriptions) {
    final map = d as Map<String, dynamic>;
    if (map['gamesystem'] == '5e-2024') return map['desc'] as String? ?? '';
  }
  return '';
}

/// A resolved reference-glossary entry - one Strength/Charisma/...,
/// Lawful Good/Chaotic Evil/..., Acid/Fire/..., or Abjuration/Evocation/...
/// Every one of these reference lists (abilities, alignments, damage
/// types, spell schools) shares this exact shape, so one class covers all
/// of them rather than four nearly-identical ones.
class SrdGlossaryEntry {
  const SrdGlossaryEntry({
    required this.key,
    required this.name,
    required this.desc,
    this.shortName,
  });
  final String key;
  final String name;
  final String desc;

  /// e.g. "CE" for Chaotic Evil - only alignments have this.
  final String? shortName;
}

class SrdSizeRef {
  const SrdSizeRef({
    required this.name,
    required this.spaceDiameter,
    required this.hitDie,
  });
  final String name;
  final int spaceDiameter; // feet
  final String hitDie; // e.g. "d8", used for some improvised-size rules
}

/// One term from the SRD's Rules Glossary chapter (rules-markdown's
/// rules-glossary.md) - the alphabetical dictionary of core rules terms
/// (Advantage, Cover, Opportunity Attack, ...), not to be confused with
/// the four small taxonomy lists above (abilities/alignments/damage
/// types/spell schools), which come from a different source file. [tag]
/// is the bracketed family a term belongs to when the SRD gives it one
/// (e.g. "Condition" for "Blinded [Condition]"), null otherwise.
class SrdGlossaryTerm {
  const SrdGlossaryTerm({
    required this.key,
    required this.name,
    required this.desc,
    this.tag,
  });
  final String key;
  final String name;
  final String desc;
  final String? tag;
}

/// A generic name+desc reference entry - one top-level section of a
/// narrative SRD rules chapter (Playing the Game, Gameplay Toolbox,
/// Character Creation), or an equipment-style listing (a mount, a
/// vehicle) whose few fields get formatted into one desc string at load
/// time. Reused rather than modeled per source, since every use is just
/// "a name and some SRD text" shown the same way in Reference.
class SrdNamedText {
  const SrdNamedText({
    required this.key,
    required this.name,
    required this.desc,
  });
  final String key;
  final String name;
  final String desc;
}

/// A class's "choose N skills" grant, parsed from trait text like "Choose
/// 2: Acrobatics, Animal Handling, ..." or Bard's "Choose any 3 skills"
/// (any of the 18, not a restricted list - `choices == null` means that).
class SrdSkillChoice {
  const SrdSkillChoice({required this.count, required this.choices});
  final int count;
  final List<String>? choices;
}

/// The bundled SRD catalog, loaded once at startup from assets/srd/ - the
/// same verified data the Quasar web app uses (src/data/srd/), copied
/// over rather than re-derived, with full 2024 rules text ported
/// wherever the source data actually has it (spells, gear, tools, magic
/// items, and the reference glossary - abilities, alignments, damage
/// types, spell schools, sizes, skills).
class SrdCatalog {
  final Map<String, SrdClass> classesByKey = {};
  final Map<String, SrdSpeciesInfo> speciesByKey = {};
  final Map<String, SrdBackgroundInfo> backgroundsByKey = {};
  final Map<String, SrdFeat> featsByKey = {};
  final Map<String, SrdWeaponRef> weaponsByKey = {};
  final Map<String, SrdArmorRef> armorByKey = {};
  final List<SrdSpellRef> spells = [];
  final Map<String, SrdWeaponPropertyRef> weaponPropertiesByName = {};
  final Map<String, SrdSkillRef> skillsByName = {};
  final Map<String, SrdGearRef> gearByKey = {};
  final Map<String, SrdToolRef> toolsByKey = {};
  final Map<String, SrdMagicItemRef> magicItemsByKey = {};
  final List<SrdRefItem> languages = [];

  /// Condition name -> full SRD rules text (e.g. "Blinded" -> "While you
  /// have the Blinded condition..."). Excludes Exhaustion, which the sheet
  /// tracks separately via its own 0-6 level rather than as a toggle here.
  final Map<String, String> conditionDescriptions = {};

  /// Reference glossary lists - abilities (6), alignments (9), damage
  /// types (13), and spell schools (8). Each entry carries the 2024
  /// rules-glossary description, not the 2014/third-party text the
  /// source file also bundles - see _srd2024Desc.
  final List<SrdGlossaryEntry> abilityGlossary = [];
  final List<SrdGlossaryEntry> alignments = [];
  final List<SrdGlossaryEntry> damageTypes = [];
  final List<SrdGlossaryEntry> spellSchools = [];
  final List<SrdSizeRef> sizes = [];

  /// The full Rules Glossary chapter (154 terms) - see SrdGlossaryTerm.
  final List<SrdGlossaryTerm> rulesGlossary = [];

  /// The narrative rules chapters with no other parser, one entry per
  /// top-level ("## ") section - see SrdNamedText. character-origins.md
  /// (species/backgrounds) isn't here since classesByKey/speciesByKey/
  /// backgroundsByKey already cover it in full.
  final List<SrdNamedText> playingTheGame = [];
  final List<SrdNamedText> gameplayToolbox = [];
  final List<SrdNamedText> characterCreationChapters = [];

  /// Purchasable mounts and vehicles (Equipment chapter's shopping list -
  /// cost/capacity/stats, not a creature stat block), combined into one
  /// list since they're one section of the same chapter.
  final List<SrdNamedText> mountsAndVehicles = [];

  /// This app's own short summaries of SRD features for the exported PDF
  /// sheet, whose Class Features/Species Traits/Feats boxes can't fit the
  /// full rules text: scope -> feature name -> text. The scope is the class,
  /// subclass, or species key the feature belongs to, or "feats" for a
  /// feat (names repeat across classes - every caster has a "Spellcasting"
  /// - so a bare name isn't enough). Written by hand from each feature's
  /// SRD text (assets/srd/sheet-text.json); see rules.sheetText for how a
  /// player's own edits and homebrew text layer on top.
  final Map<String, Map<String, String>> sheetText = {};

  Future<void> init() async {
    await Future.wait([
      _loadSheetText(),
      _loadClasses(),
      _loadSpecies(),
      _loadBackgrounds(),
      _loadFeats(),
      _loadWeapons(),
      _loadWeaponProperties(),
      _loadArmor(),
      _loadSpells(),
      _loadSkills(),
      _loadGear(),
      _loadTools(),
      _loadMagicItems(),
      _loadRefList('assets/srd/languages.json', languages),
      _loadConditions(),
      _loadGlossary(
        'assets/srd/reference/abilities.json',
        abilityGlossary,
        nameField: 'name',
      ),
      _loadGlossary(
        'assets/srd/reference/alignments.json',
        alignments,
        shortNameField: 'short_name',
      ),
      _loadGlossary('assets/srd/reference/damagetypes.json', damageTypes),
      _loadSpellSchools(),
      _loadSizes(),
      _loadRulesGlossary(),
      _loadChapter(
        'assets/srd/reference/playing-the-game.json',
        playingTheGame,
      ),
      _loadChapter(
        'assets/srd/reference/gameplay-toolbox.json',
        gameplayToolbox,
      ),
      _loadChapter(
        'assets/srd/reference/character-creation.json',
        characterCreationChapters,
      ),
      _loadMountsAndVehicles(),
    ]);
  }

  Future<void> _loadRulesGlossary() async {
    final raw = await rootBundle.loadString(
      'assets/srd/reference/rules-glossary.json',
    );
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      rulesGlossary.add(
        SrdGlossaryTerm(
          key: map['key'] as String,
          name: map['name'] as String,
          desc: map['desc'] as String? ?? '',
          tag: map['tag'] as String?,
        ),
      );
    }
  }

  /// Loads one of the pre-split ("## "-section) narrative chapter files -
  /// playing-the-game.json, gameplay-toolbox.json, character-creation.json
  /// all share the same {key, name, desc} shape.
  Future<void> _loadChapter(String asset, List<SrdNamedText> target) async {
    final raw = await rootBundle.loadString(asset);
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      target.add(
        SrdNamedText(
          key: map['key'] as String,
          name: map['name'] as String,
          desc: map['desc'] as String? ?? '',
        ),
      );
    }
  }

  /// Mounts, large vehicles, and tack/harness/drawn-vehicle gear - three
  /// small source files with differing fields (a mount has a carrying
  /// capacity, a vehicle has AC/HP/speed, tack is just weight+cost), each
  /// formatted into one stat-line desc here so they can share one list.
  Future<void> _loadMountsAndVehicles() async {
    Future<void> load(
      String asset,
      String Function(Map<String, dynamic>) formatDesc,
    ) async {
      final raw = await rootBundle.loadString(asset);
      final list = jsonDecode(raw) as List;
      for (final item in list) {
        final map = item as Map<String, dynamic>;
        mountsAndVehicles.add(
          SrdNamedText(
            key: map['key'] as String,
            name: map['name'] as String,
            desc: formatDesc(map),
          ),
        );
      }
    }

    await load('assets/srd/mounts.json', (m) {
      final parts = <String>[
        if (m['cost'] != null) 'Cost: ${m['cost']}',
        if (m['carryingCapacity'] != null)
          'Carrying Capacity: ${m['carryingCapacity']}',
      ];
      return parts.join('\n');
    });
    await load('assets/srd/large-vehicles.json', (m) {
      final parts = <String>[
        if (m['cost'] != null) 'Cost: ${m['cost']}',
        if (m['speed'] != null) 'Speed: ${m['speed']}',
        if (m['crew'] != null) 'Crew: ${m['crew']}',
        if (m['passengers'] != null) 'Passengers: ${m['passengers']}',
        if (m['cargoTons'] != null) 'Cargo: ${m['cargoTons']} tons',
        if (m['armorClass'] != null) 'AC: ${m['armorClass']}',
        if (m['hitPoints'] != null) 'HP: ${m['hitPoints']}',
        if (m['damageThreshold'] != null)
          'Damage Threshold: ${m['damageThreshold']}',
      ];
      return parts.join('\n');
    });
    await load('assets/srd/tack-vehicles.json', (m) {
      final parts = <String>[
        if (m['cost'] != null) 'Cost: ${m['cost']}',
        if (m['weight'] != null) 'Weight: ${m['weight']}',
      ];
      return parts.join('\n');
    });
  }

  /// Loads one of the reference glossary files (abilities, alignments,
  /// damage types) - all three share the same {key, descriptions: [...]}
  /// shape, differing only in whether they have a top-level `name` (vs.
  /// deriving a display name from the key) or a `short_name`.
  Future<void> _loadGlossary(
    String asset,
    List<SrdGlossaryEntry> target, {
    String? nameField,
    String? shortNameField,
  }) async {
    final raw = await rootBundle.loadString(asset);
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final key = map['key'] as String;
      final name = nameField != null && map[nameField] != null
          ? map[nameField] as String
          : key
                .split('-')
                .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1))
                .join(' ');
      target.add(
        SrdGlossaryEntry(
          key: key,
          name: name,
          desc: _srd2024Desc(map['descriptions'] as List?),
          shortName: shortNameField != null
              ? map[shortNameField] as String?
              : null,
        ),
      );
    }
  }

  Future<void> _loadSpellSchools() async {
    final raw = await rootBundle.loadString(
      'assets/srd/reference/spellschools.json',
    );
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      spellSchools.add(
        SrdGlossaryEntry(
          key: map['key'] as String,
          name: map['name'] as String,
          desc: map['desc'] as String? ?? '',
        ),
      );
    }
  }

  Future<void> _loadSizes() async {
    final raw = await rootBundle.loadString('assets/srd/reference/sizes.json');
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      sizes.add(
        SrdSizeRef(
          name: map['name'] as String,
          spaceDiameter: map['space_diameter'] as int,
          hitDie: map['suggested_hit_dice'] as String,
        ),
      );
    }
  }

  Future<void> _loadGear() async {
    final raw = await rootBundle.loadString('assets/srd/gear.json');
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final gear = SrdGearRef(
        key: map['key'] as String,
        name: map['name'] as String,
        desc: map['desc'] as String? ?? '',
        weight: map['weight'] as String?,
        cost: map['cost'] as String?,
      );
      gearByKey[gear.key] = gear;
    }
  }

  Future<void> _loadTools() async {
    final raw = await rootBundle.loadString('assets/srd/tools.json');
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final tool = SrdToolRef(
        key: map['key'] as String,
        name: map['name'] as String,
        ability: map['ability'] as String?,
        utilize: map['utilize'] as String? ?? '',
        craft: map['craft'] as String? ?? '',
        cost: map['cost'] as String?,
        variants: (map['variants'] as List? ?? const [])
            .map((v) => (v as Map<String, dynamic>)['name'] as String)
            .toList(),
      );
      toolsByKey[tool.key] = tool;
    }
  }

  Future<void> _loadMagicItems() async {
    final raw = await rootBundle.loadString('assets/srd/magic-items.json');
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final magicItem = SrdMagicItemRef(
        key: map['key'] as String,
        name: map['name'] as String,
        category: map['category'] as String? ?? '',
        rarity: map['rarity'] as String? ?? '',
        desc: map['desc'] as String? ?? '',
      );
      magicItemsByKey[magicItem.key] = magicItem;
    }
  }

  Future<void> _loadSpecies() async {
    final raw = await rootBundle.loadString('assets/srd/species.json');
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final traits = (map['traits'] as List? ?? const [])
          .map(
            (t) => SrdSpeciesTrait(
              name: (t as Map<String, dynamic>)['name'] as String,
              desc: t['desc'] as String,
            ),
          )
          .toList();
      final tables = (map['tables'] as List? ?? const [])
          .map(
            (t) => SrdSpeciesTable(
              caption: (t as Map<String, dynamic>)['caption'] as String,
              headers: (t['headers'] as List).cast<String>(),
              rows: (t['rows'] as List)
                  .map((row) => (row as List).cast<String>())
                  .toList(),
            ),
          )
          .toList();
      final info = SrdSpeciesInfo(
        key: map['key'] as String,
        name: map['name'] as String,
        size: map['size'] as String? ?? '',
        speed: map['speed'] as String? ?? '30 feet',
        traits: traits,
        tables: tables,
      );
      speciesByKey[info.key] = info;
    }
  }

  Future<void> _loadBackgrounds() async {
    final raw = await rootBundle.loadString('assets/srd/backgrounds.json');
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final info = SrdBackgroundInfo(
        key: map['key'] as String,
        name: map['name'] as String,
        skillProficiencies: (map['skillProficiencies'] as List).cast<String>(),
        feat: map['feat'] as String?,
        abilityScores:
            (map['abilityScores'] as List?)?.cast<String>() ?? const [],
        toolProficiency: map['toolProficiency'] as String?,
        equipment: map['equipment'] as String?,
      );
      backgroundsByKey[info.key] = info;
    }
  }

  Future<void> _loadSkills() async {
    final raw = await rootBundle.loadString('assets/srd/reference/skills.json');
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final skill = SrdSkillRef(
        name: map['name'] as String,
        ability: map['ability'] as String,
        desc: _srd2024Desc(map['descriptions'] as List?),
      );
      skillsByName[skill.name] = skill;
    }
  }

  /// Parses a class's "Skill Proficiencies" trait text into a count + the
  /// eligible list (null = any of the 18 skills, Bard's case). Returns
  /// null if the text doesn't match either known shape.
  SrdSkillChoice? skillChoiceFor(String classKey) {
    final text = classesByKey[classKey]?.traits['Skill Proficiencies'];
    if (text == null) return null;
    final countMatch = RegExp(r'Choose (?:any )?(\d+)').firstMatch(text);
    if (countMatch == null) return null;
    final count = int.parse(countMatch.group(1)!);
    if (text.contains('Choose any')) {
      return SrdSkillChoice(count: count, choices: null);
    }
    final afterColon = text.contains(':') ? text.split(':').last : text;
    final choices = afterColon
        .replaceAll(RegExp(r',?\s+or\s+'), ', ')
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    return SrdSkillChoice(count: count, choices: choices);
  }

  /// Every level at which this class's "Class Features" column mentions
  /// Ability Score Improvement - e.g. Fighter: 4, 6, 8, 12, 14, 16.
  /// Used to auto-surface a Pending Choice when a character crosses one
  /// of these levels (see rules.dart's pendingChoicesForLevelUp).
  List<int> abilityScoreImprovementLevels(String classKey) {
    final cls = classesByKey[classKey];
    if (cls == null) return const [];
    return [
      for (final row in cls.levels)
        if ((row['Class Features'] ?? '').contains('Ability Score Improvement'))
          int.parse(row['Level']!),
    ];
  }

  Future<void> _loadClasses() async {
    final raw = await rootBundle.loadString('assets/srd/classes.json');
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final rawLevels = (map['levels'] as List).cast<Map<String, dynamic>>();
      final levels = rawLevels
          .map((row) => row.map((k, v) => MapEntry(k, v?.toString())))
          .toList();
      // The `spellSlots` column is a nested {spell level: count} object,
      // unlike every other column - parsed here, from the raw JSON,
      // before the generic stringify pass above would otherwise mangle it.
      final spellSlotsByLevel = <int, Map<int, int>>{};
      for (final row in rawLevels) {
        final slots = row['spellSlots'] as Map<String, dynamic>?;
        if (slots == null) continue;
        final level = int.parse(row['Level'] as String);
        final parsed = <int, int>{
          for (final entry in slots.entries)
            if (entry.value != null)
              int.parse(entry.key): int.parse(entry.value.toString()),
        };
        if (parsed.isNotEmpty) spellSlotsByLevel[level] = parsed;
      }
      final traits = (map['traits'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(k, v.toString()),
      );
      SrdClassFeature toFeature(dynamic f) => SrdClassFeature(
        level: (f as Map<String, dynamic>)['level'] as int,
        name: f['name'] as String,
        desc: f['desc'] as String,
      );
      final features = (map['features'] as List? ?? const [])
          .map(toFeature)
          .toList();
      final subclassMap = map['subclass'] as Map<String, dynamic>?;
      final subclass = subclassMap == null
          ? null
          : SrdSubclass(
              key: subclassMap['key'] as String,
              name: subclassMap['name'] as String,
              features: (subclassMap['features'] as List? ?? const [])
                  .map(toFeature)
                  .toList(),
            );
      final cls = SrdClass(
        key: map['key'] as String,
        name: map['name'] as String,
        traits: traits,
        levels: levels,
        features: features,
        subclass: subclass,
        spellSlotsByLevel: spellSlotsByLevel,
      );
      classesByKey[cls.key] = cls;
    }
  }

  /// Loads a simple key+name list - used for the catalogs where nothing
  /// beyond that is needed for the picker UI (gear, tools, magic items,
  /// languages).
  Future<void> _loadRefList(String asset, List<SrdRefItem> target) async {
    final raw = await rootBundle.loadString(asset);
    final list = jsonDecode(raw) as List;
    target.addAll(
      list.map((item) {
        final map = item as Map<String, dynamic>;
        return SrdRefItem(
          key: map['key'] as String,
          name: map['name'] as String,
        );
      }),
    );
  }

  Future<void> _loadConditions() async {
    final raw = await rootBundle.loadString('assets/srd/conditions.json');
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final name = map['name'] as String;
      if (name == 'Exhaustion') continue;
      conditionDescriptions[name] = map['desc'] as String;
    }
  }

  Future<void> _loadFeats() async {
    final raw = await rootBundle.loadString('assets/srd/feats.json');
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final benefits = (map['benefits'] as List? ?? const [])
          .map(
            (b) => SrdFeatBenefit(
              (b as Map<String, dynamic>)['name'] as String,
              b['desc'] as String,
            ),
          )
          .toList();
      final feat = SrdFeat(
        key: map['key'] as String,
        name: map['name'] as String,
        category: map['category'] as String,
        prerequisite: map['prerequisite'] as String?,
        desc: map['desc'] as String? ?? '',
        benefits: benefits,
      );
      featsByKey[feat.key] = feat;
    }
  }

  Future<void> _loadWeapons() async {
    final raw = await rootBundle.loadString('assets/srd/weapons.json');
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final weapon = SrdWeaponRef(
        key: map['key'] as String,
        name: map['name'] as String,
        category: map['category'] as String,
        damage: map['damage'] as String,
        properties: (map['properties'] as List).cast<String>(),
        mastery: map['mastery'] as String?,
      );
      weaponsByKey[weapon.key] = weapon;
    }
  }

  Future<void> _loadWeaponProperties() async {
    final raw = await rootBundle.loadString(
      'assets/srd/weapon-properties.json',
    );
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final prop = SrdWeaponPropertyRef(
        name: map['name'] as String,
        desc: map['desc'] as String,
        isMastery: map['type'] == 'Mastery',
      );
      weaponPropertiesByName[prop.name] = prop;
    }
  }

  Future<void> _loadArmor() async {
    final raw = await rootBundle.loadString('assets/srd/armor.json');
    final list = jsonDecode(raw) as List;
    for (final item in list) {
      final map = item as Map<String, dynamic>;
      final armorItem = SrdArmorRef(
        key: map['key'] as String,
        name: map['name'] as String,
        category: map['category'] as String,
        armorClass: map['armorClass'] as String,
        strength: map['strength'] as String?,
        stealth: map['stealth'] as bool? ?? false,
      );
      armorByKey[armorItem.key] = armorItem;
    }
  }

  Future<void> _loadSpells() async {
    final raw = await rootBundle.loadString('assets/srd/spells.json');
    final list = jsonDecode(raw) as List;
    spells.addAll(
      list.map(
        (item) => SrdSpellRef(
          key: (item as Map<String, dynamic>)['key'] as String,
          name: item['name'] as String,
          level: item['level'] as int,
          school: item['school'] as String,
          classes: (item['classes'] as List?)?.cast<String>() ?? const [],
          ritual: item['ritual'] as bool? ?? false,
          castingTime: item['castingTime'] as String? ?? '',
          range: item['range'] as String? ?? '',
          components: item['components'] as String? ?? '',
          concentration: item['concentration'] as bool? ?? false,
          duration: item['duration'] as String? ?? '',
          desc: item['desc'] as String? ?? '',
          higherLevel: item['higherLevel'] as String?,
        ),
      ),
    );
  }

  SrdClass? byKey(String key) => classesByKey[key];

  /// Homebrew subclasses, by parent class key - filled in by
  /// homebrew_catalog.dart's registerHomebrewInCatalog.
  final Map<String, List<SrdSubclass>> homebrewSubclasses = {};

  /// Every subclass a class offers: its SRD one, plus any homebrew.
  List<SrdSubclass> subclassesFor(String classKey) => [
    ?classesByKey[classKey]?.subclass,
    ...?homebrewSubclasses[classKey],
  ];

  SrdSubclass? subclassByKey(String classKey, String? subclassKey) =>
      subclassKey == null
      ? null
      : subclassesFor(classKey).where((s) => s.key == subclassKey).firstOrNull;

  Future<void> _loadSheetText() async {
    final raw = await rootBundle.loadString('assets/srd/sheet-text.json');
    final map = jsonDecode(raw) as Map<String, dynamic>;
    for (final entry in map.entries) {
      sheetText[entry.key] = (entry.value as Map<String, dynamic>).map(
        (name, text) => MapEntry(name, text as String),
      );
    }
  }

  /// [spells] indexed by key - derived from the list on demand rather
  /// than kept in sync by hand alongside it, and rebuilt if the list has
  /// changed size since (so a lookup made before init finished can't
  /// leave it permanently empty).
  Map<String, SrdSpellRef> get spellsByKey {
    final cached = _spellsByKey;
    if (cached != null && cached.length == spells.length) return cached;
    return _spellsByKey = {for (final s in spells) s.key: s};
  }

  Map<String, SrdSpellRef>? _spellsByKey;

  /// Kept as a plain SrdRefItem list (same shape as before speciesByKey
  /// existed) so the existing Species picker/tests keep working unchanged
  /// - use speciesByKey directly for the richer traits/tables data.
  List<SrdRefItem> get species => speciesByKey.values
      .map((s) => SrdRefItem(key: s.key, name: s.name))
      .toList();

  List<SrdRefItem> get classOptions => classesByKey.values
      .map((c) => SrdRefItem(key: c.key, name: c.name))
      .toList();
  List<SrdRefItem> get backgroundOptions => backgroundsByKey.values
      .map((b) => SrdRefItem(key: b.key, name: b.name))
      .toList();
  List<SrdRefItem> get featOptions => featsByKey.values
      .map((f) => SrdRefItem(key: f.key, name: f.name))
      .toList();
  List<SrdRefItem> get weaponOptions => weaponsByKey.values
      .map((w) => SrdRefItem(key: w.key, name: w.name))
      .toList();
  List<SrdRefItem> get armorOptions => armorByKey.values
      .map((a) => SrdRefItem(key: a.key, name: a.name))
      .toList();
  List<SrdRefItem> get gear => gearByKey.values
      .map((g) => SrdRefItem(key: g.key, name: g.name))
      .toList();
  List<SrdRefItem> get tools => toolsByKey.values
      .map((t) => SrdRefItem(key: t.key, name: t.name))
      .toList();
  List<SrdRefItem> get magicItems => magicItemsByKey.values
      .map((m) => SrdRefItem(key: m.key, name: m.name))
      .toList();

  /// Condition names, sorted - what the Conditions multi-select shows
  /// (Exhaustion excluded, see conditionDescriptions).
  List<String> get conditionNames =>
      conditionDescriptions.keys.toList()..sort();
}

final srdCatalog = SrdCatalog();
