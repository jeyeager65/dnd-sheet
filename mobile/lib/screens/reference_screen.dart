import 'package:flutter/material.dart';

import '../data/srd_catalog.dart';
import '../theme/ledger_theme.dart';
import '../widgets/expandable_row.dart';
import '../widgets/layout.dart';
import '../widgets/ledger_bits.dart';
import '../widgets/markdown_text.dart';
import 'homebrew_screen.dart';

/// One browsable glossary entry - a spell, a skill, a damage type,
/// whatever - normalized to the same {name, tag, desc} shape so
/// ReferenceListScreen can render any of them the same way.
class RefEntry {
  const RefEntry({required this.name, this.tag, required this.desc});
  final String name;
  final String? tag; // e.g. "Level 3 Evocation", "CE", "Uncommon"
  final String desc;
}

/// A category's content shape, which decides which screen opens it -
/// [items] is many short, similarly-shaped entries meant to be searched
/// and scanned (spells, gear, glossary terms, ...), rendered by
/// [ReferenceListScreen]; [chapters] is a handful of long narrative
/// sections meant to be read start to finish (Playing the Game,
/// Character Creation, ...), rendered by [ReferenceChapterScreen] instead
/// - a search box and an inline accordion fit the first shape and just
/// get in the way of the second.
enum _RefKind { items, chapters }

class _RefCategory {
  const _RefCategory(this.title, this.subtitle, this.kind, this.entries);
  final String title;
  final String subtitle;
  final _RefKind kind;
  final List<RefEntry> Function() entries;
}

/// Landing page for rules text that isn't tied to a specific character
/// feature - app-wide, not per-character, so it's reachable from both the
/// character list and an open character sheet (each via the book icon in
/// their AppBar), and returning is just the normal back button since this
/// is a regular pushed route. Categories are grouped under [SectionLabel]
/// headers by what a player is actually looking for, rather than listed
/// in whatever order they were ported in.
class ReferenceScreen extends StatefulWidget {
  const ReferenceScreen({super.key});

  @override
  State<ReferenceScreen> createState() => _ReferenceScreenState();
}

/// Every items-kind category's entries in one list, each tagged with the
/// category it's from - "Search Everything".
List<RefEntry> _everythingEntries(List<(String, List<_RefCategory>)> groups) =>
    [
      for (final (_, categories) in groups)
        for (final category in categories)
          if (category.kind == _RefKind.items)
            for (final e in category.entries())
              RefEntry(
                name: e.name,
                tag: [category.title, ?e.tag].join(' · '),
                desc: e.desc,
              ),
    ];

const _searchEverything = 'Search Everything';

class _ReferenceScreenState extends State<ReferenceScreen> {
  /// The category shown on the right in the wide layout.
  String _selected = _searchEverything;

