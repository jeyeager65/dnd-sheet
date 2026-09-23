/// A flat numeric modifier a feat or magic item can contribute to some
/// piece of derived math - the data-driven replacement for hardcoded
/// checks like `hasFeat('Alert')`. Deliberately narrow: [formula] is
/// evaluated by domain/rules.dart's evaluateFormula (flat integers, no
/// dice terms), so this only ever models a bonus/penalty to one of the
/// character's own rolls, DCs, or incoming damage - never
/// Advantage/Disadvantage, a dice roll, or anything affecting a different
/// creature. See rules.dart's "Explicit scope boundary" notes for why
/// those stay as plain desc text instead.
class Effect {
  const Effect({required this.target, required this.formula, this.condition});

  /// What this modifies: 'initiative', 'attackRoll', 'damageRoll',
  /// 'spellAttack' (spell attack bonus), 'spellSaveDc' (spell save DC),
  /// 'ac', 'speed', 'maxHp' (formula may use "Level"),
  /// 'save:[ability key]' (e.g. 'save:dex'), 'skill:[Skill Name]'
  /// (matching SrdSkillRef.name exactly), 'damageResistance:[damage type
  /// key]' (halves that damage type when taken - [formula] is unused/
  /// ignored, see rules.computeDamageTaken), or 'damageReduction:[damage
  /// type key]' (subtracts [formula]'s value from that damage type when
  /// taken). The damage type key is an srdCatalog.damageTypes key (e.g.
  /// "fire"), or the synthetic bucket "physical" for Bludgeoning/
  /// Piercing/Slashing from a nonmagical source (the standard 5e grouping
  /// used by things like Heavy Armor Master).
  final String target;

  /// Evaluated by rules.evaluateFormula against the character - e.g.
  /// "Proficiency Bonus", "8 + Constitution modifier", "-1". Unused for a
  /// 'damageResistance:*' target (resistance is always "half, rounded
  /// down," not a variable amount).
  final String formula;

  /// Narrows when this applies - null (always) or a recognized condition
  /// string (see rules.dart's _effectConditionMet): 'heavyWeapon',
  /// 'anyDamage', 'bloodied', 'heavyArmor'.
  final String? condition;

  Map<String, dynamic> toJson() => {
    'target': target,
    'formula': formula,
    'condition': condition,
  };

  factory Effect.fromJson(Map<String, dynamic> j) => Effect(
    target: j['target'] as String,
    formula: j['formula'] as String,
    condition: j['condition'] as String?,
  );
}
