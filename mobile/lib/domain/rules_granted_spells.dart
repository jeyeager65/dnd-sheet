part of 'rules.dart';

// Spells a character gets from a feature, subclass, species, or feat rather
// than picking them from their class list: Paladin's Smite's Divine Smite,
// a Life Domain Cleric's domain spells, a High Elf's Detect Magic and Misty
// Step, Magic Initiate's picks, an invocation's at-will Mage Armor... They
// live in Spellcasting.spells as KnownSpells with a [KnownSpell.source],
// always prepared, and syncGrantedSpells keeps that list matching what the
// character currently has - idempotent, so it runs after anything that
// could change it and on every load.

/// Casts per rest meaning "at will" - no limit (Spell Mastery, an
/// invocation's "without expending a spell slot").
const atWill = -1;

class _Grant {
  const _Grant(
    this.spellName,
    this.source, {
    this.freeCasts = 0,
    this.recovery = 'long',
    this.ability,
  });
  final String spellName;
  final String source;
  final int freeCasts;
  final String recovery;
  final String? ability;
}

const _abilityNameToShortKey = {
  'Intelligence': 'int',
  'Wisdom': 'wis',
  'Charisma': 'cha',
};

SrdSpellRef? _spellNamed(String name) {
  final lower = name.toLowerCase().trim();
  for (final s in srdCatalog.spells) {
    if (s.name.toLowerCase() == lower) return s;
  }
  return null;
}

/// "Aid, Bless, Cure Wounds" -> the names, from a subclass spell table cell.
List<String> _splitSpellList(String cell) => [
  for (final part in cell.split(','))
    if (part.trim().isNotEmpty) part.replaceAll(RegExp(r'<[^>]+>'), '').trim(),
];

/// A subclass "... Spells" feature's table rows as (class level, spells) -
/// [heading] picks one table when the feature has several (Circle of the
/// Land's "Arid Land", "Polar Land", ...).
List<(int, List<String>)> _spellTableRows(String desc, {String? heading}) {
  var text = desc;
  if (heading != null) {
    final start = text.indexOf('**$heading**');
    if (start < 0) return const [];
    text = text.substring(start);
    final end = text.indexOf('</table>');
    if (end >= 0) text = text.substring(0, end);
  }
  return [
    for (final m in RegExp(
      r'<tr>\s*<td>(\d+)</td>\s*<td>([^<]+)</td>\s*</tr>',
    ).allMatches(text))
      (int.parse(m.group(1)!), _splitSpellList(m.group(2)!)),
  ];
}

