/// The character schema. A trimmed-down port of the Quasar app's
/// models/character.ts - only the fields Jarson's sheet actually uses so
/// far. Extend this as more of the real app gets ported, rather than
/// modeling fields nothing reads yet.
library;

class AbilityScores {
  const AbilityScores({
    required this.str,
    required this.dex,
    required this.con,
    required this.intel,
    required this.wis,
    required this.cha,
  });

  final int str;
  final int dex;
  final int con;
  final int intel;
  final int wis;
  final int cha;

  int of(String key) => switch (key) {
    'str' => str,
    'dex' => dex,
    'con' => con,
    'int' => intel,
    'wis' => wis,
    'cha' => cha,
    _ => throw ArgumentError('Unknown ability key: $key'),
  };

  /// A copy with [deltas] applied (ability key -> amount), each clamped to
  /// 20 - the max any Ability Score Improvement can push a score to.
  AbilityScores increase(Map<String, int> deltas) {
    int next(String key, int current) =>
        (current + (deltas[key] ?? 0)).clamp(1, 20);
    return AbilityScores(
      str: next('str', str),
      dex: next('dex', dex),
      con: next('con', con),
      intel: next('int', intel),
      wis: next('wis', wis),
      cha: next('cha', cha),
    );
  }

  Map<String, dynamic> toJson() => {
    'str': str,
    'dex': dex,
    'con': con,
    'int': intel,
    'wis': wis,
    'cha': cha,
  };

  factory AbilityScores.fromJson(Map<String, dynamic> j) => AbilityScores(
    str: j['str'] as int,
    dex: j['dex'] as int,
    con: j['con'] as int,
    intel: j['int'] as int,
    wis: j['wis'] as int,
    cha: j['cha'] as int,
  );
}

class SkillEntry {
  SkillEntry({
    required this.name,
    required this.ability,
    required this.proficient,
    this.expertise = false,
  });
  final String name;
  final String ability; // "str" | "dex" | "con" | "int" | "wis" | "cha"
  bool proficient;
  bool expertise;

  Map<String, dynamic> toJson() => {
    'name': name,
    'ability': ability,
    'proficient': proficient,
    'expertise': expertise,
  };

  factory SkillEntry.fromJson(Map<String, dynamic> j) => SkillEntry(
    name: j['name'] as String,
    ability: j['ability'] as String,
    proficient: j['proficient'] as bool,
    expertise: j['expertise'] as bool? ?? false,
  );
}

/// A limited-use resource (Action Surge, Second Wind, Indomitable, ...).
/// `used`/`max` mirror the real app's ResourceUse. `shortRestRecovery`
/// mirrors it too: a Long Rest always fully restores every resource (true
/// for every 2024 class checked in the web app), so only Short Rest needs
/// a per-resource recovery rule - "full" (fully restores), "partial"
/// (regain exactly 1 use), or "none" (unaffected).
class Resource {
  Resource({
    required this.key,
    required this.name,
    required this.max,
    required this.used,
    required this.hint,
    this.shortRestRecovery = 'none',
  });
  final String key;
  final String name;
  int max;
  int used;
  final String hint;
  final String shortRestRecovery;

  Map<String, dynamic> toJson() => {
    'key': key,
    'name': name,
    'max': max,
    'used': used,
    'hint': hint,
    'shortRestRecovery': shortRestRecovery,
  };

  factory Resource.fromJson(Map<String, dynamic> j) => Resource(
    key: j['key'] as String,
    name: j['name'] as String,
    max: j['max'] as int,
    used: j['used'] as int,
    hint: j['hint'] as String,
    shortRestRecovery: j['shortRestRecovery'] as String? ?? 'none',
  );
}

/// A carried weapon. Properties/mastery are freeform strings rather than a
/// catalog lookup - the real app resolves these against bundled SRD data;
/// this port hardcodes them per-weapon until that catalog is ported too.
class Weapon {
  Weapon({
    required this.name,
    required this.damageDice,
    required this.damageType,
    required this.properties,
    this.mastery,
    this.masteryDesc,
    required this.proficient,
    this.magicBonus = 0,
    this.finesse = false,
    this.specialFeatures = const [],
    this.hitStreak = 0,
  });

  final String name;
  String damageDice; // e.g. "2d6"
  String damageType;
  final List<String> properties; // e.g. ["Heavy", "Two-Handed"]
  final String? mastery;
  final String? masteryDesc;
  bool proficient;
  int magicBonus;
  bool finesse;
  List<String> specialFeatures;

