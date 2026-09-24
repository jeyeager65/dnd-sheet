import 'dart:convert';

import 'package:uuid/uuid.dart';

import '../data/homebrew_catalog.dart';
import '../data/homebrew_repository.dart';
import '../data/sheet_text_repository.dart';
import '../data/srd_catalog.dart';
import '../models/character.dart';
import '../models/effect.dart';
import '../models/homebrew.dart';

part 'rules_character.dart';
part 'rules_granted_spells.dart';
part 'rules_options.dart';

/// Pure rules functions, ported from the Quasar app's domain/rules.ts.
/// Kept as plain top-level functions rather than methods on Character, so
/// they stay trivially testable and the model stays a plain data holder.

const _historyUuid = Uuid();

/// Appends a new entry to [c.history] - the one place anything writes to
/// the log, so every writer (ability score edits, feat grants, level
/// changes, ...) produces entries in the same shape.
void logHistory(Character c, String label, {String? detail}) {
  c.history = [
    ...c.history,
    HistoryEntry(
      id: _historyUuid.v4(),
      timestamp: DateTime.now(),
      label: label,
      detail: detail,
    ),
  ];
}

/// "STR 17 → 19" style diff lines for whichever abilities actually
/// changed between [before] and [after] - shared by the manual ability
/// score edit and the Ability Score Improvement paths so both log history
/// the same way.
List<String> _abilityScoreDiff(AbilityScores before, AbilityScores after) {
  const keys = ['str', 'dex', 'con', 'int', 'wis', 'cha'];
  return [
    for (final key in keys)
      if (before.of(key) != after.of(key))
        '${key.toUpperCase()} ${before.of(key)} → ${after.of(key)}',
  ];
}

/// Directly sets a character's ability scores - a manual correction on the
/// sheet (magic item, DM ruling, fixed a typo), not a derived in-play
/// effect - and logs exactly which scores changed and to what.
void setAbilityScores(
  Character c,
  AbilityScores next, {
  String label = 'Ability scores edited',
}) {
  final diff = _abilityScoreDiff(c.abilityScores, next);
  c.abilityScores = next;
  refreshMaxHp(c); // a Constitution change moves Max HP
  if (diff.isNotEmpty) {
    logHistory(c, label, detail: diff.join(', '));
  }
}

/// Grants [feat] to [c], applies [abilityScoreDeltas] if given (an Ability
/// Score Improvement's chosen +2/+1+1 split), and logs the whole grant as
/// one history entry - the single path every feat grant goes through,
/// whether resolving a Pending Choice or the sheet's plain "+ Add Feat"
/// button, so history stays complete regardless of which UI path granted
/// it. The detail always includes the resulting weapon attack/damage
/// snapshot when it actually changed (an ability score bump moves every
/// weapon's numbers; a feat like Great Weapon Master moves them without
/// touching ability scores at all), not just an ASI's raw score diff.
void grantFeat(
  Character c,
  GrantedFeature feat, {
  Map<String, int>? abilityScoreDeltas,
}) {
  final beforeWeapons = weaponsSnapshot(c);
  c.feats = [...c.feats, feat];
  final details = <String>[];
  if (abilityScoreDeltas != null && abilityScoreDeltas.isNotEmpty) {
    final before = c.abilityScores;
    c.abilityScores = before.increase(
      abilityScoreDeltas,
      max: featAbilityIncrease(feat.name)?.max ?? 20,
    );
    final diff = _abilityScoreDiff(before, c.abilityScores);
    if (diff.isNotEmpty) details.add(diff.join(', '));
  }
  final afterWeapons = weaponsSnapshot(c);
  if (afterWeapons.isNotEmpty && afterWeapons != beforeWeapons) {
    details.add('Weapons: $afterWeapons');
  }
  final hpGain = refreshMaxHp(c);
  if (hpGain != 0) details.add('Max HP ${formatModifier(hpGain)}');
  c.pendingChoices = [...c.pendingChoices, ...featPendingChoices(c, feat)];
  syncGrantedSpells(c);
  logHistory(
    c,
    'Feat: ${feat.name} (Level ${c.level})',
    detail: details.isEmpty ? null : details.join('. '),
  );
}

/// A feat's own ability score increase - "Increase your Strength or
/// Dexterity score by 1, to a maximum of 20" - as the abilities it can go
/// to, how much, and the cap.
class FeatAbilityIncrease {
  const FeatAbilityIncrease({
    required this.abilities,
    this.amount = 1,
    this.max = 20,
  });

  /// Ability keys ('str', ...) the increase can go to - pick one.
  final List<String> abilities;
  final int amount;
  final int max;
}

const _abilityKeysByName = {
  'Strength': 'str',
  'Dexterity': 'dex',
  'Constitution': 'con',
  'Intelligence': 'int',
  'Wisdom': 'wis',
  'Charisma': 'cha',
};

/// The ability score increase [featName] grants, or null. A homebrew feat
/// says so in its own rules (My Homebrew > the feat > Ability score
/// increase); an SRD feat's is read from its text - Grappler and the Epic
/// Boons. Ability Score Improvement itself has its own +2 / +1+1 picker,
/// so it isn't one of these.
FeatAbilityIncrease? featAbilityIncrease(String featName) {
  final homebrew = _homebrewFeat(featName);
  if (homebrew != null) {
    final abilities = [
      for (final a in homebrew.data['abilityIncrease'] as List? ?? const [])
        if (_abilityKeysByName.values.contains(a)) a as String,
    ];
    if (abilities.isEmpty) return null;
    return FeatAbilityIncrease(
      abilities: abilities,
      amount: homebrew.data['abilityIncreaseAmount'] as int? ?? 1,
      max: homebrew.data['abilityIncreaseMax'] as int? ?? 20,
    );
  }
  final base = baseFeatName(featName);
  if (base == 'Ability Score Improvement') return null;
  final feat = srdCatalog.featsByKey.values
      .where((f) => f.name == base)
      .firstOrNull;
  if (feat == null) return null;
  final m = RegExp(
    r'Increase (?:one ability score of your choice|your ([A-Za-z, ]+?) '
    r'score) by (\d+), to a maximum of (\d+)',
  ).firstMatch(feat.fullDescription);
  if (m == null) return null;
  final named = m.group(1);
  return FeatAbilityIncrease(
    abilities: named == null
        ? _abilityKeysByName.values.toList()
        : [
            for (final e in _abilityKeysByName.entries)
              if (named.contains(e.key)) e.value,
          ],
    amount: int.parse(m.group(2)!),
    max: int.parse(m.group(3)!),
  );
}

int abilityModifier(int score) => ((score - 10) / 2).floor();

/// [c]'s ability scores as they currently apply: their own scores
/// (Character.abilityScores - what the player edits and what increases
/// add to), with any "set score" effect on top - a Belt of Giant Strength
/// making Strength 21 while attuned, a Headband of Intellect making
/// Intelligence 19. A set score only applies if it's higher than the
/// character's own, as those items say. Every calculation reads scores
/// through this; only edits read Character.abilityScores directly.
AbilityScores effectiveScores(Character c) {
  final base = c.abilityScores;
  final set = setScoreEffects(c);
  if (set.isEmpty) return base;
  int pick(String key) {
    final own = base.of(key);
    final best = set[key]?.$2;
    return best != null && best > own ? best : own;
  }

  return AbilityScores(
    str: pick('str'),
    dex: pick('dex'),
    con: pick('con'),
    intel: pick('int'),
    wis: pick('wis'),
    cha: pick('cha'),
  );
}

/// The highest 'setScore:[ability]' effect per ability, as (source,
/// value) - from attuned items and feats. Only a plain number counts (a
/// formula could depend on the very score it sets), and conditions are
/// ignored for the same reason.
Map<String, (String, int)> setScoreEffects(Character c) {
  final result = <String, (String, int)>{};
  void collect(String label, List<Effect> effects) {
    for (final e in effects) {
      if (!e.target.startsWith('setScore:')) continue;
      final key = e.target.substring('setScore:'.length);
      final value = int.tryParse(e.formula.trim());
      if (value == null) continue;
      final current = result[key];
      if (current == null || value > current.$2) result[key] = (label, value);
    }
  }

  for (final feat in c.feats) {
    collect(feat.name, liveFeatureEffects(feat));
  }
  for (final item in c.inventory) {
    collect(item.name, liveItemEffects(item));
  }
  return result;
}

/// The modifier of [c]'s effective [key] score.
int modifierOf(Character c, String key) =>
    abilityModifier(effectiveScores(c).of(key));

/// Reads an SRD armor formula like "15 + Dex modifier (max 2)" or a flat
/// "18" (heavy armor) and computes the resulting AC for a given Dex
/// modifier. Every one of the 12 SRD armors was checked against this
/// (see srd_catalog_test.dart / test cases below) - light armor adds the
/// full Dex modifier, medium armor caps it, heavy armor ignores it.
int armorClassFromFormula(String formula, int dexModifier) {
  final baseMatch = RegExp(r'(\d+)').firstMatch(formula);
  final base = baseMatch != null ? int.parse(baseMatch.group(1)!) : 10;
  if (!formula.contains('Dex modifier')) return base;
  final maxMatch = RegExp(r'max (\d+)').firstMatch(formula);
  final effectiveDex = maxMatch != null
      ? dexModifier.clamp(-99, int.parse(maxMatch.group(1)!))
      : dexModifier;
  return base + effectiveDex;
}

/// AC computed from what's actually equipped: worn armor (or 10 + Dex if
/// unarmored) plus a Shield's flat +2. Doesn't consult
/// [Character.armorClassOverride] - see [armorClassFor] for the value
/// the UI should actually display.
int computeArmorClass(Character c) {
  final dexMod = modifierOf(c, 'dex');
  final int base;
  if (c.equippedArmor != null) {
    base = armorClassFromFormula(c.equippedArmor!.armorClassFormula, dexMod);
  } else {
    base = [
      10 + dexMod,
      for (final formula in unarmoredDefenseOptions(c)) formula.$2,
    ].reduce((a, b) => a > b ? a : b);
  }
  return base + (c.shieldEquipped ? 2 : 0) + sumEffects(c, 'ac');
}

/// The "no armor" AC formulas [c]'s features offer, as (feature name, AC):
/// Barbarian Unarmored Defense (10 + Dex + Con, Shield allowed), Monk
/// Unarmored Defense (10 + Dex + Wis, no Shield), Draconic Sorcery's
/// Draconic Resilience (10 + Dex + Cha). computeArmorClass uses the best of
/// these and plain 10 + Dex while no armor is worn.
List<(String, int)> unarmoredDefenseOptions(Character c) {
  int mod(String key) => modifierOf(c, key);
  final dex = mod('dex');
  final names = c.features.map((f) => f.name).toSet();
  return [
    if (names.contains('Unarmored Defense') &&
        c.classKey == 'srd-2024_barbarian-class')
      ('Unarmored Defense', 10 + dex + mod('con')),
    if (names.contains('Unarmored Defense') &&
        c.classKey == 'srd-2024_monk-class' &&
        !c.shieldEquipped)
      ('Unarmored Defense', 10 + dex + mod('wis')),
    if (names.contains('Draconic Resilience'))
      ('Draconic Resilience', 10 + dex + mod('cha')),
  ];
}

/// The AC the sheet should show: the manual override if one is set,
/// otherwise the computed value. This is what every screen should call -
/// never read computeArmorClass or armorClassOverride directly.
int armorClassFor(Character c) => c.armorClassOverride ?? computeArmorClass(c);

/// Parses a class's "Hit Point Die" trait text (e.g. "D10 per Fighter
/// level") into just the die (e.g. "d10"). Returns null if unparseable -
/// ported from the web app's rules.ts.
String? parseHitDie(String? text) {
  if (text == null) return null;
  final match = RegExp('d(\\d+)', caseSensitive: false).firstMatch(text);
  return match != null ? 'd${match.group(1)}' : null;
}

const _abilityNameToKey = {
  'strength': 'str',
  'dexterity': 'dex',
  'constitution': 'con',
  'intelligence': 'int',
  'wisdom': 'wis',
  'charisma': 'cha',
};

/// Parses a class's "Saving Throw Proficiencies" trait text (e.g.
/// "Strength and Constitution") into ability keys - ported from the web
/// app's rules.ts. Returns [] for unparseable text rather than throwing.
List<String> parseSavingThrows(String? text) {
  if (text == null) return const [];
  final lower = text.toLowerCase();
  return [
    for (final entry in _abilityNameToKey.entries)
      if (lower.contains(entry.key)) entry.value,
  ];
}

/// A "Choose N `<Tool>`" proficiency, parsed down to how many picks and
/// which variant-bearing SRD tool to pick them from - see
/// [parseToolChoice].
class ToolChoiceRequirement {
  const ToolChoiceRequirement({required this.count, required this.tool});
  final int count;
  final SrdToolRef tool;
}

const _toolChoiceCountWords = {'one': 1, 'a': 1, 'an': 1};

/// Parses a background's or class's tool proficiency text into a
/// structured choice, e.g. "_Choose one kind of_ Gaming Set (see
/// "Equipment")" -> (count: 1, tool: Gaming Set) or "Choose 3 Musical
/// Instruments (see Equipment)" -> (count: 3, tool: Musical Instrument).
/// Returns null for a FIXED tool with no choice at all (e.g. "Thieves'
/// Tools" - most backgrounds/classes), or for a choice this app can't
/// cleanly resolve to a single variant-bearing tool (e.g. "Choose one
/// type of Artisan's Tools or Musical Instrument" names two different
/// things at once) - the caller falls back to a free-text field for
/// those, same as an unrecognized formula term degrades to 0 rather than
/// crashing.
ToolChoiceRequirement? parseToolChoice(String? text) {
  if (text == null) return null;
  final plain = text.replaceAll(RegExp(r'[*_]'), '').trim();
  final match = RegExp(
    r'^Choose (\w+) (?:kind of |type of )?([A-Za-z'
    "'"
    r' ]+?)\s*(?:\(|$)',
  ).firstMatch(plain);
  if (match == null) return null;
  final countWord = match.group(1)!.toLowerCase();
  final count = _toolChoiceCountWords[countWord] ?? int.tryParse(countWord);
  if (count == null) return null;
  var category = match.group(2)!.trim();
  if (category.endsWith('s') &&
      !srdCatalog.toolsByKey.values.any(
        (t) => t.name.toLowerCase() == category.toLowerCase(),
      )) {
    category = category.substring(0, category.length - 1);
  }
  final tool = srdCatalog.toolsByKey.values
      .where((t) => t.name.toLowerCase() == category.toLowerCase())
      .firstOrNull;
  if (tool == null || tool.variants.isEmpty) return null;
  return ToolChoiceRequirement(count: count, tool: tool);
}