  /// Wide layout: Back and the categories in a panel on the left, the
  /// selected category's entries (searchable, expandable) on the right.
  Widget _wide(
    BuildContext context,
    List<(String, List<_RefCategory>)> groups,
  ) {
    final all = [for (final (_, cats) in groups) ...cats];
    final selected = all.where((c) => c.title == _selected).firstOrNull;
    final entries = selected == null
        ? _everythingEntries(groups)
        : selected.entries();

    Widget tile(String title, {String? subtitle}) => ListTile(
      dense: true,
      selected: _selected == title,
      selectedTileColor: LedgerColors.accent.withValues(alpha: 0.15),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      onTap: () => setState(() => _selected = title),
    );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(selected?.title ?? _searchEverything),
      ),
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(
              width: 260,
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.arrow_back, size: 18),
                      label: const Text('Back'),
                    ),
                  ),
                  tile(_searchEverything),
                  ListTile(
                    dense: true,
                    title: const Text('My Homebrew'),
                    trailing: const Icon(Icons.chevron_right, size: 18),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const HomebrewListScreen(),
                      ),
                    ),
                  ),
                  for (final (label, categories) in groups) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 16),
                      child: SectionLabel(label),
                    ),
                    for (final c in categories) tile(c.title),
                  ],
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: ReadableWidth(
                child: ReferenceListView(
                  key: ValueKey(_selected),
                  entries: entries,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groups = <(String, List<_RefCategory>)>[
      (
        'Character Options',
        [
          _RefCategory(
            'Classes',
            '${srdCatalog.classesByKey.length} classes, with level tables '
                'and subclasses',
            _RefKind.chapters,
            _classEntries,
          ),
          _RefCategory(
            'Species',
            '${srdCatalog.speciesByKey.length} species',
            _RefKind.items,
            _speciesEntries,
          ),
          _RefCategory(
            'Backgrounds',
            '${srdCatalog.backgroundsByKey.length} backgrounds',
            _RefKind.items,
            _backgroundEntries,
          ),
          _RefCategory(
            'Feats',
            '${srdCatalog.featsByKey.length} feats',
            _RefKind.items,
            _featEntries,
          ),
          _RefCategory(
            'Spells',
            '${srdCatalog.spells.length} spells',
            _RefKind.items,
            _spellEntries,
          ),
          _RefCategory('Skills', '18 skills', _RefKind.items, _skillEntries),
          _RefCategory(
            'Abilities',
            '6 abilities',
            _RefKind.items,
            _abilityEntries,
          ),
          _RefCategory(
            'Weapon Properties & Masteries',
            '${srdCatalog.weaponPropertiesByName.length} entries',
            _RefKind.items,
            _weaponPropertyEntries,
          ),
        ],
      ),
      (
        'Equipment',
        [
          _RefCategory(
            'Weapons',
            '${srdCatalog.weaponsByKey.length} weapons',
            _RefKind.items,
            _weaponEntries,
          ),
          _RefCategory(
            'Armor',
            '${srdCatalog.armorByKey.length} armor',
            _RefKind.items,
            _armorEntries,
          ),
          _RefCategory(
            'Gear',
            '${srdCatalog.gearByKey.length} items',
            _RefKind.items,
            _gearEntries,
          ),
          _RefCategory(
            'Tools',
            '${srdCatalog.toolsByKey.length} tools',
            _RefKind.items,
            _toolEntries,
          ),
          _RefCategory(
            'Magic Items',
            '${srdCatalog.magicItemsByKey.length} items',
            _RefKind.items,
            _magicItemEntries,
          ),
          _RefCategory(
            'Mounts & Vehicles',
            '${srdCatalog.mountsAndVehicles.length} entries',
            _RefKind.items,
            _mountsAndVehiclesEntries,
          ),
        ],
      ),
      (
        'Rules',
        [
          _RefCategory(
            'Playing the Game',
            '${srdCatalog.playingTheGame.length} sections',
            _RefKind.chapters,
            _playingTheGameEntries,
          ),
          _RefCategory(
            'Gameplay Toolbox',
            '${srdCatalog.gameplayToolbox.length} sections',
            _RefKind.chapters,
            _gameplayToolboxEntries,
          ),
          _RefCategory(
            'Character Creation',
            '${srdCatalog.characterCreationChapters.length} sections',
            _RefKind.chapters,
            _characterCreationEntries,
          ),
          _RefCategory(
            'Rules Glossary',
            '${srdCatalog.rulesGlossary.length} terms',
            _RefKind.items,
            _rulesGlossaryEntries,
          ),
          _RefCategory(
            'Conditions',
            '${srdCatalog.conditionNames.length} conditions',
            _RefKind.items,
            _conditionEntries,
          ),
        ],
      ),
      (
        'Tables',
        [
          _RefCategory(
            'Alignments',
            '9 alignments',
            _RefKind.items,
            _alignmentEntries,
          ),
          _RefCategory(
            'Damage Types',
            '13 types',
            _RefKind.items,
            _damageTypeEntries,
          ),
          _RefCategory(
            'Spell Schools',
            '8 schools',
            _RefKind.items,
            _spellSchoolEntries,
          ),
          _RefCategory('Sizes', '6 sizes', _RefKind.items, _sizeEntries),
          _RefCategory(
            'Languages',
            '${srdCatalog.languages.length} languages',
            _RefKind.items,
            _languageEntries,
          ),
        ],
      ),
    ];

    if (isWideLayout(context)) return _wide(context, groups);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reference'),
        actions: [
          IconButton(
            tooltip: 'Search everything',
            icon: const Icon(Icons.search),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ReferenceListScreen(
                  title: _searchEverything,
                  entries: _everythingEntries(groups),
                ),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          children: [
            const SectionLabel('My Content'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'My Homebrew',
                style: TextStyle(
                  color: LedgerColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: const Text(
                'Browse and edit your own content',
                style: TextStyle(color: LedgerColors.inkDim, fontSize: 12),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: LedgerColors.inkDim,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const HomebrewListScreen()),
              ),
            ),
            const Divider(height: 1),
            for (final (label, categories) in groups) ...[
              SectionLabel(label),
              for (final category in categories) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    category.title,
                    style: const TextStyle(
                      color: LedgerColors.ink,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    category.subtitle,
                    style: const TextStyle(
                      color: LedgerColors.inkDim,
                      fontSize: 12,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: LedgerColors.inkDim,
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => category.kind == _RefKind.chapters
                          ? ReferenceChapterScreen(
                              title: category.title,
                              sections: category.entries(),
                            )
                          : ReferenceListScreen(
                              title: category.title,
                              entries: category.entries(),
                            ),
                    ),
                  ),
                ),
                const Divider(height: 1),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

List<RefEntry> _spellEntries() {
  final list = [...srdCatalog.spells]..sort((a, b) => a.name.compareTo(b.name));
  return [
    for (final s in list)
      RefEntry(
        name: s.name,
        tag: s.level == 0
            ? '${s.school} Cantrip'
            : 'Level ${s.level} ${s.school}',
        desc: [
          '${s.castingTime} · ${s.range} · ${s.components}',
          '${s.duration}${s.concentration ? ' (Concentration)' : ''}${s.ritual ? ' · Ritual' : ''}',
          if (s.classes.isNotEmpty) s.classes.join(', '),
          '',
          s.desc,
          if (s.higherLevel != null) '\nAt Higher Levels: ${s.higherLevel}',
        ].join('\n'),
      ),
  ];
}

/// One section per class: its traits, its level table (every column,
/// spell slots included), its features by level, and its SRD subclass.
List<RefEntry> _classEntries() => [
  for (final cls in srdCatalog.classesByKey.values)
    RefEntry(name: cls.name, desc: _classText(cls)),
];

String _classText(SrdClass cls) {
  final buffer = StringBuffer();
  for (final e in cls.traits.entries) {
    buffer.writeln('**${e.key}:** ${e.value}\n');
  }
  // Level table as HTML (MarkdownText renders <table>) - every string
  // column, then spell slots by level where the class has them.
  final columns = <String>[
    for (final key in cls.levels.first.keys)
      if (key != 'spellSlots') key,
  ];
  final slotLevels = <int>{
    for (final slots in cls.spellSlotsByLevel.values) ...slots.keys,
  }.toList()..sort();
  buffer.writeln('### ${cls.name} Features\n');
  buffer.writeln('<table><thead><tr>');
  for (final c in columns) {
    buffer.write('<th>$c</th>');
  }
  for (final s in slotLevels) {
    buffer.write('<th>Slot $s</th>');
  }
  buffer.writeln('</tr></thead><tbody>');
  for (final row in cls.levels) {
    buffer.write('<tr>');
    for (final c in columns) {
      buffer.write('<td>${row[c] ?? '-'}</td>');
    }
    final level = int.tryParse(row['Level'] ?? '') ?? 0;
    for (final s in slotLevels) {
      buffer.write('<td>${cls.spellSlotsByLevel[level]?[s] ?? '-'}</td>');
    }
    buffer.writeln('</tr>');
  }
  buffer.writeln('</tbody></table>\n');
  for (final f in cls.features) {
    buffer.writeln('### Level ${f.level}: ${f.name}\n\n${f.desc}\n');
  }
  final sub = cls.subclass;
  if (sub != null) {
    buffer.writeln('## Subclass: ${sub.name}\n');
    for (final f in sub.features) {
      buffer.writeln('### Level ${f.level}: ${f.name}\n\n${f.desc}\n');
    }
  }
  return buffer.toString();
}

List<RefEntry> _speciesEntries() => [
  for (final s in srdCatalog.speciesByKey.values)
    RefEntry(
      name: s.name,
      tag: '${RegExp(r'^\w+').stringMatch(s.size) ?? ''} · ${s.speed}',
      desc: [
        '**Size:** ${s.size}',
        '**Speed:** ${s.speed}',
        for (final t in s.traits) '**${t.name}.** ${t.desc}',
        for (final table in s.tables)
          '**${table.caption}:** ${[for (final row in table.rows) row.join(' - ')].join('; ')}',
      ].join('\n\n'),
    ),
];

List<RefEntry> _backgroundEntries() => [
  for (final b in srdCatalog.backgroundsByKey.values)
    RefEntry(
      name: b.name,
      tag: b.feat,
      desc: [
        '**Ability Scores:** ${b.abilityScores.join(', ')}',
        '**Feat:** ${b.feat ?? '-'}',
        '**Skill Proficiencies:** ${b.skillProficiencies.join(', ')}',
        if (b.toolProficiency != null)
          '**Tool Proficiency:** ${b.toolProficiency}',
        if (b.equipment != null) '**Equipment:** ${b.equipment}',
      ].join('\n\n'),
    ),
];

List<RefEntry> _featEntries() => [
  for (final f in srdCatalog.featsByKey.values)
    RefEntry(
      name: f.name,
      tag: [f.category, ?f.prerequisite].join(' · '),
      desc: [
        if (f.desc.isNotEmpty) f.desc,
        for (final b in f.benefits) '**${b.name}.** ${b.desc}',
      ].join('\n\n'),
    ),
];

List<RefEntry> _weaponEntries() => [
  for (final w in srdCatalog.weaponsByKey.values)
    RefEntry(
      name: w.name,
      tag: w.category,
      desc: [
        '**Damage:** ${w.damage}',
        if (w.properties.isNotEmpty)
          '**Properties:** ${w.properties.join(', ')}',
        if (w.mastery != null)
          '**Mastery - ${w.mastery}:** '
              '${srdCatalog.weaponPropertiesByName[w.mastery]?.desc ?? ''}',
      ].join('\n\n'),
    ),
];

List<RefEntry> _armorEntries() => [
  for (final a in srdCatalog.armorByKey.values)
    RefEntry(
      name: a.name,
      tag: a.category,
      desc: [
        '**Armor Class:** ${a.armorClass}',
        if (a.strength != null) '**Strength:** ${a.strength}',
        if (a.stealth) '**Stealth:** Disadvantage',
      ].join('\n\n'),
    ),
];

List<RefEntry> _skillEntries() => [
  for (final skill
      in srdCatalog.skillsByName.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name)))
    RefEntry(
      name: skill.name,
      tag: skill.ability.toUpperCase(),
      desc: skill.desc,
    ),
];

List<RefEntry> _abilityEntries() => [
  for (final a in srdCatalog.abilityGlossary)
    RefEntry(name: a.name, desc: a.desc),
];

List<RefEntry> _alignmentEntries() => [
  for (final a in srdCatalog.alignments)
    RefEntry(name: a.name, tag: a.shortName, desc: a.desc),
];

List<RefEntry> _damageTypeEntries() => [
  for (final d in srdCatalog.damageTypes) RefEntry(name: d.name, desc: d.desc),
];

List<RefEntry> _spellSchoolEntries() => [
  for (final s in srdCatalog.spellSchools) RefEntry(name: s.name, desc: s.desc),
];

List<RefEntry> _sizeEntries() => [
  for (final s in srdCatalog.sizes)
    RefEntry(
      name: s.name,
      desc:
          '${s.spaceDiameter} ft. space · suggested Hit Die ${s.hitDie} for an improvised size-based roll',
    ),
];

List<RefEntry> _weaponPropertyEntries() => [
  for (final p
      in srdCatalog.weaponPropertiesByName.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name)))
    RefEntry(
      name: p.name,
      tag: p.isMastery ? 'Mastery' : 'Property',
      desc: p.desc,
    ),
];

List<RefEntry> _conditionEntries() => [
  for (final name in srdCatalog.conditionNames)
    RefEntry(name: name, desc: srdCatalog.conditionDescriptions[name] ?? ''),
];

List<RefEntry> _languageEntries() => [
  for (final l in [
    ...srdCatalog.languages,
  ]..sort((a, b) => a.name.compareTo(b.name)))
    RefEntry(name: l.name, desc: ''),
];

List<RefEntry> _gearEntries() => [
  for (final g
      in srdCatalog.gearByKey.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name)))
    RefEntry(
      name: g.name,
      tag: [
        if (g.cost != null) g.cost!,
        if (g.weight != null) g.weight!,
      ].join(' · '),
      desc: g.desc,
    ),
];