  /// A generic counter for a special feature that scales with consecutive
  /// hits on the same target (e.g. "Mounting Fury") - bump it after a hit,
  /// reset it on a miss or when switching targets. Only meaningful once
  /// specialFeatures is non-empty.
  int hitStreak;

  bool get isHeavy => properties.contains('Heavy');

  Map<String, dynamic> toJson() => {
    'name': name,
    'damageDice': damageDice,
    'damageType': damageType,
    'properties': properties,
    'mastery': mastery,
    'masteryDesc': masteryDesc,
    'proficient': proficient,
    'magicBonus': magicBonus,
    'finesse': finesse,
    'specialFeatures': specialFeatures,
    'hitStreak': hitStreak,
  };

  factory Weapon.fromJson(Map<String, dynamic> j) => Weapon(
    name: j['name'] as String,
    damageDice: j['damageDice'] as String,
    damageType: j['damageType'] as String,
    properties: (j['properties'] as List).cast<String>(),
    mastery: j['mastery'] as String?,
    masteryDesc: j['masteryDesc'] as String?,
    proficient: j['proficient'] as bool,
    magicBonus: j['magicBonus'] as int? ?? 0,
    finesse: j['finesse'] as bool? ?? false,
    specialFeatures:
        (j['specialFeatures'] as List?)?.cast<String>() ?? const [],
    hitStreak: j['hitStreak'] as int? ?? 0,
  );
}

/// One (character level -> damage dice count) breakpoint for an innate
/// attack that scales with level, e.g. Breath Weapon's 1d10 at level 1,
/// 2d10 at 5, 3d10 at 11, 4d10 at 17. The live count at a given level is
/// the highest breakpoint at or below it - see domain/rules.dart's
/// innateAttackInfo.
class LevelDiceBreakpoint {
  const LevelDiceBreakpoint({required this.level, required this.diceCount});
  final int level;
  final int diceCount;

  Map<String, dynamic> toJson() => {'level': level, 'diceCount': diceCount};

  factory LevelDiceBreakpoint.fromJson(Map<String, dynamic> j) =>
      LevelDiceBreakpoint(
        level: j['level'] as int,
        diceCount: j['diceCount'] as int,
      );

  @override
  bool operator ==(Object other) =>
      other is LevelDiceBreakpoint &&
      other.level == level &&
      other.diceCount == diceCount;

  @override
  int get hashCode => Object.hash(level, diceCount);
}

/// An innate attack that isn't a carried weapon - just Breath Weapon so
/// far, but no longer modeled as one-off hardcoded logic (see
/// rules.innateAttackInfo). Kept separate from Weapon since it has a save
/// DC instead of an attack roll, and is tied to a Resource rather than
/// being always-available.
class InnateAttack {
  InnateAttack({
    required this.name,
    this.levelDice = const [],
    this.dieType = 'd6',
    required this.damageType,
    required this.saveAbility,
    this.saveDcFormula = '',
    required this.desc,
    required this.resourceKey,
  });
  final String name;

  /// Damage dice count by level - see [LevelDiceBreakpoint].
  final List<LevelDiceBreakpoint> levelDice;

  /// The die type rolled that many of, e.g. "d10" - kept apart from the
  /// count since the count is what scales with level, not the die itself.
  final String dieType;
  final String damageType;

  /// The ability the TARGET rolls to resist this attack (e.g. "dex" for
  /// Breath Weapon) - unrelated to [saveDcFormula], which is the ability
  /// that sets the DC (e.g. Constitution for Breath Weapon). Don't
  /// conflate the two.
  final String saveAbility;

  /// Formula (see rules.evaluateFormula) for this attack's save DC, e.g.
  /// "8 + Proficiency Bonus + Constitution modifier" - empty if this
  /// attack doesn't impose a save (DC shows as 0/omitted).
  final String saveDcFormula;
  final String desc;
  final String resourceKey;

  Map<String, dynamic> toJson() => {
    'name': name,
    'levelDice': levelDice.map((d) => d.toJson()).toList(),
    'dieType': dieType,
    'damageType': damageType,
    'saveAbility': saveAbility,
    'saveDcFormula': saveDcFormula,
    'desc': desc,
    'resourceKey': resourceKey,
  };