/// Every "Choose N `<Tool>`" requirement a [backgroundKey]/[classKey]
/// combination actually has - the background's own tool proficiency
/// and/or the class's, in that order. Both can apply at once (e.g. a
/// Bard with the Soldier background) or neither (most combinations,
/// since only Soldier among backgrounds and Bard/Rogue among classes
/// grant a tool choice at all). Takes raw keys rather than a Character so
/// the New Character form can compute this from the species/background/
/// class pickers before a real Character object exists yet - see
/// [toolChoiceRequirementsFor] for the character-based convenience form.
List<ToolChoiceRequirement> toolChoiceRequirementsForKeys(
  String? backgroundKey,
  String? classKey,
) {
  final background = backgroundKey != null
      ? srdCatalog.backgroundsByKey[backgroundKey]
      : null;
  final classInfo = classKey != null ? srdCatalog.byKey(classKey) : null;
  return [
    ?parseToolChoice(background?.toolProficiency),
    ?parseToolChoice(classInfo?.traits['Tool Proficiencies']),
  ];
}

List<ToolChoiceRequirement> toolChoiceRequirementsFor(Character c) =>
    toolChoiceRequirementsForKeys(c.backgroundKey, c.classKey);

/// Evaluates a small flat formula grammar - literal integers, "Proficiency
/// Bonus", and "[Ability] modifier" for any of the six abilities, combined
/// with +/- (no parens, no multiplication/division) - against [c]. The
/// same narrow, hand-rolled approach as armorClassFromFormula and
/// MarkdownText: every real formula this app has ever needed (Alert's
/// Initiative bonus, Breath Weapon's save DC, ...) is a flat sum of these
/// terms, so a full expression parser would be unused surface. An
/// unrecognized term evaluates to 0 rather than throwing, so a typo in a
/// hand-typed homebrew formula degrades visibly (a wrong number) instead
/// of crashing.
int evaluateFormula(String formula, Character c) {
  var total = 0;
  for (final m in RegExp(r'([+-]?)\s*([^+-]+)').allMatches(formula)) {
    final term = m.group(2)!.trim();
    if (term.isEmpty) continue;
    total += (m.group(1) == '-' ? -1 : 1) * _evaluateTerm(term, c);
  }
  return total;
}

int _evaluateTerm(String term, Character c) {
  final asInt = int.tryParse(term);
  if (asInt != null) return asInt;
  if (term.toLowerCase() == 'proficiency bonus') {
    return proficiencyBonusForLevel(c.level);
  }
  if (term.toLowerCase() == 'level') return c.level;
  final m = RegExp(
    r'^(\w+)\s+modifier$',
    caseSensitive: false,
  ).firstMatch(term);
  final key = m != null ? _abilityNameToKey[m.group(1)!.toLowerCase()] : null;
  return key != null ? modifierOf(c, key) : 0;
}

/// 2024 rules: +2 at level 1, +1 every 4 levels.
int proficiencyBonusForLevel(int level) => ((level - 1) / 4).floor() + 2;

String formatModifier(int n) => n >= 0 ? '+$n' : '$n';

/// Dex modifier, plus any Effect targeting 'initiative' (e.g. Alert's
/// Initiative Proficiency benefit), plus any other flat situational bonus
/// recorded directly on the character.
int initiativeModifier(Character c) {
  final base = modifierOf(c, 'dex');
  return base + sumEffects(c, 'initiative') + c.initiativeBonus;
}

int savingThrowModifier(Character c, String abilityKey) {
  final mod = modifierOf(c, abilityKey);
  final proficient = c.savingThrowProficiencies.contains(abilityKey);
  final base = proficient ? mod + proficiencyBonusForLevel(c.level) : mod;
  return base + sumEffects(c, 'save:$abilityKey');
}

int skillModifier(Character c, SkillEntry skill) {
  final mod = modifierOf(c, skill.ability);
  final prof = proficiencyBonusForLevel(c.level);
  final base = skill.proficient
      ? mod + (skill.expertise ? prof * 2 : prof)
      : mod;
  return base + sumEffects(c, 'skill:${skill.name}');
}

// Hand-authored numeric effects for real feats whose mechanics aren't
// derivable from feats.json's prose alone (SrdFeat has desc/benefits as
// display text only) - verified directly against assets/srd/feats.json's
// benefit text, so only feats actually bundled in the free SRD belong
// here. This table ships in the compiled app, so it must never encode a
// non-SRD feat's mechanics (its formula, its condition, or a paraphrase
// of its text) - that content isn't licensed for this app to redistribute
// at all, bundled or not. A real 2024 feat that isn't in the free SRD
// (General Feats like Great Weapon Master and Heavy Armor Master, for
// instance - see assets/srd/feats.json, which only ships Origin/Fighting
// Style/Epic Boon feats) is exactly what the "My Homebrew" screen's
// `source: 'official'` category is for: the player transcribes it
// themselves, into their own local, never-bundled data (see
// models/homebrew.dart's doc comment) - content they already legally own
// from the PHB, not something this app ships or redistributes.
const _builtinFeatEffects = <String, List<Effect>>{
  'Alert': [Effect(target: 'initiative', formula: 'Proficiency Bonus')],
  // Fighting Style feats with a flat number (SRD text: "+2 bonus to attack
  // rolls you make with Ranged weapons"; "While you're wearing Light,
  // Medium, or Heavy armor, you gain a +1 bonus to Armor Class").
  'Archery': [
    Effect(target: 'attackRoll', formula: '2', condition: 'rangedWeapon'),
  ],
  'Defense': [Effect(target: 'ac', formula: '1', condition: 'wearingArmor')],
};

/// The feat names [_builtinFeatEffects] hardcodes - exposed so the "My
/// Homebrew" editor can warn when a homebrew entry's name collides with
/// one of them (see HomebrewEditScreen's override-warning check).
Set<String> get builtinFeatEffectNames => _builtinFeatEffects.keys.toSet();

/// The effects a granted feat currently carries, resolved LIVE - homebrew
/// first, then [_builtinFeatEffects]. Homebrew wins deliberately: a player
/// who creates a homebrew feat named exactly "Alert" (house-ruling its
/// formula) wants THEIR version applied, not to have their edit silently
/// ignored - the homebrew editor UI surfaces a warning when a name
/// collides with real/built-in content, so the override is something the
/// player can see, not a silent surprise in either direction. This is
/// also how a real, non-SRD feat (Great Weapon Master, Heavy Armor
/// Master, ...) gets its mechanics at all - see _builtinFeatEffects' doc
/// comment. Mirrors liveFeatureText's reasoning (prefer a live lookup
/// over a stale stored value) - a correction to the built-in table, or a
/// player's edit to their homebrew feat's formula, should apply to every
/// character who already has that feat granted, not just future grants.
List<Effect> liveFeatureEffects(GrantedFeature feature) {
  final homebrew = homebrewRepo.entries.where(
    (e) =>
        e.kind == 'feat' && e.name.toLowerCase() == feature.name.toLowerCase(),
  );
  if (homebrew.isNotEmpty) return homebrew.first.effects;
  return _builtinFeatEffects[baseFeatName(feature.name)] ?? const [];
}

/// A feat's name without the parenthetical choice a background or feature
/// attaches to it - "Magic Initiate (Cleric)" -> "Magic Initiate" - which
/// is the name the SRD feat itself is catalogued under.
String baseFeatName(String name) =>
    name.replaceFirst(RegExp(r'\s*\([^)]*\)$'), '');

/// The parenthetical choice in a feat's name - "Magic Initiate (Cleric)"
/// -> "Cleric" - or null if there isn't one.
String? featNameChoice(String name) =>
    RegExp(r'\(([^)]*)\)$').firstMatch(name)?.group(1);

/// Effects from attuned magic items - homebrew only (no built-in SRD
/// magic item needs this yet), matched the same way liveFeatureEffects
/// matches feats: by name, against a same-named homebrew 'magicItem'
/// entry. Ungated by anything else - "Requires Attunement" is exactly
/// what InventoryEntry.attuned already tracks.
List<Effect> liveItemEffects(InventoryEntry item) {
  if (!item.attuned) return const [];
  final homebrew = homebrewRepo.entries.where(
    (e) =>
        e.kind == 'magicItem' &&
        e.name.toLowerCase() == item.name.toLowerCase(),
  );
  return homebrew.isNotEmpty ? homebrew.first.effects : const [];
}

/// Recognized Effect conditions - an unrecognized string never matches
/// (fails safe, doesn't crash) rather than guessing at intent.
bool _effectConditionMet(String? condition, Character c, Weapon? weapon) =>
    switch (condition) {
      null => true,
      'heavyWeapon' => weapon?.isHeavy ?? false,
      // No official 5e term for "took any damage at all" - tables invent
      // their own (this session's example: "scratched"); the Dart key
      // stays plain/mechanical rather than presenting an invented status
      // name as if it were a rule.
      'anyDamage' => c.currentHp < c.maxHp,
      // The one HP tier 2024 actually names - verified against the Rules
      // Glossary: "A creature is Bloodied while it has half its Hit
      // Points or fewer remaining."
      'bloodied' => c.currentHp * 2 <= c.maxHp,
      'heavyArmor' => c.equippedArmor?.category == 'Heavy',
      'wearingArmor' => c.equippedArmor != null,
      'noArmor' => c.equippedArmor == null,
      'rangedWeapon' => weapon != null && isRangedWeapon(weapon),
      'meleeWeapon' => weapon != null && !isRangedWeapon(weapon),
      _ => false,
    };

/// Every (source name, evaluated amount) contributing to [target] across
/// [c]'s feats and attuned inventory items - the label is used for
/// attackFor/damageFor's breakdown text. [weapon] is only consulted for a
/// weapon-scoped condition (e.g. 'heavyWeapon'); an effect with such a
/// condition simply never matches a non-weapon target (initiative, a
/// save, a skill) when weapon is null.
List<(String, int)> matchingEffects(
  Character c,
  String target, {
  Weapon? weapon,
}) {
  final result = <(String, int)>[];
  void collect(String label, List<Effect> effects) {
    for (final effect in effects) {
      if (effect.target != target) continue;
      if (!_effectConditionMet(effect.condition, c, weapon)) continue;
      final amount = evaluateFormula(effect.formula, c);
      if (amount != 0) result.add((label, amount));
    }
  }

  for (final feat in c.feats) {
    collect(feat.name, liveFeatureEffects(feat));
  }
  for (final item in c.inventory) {
    collect(item.name, liveItemEffects(item));
  }
  for (final (label, effect) in featureEffects(c)) {
    collect(label, [effect]);
  }
  return result;
}

int sumEffects(Character c, String target, {Weapon? weapon}) =>
    matchingEffects(c, target, weapon: weapon).fold(0, (a, e) => a + e.$2);

/// Draconic Ancestry's damage resistance - the one species trait this app
/// derives as a real Effect rather than display-only text (see the
/// homebrew plan's "deliberately deferred: effects on c.features" note -
/// this is a narrow, verified exception, not a general species-effects
/// system). It's not a fixed formula a static table could hold, the way
/// [_builtinFeatEffects] holds Alert: the resistance's damage type is
/// whichever ancestry color the player chose,
/// looked up live the same way the sheet already derives Breath Weapon's
/// damage type from [Character.speciesChoice] (character_sheet_screen.dart's
/// _InnateAttackRow._damageType). Verified against the 2024 Dragonborn
/// trait text: "You have Resistance to the damage type associated with
/// your Draconic Ancestry."
List<Effect> liveSpeciesResistances(Character c) {
  if (c.speciesKey != 'srd-2024_dragonborn-species' ||
      c.speciesChoice == null) {
    return const [];
  }
  final species = srdCatalog.speciesByKey[c.speciesKey];
  if (species == null || species.tables.isEmpty) return const [];
  final match = flattenSpeciesTableOptions(species.tables.first)
      .where((o) => o.name == c.speciesChoice);
  if (match.isEmpty) return const [];
  return [
    Effect(
      target: 'damageResistance:${match.first.detail.toLowerCase()}',
      formula: '',
    ),
  ];
}

/// Every (source label, Effect) with a damageResistance/damageReduction
/// target - shared by [computeDamageTaken] so it only has to walk c's
/// feats/attuned items/species resistance once.
List<(String, Effect)> _damageTakenEffects(Character c) {
  final result = <(String, Effect)>[];
  void collect(String label, List<Effect> effects) {
    for (final effect in effects) {
      if (effect.target.startsWith('damageResistance:') ||
          effect.target.startsWith('damageReduction:')) {
        result.add((label, effect));
      }
    }
  }

  for (final feat in c.feats) {
    collect(feat.name, liveFeatureEffects(feat));
  }
  for (final item in c.inventory) {
    collect(item.name, liveItemEffects(item));
  }
  collect('Draconic Resistance', liveSpeciesResistances(c));
  for (final (label, effect) in featureEffects(c)) {
    collect(label, [effect]);
  }
  return result;
}

/// Whether a damageResistance/damageReduction effect's own type (the part
/// of its target after the colon) covers the incoming damage. 'physical'
/// is a bucket for Bludgeoning/Piercing/Slashing from a nonmagical source
/// - the standard 5e phrasing for both Heavy Armor Master and features
/// like Rage - and only matches when [magical] is false; every other
/// (specific) type matches on its own regardless of [magical], since
/// elemental resistance isn't affected by that distinction.
bool _damageTakenTypeMatches(
  String effectType,
  String incomingTypeKey,
  bool magical,
) {
  if (effectType == 'physical') {
    return !magical &&
        const {'bludgeoning', 'piercing', 'slashing'}.contains(incomingTypeKey);
  }
  return effectType == incomingTypeKey;
}

/// What [computeDamageTaken] found: the amount that actually comes off
/// HP, and a labeled, ordered trail of every step that changed the raw
/// number (so the Take Damage dialog can show its work, not just the
/// final total).
class DamageTakenResult {
  const DamageTakenResult({required this.finalAmount, required this.steps});
  final int finalAmount;
  final List<String> steps;
}