List<RefEntry> _toolEntries() => [
  for (final t
      in srdCatalog.toolsByKey.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name)))
    RefEntry(
      name: t.name,
      tag: t.ability,
      desc: [
        if (t.utilize.isNotEmpty) 'Utilize: ${t.utilize}',
        if (t.craft.isNotEmpty) 'Craft: ${t.craft}',
      ].join('\n'),
    ),
];

List<RefEntry> _magicItemEntries() => [
  for (final m
      in srdCatalog.magicItemsByKey.values.toList()
        ..sort((a, b) => a.name.compareTo(b.name)))
    RefEntry(name: m.name, tag: '${m.rarity} · ${m.category}', desc: m.desc),
];

List<RefEntry> _rulesGlossaryEntries() => [
  for (final g
      in srdCatalog.rulesGlossary.toList()
        ..sort((a, b) => a.name.compareTo(b.name)))
    RefEntry(name: g.name, tag: g.tag, desc: g.desc),
];

List<RefEntry> _playingTheGameEntries() => [
  for (final s in srdCatalog.playingTheGame)
    RefEntry(name: s.name, desc: s.desc),
];

List<RefEntry> _gameplayToolboxEntries() => [
  for (final s in srdCatalog.gameplayToolbox)
    RefEntry(name: s.name, desc: s.desc),
];