  factory InnateAttack.fromJson(Map<String, dynamic> j) {
    final name = j['name'] as String;
    final rawLevelDice = j['levelDice'] as List?;
    List<LevelDiceBreakpoint> levelDice;
    String dieType;
    if (rawLevelDice != null) {
      levelDice = rawLevelDice
          .map((e) => LevelDiceBreakpoint.fromJson(e as Map<String, dynamic>))
          .toList();
      dieType = j['dieType'] as String? ?? 'd6';
    } else {
      // Migration: legacy data (pre-generalization) has only a flat
      // "damageDice" string like "2d10" and no levelDice/saveDcFormula at
      // all - treat it as a single level-1 breakpoint.
      final legacy = j['damageDice'] as String?;
      final match = legacy != null
          ? RegExp(r'^(\d+)d(\d+)$').firstMatch(legacy)
          : null;
      levelDice = [
        LevelDiceBreakpoint(
          level: 1,
          diceCount: match != null ? int.parse(match.group(1)!) : 1,
        ),
      ];
      dieType = match != null ? 'd${match.group(2)}' : 'd6';
    }
    return InnateAttack(
      name: name,
      levelDice: levelDice,
      dieType: dieType,
      damageType: j['damageType'] as String,
      saveAbility: j['saveAbility'] as String,
      // Only the one real legacy shape this repo actually has saved data
      // for (Breath Weapon) gets a safe default - any other/unknown
      // legacy name gets '' (DC 0, visibly wrong), not a guessed value.
      saveDcFormula:
          j['saveDcFormula'] as String? ??
          (name == 'Breath Weapon'
              ? '8 + Proficiency Bonus + Constitution modifier'
              : ''),
      desc: j['desc'] as String,
      resourceKey: j['resourceKey'] as String,
    );
  }
}

class GrantedFeature {
  GrantedFeature({required this.name, required this.source, this.desc});
  final String name;
  final String source;
  final String? desc;

  Map<String, dynamic> toJson() => {
    'name': name,
    'source': source,
    'desc': desc,
  };

  factory GrantedFeature.fromJson(Map<String, dynamic> j) => GrantedFeature(
    name: j['name'] as String,
    source: j['source'] as String,
    desc: j['desc'] as String?,
  );
}

/// A feature/level-up grants a choice rather than a fixed benefit (a
/// Fighter's Ability Score Improvement slot, which is actually a feat
/// pick that can itself resolve to an ASI) - this sits on the sheet
/// until the player resolves it via the feat-choice dialog, which adds
/// the result to `feats` (and, for an ASI, adjusts `abilityScores`) and
/// removes this entry.
class PendingChoice {
  PendingChoice({
    required this.id,
    required this.label,
    this.featCategory,
    this.kind,
  });
  final String id;
  final String label; // e.g. "Level 4: Ability Score Improvement"
  final String?
  featCategory; // restrict the feat picker to this SRD category, or null = any
  /// Null (the default) means "resolve through the feat picker" - the
  /// normal case (Fighting Style, Epic Boon, ...). 'subclass' resolves
  /// through a subclass picker instead - see rules.dart's
  /// subclassPendingChoices/resolveSubclassChoice. 'asi' resolves through
  /// its own dedicated "Ability Score Improvement or a General Feat?"
  /// choice first - see character_sheet_screen.dart's
  /// _resolveAsiOrFeatChoice - rather than sending the player straight
  /// into the full feat picker, where Ability Score Improvement is a real
  /// General Feat catalog entry but just one option among many to find.
  final String? kind;

  Map<String, dynamic> toJson() => {
    'id': id,
    'label': label,
    'featCategory': featCategory,
    'kind': kind,
  };

  factory PendingChoice.fromJson(Map<String, dynamic> j) => PendingChoice(
    id: j['id'] as String,
    label: j['label'] as String,
    featCategory: j['featCategory'] as String?,
    kind: j['kind'] as String?,
  );
}

/// One entry in a character's append-only change log - what changed
/// (label) and, when there's more to say than the label alone, what
/// specifically (detail, e.g. "STR 17 → 19"). Written by domain/rules.dart
/// whenever something records itself here (ability score edits, Ability
/// Score Improvements, level changes, ...) rather than being editable
/// directly - it's a record of what happened, not another piece of sheet
/// state to hand-edit.
class HistoryEntry {
  HistoryEntry({
    required this.id,
    required this.timestamp,
    required this.label,
    this.detail,
  });
  final String id;
  final DateTime timestamp;
  final String label;
  final String? detail;