/// [rawAmount] of [damageTypeKey] damage (an srdCatalog.damageTypes key,
/// e.g. "fire") after a successful save (if [halfOnSave]), resistance,
/// and reduction. [halfOnSave] is a completely different mechanic from
/// resistance - many spells/effects ("half as much damage on a
/// successful save," e.g. Fireball) halve the *rolled* damage itself
/// before the target's own defenses ever apply, so it's a per-instance
/// choice the player makes when entering this specific hit, not something
/// derived from the character's feats/items the way resistance is. The
/// two halvings (save, then resistance) are applied as separate,
/// independently-rounded-down steps rather than combined into one /4,
/// matching how 5e always resolves multiple halving effects - though the
/// two arithmetically commute either way (floor(floor(x/2)/2) ==
/// floor(x/4) for any non-negative x), only the order they're listed in
/// the breakdown differs. Reduction (flat, summed across every matching
/// source) applies last, same order 5e always resolves resistance and a
/// flat reduction together. Resistance never stacks (5e: a second source
/// of the same resistance doesn't halve twice), so at most one halving
/// from it ever applies here even if several sources grant it. Never
/// negative.
DamageTakenResult computeDamageTaken(
  Character c,
  int rawAmount,
  String damageTypeKey, {
  required bool magical,
  bool halfOnSave = false,
}) {
  final steps = <String>['Raw damage: $rawAmount'];
  var amount = rawAmount;

  if (halfOnSave) {
    amount = (amount / 2).floor();
    steps.add('Passed a save: half → $amount');
  }

  final effects = _damageTakenEffects(c)
      .where((e) => _effectConditionMet(e.$2.condition, c, null))
      .toList();

  final resistance = effects.where(
    (e) =>
        e.$2.target.startsWith('damageResistance:') &&
        _damageTakenTypeMatches(
          e.$2.target.split(':').last,
          damageTypeKey,
          magical,
        ),
  );
  if (resistance.isNotEmpty) {
    amount = (amount / 2).floor();
    steps.add('${resistance.first.$1}: Resistant, half → $amount');
  }

  for (final (label, effect) in effects) {
    if (!effect.target.startsWith('damageReduction:')) continue;
    if (!_damageTakenTypeMatches(
      effect.target.split(':').last,
      damageTypeKey,
      magical,
    )) {
      continue;
    }
    final reduceBy = evaluateFormula(effect.formula, c);
    if (reduceBy <= 0) continue;
    final before = amount;
    amount = (amount - reduceBy).clamp(0, before);
    steps.add('$label: -$reduceBy → $amount');
  }

  return DamageTakenResult(finalAmount: amount, steps: steps);
}

class AttackResult {
  const AttackResult(this.bonus, this.breakdown);
  final int bonus;
  final String breakdown;
}

class DamageResult {
  const DamageResult(this.text, this.breakdown);
  final String text;
  final String breakdown;
}

/// A one-line snapshot of every carried weapon's current attack bonus and
/// damage - '' if [c] carries none. Appended to History entries for
/// anything that can move these numbers (a level, an Ability Score
/// Improvement, a feat like Great Weapon Master, a subclass pick) so the
/// audit trail shows how weapon damage/attack actually progressed
/// over time, not just the event that caused each change.
String weaponsSnapshot(Character c) => c.weapons
    .map(
      (w) =>
          '${w.name} ${formatModifier(attackFor(c, w).bonus)}/${damageFor(c, w).text}',
    )
    .join(', ');

AttackResult attackFor(Character c, Weapon w) {
  final (abilityLabel, abilityMod) = weaponAbility(c, w);

  final parts = <String>['$abilityLabel ${formatModifier(abilityMod)}'];
  var bonus = abilityMod;
  if (w.proficient) {
    final prof = proficiencyBonusForLevel(c.level);
    parts.add('Prof ${formatModifier(prof)}');
    bonus += prof;
  }
  if (w.magicBonus != 0) {
    parts.add('Magic ${formatModifier(w.magicBonus)}');
    bonus += w.magicBonus;
  }
  for (final (label, amount) in matchingEffects(c, 'attackRoll', weapon: w)) {
    parts.add('$label ${formatModifier(amount)}');
    bonus += amount;
  }
  return AttackResult(bonus, parts.join(', '));
}

DamageResult damageFor(Character c, Weapon w) {
  final (abilityLabel, abilityMod) = weaponAbility(c, w);

  var total = abilityMod + w.magicBonus;
  final parts = <String>['$abilityLabel ${formatModifier(abilityMod)}'];
  if (w.magicBonus != 0) parts.add('Magic ${formatModifier(w.magicBonus)}');
  for (final (label, amount) in matchingEffects(c, 'damageRoll', weapon: w)) {
    parts.add('$label ${formatModifier(amount)}');
    total += amount;
  }
  final bonusText = total != 0 ? formatModifier(total) : '';
  final dice = weaponDamageDice(c, w);
  if (dice != w.damageDice) parts.add('Martial Arts $dice');
  return DamageResult(
    '$dice$bonusText ${w.damageType}'.trim(),
    parts.join(', '),
  );
}

/// Rows the PDF's WEAPONS & DAMAGE CANTRIPS table would need: weapons,
/// damaging innate attacks, and damage cantrips (see character_sheet_pdf).
int pdfAttackRowCount(Character c) =>
    c.weapons.length +
    c.innateAttacks.where((a) => innateAttackInfo(c, a).diceCount > 0).length +
    (c.spellcasting?.cantripsKnown ?? const <String>[])
        .map((k) => spellRefFor(k, homebrewLevel: 0))
        .where((s) => s != null && spellDamageInfo(s, c.level).dice != null)
        .length;

/// An Unarmed Strike's numbers: attack (Strength + Proficiency Bonus -
/// everyone is proficient), damage (1 + Strength, or with Martial Arts the
/// Martial Arts die + the better of Str/Dex), and the Grapple/Shove save DC
/// (8 + Strength + PB; Martial Arts allows Dex).
({int attack, String damage, int grappleDc, String ability}) unarmedStrike(
  Character c,
) {
  final str = modifierOf(c, 'str');
  final dex = modifierOf(c, 'dex');
  final prof = proficiencyBonusForLevel(c.level);
  final monk = martialArtsActive(c);
  final useDex = monk && dex > str;
  final mod = useDex ? dex : str;
  final die = monk ? martialArtsDie(c) : null;
  final bonus = mod != 0 ? formatModifier(mod) : '';
  return (
    attack: mod + prof + sumEffects(c, 'attackRoll'),
    damage: die != null
        ? '$die$bonus Bludgeoning'
        : '${(1 + mod).clamp(0, 99)} Bludgeoning',
    grappleDc: 8 + mod + prof,
    ability: useDex ? 'Dex' : 'Str',
  );
}

/// The SRD weapon [w] is (or is a magic/renamed version of) - an exact
/// name match first, then the longest SRD weapon name contained in its
/// name ("Longsword +1", "Flame Tongue Longsword" -> Longsword). Null for a
/// weapon that matches nothing (homebrew).
SrdWeaponRef? srdWeaponFor(Weapon w) => srdWeaponNamed(w.name);

SrdWeaponRef? srdWeaponNamed(String name) {
  final lower = name.toLowerCase();
  SrdWeaponRef? best;
  for (final ref in srdCatalog.weaponsByKey.values) {
    final refName = ref.name.toLowerCase();
    if (refName == lower) return ref;
    if (lower.contains(refName) &&
        (best == null || ref.name.length > best.name.length)) {
      best = ref;
    }
  }
  return best;
}

/// [w]'s SRD category ("Martial Ranged Weapons", ...) - stored on the
/// weapon, else resolved by name for a weapon saved before it was stored.
String? weaponCategory(Weapon w) => w.category ?? srdWeaponFor(w)?.category;

bool isRangedWeapon(Weapon w) {
  final category = weaponCategory(w);
  if (category != null) return category.contains('Ranged');
  return w.properties.any((p) => p.startsWith('Ammunition'));
}

bool isFinesseWeapon(Weapon w) => w.finesse || w.properties.contains('Finesse');

/// A Monk weapon: any Simple Melee weapon, or a Martial Melee weapon with
/// the Light property (Martial Arts' own definition).
bool isMonkWeapon(Weapon w) {
  final category = weaponCategory(w) ?? '';
  return category.startsWith('Simple Melee') ||
      (category.startsWith('Martial Melee') && w.properties.contains('Light'));
}

/// Martial Arts applies: the character has the feature and wears no armor
/// or Shield.
bool martialArtsActive(Character c) =>
    c.features.any((f) => f.name == 'Martial Arts') &&
    c.equippedArmor == null &&
    !c.shieldEquipped;

/// The ability a weapon attack uses, as (label, modifier): Dexterity for a
/// ranged weapon; the better of Strength and Dexterity for a Finesse
/// weapon or a Monk weapon under Martial Arts; Strength otherwise. A
/// thrown melee weapon (Javelin, Handaxe) keeps its melee ability, as the
/// Thrown property says.
(String, int) weaponAbility(Character c, Weapon w) {
  final str = modifierOf(c, 'str');
  final dex = modifierOf(c, 'dex');
  if (isRangedWeapon(w)) return ('Dex', dex);
  final canUseDex =
      isFinesseWeapon(w) || (martialArtsActive(c) && isMonkWeapon(w));
  return canUseDex && dex > str ? ('Dex', dex) : ('Str', str);
}

/// The Martial Arts die at [c]'s level ("1d6", "1d8", ...) - null for a
/// character without the feature.
String? martialArtsDie(Character c) {
  if (!c.features.any((f) => f.name == 'Martial Arts')) return null;
  final classData = c.classKey != null ? srdCatalog.byKey(c.classKey!) : null;
  return classData?.levelValue(c.level, 'Martial Arts');
}

/// [w]'s damage dice, with the Martial Arts die swapped in for a Monk
/// weapon when it's bigger (Martial Arts: "You can roll [the die] in place
/// of the normal damage").
String weaponDamageDice(Character c, Weapon w) {
  final die = martialArtsDie(c);
  if (die == null || !martialArtsActive(c) || !isMonkWeapon(w)) {
    return w.damageDice;
  }
  int average(String dice) {
    final m = RegExp(r'^(\d+)d(\d+)$').firstMatch(dice);
    if (m == null) return 0;
    return int.parse(m.group(1)!) * (int.parse(m.group(2)!) + 1);
  }

  return average(die) > average(w.damageDice) ? die : w.damageDice;
}

/// Whether [c] is proficient with a weapon of [category] and
/// [properties], read from the class's own Weapon Proficiencies text
/// ("Simple and Martial weapons", "Simple weapons and Martial weapons that
/// have the Finesse or Light property", ...) plus
/// Character.extraWeaponProficiencies ("Martial weapons", or a weapon's
/// name).
bool isProficientWithWeapon(
  Character c,
  String name,
  String? category,
  List<String> properties,
) {
  final classData = c.classKey != null ? srdCatalog.byKey(c.classKey!) : null;
  final classText = (classData?.traits['Weapon Proficiencies'] ?? '')
      .toLowerCase();
  final extras = c.extraWeaponProficiencies.map((e) => e.toLowerCase());
  if (extras.contains(name.toLowerCase())) return true;
  final cat = (category ?? '').toLowerCase();
  if (cat.startsWith('simple')) {
    return classText.contains('simple') || extras.contains('simple weapons');
  }
  if (cat.startsWith('martial')) {
    if (extras.contains('martial weapons')) return true;
    final conditional = RegExp(r'martial weapons that have the (.+?) property')
        .firstMatch(classText);
    if (conditional != null) {
      final allowed = conditional.group(1)!.split(' or ');
      return properties.any((p) => allowed.contains(p.toLowerCase()));
    }
    return classText.contains('martial');
  }
  return false;
}

/// A new Weapon for [c] from an SRD weapon - the one place a catalog weapon
/// becomes a character's weapon (the sheet's "+ Add Weapon", starting
/// equipment), so category, Finesse, proficiency, and mastery are always
/// filled in the same way.
Weapon weaponFromSrd(Character c, SrdWeaponRef ref) {
  final (dice, type) = ref.splitDamage;
  return Weapon(
    name: ref.name,
    damageDice: dice,
    damageType: type,
    properties: ref.properties,
    mastery: ref.mastery,
    masteryDesc: ref.mastery != null
        ? srdCatalog.weaponPropertiesByName[ref.mastery]?.desc
        : null,
    proficient: isProficientWithWeapon(
      c,
      ref.name,
      ref.category,
      ref.properties,
    ),
    finesse: ref.isFinesse,
    category: ref.category,
  );
}

/// How many weapon kinds [c]'s Weapon Mastery feature covers at their
/// level - the class table's "Weapon Mastery" column (Barbarian, Fighter),
/// or 2 for a class whose feature text fixes it at two (Paladin, Ranger,
/// Rogue). Null for a character without the feature.
int? weaponMasteryLimit(Character c) {
  if (!c.features.any((f) => f.name == 'Weapon Mastery')) return null;
  final classData = c.classKey != null ? srdCatalog.byKey(c.classKey!) : null;
  return int.tryParse(classData?.levelValue(c.level, 'Weapon Mastery') ?? '') ??
      2;
}

/// Whether [w]'s mastery property applies to [c]: the weapon has one, and
/// its kind is among the character's Weapon Mastery picks (matched the same
/// way srdWeaponFor matches names, so "Longsword +1" counts as Longsword).
/// ['*'] - a character saved before picks were tracked - applies them all.
bool masteryApplies(Character c, Weapon w) {
  if (w.mastery == null) return false;
  if (c.weaponMasteries.contains('*')) return true;
  final kind = srdWeaponFor(w)?.name ?? w.name;
  return c.weaponMasteries.any((m) => m.toLowerCase() == kind.toLowerCase());
}

/// Species' base walking speed ("35 feet" -> 35), or null if the species
/// isn't cataloged.
int? speciesBaseSpeed(String? speciesKey) {
  final raw = speciesKey != null
      ? srdCatalog.speciesByKey[speciesKey]?.speed
      : null;
  return raw == null
      ? null
      : int.tryParse(RegExp(r'\d+').stringMatch(raw) ?? '');
}

/// [c]'s Speed: their base speed (Character.speed - the species' speed,
/// editable) plus class features that raise it (Barbarian Fast Movement and
/// Ranger Roving: +10 ft without Heavy armor; Monk Unarmored Movement: the
/// table's bonus without armor or a Shield) and any 'speed' Effect.
int speedFor(Character c) {
  final names = c.features.map((f) => f.name).toSet();
  final heavy = c.equippedArmor?.category == 'Heavy';
  var speed = c.speed + sumEffects(c, 'speed');
  if (names.contains('Fast Movement') && !heavy) speed += 10;
  if (names.contains('Roving') && !heavy) speed += 10;
  if (names.contains('Unarmored Movement') &&
      c.equippedArmor == null &&
      !c.shieldEquipped) {
    final classData = c.classKey != null ? srdCatalog.byKey(c.classKey!) : null;
    final bonus = classData?.levelValue(c.level, 'Unarmored Movement');
    speed += int.tryParse(RegExp(r'\d+').stringMatch(bonus ?? '') ?? '') ?? 0;
  }
  return speed;
}

/// Hit points added on top of the class's Hit Dice: Dwarven Toughness (+1
/// per level), Draconic Sorcery's Draconic Resilience (+3 at level 3, +1
/// per Sorcerer level after - i.e. the Sorcerer level), and any 'maxHp'
/// Effect - e.g. a transcribed Tough feat, "Level + Level" (formulas only
/// add and subtract terms).
int _hitDieSides(Character c) =>
    int.tryParse(
      c.hitDiceDie.replaceFirst(RegExp('^d', caseSensitive: false), ''),
    ) ??
    8;