List<RefEntry> _characterCreationEntries() => [
  for (final s in srdCatalog.characterCreationChapters)
    RefEntry(name: s.name, desc: s.desc),
];

List<RefEntry> _mountsAndVehiclesEntries() => [
  for (final m
      in srdCatalog.mountsAndVehicles.toList()
        ..sort((a, b) => a.name.compareTo(b.name)))
    RefEntry(name: m.name, desc: m.desc),
];

/// Search + tap-to-expand list over a category's [RefEntry]s - reused for
/// every Reference category, small glossary or large catalog alike.
class ReferenceListScreen extends StatelessWidget {
  const ReferenceListScreen({
    super.key,
    required this.title,
    required this.entries,
  });
  final String title;
  final List<RefEntry> entries;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: SafeArea(
      child: ReadableWidth(child: ReferenceListView(entries: entries)),
    ),
  );
}

/// A search box over [entries], each an expandable row with its rules
/// text - the phone's category page, and the right side of the wide
/// Reference layout.
class ReferenceListView extends StatefulWidget {
  const ReferenceListView({super.key, required this.entries});
  final List<RefEntry> entries;

  @override
  State<ReferenceListView> createState() => _ReferenceListViewState();
}

class _ReferenceListViewState extends State<ReferenceListView> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _query.isEmpty
        ? widget.entries
        : widget.entries
              .where((e) => e.name.toLowerCase().contains(_query.toLowerCase()))
              .toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: LedgerColors.ink),
            decoration: const InputDecoration(
              hintText: 'Search…',
              prefixIcon: Icon(
                Icons.search,
                color: LedgerColors.inkDim,
                size: 20,
              ),
              isDense: true,
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'Nothing matches that search.',
                    style: TextStyle(color: LedgerColors.inkDim),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  children: [
                    for (final entry in filtered)
                      ExpandableRow(
                        title: entry.name,
                        tag: entry.tag,
                        body: MarkdownText(
                          entry.desc.isEmpty
                              ? 'No further rules text.'
                              : entry.desc,
                        ),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

/// Table of contents for a narrative rules chapter (Playing the Game,
/// Gameplay Toolbox, Character Creation) - just the handful of section
/// titles, tapping one opens it as its own full page. Deliberately not
/// [ReferenceListScreen]: a search box and an inline accordion are built
/// for scanning many short items, not for reading a few long sections
/// start to finish.
class ReferenceChapterScreen extends StatelessWidget {
  const ReferenceChapterScreen({
    super.key,
    required this.title,
    required this.sections,
  });
  final String title;
  final List<RefEntry> sections;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          itemCount: sections.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final section = sections[i];
            return ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                section.name,
                style: const TextStyle(
                  color: LedgerColors.ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
              trailing: const Icon(
                Icons.chevron_right,
                color: LedgerColors.inkDim,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ReferenceChapterDetailScreen(
                    title: section.name,
                    body: section.desc,
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Full-page read of one chapter section's SRD text - a plain scrolling
/// page rather than an accordion row, since these run thousands of
/// characters (e.g. "Combat") and are meant to be read, not skimmed.
class ReferenceChapterDetailScreen extends StatelessWidget {
  const ReferenceChapterDetailScreen({
    super.key,
    required this.title,
    required this.body,
  });
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: MarkdownText(body),
        ),
      ),
    );
  }
}