  Map<String, dynamic> toJson() => {
    'id': id,
    'timestamp': timestamp.toIso8601String(),
    'label': label,
    'detail': detail,
  };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
    id: j['id'] as String,
    timestamp: DateTime.parse(j['timestamp'] as String),
    label: j['label'] as String,
    detail: j['detail'] as String?,
  );
}

class InventoryEntry {
  InventoryEntry({
    required this.name,
    required this.quantity,
    this.equipped = false,
    this.attuned = false,
    this.caption,
  });
  String name;
  int quantity;
  bool equipped;
  bool attuned; // magic item attunement - meaningless for a mundane item
  String? caption;

  Map<String, dynamic> toJson() => {
    'name': name,
    'quantity': quantity,
    'equipped': equipped,
    'attuned': attuned,
    'caption': caption,
  };

  factory InventoryEntry.fromJson(Map<String, dynamic> j) => InventoryEntry(
    name: j['name'] as String,
    quantity: j['quantity'] as int,
    equipped: j['equipped'] as bool? ?? false,
    attuned: j['attuned'] as bool? ?? false,
    caption: j['caption'] as String?,
  );
}

/// Body armor the character is wearing - drives computed AC (see
/// domain/rules.dart's armorClassFor). Deliberately separate from
/// InventoryItem: this is a structural "what's in the AC slot" fact, not
/// a line in a carried-goods list, so it can't silently duplicate or
/// drift from what actually affects AC.
class EquippedArmor {
  EquippedArmor({
    required this.name,
    required this.armorClassFormula,
    this.strengthRequirement,
    this.stealth = false,
    this.category,
  });
  final String name;
  final String
  armorClassFormula; // e.g. "15 + Dex modifier (max 2)", or flat "18"
  final String? strengthRequirement;
  final bool stealth; // true = Disadvantage on Stealth checks

  /// 'Light' | 'Medium' | 'Heavy', or null if never set (e.g. armor
  /// equipped before this field existed). Not derivable from
  /// [strengthRequirement] - Medium armor can carry one too - so it's its
  /// own explicit field. Drives conditions like Heavy Armor Master's
  /// damage reduction - see rules.dart's _effectConditionMet.
  final String? category;

  Map<String, dynamic> toJson() => {
    'name': name,
    'armorClassFormula': armorClassFormula,
    'strengthRequirement': strengthRequirement,
    'stealth': stealth,
    'category': category,
  };

  factory EquippedArmor.fromJson(Map<String, dynamic> j) => EquippedArmor(
    name: j['name'] as String,
    armorClassFormula: j['armorClassFormula'] as String,
    strengthRequirement: j['strengthRequirement'] as String?,
    stealth: j['stealth'] as bool? ?? false,
    category: j['category'] as String?,
  );
}

/// A mount (a riding horse, a warhorse, a griffon, ...) with its own AC/
/// HP/Speed to track during mounted combat. Freeform rather than
/// catalog-backed: neither this app's nor the source SRD's bundled data
/// has real creature stat blocks (mounts.json is just a carrying-capacity/
/// cost reference table, not AC/HP/Speed) - the player enters their
/// mount's actual stats by hand, the same as a homebrew weapon's mechanics.
class Mount {
  Mount({
    required this.name,
    this.armorClass = 10,
    required this.maxHp,
    int? currentHp,
    this.speed = 30,
    this.notes = '',
    this.active = false,
  }) : currentHp = currentHp ?? maxHp;
  String name;
  int armorClass;
  int maxHp;
  int currentHp;
  int speed;

  /// Freeform - attacks, traits, tack equipped, anything worth a
  /// reminder mid-session.
  String notes;

  /// True if this is the mount currently being ridden. Not enforced as
  /// exclusive across the list - a two-seat mount, or just an oversight,
  /// isn't worth blocking on.
  bool active;

  Map<String, dynamic> toJson() => {
    'name': name,
    'armorClass': armorClass,
    'maxHp': maxHp,
    'currentHp': currentHp,
    'speed': speed,
    'notes': notes,
    'active': active,
  };

  factory Mount.fromJson(Map<String, dynamic> j) => Mount(
    name: j['name'] as String,
    armorClass: j['armorClass'] as int? ?? 10,
    maxHp: j['maxHp'] as int,
    currentHp: j['currentHp'] as int?,
    speed: j['speed'] as int? ?? 30,
    notes: j['notes'] as String? ?? '',
    active: j['active'] as bool? ?? false,
  );
}