/// The fixed-value Hit Die result for [c]'s die (d10 -> 6).
int averageHitDieResult(Character c) => _hitDieSides(c) ~/ 2 + 1;

/// The Hit Die result counted at [level]: the die's maximum at level 1,
/// else the recorded roll (Character.hitPointRolls) or the average.
int hitDieResultAt(Character c, int level) => level == 1
    ? _hitDieSides(c)
    : c.hitPointRolls[level] ?? averageHitDieResult(c);

/// Max HP from its parts: each level's Hit Die result + Constitution
/// modifier (at least 1 per level, per the rules), plus [maxHpBonus]
/// (Dwarven Toughness, Draconic Resilience, 'maxHp' effects), plus the
/// hand adjustment. Always at least 1.
int computedMaxHp(Character c) {
  final con = modifierOf(c, 'con');
  var total = 0;
  for (var level = 1; level <= c.level; level++) {
    final gain = hitDieResultAt(c, level) + con;
    total += gain < 1 ? 1 : gain;
  }
  total += maxHpBonus(c) + c.maxHpAdjustment;
  return total < 1 ? 1 : total;
}

/// Brings Max HP up to date with its parts after something changed (a Con
/// increase, a feat, an attuned item, a new species). A gain also raises
/// Current HP by the same amount, the way gaining Max HP works; a loss
/// only caps it. Returns the change.
int refreshMaxHp(Character c) {
  final before = c.maxHp;
  c.maxHp = computedMaxHp(c);
  final delta = c.maxHp - before;
  if (delta > 0) c.currentHp += delta;
  c.currentHp = c.currentHp.clamp(0, c.maxHp);
  return delta;
}

/// One-time switch for a character saved before Max HP was built from its
/// parts: whatever its stored Max HP differs from the computed value by
/// becomes [Character.maxHpAdjustment], so nothing changes on screen.
void adoptHpTracking(Character c) {
  if (c.hpTracked) return;
  c.maxHpAdjustment = 0;
  c.maxHpAdjustment = c.maxHp - computedMaxHp(c);
  c.hpTracked = true;
}

int maxHpBonus(Character c) {
  var bonus = sumEffects(c, 'maxHp');
  if (c.speciesKey == 'srd-2024_dwarf-species') bonus += c.level;
  if (c.features.any((f) => f.name == 'Draconic Resilience')) {
    bonus += c.level;
  }
  return bonus;
}

/// A Short Rest recovers per-resource ("full", "partial" = +1 use, or
/// "none"); a Long Rest always fully restores every resource, restores
/// all HP, and restores half your total Hit Dice (rounded down, min 1) -
/// the same assumption the web app verified against every 2024 class.
void applyShortRest(Character c) {
  for (final r in c.resources) {
    switch (r.shortRestRecovery) {
      case 'full':
        r.used = 0;
      case 'partial':
        r.used = (r.used - 1).clamp(0, r.max);
      default:
        break;
    }
  }
  // Pact Magic: "You regain all expended Pact Magic spell slots when you
  // finish a Short or Long Rest" - every other caster's slots wait for a
  // Long Rest.
  if (usesPactMagic(c)) {
    for (final slot in c.spellcasting?.slots.values ?? const <SpellSlot>[]) {
      slot.used = 0;
    }
  }
  _recoverFreeCasts(c, longRest: false);
}

void applyLongRest(Character c) {
  for (final r in c.resources) {
    r.used = 0;
  }
  // A Long Rest fully restores every spell slot, Pact Magic included, and
  // ends Concentration - its sleep leaves you Unconscious (Incapacitated)
  // for hours, longer than nearly every Concentration spell lasts anyway.
  for (final slot in c.spellcasting?.slots.values ?? const <SpellSlot>[]) {
    slot.used = 0;
  }
  _recoverFreeCasts(c, longRest: true);
  endConcentration(c);
  c.currentHp = c.maxHp;
  c.tempHp = 0;
  final regained = (c.hitDiceTotal / 2).floor().clamp(1, c.hitDiceTotal);
  c.hitDiceSpent = (c.hitDiceSpent - regained).clamp(0, c.hitDiceTotal);
  // 2024 rules: finishing a Long Rest (with food and drink) reduces
  // Exhaustion by 1, and there's no reason to still be tracking a death
  // save once you're back to full HP.
  c.exhaustionLevel = (c.exhaustionLevel - 1).clamp(0, 6);
  c.deathSaveSuccesses = 0;
  c.deathSaveFailures = 0;
  for (final m in c.mounts) {
    m.rechargeActionUsed = false;
  }
}

/// What a Short or Long Rest would change for [c], one line per change
/// ("HP 12 â†’ 45", "Second Wind 0 â†’ 2 of 2 left") - empty if nothing
/// would. Worked out by resting a copy, so the preview always matches
/// [applyShortRest]/[applyLongRest] exactly.
List<String> restPreview(Character c, {required bool longRest}) {
  final after = Character.fromJson(
    jsonDecode(jsonEncode(c.toJson())) as Map<String, dynamic>,
  );
  longRest ? applyLongRest(after) : applyShortRest(after);

  final changes = <String>[];
  void change(String label, Object before, Object now, [String suffix = '']) {
    if (before != now) changes.add('$label: $before â†’ $now$suffix');
  }

  change('HP', c.currentHp, after.currentHp, ' of ${c.maxHp}');
  change('Temporary HP', c.tempHp, after.tempHp);
  change(
    'Hit Dice',
    c.hitDiceTotal - c.hitDiceSpent,
    after.hitDiceTotal - after.hitDiceSpent,
    ' of ${c.hitDiceTotal} left',
  );
  change('Exhaustion', c.exhaustionLevel, after.exhaustionLevel);
  if (c.deathSaveSuccesses + c.deathSaveFailures > 0 &&
      after.deathSaveSuccesses + after.deathSaveFailures == 0) {
    changes.add('Death saves cleared');
  }
  for (var i = 0; i < c.resources.length; i++) {
    final r = c.resources[i];
    change(
      r.name,
      r.max - r.used,
      r.max - after.resources[i].used,
      ' of ${r.max} left',
    );
  }
  final slots = c.spellcasting?.slots ?? const <int, SpellSlot>{};
  final slotsAfter = after.spellcasting?.slots ?? const <int, SpellSlot>{};
  for (final level in slots.keys.toList()..sort()) {
    final s = slots[level]!;
    change(
      'Level $level spell slots',
      s.max - s.used,
      s.max - slotsAfter[level]!.used,
      ' of ${s.max} left',
    );
  }
  final spells = c.spellcasting?.spells ?? const <KnownSpell>[];
  final spellsAfter = after.spellcasting?.spells ?? const <KnownSpell>[];
  for (var i = 0; i < spells.length; i++) {
    final s = spells[i];
    if (s.freeCasts <= 0) continue; // none, or at will
    change(
      '${knownSpellRef(s)?.name ?? s.spellKey} free casts',
      s.freeCasts - s.freeCastsUsed,
      s.freeCasts - spellsAfter[i].freeCastsUsed,
      ' of ${s.freeCasts} left',
    );
  }
  for (var i = 0; i < c.mounts.length; i++) {
    final m = c.mounts[i];
    if (m.rechargeActionUsed && !after.mounts[i].rechargeActionUsed) {
      changes.add('${m.name}: ${m.rechargeAction} available again');
    }
  }
  final concentrating = c.spellcasting?.concentratingOn;
  if (concentrating != null && after.spellcasting?.concentratingOn == null) {
    changes.add(
      'Ends Concentration on '
      '${spellRefFor(concentrating)?.name ?? concentrating}',
    );
  }
  return changes;
}

/// Average result of rolling a die like "d10" - offered as the default
/// when spending a Hit Die, though the player can enter their actual roll.
int rollableAverage(String die) {
  final sides = int.parse(
    die.replaceFirst(RegExp('^d', caseSensitive: false), ''),
  );
  return (sides / 2).floor() + 1;
}

/// Damage/heal that spends Temporary HP first, same as the web app: a
/// negative delta is absorbed by tempHp before touching currentHp; a
/// positive delta (healing) never overflows past maxHp or tempHp.
void applyDamageOrHeal(Character c, int delta) {
  if (delta < 0) {
    final remaining = (c.tempHp + delta).clamp(-999999, 0);
    c.tempHp = (c.tempHp + delta).clamp(0, 999999);
    c.currentHp = (c.currentHp + remaining).clamp(0, c.maxHp);
    // Dropping to 0 HP leaves you Unconscious, which (being Incapacitated)
    // ends Concentration outright - no save.
    if (c.currentHp == 0) endConcentration(c);
  } else {
    c.currentHp = (c.currentHp + delta).clamp(0, c.maxHp);
  }
}

/// Grants Temporary Hit Points. Per the SRD ("Temporary Hit Points" ->
/// "They Don't Stack"), a new grant never adds to an existing one - the
/// player decides whether to keep what they have or take the new amount
/// - so this always replaces c.tempHp outright; the UI shows the current
/// value alongside the field so the player can make that call themselves
/// before confirming a lower replacement.
void setTempHp(Character c, int amount) {
  c.tempHp = amount.clamp(0, 999999);
}

/// Spending a Hit Die on a Short Rest heals `roll + Constitution modifier`
/// (minimum 0) and marks one die spent.
void spendHitDie(Character c, int roll) {
  if (c.hitDiceSpent >= c.hitDiceTotal) return;
  c.hitDiceSpent += 1;
  final heal = (roll + modifierOf(c, 'con')).clamp(0, 999999);
  c.currentHp = (c.currentHp + heal).clamp(0, c.maxHp);
}

/// Max HP for a given level/die/Constitution modifier: the max die result
/// at level 1, then the average die result (rounded up) each level after -
/// never a random roll, so this is safe to recompute at any time (the
/// same rule the web app's recalculateDerivedStats relied on). Verified
/// against Jarson's real numbers: d10, Con +2, level 9 -> 76, matching
/// the character as the DM originally built him.
int maxHpForLevel({
  required String die,
  required int conModifier,
  required int level,
}) {
  final sides = int.parse(
    die.replaceFirst(RegExp('^d', caseSensitive: false), ''),
  );
  final average = (sides / 2).floor() + 1;
  var total = sides + conModifier;
  for (var lvl = 2; lvl <= level; lvl++) {
    total += average + conModifier;
  }
  return total;
}

/// Recomputes Max HP and Hit Dice total from the character's current
/// level - a correction tool (mislabeled level, hand-built starting
/// character), not a "level up in play" action. Current HP and spent Hit
/// Dice are clamped to the new totals rather than preserved or bumped, so
/// this is always safe to call, even repeatedly.
///
/// Doesn't touch resource maximums (Action Surge, Second Wind, ...) -
/// those scale with level per a class's own level table, which isn't
/// ported yet (no SRD catalog behind this app so far). Deliberately
/// avoids guessing those numbers rather than risking a wrong table.
void recalculateHp(Character c) {
  c.maxHp = computedMaxHp(c);
  c.hitDiceTotal = c.level;
  c.currentHp = c.currentHp.clamp(0, c.maxHp);
  c.hitDiceSpent = c.hitDiceSpent.clamp(0, c.hitDiceTotal);
}

/// A resource definition resolved for a specific level - everything
/// needed to create or update the matching [Resource] on a character.
class ResourceDefinition {
  const ResourceDefinition({
    required this.key,
    required this.name,
    required this.max,
    required this.shortRestRecovery,
  });
  final String key;
  final String name;
  final int max;
  final String shortRestRecovery;
}

/// Which of a class's level-table columns are genuine spendable/
/// rechargeable resources (vs. descriptive columns like Barbarian's "Rage
/// Damage" or Fighter's "Weapon Mastery" count, which aren't something you
/// spend), and how each recovers on a Short Rest - ported from the web
/// app's rules.ts, verified against every resource's own rules text (all
/// of them fully recover on a Long Rest, so that part isn't tracked
/// per-resource). Bard (Bardic Inspiration), Ranger (Favored Enemy), Rogue
/// (Sneak Attack), and Warlock (Eldritch Invocations; Pact Magic slots are
/// spellcasting, handled separately) don't have a table column that's a
/// simple rest-recoverable use counter, so they're intentionally absent.
const _resourceDefsByClassKey = {
  'srd-2024_barbarian-class': [('Rages', 'partial')],
  'srd-2024_cleric-class': [('Channel Divinity', 'partial')],
  'srd-2024_druid-class': [('Wild Shape', 'partial')],
  'srd-2024_fighter-class': [('Second Wind', 'partial')],
  'srd-2024_monk-class': [('Focus Points', 'full')],
  'srd-2024_paladin-class': [('Channel Divinity', 'partial')],
  'srd-2024_sorcerer-class': [('Sorcery Points', 'none')],
};

/// Reads whichever tracked resources have a numeric (i.e. already
/// unlocked) value at the given level. A resource not yet unlocked at this
/// level (the column is blank, e.g. Sorcery Points before level 2) is
/// simply omitted.
List<ResourceDefinition> resourcesAtLevel(
  String classKey,
  SrdClass classData,
  int level,
) {
  final defs = _resourceDefsByClassKey[classKey];
  if (defs == null) return const [];
  final result = <ResourceDefinition>[];
  for (final (column, recovery) in defs) {
    final raw = classData.levelValue(level, column);
    final max = raw != null ? int.tryParse(raw) : null;
    if (max != null && max > 0) {
      result.add(
        ResourceDefinition(
          key: '${classKey}_$column',
          name: column,
          max: max,
          shortRestRecovery: recovery,
        ),
      );
    }
  }
  return result;
}

/// A second kind of class resource: features whose use count is written
/// into the "Class Features" column text (e.g. "Action Surge (one use)"),
/// not given its own table column like Second Wind/Rages/etc. Verified
/// against the actual feature text for every class - only Fighter's
/// Action Surge and Indomitable fit this "simple counter, no sub-choice"
/// shape; other classes have similar single-use-until-rest features
/// (Cleric's Divine Intervention, Wizard's Arcane Recovery, etc.) but
/// those are each one-off long-rest toggles rather than a scaling
/// counter, and are left as plain features rather than resources.
const _classThresholdResources = {
  'srd-2024_fighter-class': [
    ('Action Surge', 'full', [(2, 1), (17, 2)]),
    ('Indomitable', 'none', [(9, 1), (13, 2), (17, 3)]),
  ],
};

List<ResourceDefinition> classThresholdResourcesAtLevel(
  String classKey,
  int level,
) {
  final defs = _classThresholdResources[classKey];
  if (defs == null) return const [];
  final result = <ResourceDefinition>[];
  for (final (name, recovery, thresholds) in defs) {
    int? max;
    for (final (lvl, m) in thresholds) {
      if (level >= lvl) max = m;
    }
    if (max != null) {
      result.add(
        ResourceDefinition(
          key: '${classKey}_$name',
          name: name,
          max: max,
          shortRestRecovery: recovery,
        ),
      );
    }
  }
  return result;
}