/// Every spell [c] should currently have from somewhere other than their
/// class list.
List<_Grant> _grantsFor(Character c) {
  final grants = <_Grant>[];
  final names = c.features.map((f) => f.name).toSet();
  final classData = _classData(c);
  int table(String column) =>
      int.tryParse(classData?.levelValue(c.level, column) ?? '') ?? 0;

  // Class features.
  if (names.contains('Druidic')) {
    grants.add(const _Grant('Speak with Animals', 'Druidic'));
  }
  if (names.contains("Paladin's Smite")) {
    grants.add(const _Grant('Divine Smite', "Paladin's Smite", freeCasts: 1));
  }
  if (names.contains('Faithful Steed')) {
    grants.add(const _Grant('Find Steed', 'Faithful Steed', freeCasts: 1));
  }
  if (names.contains('Favored Enemy')) {
    grants.add(
      _Grant(
        "Hunter's Mark",
        'Favored Enemy',
        freeCasts: table('Favored Enemy'),
      ),
    );
  }
  if (names.contains('Contact Patron')) {
    grants.add(
      const _Grant('Contact Other Plane', 'Contact Patron', freeCasts: 1),
    );
  }
  if (names.contains('Words of Creation')) {
    grants.add(const _Grant('Power Word Heal', 'Words of Creation'));
    grants.add(const _Grant('Power Word Kill', 'Words of Creation'));
  }
  for (final spell in c.featureChoices['Mystic Arcanum'] ?? const <String>[]) {
    grants.add(_Grant(spell, 'Mystic Arcanum', freeCasts: 1));
  }
  for (final spell in c.featureChoices['Spell Mastery'] ?? const <String>[]) {
    grants.add(_Grant(spell, 'Spell Mastery', freeCasts: atWill));
  }
  for (final spell
      in c.featureChoices['Signature Spells'] ?? const <String>[]) {
    grants.add(
      _Grant(spell, 'Signature Spells', freeCasts: 1, recovery: 'short'),
    );
  }
  for (final spell
      in c.featureChoices['Magical Discoveries'] ?? const <String>[]) {
    grants.add(_Grant(spell, 'Magical Discoveries'));
  }

  // Invocations that cast a spell "without expending a spell slot".
  for (final f in c.features.where((f) => f.source == 'Eldritch Invocations')) {
    final m = RegExp(
      r'cast _(.+?)_ (?:on yourself )?without expending a spell slot',
    ).firstMatch(f.desc ?? '');
    if (m != null) grants.add(_Grant(m.group(1)!, f.name, freeCasts: atWill));
    if (f.name == 'Gift of the Depths') {
      grants.add(
        const _Grant('Water Breathing', 'Gift of the Depths', freeCasts: 1),
      );
    }
    if (f.name == 'Pact of the Chain') {
      grants.add(
        const _Grant('Find Familiar', 'Pact of the Chain', freeCasts: atWill),
      );
    }
  }

  // Subclass "... Spells" tables (Life Domain, Oath of Devotion, Draconic,
  // Fiend) and Circle of the Land's land table.
  final subclass = chosenSubclass(c);
  if (subclass != null) {
    for (final entry in subclass.spellsByLevel.entries) {
      if (entry.key > c.level) continue;
      for (final spell in entry.value) {
        grants.add(_Grant(spell, subclass.name));
      }
    }
    for (final f in subclass.features) {
      if (!f.name.endsWith(' Spells') || !names.contains(f.name)) continue;
      final land = optionPick(c, 'Circle of the Land Spells');
      final rows = f.name == 'Circle of the Land Spells'
          ? (land == null
                ? const <(int, List<String>)>[]
                : _spellTableRows(f.desc, heading: '$land Land'))
          : _spellTableRows(f.desc);
      for (final (level, spells) in rows) {
        if (level > c.level) continue;
        for (final spell in spells) {
          grants.add(_Grant(spell, f.name));
        }
      }
    }
  }

  // Species lineages.
  final lineageAbility =
      _abilityNameToShortKey[optionPick(c, 'Lineage Spellcasting Ability')];
  final species = c.speciesKey != null
      ? srdCatalog.speciesByKey[c.speciesKey]
      : null;
  if ((c.speciesKey == 'srd-2024_elf-species' ||
          c.speciesKey == 'srd-2024_tiefling-species') &&
      species != null &&
      species.tables.isNotEmpty &&
      c.speciesChoice != null) {
    final source = c.speciesKey == 'srd-2024_elf-species'
        ? 'Elven Lineage'
        : 'Fiendish Legacy';
    for (final row in species.tables.first.rows) {
      if (row.isEmpty || row.first != c.speciesChoice || row.length < 4) {
        continue;
      }
      final cantrip = RegExp(r'know the (.+?) cantrip').firstMatch(row[1]);
      if (cantrip != null) {
        grants.add(_Grant(cantrip.group(1)!, source, ability: lineageAbility));
      }
      if (c.level >= 3) {
        grants.add(
          _Grant(row[2], source, freeCasts: 1, ability: lineageAbility),
        );
      }
      if (c.level >= 5) {
        grants.add(
          _Grant(row[3], source, freeCasts: 1, ability: lineageAbility),
        );
      }
    }
  }
  if (c.speciesKey == 'srd-2024_tiefling-species') {
    grants.add(
      _Grant('Thaumaturgy', 'Otherworldly Presence', ability: lineageAbility),
    );
  }
  if (c.speciesKey == 'srd-2024_gnome-species') {
    switch (optionPick(c, 'Gnomish Lineage')) {
      case 'Forest Gnome':
        grants.add(
          _Grant('Minor Illusion', 'Gnomish Lineage', ability: lineageAbility),
        );
        grants.add(
          _Grant(
            'Speak with Animals',
            'Gnomish Lineage',
            freeCasts: proficiencyBonusForLevel(c.level),
            ability: lineageAbility,
          ),
        );
      case 'Rock Gnome':
        grants.add(
          _Grant('Mending', 'Gnomish Lineage', ability: lineageAbility),
        );
        grants.add(
          _Grant(
            'Prestidigitation',
            'Gnomish Lineage',
            ability: lineageAbility,
          ),
        );
    }
  }

  // Magic Initiate (each instance has its own list's picks).
  for (final feat in c.feats) {
    if (baseFeatName(feat.name) != 'Magic Initiate') continue;
    final ability =
        _abilityNameToShortKey[optionPick(c, '${feat.name} Ability')];
    for (final spell
        in c.featureChoices['${feat.name} Cantrips'] ?? const <String>[]) {
      grants.add(_Grant(spell, feat.name, ability: ability));
    }
    for (final spell
        in c.featureChoices['${feat.name} Spell'] ?? const <String>[]) {
      grants.add(_Grant(spell, feat.name, freeCasts: 1, ability: ability));
    }
  }
  return grants;
}