class Currency {
  const Currency({
    this.cp = 0,
    this.sp = 0,
    this.ep = 0,
    this.gp = 0,
    this.pp = 0,
  });
  final int cp, sp, ep, gp, pp;

  Map<String, dynamic> toJson() => {
    'cp': cp,
    'sp': sp,
    'ep': ep,
    'gp': gp,
    'pp': pp,
  };

  factory Currency.fromJson(Map<String, dynamic> j) => Currency(
    cp: j['cp'] as int? ?? 0,
    sp: j['sp'] as int? ?? 0,
    ep: j['ep'] as int? ?? 0,
    gp: j['gp'] as int? ?? 0,
    pp: j['pp'] as int? ?? 0,
  );
}

/// One spell slot level's use tracking - e.g. level 3 slots: 2 max, 1 used.
class SpellSlot {
  SpellSlot({required this.max, this.used = 0});
  int max;
  int used;

  Map<String, dynamic> toJson() => {'max': max, 'used': used};

  factory SpellSlot.fromJson(Map<String, dynamic> j) =>
      SpellSlot(max: j['max'] as int, used: j['used'] as int? ?? 0);
}

/// A spell the character knows or has prepared.
class KnownSpell {
  KnownSpell({
    required this.spellKey,
    this.prepared = true,
    this.alwaysPrepared = false,
    this.level,
  });
  final String spellKey;

  /// Only set for a homebrew spell, which has no SRD record to read a
  /// level from - asked for when it's added (see the Spells tab's
  /// _addSpell). An SRD spell's level always comes live from the catalog
  /// instead (see rules.spellRefFor), so this stays null for one.
  int? level;

  /// Meaningless for a "known" caster (Bard/Sorcerer/Warlock) - always
  /// true there. Matters for a "prepared" caster (Cleric/Druid/Paladin/
  /// Wizard), who knows more spells than they can ready at once.
  bool prepared;

  /// Granted by a feature/feat and doesn't count against the prepared
  /// limit.
  bool alwaysPrepared;

  Map<String, dynamic> toJson() => {
    'spellKey': spellKey,
    'prepared': prepared,
    'alwaysPrepared': alwaysPrepared,
    'level': level,
  };

  factory KnownSpell.fromJson(Map<String, dynamic> j) => KnownSpell(
    spellKey: j['spellKey'] as String,
    prepared: j['prepared'] as bool? ?? true,
    alwaysPrepared: j['alwaysPrepared'] as bool? ?? false,
    level: j['level'] as int?,
  );
}

/// A character's spellcasting, if any - null for a non-caster. Present
/// once the player turns it on (automatically for a spellcasting class at
/// creation, or by hand via the Spells tab's "Enable Spellcasting").
class Spellcasting {
  Spellcasting({
    required this.ability,
    this.cantripsKnown = const [],
    this.spells = const [],
    this.slots = const {},
    this.concentratingOn,
  });
  String ability; // ability key: "str" | "dex" | ... | "cha"
  List<String> cantripsKnown; // spell keys, level-0 only
  List<KnownSpell> spells;
  Map<int, SpellSlot> slots; // spell level (1-9) -> that level's slots

  /// The spell key currently being concentrated on, or null - set by
  /// casting a Concentration spell (rules.castSpell), cleared by ending it
  /// by hand, by casting another Concentration spell (you can only hold
  /// one), by dropping to 0 HP, or by a Long Rest. Only one at a time, per
  /// the rules.
  String? concentratingOn;

  Map<String, dynamic> toJson() => {
    'ability': ability,
    'cantripsKnown': cantripsKnown,
    'spells': spells.map((s) => s.toJson()).toList(),
    'slots': slots.map((level, slot) => MapEntry('$level', slot.toJson())),
    'concentratingOn': concentratingOn,
  };

  factory Spellcasting.fromJson(Map<String, dynamic> j) => Spellcasting(
    ability: j['ability'] as String,
    cantripsKnown: (j['cantripsKnown'] as List?)?.cast<String>() ?? const [],
    spells: (j['spells'] as List? ?? const [])
        .map((e) => KnownSpell.fromJson(e as Map<String, dynamic>))
        .toList(),
    slots: (j['slots'] as Map<String, dynamic>? ?? const {}).map(
      (level, slot) => MapEntry(
        int.parse(level),
        SpellSlot.fromJson(slot as Map<String, dynamic>),
      ),
    ),
    concentratingOn: j['concentratingOn'] as String?,
  );
}