/// Species traits that grant a limited use of something scaled to
/// Proficiency Bonus, all recovering on a rest exactly like a class
/// resource - verified against every species trait's own rules text (the
/// complete set with this exact "X times = Proficiency Bonus" shape in
/// the SRD; Elf/Gnome/Tiefling's lineage-granted spells are a different,
/// more varied shape and aren't covered here).
const _speciesResources = {
  'srd-2024_dragonborn-species': [('Breath Weapon', 'none')],
  'srd-2024_dwarf-species': [('Stonecunning', 'none')],
  'srd-2024_goliath-species': [('Giant Ancestry', 'none')],
  'srd-2024_orc-species': [('Adrenaline Rush', 'full')],
};

List<ResourceDefinition> speciesResourcesAtLevel(String speciesKey, int level) {
  final defs = _speciesResources[speciesKey];
  if (defs == null) return const [];
  final max = proficiencyBonusForLevel(level);
  return [
    for (final (name, recovery) in defs)
      ResourceDefinition(
        key: '${speciesKey}_$name',
        name: name,
        max: max,
        shortRestRecovery: recovery,
      ),
  ];
}

/// Species traits that are an attack, not just a limited use - Breath
/// Weapon is the only one in the SRD. Keyed like [_speciesResources], and
/// tied to that same resource by key. The numbers mirror the trait's own
/// text: "1d10 ... increases by 1d10 when you reach character levels 5
/// (2d10), 11 (3d10), and 17 (4d10)", a Dexterity save at "DC 8 plus your
/// Constitution modifier and Proficiency Bonus". [InnateAttack.damageType]
/// is only a fallback - see [innateAttackDamageType].
InnateAttack? _speciesInnateAttack(String speciesKey) => switch (speciesKey) {
  'srd-2024_dragonborn-species' => InnateAttack(
    name: 'Breath Weapon',
    levelDice: const [
      LevelDiceBreakpoint(level: 1, diceCount: 1),
      LevelDiceBreakpoint(level: 5, diceCount: 2),
      LevelDiceBreakpoint(level: 11, diceCount: 3),
      LevelDiceBreakpoint(level: 17, diceCount: 4),
    ],
    dieType: 'd10',
    damageType: 'Fire',
    saveAbility: 'dex',
    saveDcFormula: '8 + Proficiency Bonus + Constitution modifier',
    desc:
        'Replace an attack with a 15-ft Cone or 30-ft Line breath; each '
        'creature makes a Dexterity save or takes damage (half on success).',
    resourceKey: '${speciesKey}_Breath Weapon',
  ),
  _ => null,
};

/// Adds [c]'s species attack (Breath Weapon) if it's missing, and drops a
/// species attack left over from a species they no longer have (changed
/// via Edit). Hand-added innate attacks are left alone. Before this
/// existed only the bundled sample character ever had Breath Weapon - a
/// Dragonborn made through New Character got the uses but no attack.
void _syncSpeciesInnateAttacks(Character c) {
  final attack = c.speciesKey != null
      ? _speciesInnateAttack(c.speciesKey!)
      : null;
  final kept = c.innateAttacks.where((a) {
    final speciesKey = a.resourceKey.split('_${a.name}').first;
    final managed = _speciesInnateAttack(speciesKey) != null;
    return !managed || a.resourceKey == attack?.resourceKey;
  }).toList();
  if (attack != null && !kept.any((a) => a.resourceKey == attack.resourceKey)) {
    kept.add(attack);
  }
  c.innateAttacks = kept;
}

/// An innate attack's damage type - for Breath Weapon, the one set by the
/// character's Draconic Ancestry choice (Blue -> Lightning), read live from
/// the species' own choice table. Falls back to the stored
/// [InnateAttack.damageType] for an unresolvable species or no choice yet.
String innateAttackDamageType(Character c, InnateAttack attack) {
  final species = c.speciesKey != null
      ? srdCatalog.speciesByKey[c.speciesKey]
      : null;
  if (species == null || species.tables.isEmpty || c.speciesChoice == null) {
    return attack.damageType;
  }
  final matches = flattenSpeciesTableOptions(species.tables.first)
      .where((o) => o.name == c.speciesChoice);
  return matches.isEmpty ? attack.damageType : matches.first.detail;
}

/// Short, hand-written usage reminders for the resources above - seeing
/// e.g. "Action Surge: 1/1" without a reminder of what it actually does
/// isn't much more useful than not tracking it at all. Ported from the
/// web app's STATIC_RESOURCE_HINTS.
const _staticResourceHints = {
  'Second Wind': 'Bonus Action: regain 1d10 + Fighter level HP.',
  'Action Surge':
      'Take one additional action this turn (not the Magic action).',
  'Indomitable': "Failed a save? Reroll it, adding your Fighter level.",
  'Rages': 'Bonus Action: Resistance to B/P/S damage, extra Strength damage, adv. on Str checks/saves.',
  'Channel Divinity': 'Fuel a Channel Divinity option.',
  'Wild Shape': 'Bonus Action: shape-shift into a known Beast form.',
  'Focus Points':
      'Spend to fuel Flurry of Blows, Patient Defense, Step of the Wind, etc.',
  'Sorcery Points': 'Spend on Metamagic or to create/convert spell slots.',
  'Stonecunning': 'Bonus Action: gain Tremorsense 60 ft for 10 min (must be on/touching stone).',
  'Giant Ancestry': 'Use your chosen Giant boon.',
  'Adrenaline Rush':
      'Bonus Action Dash; gain temporary HP equal to your Proficiency Bonus.',
};

/// Damage dice (scaled by [attack.levelDice], the highest breakpoint at or
/// below the character's level) and save DC (evaluateFormula against
/// [attack.saveDcFormula]) for ANY innate attack - generalizes what used
/// to be hardcoded to Breath Weapon alone (1d10 at level 1, 2d10 at 5,
/// 3d10 at 11, 4d10 at 17; DC 8 + Con modifier + Proficiency Bonus).
class InnateAttackInfo {
  const InnateAttackInfo({
    required this.diceCount,
    required this.dieType,
    required this.saveDc,
  });
  final int diceCount;
  final String dieType;
  final int saveDc;
}

InnateAttackInfo innateAttackInfo(Character c, InnateAttack attack) {
  var diceCount = attack.levelDice.isNotEmpty
      ? attack.levelDice.first.diceCount
      : 0;
  for (final bp in attack.levelDice) {
    if (c.level >= bp.level) diceCount = bp.diceCount;
  }
  final saveDc = attack.saveDcFormula.isEmpty
      ? 0
      : evaluateFormula(attack.saveDcFormula, c);
  return InnateAttackInfo(
    diceCount: diceCount,
    dieType: attack.dieType,
    saveDc: saveDc,
  );
}

/// The usage reminder shown under a resource on the Combat tab - static
/// for most resources, computed for any resource tied to an innate attack
/// (matched by [resourceKey], not by name - generalizes what used to be
/// hardcoded to a `resourceName == 'Breath Weapon'` check).
String resourceHint(String resourceKey, String resourceName, Character c) {
  final matches = c.innateAttacks.where((a) => a.resourceKey == resourceKey);
  if (matches.isNotEmpty) {
    final attack = matches.first;
    if (attack.saveDcFormula.isEmpty) return attack.desc;
    final info = innateAttackInfo(c, attack);
    return '${attack.desc} DC ${info.saveDc}.';
  }
  return _staticResourceHints[resourceName] ?? '';
}

/// What [c] can do with [r], right where it's tracked: every one of their
/// features whose rules text mentions it - "Channel Divinity" finds the
/// class's own Channel Divinity (Divine Spark, Turn Undead) and subclass
/// options like Preserve Life or Sacred Weapon; "Focus Points" finds
/// Monk's Focus, Deflect Attacks, Stunning Strike, ...; "Giant Ancestry"
/// finds the trait, whose text is the chosen boon. Each is (name, its
/// short sheet text). Works the same for a homebrew feature that
/// mentions the resource by name.
List<(String, String)> resourceUses(Character c, Resource r) {
  // "Focus Points" / "Rages" are written "Focus Point" / "Rage" in most
  // rules text, so match the singular with an optional s.
  final name = r.name;
  final singular = name.endsWith('s') && !name.endsWith('ss')
      ? name.substring(0, name.length - 1)
      : name;
  final mention = RegExp('\\b${RegExp.escape(singular)}s?\\b');
  final seen = <String>{};
  return [
    for (final f in [...c.features, ...speciesTraitFeatures(c)])
      if (seen.add(f.name) &&
          (f.name == name ||
              mention.hasMatch(liveFeatureText(c, f) ?? f.desc ?? '')))
        (f.name, sheetText(c, f)),
  ];
}

/// One-line reminders of what each (non-Mastery) weapon property does,
/// shown on the weapon's row - condensed from the SRD's Weapon Properties.
const _weaponPropertyShort = {
  'Ammunition':
      'Needs ammunition to fire; drawing it is part of the attack. After a '
      'fight, spend 1 minute to recover half of what you fired.',
  'Finesse':
      'Use Strength or Dexterity for the attack and damage rolls (the same '
      'one for both).',
  'Heavy':
      'Disadvantage on attacks if your Strength (melee) or Dexterity '
      '(ranged) is below 13.',
  'Light':
      'After attacking with it on the Attack action, make one extra attack '
      'as a Bonus Action with a different Light weapon - no ability '
      'modifier to that damage unless it is negative.',
  'Loading':
      'Fire only one piece of ammunition per action, Bonus Action, or '
      'Reaction, however many attacks you have.',
  'Reach': '+5 feet of reach, including for Opportunity Attacks.',
  'Thrown':
      'Throw it for a ranged attack (a melee weapon uses the same ability '
      'as in melee); drawing it is part of the attack.',
  'Two-Handed': 'Needs two hands to attack with it.',
  'Versatile': 'One or two hands; the damage in parentheses is for two hands.',
};

/// (property, reminder) for each of [w]'s properties that has one -
/// "Versatile (1d10)" matches Versatile.
List<(String, String)> weaponPropertyNotes(Weapon w) => [
  for (final p in w.properties)
    if (_weaponPropertyShort[p.split(' (').first.trim()] case final note?)
      (p, note),
];

/// Every resource *name* [c]'s class/species could ever grant at some
/// level, whether or not it's currently unlocked - lets "not unlocked yet"
/// (e.g. Action Surge below level 2 - correctly dropped, not shown as
/// 0/0) be told apart from "a custom resource the player added by hand"
/// (kept untouched by recalculateClassResources).
Set<String> _managedResourceNames(Character c) => {
  ...?_resourceDefsByClassKey[c.classKey]?.map((d) => d.$1),
  ...?_classThresholdResources[c.classKey]?.map((d) => d.$1),
  ...?_speciesResources[c.speciesKey]?.map((d) => d.$1),
};

/// Whether [r] is a resource the player added by hand ("+ Add Resource")
/// rather than one derived from [c]'s class/species level tables - used
/// to gate the delete option, since a managed resource is regenerated by
/// recalculateClassResources and has no meaningful "delete" of its own.
bool isCustomResource(Character c, Resource r) =>
    !_managedResourceNames(c).contains(r.name) && !r.key.startsWith('item:');

/// Recomputes every resource (class + species) from the character's
/// current level and classKey/speciesKey - works for any ported class or
/// species, not just Fighter. A homebrew/uncataloged class or species is
/// simply skipped for its half of the recompute rather than guessed.
/// Existing `used` counts are clamped down if a resource's max shrank,
/// never reset outright, so this is always safe to call repeatedly.
void recalculateClassResources(Character c) {
  // First, so a Breath Weapon resource's hint (resourceHint) can find its
  // attack.
  _syncSpeciesInnateAttacks(c);
  final classData = c.classKey != null ? srdCatalog.byKey(c.classKey!) : null;
  final defs = [
    if (c.classKey != null && classData != null) ...[
      ...resourcesAtLevel(c.classKey!, classData, c.level),
      ...classThresholdResourcesAtLevel(c.classKey!, c.level),
    ],
    if (c.speciesKey != null)
      ...speciesResourcesAtLevel(c.speciesKey!, c.level),
  ];

  final updated = <Resource>[];
  for (final def in defs) {
    final existing = c.resources.where((r) => r.key == def.key);
    final used = existing.isEmpty ? 0 : existing.first.used;
    updated.add(
      Resource(
        key: def.key,
        name: def.name,
        max: def.max,
        used: used.clamp(0, def.max),
        hint: resourceHint(def.key, def.name, c),
        shortRestRecovery: def.shortRestRecovery,
      ),
    );
  }
  // Charges on carried homebrew/official magic items (a wand's 7 charges
  // regaining 1d6+1 at dawn) - tracked like any other resource, and
  // dropped when the item is.
  for (final item in c.inventory) {
    final entry = homebrewRepo.entries
        .where(
          (e) =>
              e.kind == 'magicItem' &&
              e.name.toLowerCase() == item.name.toLowerCase(),
        )
        .firstOrNull;
    final charges = entry?.data['charges'] as int?;
    if (entry == null || charges == null || charges <= 0) continue;
    final key = 'item:${entry.id}';
    if (updated.any((r) => r.key == key)) continue;
    final existing = c.resources.where((r) => r.key == key).firstOrNull;
    final recharge = entry.data['recharge'] as String? ?? 'long';
    updated.add(
      Resource(
        key: key,
        name: '${item.name} charges',
        max: charges,
        used: (existing?.used ?? 0).clamp(0, charges),
        hint: switch (recharge) {
          'dawn' => 'Regains charges at dawn (restore by hand).',
          'short' => 'Regains all charges on a Short or Long Rest.',
          'none' => "Doesn't recharge.",
          _ => 'Regains all charges on a Long Rest.',
        },
        shortRestRecovery: recharge == 'short' ? 'full' : 'none',
      ),
    );
  }
  final managedNames = _managedResourceNames(c);
  for (final r in c.resources) {
    if (!managedNames.contains(r.name) && !r.key.startsWith('item:')) {
      updated.add(r);
    }
  }
  c.resources = updated;
}

/// The 8 SRD classes that cast spells, mapped to their spellcasting
/// ability. Hardcoded rather than parsed from each class's free-text
/// "Primary Ability" trait (e.g. Paladin's is "Strength and Charisma,"
/// which names a martial ability alongside the casting one - not reliably
/// separable by text matching alone) since the domain is small and fixed
/// by the rules. Ported from the web app's SPELLCASTING_ABILITY_BY_CLASS_KEY.
const _spellcastingAbilityByClassKey = {
  'srd-2024_bard-class': 'cha',
  'srd-2024_cleric-class': 'wis',
  'srd-2024_druid-class': 'wis',
  'srd-2024_paladin-class': 'cha',
  'srd-2024_ranger-class': 'wis',
  'srd-2024_sorcerer-class': 'cha',
  'srd-2024_warlock-class': 'cha',
  'srd-2024_wizard-class': 'int',
};