/// Brings [c]'s granted spells in line with [_grantsFor]: adds new ones,
/// drops ones whose source is gone, and updates free-cast counts (keeping
/// what's already been spent). Creates a Spellcasting block for a
/// non-caster who gains a spell (a Fighter Elf's lineage spells), using the
/// grant's own ability.
void syncGrantedSpells(Character c) {
  final grants = [
    for (final g in _grantsFor(c))
      if (_spellNamed(g.spellName) != null) g,
  ];
  if (grants.isEmpty && c.spellcasting == null) return;
  final sc = c.spellcasting ??= Spellcasting(
    ability: grants.first.ability ?? 'int',
  );
  final existing = {
    for (final s in sc.spells)
      if (s.source != null) '${s.source}|${s.spellKey}': s,
  };
  final wanted = <KnownSpell>[];
  for (final g in grants) {
    final key = _spellNamed(g.spellName)!.key;
    final old = existing['${g.source}|$key'];
    wanted.add(
      KnownSpell(
        spellKey: key,
        prepared: true,
        alwaysPrepared: true,
        source: g.source,
        freeCasts: g.freeCasts,
        freeCastsUsed: g.freeCasts == atWill
            ? 0
            : (old?.freeCastsUsed ?? 0).clamp(0, g.freeCasts),
        freeCastRecovery: g.recovery,
        abilityOverride: g.ability,
      ),
    );
  }
  // One entry per spell+source; a spell granted twice (Druidic and Forest
  // Gnome both give Speak with Animals) keeps both, since each has its own
  // free casts.
  final seen = <String>{};
  sc.spells = [
    ...sc.spells.where((s) => s.source == null),
    for (final s in wanted)
      if (seen.add('${s.source}|${s.spellKey}')) s,
  ];
}

/// Free casts left for [s] - null when it has none; [atWill] when
/// unlimited.
int? freeCastsLeft(KnownSpell s) {
  if (s.freeCasts == 0) return null;
  if (s.freeCasts == atWill) return atWill;
  return s.freeCasts - s.freeCastsUsed;
}

/// Resets free casts on a rest - every one on a Long Rest, the
/// short-recovery ones (Signature Spells) on a Short Rest too.
void _recoverFreeCasts(Character c, {required bool longRest}) {
  for (final s in c.spellcasting?.spells ?? const <KnownSpell>[]) {
    if (longRest || s.freeCastRecovery == 'short') s.freeCastsUsed = 0;
  }
}