class Character {
  Character({
    required this.id,
    String? familyId,
    this.isCurrent = true,
    required this.name,
    this.playerName = '',
    this.alignment,
    required this.speciesLabel,
    this.speciesKey,
    this.speciesChoice,
    this.languages = const [],
    this.backgroundLabel,
    this.backgroundKey,
    this.toolProficiencyChoices = const [],
    required this.classLabel,
    this.classKey,
    this.subclassKey,
    required this.level,
    required this.abilityScores,
    required this.maxHp,
    required this.currentHp,
    this.tempHp = 0,
    this.equippedArmor,
    this.shieldEquipped = false,
    this.armorClassOverride,
    this.initiativeBonus = 0,
    this.speed = 30,
    required this.hitDiceDie,
    required this.hitDiceTotal,
    this.hitDiceSpent = 0,
    this.deathSaveSuccesses = 0,
    this.deathSaveFailures = 0,
    this.exhaustionLevel = 0,
    this.activeConditions = const [],
    required this.savingThrowProficiencies,
    required this.skills,
    required this.resources,
    required this.weapons,
    this.innateAttacks = const [],
    required this.features,
    required this.feats,
    this.pendingChoices = const [],
    required this.inventory,
    required this.currency,
    this.heroicInspiration = 0,
    this.notes = '',
    this.appearance = '',
    this.spellcasting,
    this.mounts = const [],
    this.history = const [],
  }) : familyId = familyId ?? id;

  final String id;

  /// Shared across every snapshot of "the same" character - equals [id]
  /// for a character with no alternate snapshots. A family accumulates one
  /// extra (non-current) snapshot automatically every time
  /// rules.levelUpOneLevel runs (see character_repository.dart's
  /// levelUpCharacter) - a backup of the character exactly as they were
  /// the moment before that level's HP/resources/features changed, so a
  /// level-up is never a one-way, unreviewable mutation. Promote one back
  /// to undo a level; Delete removes it for good. Also what
  /// duplicateAsNewCharacter starts a fresh, unrelated family from.
  String familyId;

  /// What to show wherever this character is listed as a non-current
  /// snapshot - its own real [level], never a free-typed label (there's
  /// nothing to type: a snapshot is always a past current, automatically
  /// kept as history by a level-up).
  String get snapshotStatusLabel => 'Level $level (previous)';

  /// Exactly one snapshot per familyId should have this true at a time -
  /// promoteToCurrent enforces that, not this field itself.
  bool isCurrent;
  String name;
  String playerName;
  String? alignment;
  String speciesLabel; // e.g. "Draconic Ancestry · Red"
  /// SRD key into srdCatalog.speciesByKey (e.g. "srd-2024_dragonborn-species"),
  /// or null for a homebrew/uncataloged species. Drives the species-choice
  /// picker on the Overview tab - see srd_catalog.dart's SrdSpeciesInfo.
  String? speciesKey;

  /// The option picked from the species' own embedded choice table, by its
  /// name (e.g. "Red" for Dragonborn's Draconic Ancestry) - null if the
  /// species has no such table or nothing's picked yet. What that choice
  /// actually grants (e.g. Red -> Fire damage) is a display-time lookup
  /// against the species catalog, not duplicated here - see
  /// srd_catalog.dart's SrdSpeciesInfo.choiceTable / flattenSpeciesTableOptions.
  String? speciesChoice;
  List<String> languages;

  /// Denormalized display name (e.g. "Soldier") - shown even if
  /// [backgroundKey] is homebrew/unresolved or null (a character built
  /// before this field existed).
  String? backgroundLabel;

  /// SRD key into srdCatalog.backgroundsByKey, or null for a homebrew/
  /// uncataloged background. Drives the Background info section on the
  /// Overview tab (equipment, tool proficiency, ability score options).
  String? backgroundKey;

  /// What the player actually picked for a "Choose N ..." tool
  /// proficiency (the background's own, and/or the class's, e.g. Bard's
  /// "Choose 3 Musical Instruments") - e.g. ["Dice", "Lute", "Lyre"].
  /// Empty until resolved; the raw "Choose..." prompt text is shown
  /// instead until then - see rules.dart's parseToolChoice/
  /// toolChoiceRequirementsFor. A background/class with a fixed tool (no
  /// choice, e.g. "Thieves' Tools") never needs an entry here at all.
  List<String> toolProficiencyChoices;