String? spellcastingAbilityForClass(String classKey) =>
    _spellcastingAbilityByClassKey[classKey] ??
    // A homebrew class records its ability as a trait (homebrew_catalog).
    srdCatalog.byKey(classKey)?.traits['Spellcasting Ability'];

bool isSpellcastingClass(String classKey) =>
    spellcastingAbilityForClass(classKey) != null;

/// Turns on spellcasting for a character who doesn't have it yet - either
/// automatically for a spellcasting class at creation, or by hand via the
/// Spells tab's "Enable Spellcasting" (available for any class, the same
/// as the web app - a homebrew class/multiclass dip might cast even
/// though the free SRD class list doesn't know it).
void enableSpellcasting(Character c) {
  final ability = c.classKey != null
      ? spellcastingAbilityForClass(c.classKey!)
      : null;
  c.spellcasting = Spellcasting(ability: ability ?? 'int');
  recalculateSpellSlots(c);
}

/// Recomputes spell slot maximums from the character's current level,
/// against the real class level table - works for any ported caster,
/// including Warlock's flat Pact Magic slots (see SrdClass.spellSlotsAtLevel).
/// A slot level no longer present at the new level is dropped; one newly
/// unlocked is added at 0 used; an existing one's `used` is clamped down
/// if its max shrank. Does nothing if the character isn't a caster.
void recalculateSpellSlots(Character c) {
  final sc = c.spellcasting;
  if (sc == null || c.classKey == null) return;
  final classData = srdCatalog.byKey(c.classKey!);
  if (classData == null) return;
  final counts = classData.spellSlotsAtLevel(c.level);
  final updated = <int, SpellSlot>{};
  for (final entry in counts.entries) {
    final existing = sc.slots[entry.key];
    updated[entry.key] = SpellSlot(
      max: entry.value,
      used: (existing?.used ?? 0).clamp(0, entry.value),
    );
  }
  sc.slots = updated;
}

const _abilityShortLabels = {
  'str': 'Str',
  'dex': 'Dex',
  'con': 'Con',
  'int': 'Int',
  'wis': 'Wis',
  'cha': 'Cha',
};

/// The spellcasting ability's modifier - 0 for a non-caster. [ability]
/// overrides the class's (a lineage or Magic Initiate spell's own ability).
int spellcastingModifier(Character c, {String? ability}) {
  final key = ability ?? c.spellcasting?.ability;
  if (key == null) return 0;
  return modifierOf(c, key);
}

/// Spell save DC = 8 + spellcasting modifier + Proficiency Bonus, plus
/// any 'spellSaveDc' Effect (a homebrew/official item like a Rod of the
/// Pact Keeper, transcribed via My Homebrew).
int spellSaveDc(Character c, {String? ability}) =>
    8 +
    spellcastingModifier(c, ability: ability) +
    proficiencyBonusForLevel(c.level) +
    sumEffects(c, 'spellSaveDc');

/// Spell attack bonus = spellcasting modifier + Proficiency Bonus, plus
/// any 'spellAttack' Effect - same sources as [spellSaveDc].
int spellAttackBonus(Character c, {String? ability}) =>
    spellcastingModifier(c, ability: ability) +
    proficiencyBonusForLevel(c.level) +
    sumEffects(c, 'spellAttack');

SrdClass? _classData(Character c) =>
    c.classKey != null ? srdCatalog.byKey(c.classKey!) : null;

/// How many cantrips / prepared spells the class's own level table allows
/// at the character's current level - null when there's no such column
/// (Paladin/Ranger have no cantrips) or no SRD class to read it from (a
/// homebrew class that turned spellcasting on by hand), in which case the
/// Spells tab shows a plain count with no limit.
int? cantripLimit(Character c) {
  final base = _classData(c)?.cantripsAtLevel(c.level);
  if (base == null) return null;
  final order = optionPick(c, 'Divine Order') ?? optionPick(c, 'Primal Order');
  return order == 'Thaumaturge' || order == 'Magician' ? base + 1 : base;
}

int? preparedSpellLimit(Character c) =>
    _classData(c)?.preparedSpellsAtLevel(c.level);

/// Prepared spells that count against [preparedSpellLimit] - an
/// always-prepared spell (a subclass/species/feat grant) doesn't.
int preparedSpellCount(Character c) =>
    c.spellcasting?.spells
        .where((s) => s.prepared && !s.alwaysPrepared)
        .length ??
    0;

/// True for a Warlock's Pact Magic - see SrdClass.hasPactMagic.
bool usesPactMagic(Character c) => _classData(c)?.hasPactMagic ?? false;

/// The spell [key] resolves to, SRD or homebrew. A homebrew spell has no
/// SRD record, so one is synthesized from its HomebrewEntry (name/desc)
/// and [homebrewLevel] (KnownSpell.level - 0 for a homebrew cantrip).
/// Null only if the key matches nothing at all (homebrew deleted since).
SrdSpellRef? spellRefFor(String key, {int? homebrewLevel}) {
  final srd = srdCatalog.spellsByKey[key];
  if (srd != null) return srd;
  final homebrew = homebrewRepo.entries.where(
    (e) => e.kind == 'spell' && e.id == key,
  );
  if (homebrew.isEmpty) return null;
  // Its own stat block if it has one (My Homebrew's spell editor), else
  // just the name and text at the level it was added with.
  return homebrewSpellRef(homebrew.first) ??
      SrdSpellRef(
        key: key,
        name: homebrew.first.name,
        level: homebrewLevel ?? 1,
        school: 'Homebrew',
        desc: homebrew.first.desc,
      );
}

/// The resolved spell for a KnownSpell entry (its own homebrew level, if
/// any) - see [spellRefFor].
SrdSpellRef? knownSpellRef(KnownSpell s) =>
    spellRefFor(s.spellKey, homebrewLevel: s.level);

/// The class name as it appears in a spell's `classes` list ("Wizard") -
/// null for a character with no SRD class.
String? spellListClassName(Character c) => _classData(c)?.name;

/// The highest spell level the character currently has a slot for - 0 if
/// none yet (a Paladin/Ranger before level 1 slots, a homebrew caster).
int highestSlotLevel(Character c) {
  final levels = c.spellcasting?.slots.keys ?? const <int>[];
  return levels.isEmpty ? 0 : levels.reduce((a, b) => a > b ? a : b);
}

/// Slot levels a spell of [spellLevel] could be cast with right now -
/// every slot level at or above it with at least one slot left, lowest
/// first. Empty for a cantrip (no slot needed) or when everything's spent.
List<int> castableSlotLevels(Character c, int spellLevel) {
  if (spellLevel < 1) return const [];
  final slots = c.spellcasting?.slots ?? const <int, SpellSlot>{};
  return [
    for (final level in slots.keys.toList()..sort())
      if (level >= spellLevel && slots[level]!.used < slots[level]!.max) level,
  ];
}

/// Casts [spellKey]: spends one slot of [slotLevel] if given (null for a
/// cantrip or a Ritual casting, which spend none), and if the spell needs
/// Concentration, starts concentrating on it - replacing whatever was
/// held before, since only one Concentration spell can be up at a time.
/// Returns the spell key whose Concentration this cast ended, if any, so
/// the UI can say so.
String? castSpell(
  Character c,
  SrdSpellRef spell, {
  int? slotLevel,
  KnownSpell? freeCastFrom,
}) {
  final sc = c.spellcasting;
  if (sc == null) return null;
  if (freeCastFrom != null && freeCastFrom.freeCasts != atWill) {
    if (freeCastFrom.freeCastsUsed >= freeCastFrom.freeCasts) {
      throw StateError('No free casts left');
    }
    freeCastFrom.freeCastsUsed++;
  }
  if (slotLevel != null) {
    final slot = sc.slots[slotLevel];
    if (slot == null || slot.used >= slot.max) {
      throw StateError('No level $slotLevel slot left');
    }
    slot.used++;
  }
  if (!spell.concentration) return null;
  final previous = sc.concentratingOn;
  sc.concentratingOn = spell.key;
  return previous != null && previous != spell.key ? previous : null;
}

const findSteedKey = 'srd-2024_find-steed-spell';

/// Find Steed's creature types - each changes the Otherworldly Steed's
/// damage type and its once-per-Long-Rest bonus action.
const steedCreatureTypes = ['Celestial', 'Fey', 'Fiend'];

/// The mount [spellKey] summoned, or null.
Mount? summonedMount(Character c, String spellKey) =>
    c.mounts.where((m) => m.summonedBy == spellKey).firstOrNull;

/// Casting Find Steed: summons the Otherworldly Steed at [spellLevel]
/// (the slot's level) as a mount, replacing any steed the spell already
/// summoned - "If you already have a steed from this spell, the steed is
/// replaced by the new one." A replaced steed keeps the name the player
/// gave it, their notes, and whether it's being ridden; its stats,
/// traits, and bonus action are rebuilt for the new level and
/// [creatureType].
Mount summonSteed(
  Character c, {
  required int spellLevel,
  required String creatureType,
  String? ability,
}) {
  final attack = formatModifier(spellAttackBonus(c, ability: ability));
  final dc = spellSaveDc(c, ability: ability);
  final (damageType, bonusAction, bonusText) = switch (creatureType) {
    'Fey' => (
      'Psychic',
      'Fey Step',
      'The steed teleports, along with its rider, to an unoccupied space '
          'of your choice up to 60 feet away from itself.',
    ),
    'Fiend' => (
      'Necrotic',
      'Fell Glare',
      'DC $dc Wisdom save, one creature within 60 feet the steed can see. '
          'Failure: Frightened until the end of your next turn.',
    ),
    _ => (
      'Radiant',
      'Healing Touch',
      'One creature within 5 feet of the steed regains 2d8 + $spellLevel '
          'Hit Points.',
    ),
  };
  final previous = summonedMount(c, findSteedKey);
  final steed = Mount(
    name: previous?.name ?? 'Otherworldly Steed',
    armorClass: 10 + spellLevel,
    maxHp: 5 + 10 * spellLevel,
    speed: 60,
    flySpeed: spellLevel >= 4 ? 60 : 0,
    active: previous?.active ?? false,
    notes: previous?.notes ?? '',
    summonedBy: findSteedKey,
    creatureType: creatureType,
    rechargeAction: bonusAction,
    traits:
        '_Large $creatureType, level $spellLevel steed. Str 18, Dex 12, '
        'Con 14, Int 6, Wis 12, Cha 8. $spellLevel Hit Dice (d10). '
        'Telepathy 1 mile (with you only). Shares your Initiative._\n\n'
        '**Life Bond.** When you regain Hit Points from a level 1+ spell, '
        'the steed regains the same number if you are within 5 feet of '
        'it.\n\n'
        '**Otherworldly Slam.** $attack to hit, reach 5 ft. '
        'Hit: 1d8 + $spellLevel $damageType damage.\n\n'
        '**$bonusAction** (bonus action, once per Long Rest). $bonusText',
  );
  c.mounts = [
    for (final m in c.mounts)
      if (m != previous) m,
    steed,
  ];
  return steed;
}

void endConcentration(Character c) => c.spellcasting?.concentratingOn = null;

/// The Constitution save DC to keep Concentration after taking [damage]:
/// 10 or half the damage (rounded down), whichever is higher, capped at
/// 30 - per the 2024 Rules Glossary's Concentration entry.
int concentrationSaveDc(int damage) => (damage ~/ 2).clamp(10, 30);

/// A spell's attack/save and damage, read out of its own SRD text - for
/// the one-line summaries on the Spells tab and the PDF's spell tables.
/// Only as good as the text's phrasing: [dice]/[damageType] are null when
/// no "NdM Type damage" phrase is found (utility spells, healing, most
/// buffs), [isAttack]/[saveAbility] both unset when neither a spell attack
/// nor a saving throw is mentioned.
class SpellDamageInfo {
  const SpellDamageInfo({
    this.isAttack = false,
    this.saveAbility,
    this.dice,
    this.damageType,
    this.beams = 1,
  });
  final bool isAttack;
  final String? saveAbility; // ability key, e.g. 'dex'
  final String? dice; // e.g. "2d10" - already scaled for a cantrip
  final String? damageType; // e.g. "Fire"
  final int beams; // Eldritch Blast's separate rays

  bool get isEmpty => !isAttack && saveAbility == null && dice == null;
}

const _abilityNameToKeyLower = {
  'strength': 'str',
  'dexterity': 'dex',
  'constitution': 'con',
  'intelligence': 'int',
  'wisdom': 'wis',
  'charisma': 'cha',
};

/// Reads [spell]'s attack/save/damage out of its SRD text (see
/// [SpellDamageInfo]). A cantrip's dice are scaled to [characterLevel]
/// from its own "At Higher Levels" text, which the SRD always phrases as
/// "levels 5 (2d10), 11 (3d10), and 17 (4d10)" (or, for Eldritch Blast,
/// as extra beams at those same levels).
SpellDamageInfo spellDamageInfo(SrdSpellRef spell, int characterLevel) {
  final desc = spell.desc;
  final isAttack = RegExp(r'spell attack', caseSensitive: false).hasMatch(desc);
  // "a Dexterity saving throw" - singular with an article, which is how
  // the SRD phrases a save the spell forces. Skips "Advantage on Dexterity
  // saving throws" (Haste, Beacon of Hope), which is a buff, not a DC.
  final saveMatch = RegExp(
    r'\b(?:a|an) (Strength|Dexterity|Constitution|Intelligence|Wisdom|Charisma) saving throw(?!s)',
  ).firstMatch(desc);
  final damageMatch = RegExp(r'(\d+d\d+(?: \+ \d+)?) ([A-Z][a-z]+) damage')
      .firstMatch(desc);
  var dice = damageMatch?.group(1);
  var beams = 1;

  if (spell.level == 0 && dice != null) {
    final tier = characterLevel >= 17
        ? 3
        : characterLevel >= 11
        ? 2
        : characterLevel >= 5
        ? 1
        : 0;
    final higher = spell.higherLevel ?? '';
    final tierDice = RegExp(
      r'levels 5 \((\d+d\d+)\), 11 \((\d+d\d+)\), and 17 \((\d+d\d+)\)',
    ).firstMatch(higher);
    if (tier > 0 && tierDice != null) {
      dice = tierDice.group(tier);
    } else if (RegExp(r'beams at level 5').hasMatch(higher)) {
      beams = tier + 1;
    }
  }

  return SpellDamageInfo(
    isAttack: isAttack,
    saveAbility: isAttack
        ? null
        : _abilityNameToKeyLower[saveMatch?.group(1)?.toLowerCase()],
    dice: dice,
    damageType: damageMatch?.group(2),
    beams: beams,
  );
}

/// The "to hit or DC" half of a spell's summary - "+5" / "DC 13 Dex" -
/// or '' for a spell with neither.
String spellAttackOrDcText(
  Character c,
  SpellDamageInfo info, {
  String? ability,
}) {
  if (info.isAttack) {
    return formatModifier(spellAttackBonus(c, ability: ability));
  }
  if (info.saveAbility != null) {
    return 'DC ${spellSaveDc(c, ability: ability)} '
        '${_abilityShortLabels[info.saveAbility]}';
  }
  return '';
}

/// The damage half - "2d10 Fire", "1d10 Force ×2" (Eldritch Blast's
/// beams) - or '' for a spell with no damage phrase found.
String spellDamageText(SpellDamageInfo info) {
  if (info.dice == null) return '';
  final beams = info.beams > 1 ? ' ×${info.beams}' : '';
  return '${info.dice} ${info.damageType ?? ''}'.trim() + beams;
}

/// One line combining both - "+5 to hit · 2d10 Fire", "DC 13 Dex · 8d6
/// Fire" - or '' when the spell's text yields nothing.
String spellSummary(Character c, SrdSpellRef spell, {String? ability}) {
  final info = spellDamageInfo(spell, c.level);
  final hit = spellAttackOrDcText(c, info, ability: ability);
  return [
    if (hit.isNotEmpty) info.isAttack ? '$hit to hit' : hit,
    if (spellDamageText(info).isNotEmpty) spellDamageText(info),
  ].join(' · ');
}

/// What a level change from [oldLevel] to [c]'s current level did to
/// their spellcasting, as readable lines - "Cantrips: 3 → 4", "Prepared
/// Spells: 5 → 6", "New spell slot level: 3" - for the level-up summary
/// and History. Empty for a non-caster or a level that changed nothing.
List<String> spellcastingLevelUpNotes(
  Character c,
  int oldLevel,
  Set<int> oldSlotLevels,
) {
  if (c.spellcasting == null) return const [];
  final classData = _classData(c);
  final notes = <String>[];
  final oldCantrips = classData?.cantripsAtLevel(oldLevel);
  final newCantrips = classData?.cantripsAtLevel(c.level);
  if (newCantrips != null && newCantrips != oldCantrips) {
    notes.add('Cantrips: ${oldCantrips ?? 0} → $newCantrips');
  }
  final oldPrepared = classData?.preparedSpellsAtLevel(oldLevel);
  final newPrepared = classData?.preparedSpellsAtLevel(c.level);
  if (newPrepared != null && newPrepared != oldPrepared) {
    notes.add('Prepared Spells: ${oldPrepared ?? 0} → $newPrepared');
  }
  final newSlotLevels =
      c.spellcasting!.slots.keys
          .where((l) => !oldSlotLevels.contains(l))
          .toList()
        ..sort();
  for (final level in newSlotLevels) {
    notes.add('New spell slot level: $level');
  }
  return notes;
}

/// New Pending Choices to surface when a character's level increases from
/// [oldLevel] to [newLevel] - currently just Ability Score Improvement,
/// detected from the class's own level table (works for any ported class,
/// not just Fighter, since it only reads the "Class Features" column
/// text). Doesn't return one already present in `c.pendingChoices`, so
/// it's safe to call on every level change without creating duplicates.
List<PendingChoice> pendingChoicesForLevelUp(
  Character c,
  int oldLevel,
  int newLevel,
) {
  if (c.classKey == null || newLevel <= oldLevel) return const [];
  final asiLevels = srdCatalog.abilityScoreImprovementLevels(c.classKey!);
  final existingIds = c.pendingChoices.map((p) => p.id).toSet();
  return [
    for (final lvl in asiLevels)
      if (lvl > oldLevel && lvl <= newLevel)
        if (!existingIds.contains('${c.classKey}-asi-$lvl'))
          PendingChoice(
            id: '${c.classKey}-asi-$lvl',
            label: 'Level $lvl: Ability Score Improvement',
            kind: 'asi',
          ),
  ];
}

/// Resolves a Pending Choice with a chosen feat: removes the choice and
/// grants the feat via [grantFeat] - which applies the chosen ability
/// score deltas too, if it's specifically an Ability Score Improvement
/// (that feat alone doesn't say which scores go up; the picker UI collects
/// that), and logs the grant to history.
void resolvePendingChoice(
  Character c,
  String choiceId,
  GrantedFeature feat, {
  Map<String, int>? abilityScoreDeltas,
}) {
  c.pendingChoices = c.pendingChoices.where((p) => p.id != choiceId).toList();
  grantFeat(c, feat, abilityScoreDeltas: abilityScoreDeltas);
}

/// Class/subclass features that don't fully resolve themselves - they hand
/// the player a feat pick instead. Verified as the complete set of such
/// names across all 12 SRD classes and their subclasses. The mapped value
/// restricts the feat picker to that SRD category; null means any
/// category is offered, matching the 2024 rule that an Ability Score
/// Improvement slot can become "another feat of your choice for which you
/// qualify," not just a General feat. Ported from the web app's
/// FEAT_CHOICE_TRIGGERS.
const _featChoiceTriggers = {
  'Fighting Style': 'Fighting Style Feat',
  'Additional Fighting Style': 'Fighting Style Feat',
  'Ability Score Improvement': null,
  'Epic Boon': 'Epic Boon Feat',
};

/// Whether a class/subclass feature is choice-driven (see above) - never
/// auto-granted as a plain GrantedFeature. Every class's subclass-choice
/// feature is also excluded here (always literally named "[Class Name]
/// Subclass" in the SRD data, e.g. "Fighter Subclass," "Wizard Subclass"),
/// since that's handled by its own Pending Choice + subclass picker.
bool _isChoiceFeature(String name) =>
    _featChoiceTriggers.containsKey(name) || name.endsWith(' Subclass');

/// Shared by featChoicePendingChoices and resolveSubclassChoice: builds a
/// Pending Choice for each choice-driven feature (Fighting Style, Epic
/// Boon, ...) in [features] newly reached between [oldLevel] and
/// [newLevel], skipping anything already pending under the same id.
/// [idPrefix] is the class or subclass key, so a class feature and a
/// same-named subclass feature (there are none today, but nothing stops
/// a homebrew or future one) never collide.
List<PendingChoice> _choiceFeatureChoices(
  String idPrefix,
  Iterable<SrdClassFeature> features,
  int oldLevel,
  int newLevel,
  Set<String> existingIds,
) => [
  for (final feature in features)
    if (feature.level > oldLevel && feature.level <= newLevel)
      if (feature.name != 'Ability Score Improvement')
        if (_featChoiceTriggers.containsKey(feature.name))
          if (!existingIds.contains(
            '$idPrefix-${feature.name}-${feature.level}',
          ))
            PendingChoice(
              id: '$idPrefix-${feature.name}-${feature.level}',
              label: 'Level ${feature.level}: ${feature.name}',
              featCategory: _featChoiceTriggers[feature.name],
            ),
];

/// New Pending Choices for whichever of a class's (or its already-chosen
/// subclass's) newly-reached features are choice-driven (Fighting Style,
/// Additional Fighting Style, Epic Boon, ...) - the counterpart to
/// classFeaturesForLevelUp/subclassFeaturesForLevelUp, which both skip
/// granting these same entries as inert features. Deliberately excludes
/// Ability Score Improvement, which pendingChoicesForLevelUp already
/// covers (reading it off the level table directly, since it's not
/// always phrased as a "Class Features" list entry) - including it here
/// too would double up that Pending Choice. Used both at character
/// creation (oldLevel: 0) and on a level-up. A subclass feature only
/// contributes once a subclass is actually chosen (c.subclassKey set) -
/// resolveSubclassChoice handles the one-time backfill of subclass-level
/// choice features reached before that point.
List<PendingChoice> featChoicePendingChoices(
  Character c,
  int oldLevel,
  int newLevel,
) {
  if (c.classKey == null || newLevel <= oldLevel) return const [];
  final classData = srdCatalog.byKey(c.classKey!);
  final existingIds = c.pendingChoices.map((p) => p.id).toSet();
  final choices = [
    ..._choiceFeatureChoices(
      c.classKey!,
      classData?.features ?? const [],
      oldLevel,
      newLevel,
      existingIds,
    ),
  ];
  final subclass = chosenSubclass(c);
  if (subclass != null) {
    choices.addAll(
      _choiceFeatureChoices(
        subclass.key,
        subclass.features,
        oldLevel,
        newLevel,
        existingIds,
      ),
    );
  }
  return choices;
}

/// New class features to grant when a character's level increases from
/// [oldLevel] to [newLevel] (or from 0, for a freshly created level-1
/// character) - read straight from classes.json's `features` list for
/// whatever class is set on [c], skipping choice-driven entries (see
/// above) and anything already granted (so repeated level corrections
/// never duplicate). Works for any ported class, not just Fighter.
List<GrantedFeature> classFeaturesForLevelUp(
  Character c,
  int oldLevel,
  int newLevel,
) {
  if (c.classKey == null || newLevel <= oldLevel) return const [];
  final classData = srdCatalog.byKey(c.classKey!);
  final existingNames = c.features.map((f) => f.name).toSet();
  return [
    for (final feature in classData?.features ?? const [])
      if (feature.level > oldLevel && feature.level <= newLevel)
        if (!_isChoiceFeature(feature.name))
          if (!existingNames.contains(feature.name))
            GrantedFeature(
              name: feature.name,
              source: 'class',
              desc: feature.desc,
            ),
  ];
}

/// The live SRD text for a granted feature/feat, matched by name against
/// whichever catalog it should have come from (species trait, class
/// feature, subclass feature, homebrew feat, or SRD feat) - falls back to
/// the feature's own stored `desc` if it's uncataloged or the name isn't
/// found anywhere. A stored desc can go stale exactly the way Breath
/// Weapon's did: hand-seeded data written before this text was ported, or
/// the SRD text itself corrected afterward (e.g. Champion's Remarkable
/// Athlete, whose pre-port sample data still had the 2014 "half your
/// Proficiency Bonus" wording instead of the real 2024 "Advantage on
/// Initiative rolls" text) - this is the general fix, applied everywhere a
/// feature/feat is displayed rather than patched one trait at a time.
///
/// The homebrew check runs BEFORE srdCatalog.featsByKey (same
/// override-wins ordering as liveFeatureEffects) - a homebrew feat named
/// exactly like a real SRD feat overrides its text, not the other way
/// round, matching how effects already work for that same collision.
String? liveFeatureText(Character c, GrantedFeature feature) {
  final species = c.speciesKey != null
      ? srdCatalog.speciesByKey[c.speciesKey]
      : null;
  for (final trait in species?.traits ?? const []) {
    if (trait.name == feature.name) return trait.desc;
  }
  final classData = c.classKey != null ? srdCatalog.byKey(c.classKey!) : null;
  for (final f in classData?.features ?? const []) {
    if (f.name == feature.name) return f.desc;
  }
  for (final f in chosenSubclass(c)?.features ?? const []) {
    if (f.name == feature.name) return f.desc;
  }
  final homebrewFeat = homebrewRepo.entries.where(
    (e) =>
        e.kind == 'feat' && e.name.toLowerCase() == feature.name.toLowerCase(),
  );
  if (homebrewFeat.isNotEmpty) return homebrewFeat.first.desc;
  final featName = baseFeatName(feature.name);
  for (final feat in srdCatalog.featsByKey.values) {
    if (feat.name == featName) return feat.fullDescription;
  }
  return feature.desc;
}

/// Which catalog [feature] belongs to, as the first half of its sheet text
/// key: the species, class, or subclass key, "homebrew" for a homebrew
/// feat, "feats" for an SRD feat, or "custom" for anything else (a feature
/// added by hand). Same lookup order as [liveFeatureText], so the short
/// text always describes the same feature the full text does.
String sheetTextScope(Character c, GrantedFeature feature) {
  final species = c.speciesKey != null
      ? srdCatalog.speciesByKey[c.speciesKey]
      : null;
  if (species?.traits.any((t) => t.name == feature.name) ?? false) {
    return species!.key;
  }
  final classData = c.classKey != null ? srdCatalog.byKey(c.classKey!) : null;
  if (classData?.features.any((f) => f.name == feature.name) ?? false) {
    return classData!.key;
  }
  final subclass = chosenSubclass(c);
  if (subclass?.features.any((f) => f.name == feature.name) ?? false) {
    return subclass!.key;
  }
  if (_homebrewFeat(feature.name) != null) return 'homebrew';
  // A pick added as its own feature (an Eldritch Invocation, a Metamagic
  // option) - its source is the option set.
  if (featureOptionSet(c, feature.source)?.kind == OptionKind.feature) {
    return 'option:${feature.source}';
  }
  final featName = baseFeatName(feature.name);
  if (srdCatalog.featsByKey.values.any((f) => f.name == featName)) {
    return 'feats';
  }
  return 'custom';
}

HomebrewEntry? _homebrewFeat(String name) {
  final matches = homebrewRepo.entries.where(
    (e) => e.kind == 'feat' && e.name.toLowerCase() == name.toLowerCase(),
  );
  return matches.isEmpty ? null : matches.first;
}

/// The key a player's own sheet text edit is saved under - see
/// SheetTextRepository.
String sheetTextKey(Character c, GrantedFeature feature) =>
    '${sheetTextScope(c, feature)}|${feature.name}';

/// The sheet text [feature] gets when the player hasn't written their own:
/// a homebrew feat's own sheet text, or this app's bundled summary of an
/// SRD feature (assets/srd/sheet-text.json). Null when there's neither -
/// a hand-added feature, a homebrew feat with no sheet text yet.
String? defaultSheetText(Character c, GrantedFeature feature) {
  // A feature specialized by a single pick (Divine Order: Protector) shows
  // the pick's own line.
  final picked = optionSheetText(c, feature);
  if (picked != null) return picked;
  final scope = sheetTextScope(c, feature);
  if (scope.startsWith('option:')) {
    return srdCatalog
        .sheetText['options']?['${scope.substring(7)}|${feature.name}'];
  }
  if (scope == 'homebrew') {
    final text = _homebrewFeat(feature.name)!.shortDesc;
    return text.isEmpty ? null : text;
  }
  final text =
      srdCatalog.sheetText[scope]?[scope == 'feats'
          ? baseFeatName(feature.name)
          : feature.name];
  if (text != null) return text;
  // A fighting style stored as a feature named after the feat it grants
  // ("Fighting Style: Great Weapon Fighting", as the sample character
  // has it) - use that feat's text.
  const prefix = 'Fighting Style: ';
  if (feature.name.startsWith(prefix)) {
    return srdCatalog.sheetText['feats']?[feature.name.substring(
      prefix.length,
    )];
  }
  return null;
}