  String classLabel; // e.g. "Lv.9 Dragonborn Fighter · Champion"
  /// SRD key into srdCatalog.classesByKey (e.g. "srd-2024_fighter-class"),
  /// or null for a homebrew/uncataloged class. Drives level-based resource
  /// recalculation - see rules.dart's recalculateClassResources.
  String? classKey;

  /// SRD key of the assigned subclass (e.g. "srd-2024_champion-subclass"),
  /// or null if not yet reached/assigned. The free SRD has exactly one
  /// subclass per class, so this is auto-assigned rather than chosen -
  /// see rules.dart's fighterSubclassForLevelUp.
  String? subclassKey;
  int level;
  AbilityScores abilityScores;
  int maxHp;
  int currentHp;
  int tempHp;

  /// The character's worn body armor, or null if unarmored. Together with
  /// [shieldEquipped], this is what domain/rules.dart's armorClassFor
  /// computes AC from - see [armorClassOverride] for bypassing that.
  EquippedArmor? equippedArmor;
  bool shieldEquipped;

  /// Non-null wins over the computed AC entirely (a magic item, a DM
  /// ruling, or just not trusting the computed value yet). Null (the
  /// normal case) means "compute AC from equipped armor + Dex."
  int? armorClassOverride;
  int initiativeBonus;
  int speed;
  String hitDiceDie; // e.g. "d10"
  int hitDiceTotal;
  int hitDiceSpent;
  int deathSaveSuccesses; // 0-3
  int deathSaveFailures; // 0-3
  int exhaustionLevel; // 0-6
  List<String>
  activeConditions; // condition names currently affecting the character
  List<String> savingThrowProficiencies; // ability keys
  List<SkillEntry> skills;
  List<Resource> resources;
  List<Weapon> weapons;
  List<InnateAttack> innateAttacks;
  List<GrantedFeature> features;
  List<GrantedFeature> feats;
  List<PendingChoice> pendingChoices;
  List<InventoryEntry> inventory;
  Currency currency;
  int heroicInspiration; // 2024: bankable, not just a yes/no flag
  String notes; // shown on the exported sheet as Backstory & Personality
  String appearance;
  Spellcasting? spellcasting; // null for a non-caster
  List<Mount> mounts;

  /// Append-only log of what changed and why - oldest first (screens
  /// reverse it for newest-first display). See domain/rules.dart's
  /// logHistory/setAbilityScores/grantFeat for what writes to it.
  List<HistoryEntry> history;

  bool hasFeat(String name) => feats.any((f) => f.name == name);

  Map<String, dynamic> toJson() => {
    'id': id,
    'familyId': familyId,
    'isCurrent': isCurrent,
    'name': name,
    'playerName': playerName,
    'alignment': alignment,
    'speciesLabel': speciesLabel,
    'speciesKey': speciesKey,
    'speciesChoice': speciesChoice,
    'languages': languages,
    'backgroundLabel': backgroundLabel,
    'backgroundKey': backgroundKey,
    'toolProficiencyChoices': toolProficiencyChoices,
    'classLabel': classLabel,
    'classKey': classKey,
    'subclassKey': subclassKey,
    'level': level,
    'abilityScores': abilityScores.toJson(),
    'maxHp': maxHp,
    'currentHp': currentHp,
    'tempHp': tempHp,
    'equippedArmor': equippedArmor?.toJson(),
    'shieldEquipped': shieldEquipped,
    'armorClassOverride': armorClassOverride,
    'initiativeBonus': initiativeBonus,
    'speed': speed,
    'hitDiceDie': hitDiceDie,
    'hitDiceTotal': hitDiceTotal,
    'hitDiceSpent': hitDiceSpent,
    'deathSaveSuccesses': deathSaveSuccesses,
    'deathSaveFailures': deathSaveFailures,
    'exhaustionLevel': exhaustionLevel,
    'activeConditions': activeConditions,
    'savingThrowProficiencies': savingThrowProficiencies,
    'skills': skills.map((s) => s.toJson()).toList(),
    'resources': resources.map((r) => r.toJson()).toList(),
    'weapons': weapons.map((w) => w.toJson()).toList(),
    'innateAttacks': innateAttacks.map((a) => a.toJson()).toList(),
    'features': features.map((f) => f.toJson()).toList(),
    'feats': feats.map((f) => f.toJson()).toList(),
    'pendingChoices': pendingChoices.map((p) => p.toJson()).toList(),
    'inventory': inventory.map((i) => i.toJson()).toList(),
    'currency': currency.toJson(),
    'heroicInspiration': heroicInspiration,
    'notes': notes,
    'appearance': appearance,
    'spellcasting': spellcasting?.toJson(),
    'mounts': mounts.map((m) => m.toJson()).toList(),
    'history': history.map((h) => h.toJson()).toList(),
  };