/// What the exported PDF sheet prints for [feature]: the player's own edit
/// if they've made one, else [defaultSheetText], else the full rules text
/// as a last resort (it may not fit - the sheet drops what doesn't).
String sheetText(Character c, GrantedFeature feature) =>
    sheetTextRepo[sheetTextKey(c, feature)] ??
    defaultSheetText(c, feature) ??
    liveFeatureText(c, feature) ??
    feature.desc ??
    '';

/// [c]'s species traits, as features: every trait of their SRD species
/// (read live, the way the Overview tab shows them - New Character never
/// stores species traits on the character), plus any species-sourced
/// feature stored on the character that the SRD list doesn't already
/// cover (a hand-seeded or homebrew-species trait).
List<GrantedFeature> speciesTraitFeatures(Character c) {
  final species = c.speciesKey != null
      ? srdCatalog.speciesByKey[c.speciesKey]
      : null;
  final traits = [
    for (final t in species?.traits ?? const <SrdSpeciesTrait>[])
      GrantedFeature(name: t.name, source: 'species', desc: t.desc),
  ];
  final names = traits.map((t) => t.name).toSet();
  return [
    ...traits,
    for (final f in c.features)
      if (f.source == 'species' && !names.contains(f.name)) f,
  ];
}

/// The character's class's subclass options, for the subclass picker UI -
/// just one in the free SRD (Champion for Fighter, Evoker for Wizard,
/// ...), but exposed as a list since a homebrew ruleset could offer more,
/// and the picker UI shouldn't assume there's only ever one.
List<SrdSubclass> subclassOptionsFor(Character c) {
  if (c.classKey == null) return const [];
  return srdCatalog.subclassesFor(c.classKey!);
}

/// The subclass [c] has chosen, SRD or homebrew - null before level 3 or
/// if it no longer resolves.
SrdSubclass? chosenSubclass(Character c) => c.classKey == null
    ? null
    : srdCatalog.subclassByKey(c.classKey!, c.subclassKey);

/// Surfaces a "[Class] Subclass" Pending Choice once the character's
/// level reaches their class's subclass level (3 for every SRD class) and
/// none is chosen yet. The free SRD ships exactly one subclass per class,
/// but it's deliberately never auto-assigned - the player always resolves
/// this explicitly through the subclass picker (see
/// resolveSubclassChoice), the same way Ability Score Improvement and
/// Fighting Style are never auto-resolved either.
List<PendingChoice> subclassPendingChoices(
  Character c,
  int oldLevel,
  int newLevel,
) {
  if (c.classKey == null || c.subclassKey != null || newLevel <= oldLevel) {
    return const [];
  }
  final classData = srdCatalog.byKey(c.classKey!);
  final choiceLevel = classData?.subclassChoiceLevel;
  if (choiceLevel == null ||
      newLevel < choiceLevel ||
      oldLevel >= choiceLevel) {
    return const [];
  }
  final id = '${c.classKey}-subclass';
  if (c.pendingChoices.any((p) => p.id == id)) return const [];
  return [
    PendingChoice(
      id: id,
      label: 'Level $choiceLevel: ${classData?.name ?? 'Class'} Subclass',
      kind: 'subclass',
    ),
  ];
}

/// Resolves a "[Class] Subclass" Pending Choice: removes the choice,
/// assigns [subclassKey], updates classLabel, grants every non-choice
/// subclass feature already reached at the character's current level, and
/// adds a Pending Choice for any reached subclass feature that's itself
/// choice-driven (e.g. Champion's Additional Fighting Style at level 7) -
/// never auto-grants those, same as an ordinary level-up never would.
void resolveSubclassChoice(Character c, String choiceId, String subclassKey) {
  c.pendingChoices = c.pendingChoices.where((p) => p.id != choiceId).toList();
  if (c.classKey == null) return;
  final subclass = srdCatalog.subclassByKey(c.classKey!, subclassKey);
  if (subclass == null) return;
  final beforeWeapons = weaponsSnapshot(c);
  c.subclassKey = subclass.key;
  if (!c.classLabel.contains(subclass.name)) {
    c.classLabel = '${c.classLabel} · ${subclass.name}';
  }
  final existingNames = c.features.map((f) => f.name).toSet();
  final newFeatures = [
    for (final feature in subclass.features)
      if (feature.level <= c.level)
        if (!_isChoiceFeature(feature.name))
          if (!existingNames.contains(feature.name))
            GrantedFeature(
              name: feature.name,
              source: 'subclass',
              desc: feature.desc,
            ),
  ];
  c.features = [...c.features, ...newFeatures];
  final existingChoiceIds = c.pendingChoices.map((p) => p.id).toSet();
  final newChoiceFeatures = _choiceFeatureChoices(
    subclass.key,
    subclass.features,
    0,
    c.level,
    existingChoiceIds,
  );
  c.pendingChoices = [...c.pendingChoices, ...newChoiceFeatures];
  c.pendingChoices = [
    ...c.pendingChoices,
    ...featureOptionPendingChoices(c, 0, c.level),
  ];
  syncGrantedSpells(c);
  refreshMaxHp(c);
  final afterWeapons = weaponsSnapshot(c);
  final details = <String>[];
  if (newFeatures.isNotEmpty) {
    details.add('New features: ${newFeatures.map((f) => f.name).join(', ')}.');
  }
  if (newChoiceFeatures.isNotEmpty) {
    details.add(
      'New choices to make: ${newChoiceFeatures.map((p) => p.label).join(', ')}.',
    );
  }
  if (afterWeapons.isNotEmpty && afterWeapons != beforeWeapons) {
    details.add('Weapons: $afterWeapons.');
  }
  logHistory(
    c,
    'Subclass chosen: ${subclass.name} (Level ${c.level})',
    detail: details.isEmpty ? null : details.join(' '),
  );
}

/// New subclass features to grant when a character who has already chosen
/// their subclass (see resolveSubclassChoice) crosses a level with
/// newly-reached subclass features. Does nothing until a subclass is
/// actually chosen - never auto-assigns one, even for a class whose free
/// SRD data only offers a single option. Skips choice-driven subclass
/// features (e.g. Champion's Additional Fighting Style) exactly like
/// classFeaturesForLevelUp skips choice-driven class features - those are
/// surfaced as a Pending Choice by featChoicePendingChoices instead of
/// being silently auto-granted as an inert feature.
void subclassFeaturesForLevelUp(Character c, int oldLevel, int newLevel) {
  if (c.classKey == null || c.subclassKey == null || newLevel <= oldLevel) {
    return;
  }
  final subclass = chosenSubclass(c);
  if (subclass == null) return;
  final existingNames = c.features.map((f) => f.name).toSet();
  final newFeatures = [
    for (final feature in subclass.features)
      if (feature.level > oldLevel && feature.level <= newLevel)
        if (!_isChoiceFeature(feature.name))
          if (!existingNames.contains(feature.name))
            GrantedFeature(
              name: feature.name,
              source: 'subclass',
              desc: feature.desc,
            ),
  ];
  c.features = [...c.features, ...newFeatures];
}

/// One-time repair for a character saved before featChoicePendingChoices
/// was wired into levelUpOneLevel/the manual level-correction path/
/// resolveSubclassChoice's backfill: a choice-driven feature (Fighting
/// Style, Additional Fighting Style, Epic Boon) crossed on a level-up
/// could have been silently auto-granted as an inert GrantedFeature
/// instead of surfacing a Pending Choice the player actually gets to
/// resolve - exactly the bug a Champion Fighter hit at level 7's
/// Additional Fighting Style. Detects any such already-granted inert
/// feature by name against the class's/subclass's real feature list,
/// removes it, and replaces it with the Pending Choice it should have
/// been - same id scheme featChoicePendingChoices uses, so once resolved
/// through the normal picker it can never double up. Idempotent and safe
/// to call on every load: a character with nothing to repair (including
/// one that never had the bug, or was already repaired) does nothing.
/// Called from CharacterRepository.init() alongside
/// recalculateClassResources, the other per-load data-freshness pass.
void repairMissingFeatChoices(Character c) {
  if (c.classKey == null) return;
  final classData = srdCatalog.byKey(c.classKey!);
  if (classData == null) return;
  final subclass = chosenSubclass(c);
  final sourced = [
    for (final f in classData.features) (c.classKey!, f),
    if (subclass != null)
      for (final f in subclass.features) (subclass.key, f),
  ];
  final existingChoiceIds = c.pendingChoices.map((p) => p.id).toSet();
  final removeNames = <String>{};
  final newChoices = <PendingChoice>[];
  for (final (idPrefix, feature) in sourced) {
    if (!_featChoiceTriggers.containsKey(feature.name)) continue;
    if (!c.features.any((f) => f.name == feature.name)) continue;
    final id = '$idPrefix-${feature.name}-${feature.level}';
    if (existingChoiceIds.contains(id)) continue;
    removeNames.add(feature.name);
    newChoices.add(
      PendingChoice(
        id: id,
        label: 'Level ${feature.level}: ${feature.name}',
        featCategory: _featChoiceTriggers[feature.name],
      ),
    );
  }
  if (newChoices.isEmpty) return;
  c.features = c.features.where((f) => !removeNames.contains(f.name)).toList();
  c.pendingChoices = [...c.pendingChoices, ...newChoices];
  logHistory(
    c,
    'Data repair: recovered a missing choice',
    detail:
        'A previous app version silently granted '
        '${newChoices.map((p) => p.label.split(': ').last).join(', ')} '
        'as a plain feature instead of letting you pick a feat for it. '
        "Converted back into a Pending Choice - resolve it from the "
        'Features tab.',
  );
}

/// What changed when [levelUpOneLevel] advanced a character by one level -
/// enough to show a "here's what's new" summary without the caller
/// re-deriving any of it itself.
class LevelUpSummary {
  const LevelUpSummary({
    required this.oldLevel,
    required this.newLevel,
    required this.oldMaxHp,
    required this.newMaxHp,
    required this.newFeatureNames,
    required this.newPendingChoices,
    this.spellcastingNotes = const [],
  });
  final int oldLevel;
  final int newLevel;
  final int oldMaxHp;
  final int newMaxHp;

  /// Every newly-granted class/subclass feature's name, in the order
  /// granted - class features first, then subclass features.
  final List<String> newFeatureNames;

  /// Every PendingChoice this level-up added (ASI/feat-choice features,
  /// and a subclass choice at whatever level the class first offers one) -
  /// already appended to [Character.pendingChoices] too; kept here as its
  /// own list so a guided walkthrough can resolve exactly these, in order,
  /// without hunting through choices that were already pending before.
  final List<PendingChoice> newPendingChoices;

  /// What changed about the character's spellcasting - see
  /// spellcastingLevelUpNotes. Empty for a non-caster.
  final List<String> spellcastingNotes;
}

/// Advances [c] by exactly one level - the single path a guided "Level
/// Up" action goes through, running every step a level gain touches (HP,
/// class/species resource maximums, newly-reached class/subclass
/// features, and any newly-surfaced Pending Choices - Ability Score
/// Improvement, a feat-choice feature, a subclass pick) in the same order
/// and via the same rules.dart functions the free-text "correct this
/// character's level" edit already used (see character_form_screen.dart's
/// _save) - this just packages it as its own reusable step advancing
/// exactly one level, plus a summary of what actually changed, instead of
/// leaving the caller to re-derive that from a before/after diff.
LevelUpSummary levelUpOneLevel(Character c, {int? hpRoll}) {
  final oldLevel = c.level;
  final newLevel = oldLevel + 1;
  final oldMaxHp = c.maxHp;
  final oldProficiencyBonus = proficiencyBonusForLevel(oldLevel);
  final beforeWeapons = weaponsSnapshot(c);
  final oldSlotLevels = c.spellcasting?.slots.keys.toSet() ?? const <int>{};

  c.level = newLevel;
  if (hpRoll != null) {
    c.hitPointRolls = {...c.hitPointRolls, newLevel: hpRoll};
  }
  c.hitDiceTotal = newLevel;
  refreshMaxHp(c);
  recalculateClassResources(c);

  final newChoices = pendingChoicesForLevelUp(c, oldLevel, newLevel);
  c.pendingChoices = [...c.pendingChoices, ...newChoices];

  final newClassFeatures = classFeaturesForLevelUp(c, oldLevel, newLevel);
  c.features = [...c.features, ...newClassFeatures];

  final newSubclassChoices = subclassPendingChoices(c, oldLevel, newLevel);
  c.pendingChoices = [...c.pendingChoices, ...newSubclassChoices];

  final newFeatChoices = featChoicePendingChoices(c, oldLevel, newLevel);
  c.pendingChoices = [...c.pendingChoices, ...newFeatChoices];

  final featureNamesBefore = c.features.map((f) => f.name).toSet();
  subclassFeaturesForLevelUp(c, oldLevel, newLevel);
  final newSubclassFeatureNames = c.features
      .where((f) => !featureNamesBefore.contains(f.name))
      .map((f) => f.name)
      .toList();

  recalculateSpellSlots(c);
  final newOptionChoices = featureOptionPendingChoices(c, oldLevel, newLevel);
  c.pendingChoices = [...c.pendingChoices, ...newOptionChoices];
  syncGrantedSpells(c);
  final spellNotes = spellcastingLevelUpNotes(c, oldLevel, oldSlotLevels);

  final newFeatureNames = [
    ...newClassFeatures.map((f) => f.name),
    ...newSubclassFeatureNames,
  ];
  final allNewChoices = [
    ...newChoices,
    ...newSubclassChoices,
    ...newFeatChoices,
    ...newOptionChoices,
  ];
  final newProficiencyBonus = proficiencyBonusForLevel(newLevel);
  final afterWeapons = weaponsSnapshot(c);
  logHistory(
    c,
    'Leveled up: $oldLevel → $newLevel',
    detail:
        'Max HP: $oldMaxHp → ${c.maxHp}.'
        '${newProficiencyBonus == oldProficiencyBonus ? '' : ' Proficiency Bonus: ${formatModifier(oldProficiencyBonus)} → ${formatModifier(newProficiencyBonus)}.'}'
        '${newFeatureNames.isEmpty ? '' : ' New features: ${newFeatureNames.join(', ')}.'}'
        '${allNewChoices.isEmpty ? '' : ' New choices to make: ${allNewChoices.map((p) => p.label).join(', ')}.'}'
        '${spellNotes.isEmpty ? '' : ' Spellcasting: ${spellNotes.join(', ')}.'}'
        '${afterWeapons.isEmpty || afterWeapons == beforeWeapons ? '' : ' Weapons: $afterWeapons.'}',
  );

  return LevelUpSummary(
    oldLevel: oldLevel,
    newLevel: newLevel,
    oldMaxHp: oldMaxHp,
    newMaxHp: c.maxHp,
    newFeatureNames: newFeatureNames,
    newPendingChoices: allNewChoices,
    spellcastingNotes: spellNotes,
  );
}