  factory Character.fromJson(Map<String, dynamic> j) => Character(
    id: j['id'] as String,
    familyId: j['familyId'] as String?,
    isCurrent: j['isCurrent'] as bool? ?? true,
    name: j['name'] as String,
    playerName: j['playerName'] as String? ?? '',
    alignment: j['alignment'] as String?,
    speciesLabel: j['speciesLabel'] as String,
    speciesKey: j['speciesKey'] as String?,
    speciesChoice: j['speciesChoice'] as String?,
    languages: (j['languages'] as List?)?.cast<String>() ?? const [],
    backgroundLabel: j['backgroundLabel'] as String?,
    backgroundKey: j['backgroundKey'] as String?,
    toolProficiencyChoices:
        (j['toolProficiencyChoices'] as List?)?.cast<String>() ?? const [],
    classLabel: j['classLabel'] as String,
    classKey: j['classKey'] as String?,
    subclassKey: j['subclassKey'] as String?,
    level: j['level'] as int,
    abilityScores: AbilityScores.fromJson(
      j['abilityScores'] as Map<String, dynamic>,
    ),
    maxHp: j['maxHp'] as int,
    currentHp: j['currentHp'] as int,
    tempHp: j['tempHp'] as int? ?? 0,
    equippedArmor: j['equippedArmor'] != null
        ? EquippedArmor.fromJson(j['equippedArmor'] as Map<String, dynamic>)
        : null,
    shieldEquipped: j['shieldEquipped'] as bool? ?? false,
    armorClassOverride: j['armorClassOverride'] as int?,
    initiativeBonus: j['initiativeBonus'] as int? ?? 0,
    speed: j['speed'] as int? ?? 30,
    hitDiceDie: j['hitDiceDie'] as String? ?? 'd10',
    hitDiceTotal: j['hitDiceTotal'] as int? ?? (j['level'] as int),
    hitDiceSpent: j['hitDiceSpent'] as int? ?? 0,
    deathSaveSuccesses: j['deathSaveSuccesses'] as int? ?? 0,
    deathSaveFailures: j['deathSaveFailures'] as int? ?? 0,
    exhaustionLevel: j['exhaustionLevel'] as int? ?? 0,
    activeConditions:
        (j['activeConditions'] as List?)?.cast<String>() ?? const [],
    savingThrowProficiencies: (j['savingThrowProficiencies'] as List)
        .cast<String>(),
    skills: (j['skills'] as List)
        .map((e) => SkillEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    resources: (j['resources'] as List)
        .map((e) => Resource.fromJson(e as Map<String, dynamic>))
        .toList(),
    weapons: (j['weapons'] as List)
        .map((e) => Weapon.fromJson(e as Map<String, dynamic>))
        .toList(),
    innateAttacks: (j['innateAttacks'] as List? ?? const [])
        .map((e) => InnateAttack.fromJson(e as Map<String, dynamic>))
        .toList(),
    features: (j['features'] as List)
        .map((e) => GrantedFeature.fromJson(e as Map<String, dynamic>))
        .toList(),
    feats: (j['feats'] as List)
        .map((e) => GrantedFeature.fromJson(e as Map<String, dynamic>))
        .toList(),
    pendingChoices: (j['pendingChoices'] as List? ?? const [])
        .map((e) => PendingChoice.fromJson(e as Map<String, dynamic>))
        .toList(),
    inventory: (j['inventory'] as List)
        .map((e) => InventoryEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
    currency: Currency.fromJson(j['currency'] as Map<String, dynamic>),
    heroicInspiration: j['heroicInspiration'] as int? ?? 0,
    notes: j['notes'] as String? ?? '',
    appearance: j['appearance'] as String? ?? '',
    spellcasting: j['spellcasting'] != null
        ? Spellcasting.fromJson(j['spellcasting'] as Map<String, dynamic>)
        : null,
    mounts: (j['mounts'] as List? ?? const [])
        .map((e) => Mount.fromJson(e as Map<String, dynamic>))
        .toList(),
    history: (j['history'] as List? ?? const [])
        .map((e) => HistoryEntry.fromJson(e as Map<String, dynamic>))
        .toList(),
  );
}
