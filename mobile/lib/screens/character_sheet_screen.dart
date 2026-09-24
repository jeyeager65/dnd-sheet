import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../data/character_repository.dart';
import '../data/homebrew_repository.dart';
import '../data/sheet_text_repository.dart';
import '../data/srd_catalog.dart';
import '../domain/character_sheet_pdf.dart';
import '../domain/rules.dart' as rules;
import '../models/character.dart';
import '../models/homebrew.dart';
import '../theme/ledger_theme.dart';
import '../widgets/expandable_row.dart';
import '../widgets/layout.dart';
import '../widgets/ledger_bits.dart';
import '../widgets/markdown_text.dart';
import '../widgets/stat_grid.dart';
import '../widgets/weapon_stats_fields.dart';
import '../data/homebrew_catalog.dart';
import 'catalog_picker_screen.dart';
import 'character_form_screen.dart';
import 'option_picker.dart';
import 'reference_screen.dart';
import 'share_json.dart';

/// The five tabs mirror the Quasar app's Overview / Combat / Features /
/// Items / Spells structure; Combat is the default because that's the tab
/// you actually need mid-session. Everything shown is computed from the
/// Character in charactersRepo via domain/rules.dart, not hardcoded -
/// change Jarson's feats or ability scores and the math here follows.
class CharacterSheetScreen extends StatefulWidget {
  const CharacterSheetScreen({super.key, required this.characterId});

  final String characterId;

  @override
  State<CharacterSheetScreen> createState() => _CharacterSheetScreenState();
}

class _CharacterSheetScreenState extends State<CharacterSheetScreen> {
  int _tab = 1;

  /// Guided level-up: confirms, advances exactly one level (snapshotting
  /// the pre-level-up state as an automatic backup first - see
  /// CharacterRepository.levelUpCharacter), then shows what changed and
  /// offers to jump straight to the Features tab to resolve any new
  /// Pending Choices (Ability Score Improvement, Fighting Style, a
  /// subclass pick, ...) instead of leaving them to be discovered later.
  Future<void> _levelUp(BuildContext context, Character character) async {
    // Hit Points for the new level: the fixed average, or a roll of the
    // Hit Die (the player rolls; this records it).
    final sides = int.tryParse(character.hitDiceDie.substring(1)) ?? 8;
    final average = rules.averageHitDieResult(character);
    final conMod = rules.modifierOf(character, 'con');
    var rolled = false;
    var roll = average;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Level Up to ${character.level + 1}?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Saves ${character.name}'s current Level ${character.level} "
                  'state as a backup first (Promote it back later if you '
                  'need to undo this), then advances the live sheet to '
                  'Level ${character.level + 1}.',
                ),
                const SizedBox(height: 12),
                Text(
                  'Hit Points (${character.hitDiceDie} '
                  '${rules.formatModifier(conMod)} Con)',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                RadioGroup<bool>(
                  groupValue: rolled,
                  onChanged: (v) => setState(() => rolled = v ?? false),
                  child: Column(
                    children: [
                      RadioListTile<bool>(
                        value: false,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          'Take the average: $average '
                          '(+${(average + conMod).clamp(1, 99)} HP)',
                        ),
                      ),
                      RadioListTile<bool>(
                        value: true,
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Row(
                          children: [
                            const Text('I rolled: '),
                            DropdownButton<int>(
                              value: roll,
                              items: [
                                for (var n = 1; n <= sides; n++)
                                  DropdownMenuItem(value: n, child: Text('$n')),
                              ],
                              onChanged: (v) => setState(() {
                                roll = v ?? roll;
                                rolled = true;
                              }),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Level Up'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    final summary = await charactersRepo.levelUpCharacter(
      character.id,
      hpRoll: rolled ? roll : null,
    );
    if (!context.mounted) return;

    final hasChoices = summary.newPendingChoices.isNotEmpty;
    final jumpToFeatures = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Level ${summary.newLevel}!'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Max HP: ${summary.oldMaxHp} → ${summary.newMaxHp}'),
            if (summary.newFeatureNames.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'New features:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final name in summary.newFeatureNames) Text('• $name'),
            ],
            if (summary.spellcastingNotes.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Spellcasting:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final note in summary.spellcastingNotes) Text('• $note'),
            ],
            if (hasChoices) ...[
              const SizedBox(height: 10),
              const Text(
                'New choices to make:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              for (final choice in summary.newPendingChoices)
                Text('• ${choice.label}'),
            ],
          ],
        ),
        actions: [
          if (hasChoices)
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Later'),
            ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(hasChoices),
            child: Text(hasChoices ? 'Resolve Now' : 'Done'),
          ),
        ],
      ),
    );
    if (jumpToFeatures == true) setState(() => _tab = 2);
  }

  /// Exports a PDF version of the sheet onto the official 2024 D&D
  /// character sheet (see domain/character_sheet_pdf.dart) and opens the
  /// OS share sheet for it. First pass: just the top section (identity,
  /// ability scores, AC/HP/Hit Dice, Proficiency Bonus, Initiative/Speed/
  /// Passive Perception) - see that file's doc comment for what's still
  /// out of scope. The official PDF is fetched once and cached locally
  /// (data/official_sheet_cache.dart), so this needs a connection the
  /// first time it's used on a given device, but not after.
  Future<void> _exportPdf(BuildContext context, Character character) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Generating PDF…'),
        duration: Duration(seconds: 20),
      ),
    );
    try {
      final bytes = await buildCharacterSheetPdf(character);
      messenger.hideCurrentSnackBar();
      if (!context.mounted) return;
      await shareBytes(context, bytes, '${character.name}.pdf');
    } catch (e) {
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        SnackBar(content: Text('Could not create the PDF: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: charactersRepo,
      builder: (context, _) {
        final character = charactersRepo.byId(widget.characterId);
        final tabs = [
          _OverviewTab(
            character: character,
            onChanged: () => charactersRepo.save(character),
          ),
          _CombatTab(
            character: character,
            onChanged: () => charactersRepo.save(character),
          ),
          _FeaturesTab(
            character: character,
            onChanged: () => charactersRepo.save(character),
          ),
          _ItemsTab(
            character: character,
            onChanged: () => charactersRepo.save(character),
          ),
          _SpellsTab(
            character: character,
            onChanged: () => charactersRepo.save(character),
          ),
        ];

        // On a wide window (desktop, tablet landscape) the tabs sit in a
        // rail on the left, with "My Characters" at its top instead of the
        // AppBar's back arrow; on a phone they're the bottom bar.
        final wide = isWideLayout(context);
        const tabItems = [
          (Icons.person_outline, 'Overview'),
          (Icons.shield_outlined, 'Combat'),
          (Icons.menu_book_outlined, 'Features'),
          (Icons.backpack_outlined, 'Items'),
          (Icons.auto_fix_high_outlined, 'Spells'),
        ];
        final content = Column(
          children: [
            if (!character.isCurrent)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 8,
                ),
                color: LedgerColors.accent.withValues(alpha: 0.18),
                child: Text(
                  '${character.snapshotStatusLabel} — not the current in-play sheet.',
                  style: const TextStyle(fontSize: 12, color: LedgerColors.ink),
                ),
              ),
            Expanded(child: tabs[_tab]),
          ],
        );

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: !wide,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  character.name,
                  style: LedgerTheme.nameStyle(fontSize: 18),
                ),
                Text(
                  'Lv.${character.level} ${character.classLabel}',
                  style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.4,
                    color: LedgerColors.inkDim,
                  ),
                ),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Reference',
                icon: const Icon(Icons.menu_book_outlined),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ReferenceScreen()),
                ),
              ),
              if (character.isCurrent && character.level < 20)
                IconButton(
                  tooltip: 'Level Up',
                  icon: const Icon(Icons.arrow_circle_up_outlined),
                  onPressed: () => _levelUp(context, character),
                ),
              IconButton(
                tooltip: 'Export PDF',
                icon: const Icon(Icons.picture_as_pdf_outlined),
                onPressed: () => _exportPdf(context, character),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => CharacterFormScreen(
                      mode: CharacterFormMode.edit,
                      character: character,
                    ),
                  ),
                ),
                child: const Text('Edit'),
              ),
              const SizedBox(width: 6),
            ],
          ),
          body: SafeArea(
            child: wide
                ? Row(
                    children: [
                      NavigationRail(
                        extended: true,
                        minExtendedWidth: 200,
                        // Item 0 is My Characters (leaves the sheet); the
                        // tabs follow it.
                        selectedIndex: _tab + 1,
                        onDestinationSelected: (i) => i == 0
                            ? Navigator.of(context).maybePop()
                            : setState(() => _tab = i - 1),
                        destinations: [
                          const NavigationRailDestination(
                            icon: Icon(Icons.groups_outlined),
                            label: Text('My Characters'),
                            padding: EdgeInsets.only(bottom: 16),
                          ),
                          for (final (icon, label) in tabItems)
                            NavigationRailDestination(
                              icon: Icon(icon),
                              label: Text(label),
                            ),
                        ],
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: content),
                    ],
                  )
                : content,
          ),
          bottomNavigationBar: wide
              ? null
              : SafeArea(
                  child: NavigationBar(
                    selectedIndex: _tab,
                    onDestinationSelected: (i) => setState(() => _tab = i),
                    destinations: [
                      for (final (icon, label) in tabItems)
                        NavigationDestination(icon: Icon(icon), label: label),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

/// Each tab's list padding - inside the scroll view, so the desktop
/// scrollbar sits in the margin instead of over the content.
const _tabPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 6);

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.character, required this.onChanged});
  final Character character;
  final VoidCallback onChanged;

  /// The species' embedded choice table (Dragonborn's Draconic Ancestors,
  /// Elf's Elven Lineages, ...), or null if the species isn't cataloged or
  /// has no such table - most don't.
  SrdSpeciesTable? get _choiceTable {
    final species = character.speciesKey != null
        ? srdCatalog.speciesByKey[character.speciesKey]
        : null;
    if (species == null || species.tables.isEmpty) return null;
    return species.tables.first;
  }

  Future<void> _pickSpeciesChoice(BuildContext context) async {
    final table = _choiceTable;
    if (table == null) return;
    final options = flattenSpeciesTableOptions(table);
    final picked = await showDialog<SpeciesChoiceOption>(
      context: context,
      builder: (context) => SimpleDialog(
        title: Text(table.caption),
        children: [
          for (final option in options)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(option),
              child: Text(
                option.detail.isEmpty
                    ? option.name
                    : '${option.name} — ${option.detail}',
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    character.speciesChoice = picked.name;
    character.speciesLabel = picked.detail.isEmpty
        ? picked.name
        : '${picked.name} · ${picked.detail}';
    // A lineage/legacy pick changes which spells the species grants.
    rules.syncGrantedSpells(character);
    onChanged();
  }

  void _toggleSavingThrow(String ability, bool checked) {
    final current = {...character.savingThrowProficiencies};
    if (checked) {
      current.add(ability);
    } else {
      current.remove(ability);
    }
    character.savingThrowProficiencies = current.toList();
    onChanged();
  }

  /// Finds this character's existing SkillEntry for [name], or a
  /// synthetic not-proficient one - `character.skills` only ever stores
  /// entries with something set (proficient and/or expertise), so a skill
  /// the character has no training in simply isn't in the list, the same
  /// as an unset PWA skill.
  SkillEntry _skillEntryFor(SrdSkillRef ref) {
    final matches = character.skills.where((s) => s.name == ref.name);
    if (matches.isNotEmpty) return matches.first;
    return SkillEntry(name: ref.name, ability: ref.ability, proficient: false);
  }

  void _setSkillState(
    SrdSkillRef ref, {
    required bool proficient,
    required bool expertise,
  }) {
    final others = character.skills.where((s) => s.name != ref.name).toList();
    // Nothing set - drop the entry entirely rather than storing an inert
    // {proficient: false, expertise: false} row for every one of the 18
    // skills a character isn't trained in.
    if (!proficient && !expertise) {
      character.skills = others;
    } else {
      character.skills = [
        ...others,
        SkillEntry(
          name: ref.name,
          ability: ref.ability,
          proficient: proficient,
          expertise: expertise,
        ),
      ];
    }
    onChanged();
  }

  void _toggleSkillProficient(SrdSkillRef ref, bool checked) {
    final entry = _skillEntryFor(ref);
    // Expertise without proficiency isn't a real state - turning
    // proficiency off drops expertise too, same as the web app.
    _setSkillState(
      ref,
      proficient: checked,
      expertise: checked && entry.expertise,
    );
  }

  void _toggleSkillExpertise(SrdSkillRef ref, bool checked) {
    final entry = _skillEntryFor(ref);
    _setSkillState(ref, proficient: entry.proficient, expertise: checked);
  }

  @override
  Widget build(BuildContext context) {
    // Effective scores (an attuned Belt of Giant Strength's 21), with the
    // item noted below - Edit Scores still edits the character's own.
    final scores = rules.effectiveScores(character);
    final setBy = rules.setScoreEffects(character);
    String cell(int score) =>
        '${rules.abilityModifier(score) >= 0 ? '+' : ''}${rules.abilityModifier(score)}';
    final table = _choiceTable;

    return ListView(
      padding: _tabPadding,
      children: [
        GestureDetector(
          onTap: table != null ? () => _pickSpeciesChoice(context) : null,
          child: FactRow(
            label: table != null ? table.caption : 'Species',
            value: character.speciesChoice ?? character.speciesLabel,
            caption: table != null
                ? switch (character.speciesKey) {
                    'srd-2024_dragonborn-species' => 'Sets Breath Weapon damage type and your damage resistance — tap to change',
                    _ => 'Sets the lineage benefits and spells you get — tap to change',
                  }
                : null,
          ),
        ),
        if (character.speciesKey != null &&
            srdCatalog.speciesByKey[character.speciesKey]?.traits.isNotEmpty ==
                true) ...[
          const SectionLabel('Species Traits'),
          ExpandableGroup(
            builder: (context, group) => Column(
              children: [
                for (final trait
                    in srdCatalog.speciesByKey[character.speciesKey]!.traits)
                  ExpandableRow(
                    group: group,
                    groupId: trait.name,
                    title: trait.name,
                    body: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        MarkdownText(trait.desc),
                        FeatureOptionsBlock(
                          character: character,
                          featureName: trait.name,
                          onChanged: onChanged,
                        ),
                        _SheetTextBlock(
                          character: character,
                          feature: GrantedFeature(
                            name: trait.name,
                            source: 'species',
                            desc: trait.desc,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
        if (character.backgroundLabel != null) ...[
          const SectionLabel('Background'),
          Builder(
            builder: (context) {
              final info = character.backgroundKey != null
                  ? srdCatalog.backgroundsByKey[character.backgroundKey]
                  : null;
              if (info == null) {
                return FactRow(
                  label: 'Background',
                  value: character.backgroundLabel!,
                );
              }
              return ExpandableRow(
                title: character.backgroundLabel!,
                body: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (info.abilityScores.isNotEmpty)
                      Text('Ability Scores: ${info.abilityScores.join(', ')}'),
                    if (character.toolProficiencyChoices.isNotEmpty)
                      Text(
                        'Tool Proficiency: ${character.toolProficiencyChoices.join(', ')}',
                      )
                    else if (info.toolProficiency != null)
                      MarkdownText('Tool Proficiency: ${info.toolProficiency}'),
                    if (info.equipment != null) ...[
                      const SizedBox(height: 4),
                      MarkdownText('Equipment: ${info.equipment}'),
                    ],
                  ],
                ),
              );
            },
          ),
        ],
        SectionLabel(
          'Ability Scores',
          trailing: TextButton(
            onPressed: () =>
                _showEditAbilityScoresDialog(context, character, onChanged),
            child: const Text('Edit Scores'),
          ),
        ),
        StatGrid(
          cells: [
            StatCell('${scores.str}', 'Str · ${cell(scores.str)}'),
            StatCell('${scores.dex}', 'Dex · ${cell(scores.dex)}'),
            StatCell('${scores.con}', 'Con · ${cell(scores.con)}'),
            StatCell('${scores.intel}', 'Int · ${cell(scores.intel)}'),
            StatCell('${scores.wis}', 'Wis · ${cell(scores.wis)}'),
            StatCell('${scores.cha}', 'Cha · ${cell(scores.cha)}'),
          ],
        ),
        for (final MapEntry(key: key, value: (source, value)) in setBy.entries)
          if (value > character.abilityScores.of(key))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${key.toUpperCase()} $value from $source '
                '(your own score: ${character.abilityScores.of(key)}).',
                style: const TextStyle(
                  fontSize: 12,
                  color: LedgerColors.inkDim,
                ),
              ),
            ),
        const SectionLabel('Saving Throws'),
        for (final ability in const ['str', 'dex', 'con', 'int', 'wis', 'cha'])
          Row(
            children: [
              Checkbox(
                value: character.savingThrowProficiencies.contains(ability),
                onChanged: (v) => _toggleSavingThrow(ability, v ?? false),
              ),
              Expanded(child: Text(_abilityName(ability))),
              Text(
                rules.formatModifier(
                  rules.savingThrowModifier(character, ability),
                ),
                style: LedgerTheme.dataStyle(
                  fontSize: 14,
                  weight: FontWeight.w600,
                ),
              ),
            ],
          ),
        const SectionLabel('Skills'),
        for (final ref
            in srdCatalog.skillsByName.values.toList()
              ..sort((a, b) => a.name.compareTo(b.name)))
          Builder(
            builder: (context) {
              final skill = _skillEntryFor(ref);
              return Row(
                children: [
                  Checkbox(
                    value: skill.proficient,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: (v) => _toggleSkillProficient(ref, v ?? false),
                  ),
                  const SizedBox(width: 4),
                  Checkbox(
                    value: skill.expertise,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    onChanged: skill.proficient
                        ? (v) => _toggleSkillExpertise(ref, v ?? false)
                        : null,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('${ref.name} (${_abilityName(ref.ability)})'),
                  ),
                  Text(
                    rules.formatModifier(rules.skillModifier(character, skill)),
                    style: LedgerTheme.dataStyle(
                      fontSize: 14,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              );
            },
          ),
        const Padding(
          padding: EdgeInsets.only(top: 4, bottom: 16),
          child: Text(
            'Second checkbox is Expertise (double proficiency bonus).',
            style: TextStyle(fontSize: 11, color: LedgerColors.inkDim),
          ),
        ),
        const SectionLabel('Proficiencies'),
        _ProficienciesSection(character: character, onChanged: onChanged),
        if (character.history.isNotEmpty) ...[
          const SectionLabel('History'),
          ExpandableGroup(
            builder: (context, group) => Column(
              children: [
                for (final entry in character.history.reversed)
                  ExpandableRow(
                    group: group,
                    groupId: entry.id,
                    title: entry.label,
                    tag: _formatHistoryDate(entry.timestamp),
                    body: Text(entry.detail ?? 'No further detail.'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  String _abilityName(String key) => switch (key) {
    'str' => 'Strength',
    'dex' => 'Dexterity',
    'con' => 'Constitution',
    'int' => 'Intelligence',
    'wis' => 'Wisdom',
    'cha' => 'Charisma',
    _ => key,
  };
}

const _historyMonths = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String _formatHistoryDate(DateTime dt) =>
    '${_historyMonths[dt.month - 1]} ${dt.day}, ${dt.year}';

/// Lets the player directly correct ability scores (a magic item, a DM
/// ruling, fixing a typo) - separate from the Ability Score Improvement
/// flow, which goes through the feat picker instead since it's tied to a
/// specific class-level feature. Either way lands in the same history log
/// via rules.setAbilityScores, so "what changed and why" stays complete
/// regardless of which path made the change.
Future<void> _showEditAbilityScoresDialog(
  BuildContext context,
  Character character,
  VoidCallback onChanged,
) async {
  final scores = character.abilityScores;
  final controllers = {
    'str': TextEditingController(text: '${scores.str}'),
    'dex': TextEditingController(text: '${scores.dex}'),
    'con': TextEditingController(text: '${scores.con}'),
    'int': TextEditingController(text: '${scores.intel}'),
    'wis': TextEditingController(text: '${scores.wis}'),
    'cha': TextEditingController(text: '${scores.cha}'),
  };
  final reasonController = TextEditingController();

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Edit Ability Scores'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final key in const [
                  'str',
                  'dex',
                  'con',
                  'int',
                  'wis',
                  'cha',
                ])
                  SizedBox(
                    width: 72,
                    child: TextField(
                      controller: controllers[key],
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: key.toUpperCase(),
                        isDense: true,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                hintText: 'e.g. Belt of Giant Strength',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (saved == true) {
    int parsed(String key, int fallback) =>
        int.tryParse(controllers[key]!.text.trim())?.clamp(1, 30) ?? fallback;
    final next = AbilityScores(
      str: parsed('str', scores.str),
      dex: parsed('dex', scores.dex),
      con: parsed('con', scores.con),
      intel: parsed('int', scores.intel),
      wis: parsed('wis', scores.wis),
      cha: parsed('cha', scores.cha),
    );
    final reason = reasonController.text.trim();
    rules.setAbilityScores(
      character,
      next,
      label: reason.isEmpty ? 'Ability scores edited' : reason,
    );
    onChanged();
  }
}

class _CombatTab extends StatelessWidget {
  const _CombatTab({required this.character, required this.onChanged});
  final Character character;
  final VoidCallback onChanged;

  Future<void> _addWeapon(BuildContext context) async {
    final picked = await Navigator.of(context).push<SrdRefItem>(
      MaterialPageRoute(
        builder: (_) => CatalogPickerScreen(
          title: 'Add Weapon',
          options: srdCatalog.weaponOptions,
          homebrewKind: 'weapon',
        ),
      ),
    );
    if (picked == null) return;
    final srdWeapon = srdCatalog.weaponsByKey[picked.key];
    if (srdWeapon == null) {
      // Homebrew (or otherwise unresolved) pick - no SRD mechanics to
      // pull from, so ask for them by hand instead of silently dropping
      // the add.
      final entry = picked.isHomebrew ? homebrewById(picked.key) : null;
      var stats = entry != null ? WeaponStats.fromData(entry.data) : null;
      if (stats == null) {
        if (!context.mounted) return;
        stats = await _showHomebrewWeaponDialog(context, picked.name);
        if (stats == null) return;
        if (entry != null) saveHomebrewData(entry.id, stats.toData());
      }
      character.weapons = [
        ...character.weapons,
        stats.toWeapon(
          picked.name,
          proficient: rules.isProficientWithWeapon(
            character,
            picked.name,
            stats.category,
            stats.properties,
          ),
        ),
      ];
      onChanged();
      return;
    }
    character.weapons = [
      ...character.weapons,
      rules.weaponFromSrd(character, srdWeapon),
    ];
    onChanged();
  }

  Future<void> _addMount(BuildContext context) async {
    final mount = await _showMountDialog(context);
    if (mount == null) return;
    character.mounts = [...character.mounts, mount];
    onChanged();
  }

  void _removeMount(Mount mount) {
    character.mounts = character.mounts.where((m) => m != mount).toList();
    onChanged();
  }

  /// Confirms a Short or Long Rest, listing what it would recover first.
  Future<void> _rest(BuildContext context, {required bool longRest}) async {
    final name = longRest ? 'Long Rest' : 'Short Rest';
    final changes = rules.restPreview(character, longRest: longRest);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Take a $name?'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (changes.isEmpty)
                const Text(
                  'Nothing to recover - everything a rest restores is '
                  'already full.',
                  style: TextStyle(color: LedgerColors.inkDim),
                )
              else
                for (final line in changes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• $line'),
                  ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('Take $name'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    longRest ? rules.applyLongRest(character) : rules.applyShortRest(character);
    onChanged();
  }

  void _removeWeapon(String name) {
    character.weapons = character.weapons.where((w) => w.name != name).toList();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final prof = rules.proficiencyBonusForLevel(character.level);

    return ListView(
      padding: _tabPadding,
      children: [
        StatGrid(
          cells: [
            StatCell('${character.currentHp}/${character.maxHp}', 'HP'),
            StatCell('${rules.armorClassFor(character)}', 'AC'),
            StatCell(
              rules.formatModifier(rules.initiativeModifier(character)),
              'Init',
            ),
            StatCell('${rules.speedFor(character)}', 'Spd'),
            StatCell(rules.formatModifier(prof), 'Prof'),
          ],
        ),
        if (character.spellcasting?.concentratingOn != null) ...[
          const SizedBox(height: 12),
          _ConcentrationBanner(character: character, onChanged: onChanged),
        ],
        const SectionLabel('Rests'),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _rest(context, longRest: false),
                child: const Text('Short Rest'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _rest(context, longRest: true),
                child: const Text('Long Rest'),
              ),
            ),
          ],
        ),
        SectionLabel(
          'Hit Points',
          trailing: TextButton(
            onPressed: () => _showMaxHpDialog(context, character, onChanged),
            child: const Text('Max HP'),
          ),
        ),
        Row(
          children: [
            Text(
              '${character.currentHp} / ${character.maxHp}',
              style: LedgerTheme.dataStyle(
                fontSize: 16,
                weight: FontWeight.w700,
              ),
            ),
            if (character.tempHp > 0) ...[
              const SizedBox(width: 8),
              Text(
                '+${character.tempHp} temp',
                style: const TextStyle(
                  color: LedgerColors.inkDim,
                  fontSize: 12,
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final delta in [-5, -1, 1, 5])
              OutlinedButton(
                onPressed: () {
                  rules.applyDamageOrHeal(character, delta);
                  onChanged();
                },
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                ),
                child: Text(delta > 0 ? '+$delta' : '$delta'),
              ),
            OutlinedButton(
              onPressed: () => _showTempHpDialog(context, character, onChanged),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
              ),
              child: const Text('Temp HP'),
            ),
            OutlinedButton(
              onPressed: () =>
                  _showTakeDamageDialog(context, character, onChanged),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
              ),
              child: const Text('Take Damage'),
            ),
          ],
        ),
        const SectionLabel('Hit Dice'),
        Row(
          children: [
            Text(
              '${character.hitDiceTotal - character.hitDiceSpent} / ${character.hitDiceTotal} ${character.hitDiceDie} remaining',
              style: const TextStyle(color: LedgerColors.inkDim),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            OutlinedButton(
              onPressed: character.hitDiceSpent < character.hitDiceTotal
                  ? () => _showSpendHitDieDialog(context, character, onChanged)
                  : null,
              child: const Text('Spend'),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: character.hitDiceSpent > 0
                  ? () {
                      character.hitDiceSpent--;
                      onChanged();
                    }
                  : null,
              icon: const Icon(Icons.undo, size: 18),
              tooltip: 'Undo a spent Hit Die (no HP change)',
              color: LedgerColors.inkDim,
            ),
          ],
        ),
        const SectionLabel('Death Saves'),
        _DeathSaves(character: character, onChanged: onChanged),
        const SectionLabel('Status'),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'HEROIC INSPIRATION',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                      color: LedgerColors.inkDim,
                    ),
                  ),
                  Row(
                    children: [
                      IconButton(
                        onPressed: character.heroicInspiration > 0
                            ? () {
                                character.heroicInspiration--;
                                onChanged();
                              }
                            : null,
                        icon: const Icon(Icons.remove),
                      ),
                      Text(
                        '${character.heroicInspiration}',
                        style: LedgerTheme.dataStyle(
                          fontSize: 16,
                          weight: FontWeight.w700,
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          character.heroicInspiration++;
                          onChanged();
                        },
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'EXHAUSTION',
                    style: TextStyle(
                      fontSize: 11,
                      letterSpacing: 0.6,
                      fontWeight: FontWeight.w600,
                      color: LedgerColors.inkDim,
                    ),
                  ),
                  _ExhaustionRow(character: character, onChanged: onChanged),
                ],
              ),
            ),
          ],
        ),
        SectionLabel(
          'Resources',
          trailing: TextButton(
            onPressed: () =>
                _showAddResourceDialog(context, character, onChanged),
            child: const Text('+ Add Resource'),
          ),
        ),
        ExpandableGroup(
          builder: (context, group) => Column(
            children: [
              for (final resource in character.resources.where(
                (r) =>
                    !character.innateAttacks.any((a) => a.resourceKey == r.key),
              ))
                ExpandableRow(
                  group: group,
                  groupId: resource.key,
                  title: resource.name,
                  leading: Tally(on: resource.used < resource.max),
                  trailing: _SpendRestore(
                    remaining: resource.max - resource.used,
                    max: resource.max,
                    onSpend: resource.used < resource.max
                        ? () {
                            resource.used++;
                            onChanged();
                          }
                        : null,
                    onRestore: resource.used > 0
                        ? () {
                            resource.used--;
                            onChanged();
                          }
                        : null,
                  ),
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ..._resourceUseLines(character, resource),
                      if (rules.isCustomResource(character, resource)) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton(
                              onPressed: () {
                                character.resources = character.resources
                                    .where((r) => r.key != resource.key)
                                    .toList();
                                onChanged();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: LedgerColors.danger,
                              ),
                              child: const Text('Remove'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        ),
        SectionLabel(
          'Weapons',
          trailing: TextButton(
            onPressed: () => _addWeapon(context),
            child: const Text('+ Add Weapon'),
          ),
        ),
        ExpandableGroup(
          builder: (context, group) => Column(
            children: [
              Builder(
                builder: (context) {
                  final unarmed = rules.unarmedStrike(character);
                  return ExpandableRow(
                    group: group,
                    groupId: 'Unarmed Strike',
                    title: 'Unarmed Strike',
                    subtitle: Text(
                      '${rules.formatModifier(unarmed.attack)} / ${unarmed.damage}',
                      style: LedgerTheme.dataStyle(
                        fontSize: 13,
                        color: LedgerColors.inkDim,
                      ),
                    ),
                    body: MarkdownText(
                      'Punch, kick, headbutt: ${unarmed.ability} + Proficiency '
                      'Bonus to hit, ${unarmed.damage} damage. Or instead: '
                      '**Grapple** (target makes a Str or Dex save, DC '
                      '${unarmed.grappleDc}, or is Grappled) or **Shove** (same '
                      'DC, or pushed 5 ft or knocked Prone). Needs a free hand to '
                      'grapple.',
                    ),
                  );
                },
              ),
              for (final attack in character.innateAttacks)
                _InnateAttackRow(
                  character: character,
                  attack: attack,
                  onChanged: onChanged,
                  group: group,
                ),
              for (final weapon in character.weapons)
                _WeaponRow(
                  character: character,
                  weapon: weapon,
                  onRemove: () => _removeWeapon(weapon.name),
                  onChanged: onChanged,
                  group: group,
                ),
            ],
          ),
        ),
        if (rules.pdfAttackRowCount(character) > 6)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'The PDF sheet has room for 6 attacks; '
              '${rules.pdfAttackRowCount(character) - 6} past that '
              "(weapons first, then Breath Weapon, then damage cantrips) "
              "won't be printed.",
              style: const TextStyle(fontSize: 12, color: LedgerColors.inkDim),
            ),
          ),
        SectionLabel(
          'Mounts',
          trailing: TextButton(
            onPressed: () => _addMount(context),
            child: const Text('+ Add Mount'),
          ),
        ),
        ExpandableGroup(
          builder: (context, group) => Column(
            children: [
              for (final mount in character.mounts)
                _MountRow(
                  mount: mount,
                  onChanged: onChanged,
                  onRemove: () => _removeMount(mount),
                  group: group,
                ),
            ],
          ),
        ),
        const SectionLabel('Actions'),
        const _ActionsReference(),
        const SectionLabel('Conditions'),
        _ConditionsSection(character: character, onChanged: onChanged),
        const SizedBox(height: 16),
      ],
    );
  }
}

const _abilityLabels = {
  'str': 'Strength',
  'dex': 'Dexterity',
  'con': 'Constitution',
  'int': 'Intelligence',
  'wis': 'Wisdom',
  'cha': 'Charisma',
};

/// Opens the feat picker (optionally restricted to [category]) and grants
/// whatever's chosen - either directly onto the character (the Features
/// tab's plain "+ Add Feat"), or resolving a Pending Choice if
/// [pendingChoiceId] is given. Ability Score Improvement is special-cased
/// either way: picking it always opens the +2-to-one/+1-to-two follow-up
/// before anything is granted, since the feat alone doesn't say which
/// scores go up. [excludeName] drops one option from the list -
/// _resolveAsiOrFeatChoice's "Choose a Feat" path uses it to hide
/// "Ability Score Improvement" (a real General Feat catalog entry), since
/// that path already offers it as its own dedicated button one screen up.
Future<void> _pickAndGrantFeat(
  BuildContext context,
  Character character,
  VoidCallback onChanged, {
  required String? category,
  String? pendingChoiceId,
  String? excludeName,
}) async {
  final options =
      (category == null
              ? srdCatalog.featOptions
              : srdCatalog.featsByKey.values
                    .where((f) => f.category == category)
                    .map((f) => SrdRefItem(key: f.key, name: f.name))
                    .toList())
          .where((o) => o.name != excludeName)
          .toList();
  final picked = await Navigator.of(context).push<SrdRefItem>(
    MaterialPageRoute(
      builder: (_) => CatalogPickerScreen(
        title: 'Feat',
        options: options,
        homebrewKind: 'feat',
        unavailableReason: (item) =>
            rules.featUnavailableReason(character, item.name),
        // A category-restricted picker (resolving a "Choose a Fighting
        // Style"/"Choose an Epic Boon" Pending Choice) only offers
        // homebrew feats tagged with that same category - an
        // uncategorized or differently-categorized homebrew feat doesn't
        // belong in, say, the Fighting Style list, same as a real SRD
        // General Feat wouldn't. The unrestricted "+ Add Feat"
        // (category: null) still offers every homebrew feat regardless
        // of category, same as it always has.
        homebrewFilter: category == null
            ? null
            : (entry) => entry.category == category,
        // A feat quick-added from inside a restricted picker is tagged
        // with that category immediately, so it actually shows up here
        // again later instead of silently landing uncategorized.
        onHomebrewCreated: category == null
            ? null
            : (entry) => homebrewRepo.update(
                HomebrewEntry(
                  id: entry.id,
                  kind: entry.kind,
                  name: entry.name,
                  desc: entry.desc,
                  source: entry.source,
                  effects: entry.effects,
                  category: category,
                  prerequisite: entry.prerequisite,
                  shortDesc: entry.shortDesc,
                  data: entry.data,
                ),
              ),
      ),
    ),
  );
  if (picked == null) return;
  if (!context.mounted) return;

  final feat = srdCatalog.featsByKey[picked.key];
  Map<String, int>? deltas;
  if (picked.name == 'Ability Score Improvement') {
    deltas = await _showAsiDialog(context);
    if (deltas == null) return; // cancelled the sub-dialog - grant nothing
  } else if (rules.featAbilityIncrease(picked.name) case final increase?) {
    deltas = await _pickFeatAbilityIncrease(
      context,
      character,
      picked.name,
      increase,
    );
    if (deltas == null) return; // cancelled - grant nothing
  }

  // A homebrew pick's key is the HomebrewEntry's id, not an SRD feat key -
  // srdCatalog.featsByKey never matches it, so feat?.fullDescription is
  // always null there. Snapshot the homebrew entry's own desc instead, the
  // same way an SRD pick snapshots feat.fullDescription - gives every
  // homebrew feat a real, portable baseline description the moment it's
  // granted (rules.liveFeatureText also refreshes this live afterward, if
  // a same-named homebrew entry is still present).
  String? desc = feat?.fullDescription;
  if (desc == null && picked.isHomebrew) {
    final homebrew = homebrewRepo.entries.where((e) => e.id == picked.key);
    if (homebrew.isNotEmpty) desc = homebrew.first.desc;
  }

  final grantedFeat = GrantedFeature(
    name: picked.name,
    source: 'feat',
    desc: desc,
  );
  if (pendingChoiceId != null) {
    rules.resolvePendingChoice(
      character,
      pendingChoiceId,
      grantedFeat,
      abilityScoreDeltas: deltas,
    );
  } else {
    rules.grantFeat(character, grantedFeat, abilityScoreDeltas: deltas);
  }
  onChanged();
}

Future<Map<String, int>?> _showAsiDialog(BuildContext context) {
  var mode = 'single'; // 'single' = +2 to one, 'double' = +1 to two
  var first = 'str';
  var second = 'dex';

  return showDialog<Map<String, int>>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          final canConfirm = mode == 'single' || first != second;
          return AlertDialog(
            title: const Text('Ability Score Improvement'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Increase one ability by 2, or two abilities by 1 each (max 20).',
                  style: TextStyle(color: LedgerColors.inkDim),
                ),
                const SizedBox(height: 12),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'single', label: Text('+2 to one')),
                    ButtonSegment(value: 'double', label: Text('+1 to two')),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => setState(() => mode = s.first),
                ),
                const SizedBox(height: 12),
                DropdownButton<String>(
                  value: first,
                  isExpanded: true,
                  items: [
                    for (final key in _abilityLabels.keys)
                      DropdownMenuItem(
                        value: key,
                        child: Text(_abilityLabels[key]!),
                      ),
                  ],
                  onChanged: (v) => setState(() => first = v!),
                ),
                if (mode == 'double') ...[
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    value: second,
                    isExpanded: true,
                    items: [
                      for (final key in _abilityLabels.keys)
                        DropdownMenuItem(
                          value: key,
                          child: Text(_abilityLabels[key]!),
                        ),
                    ],
                    onChanged: (v) => setState(() => second = v!),
                  ),
                  if (first == second)
                    const Text(
                      'Pick two different abilities.',
                      style: TextStyle(
                        color: LedgerColors.danger,
                        fontSize: 12,
                      ),
                    ),
                ],
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: canConfirm
                    ? () => Navigator.of(context).pop(
                        mode == 'single' ? {first: 2} : {first: 1, second: 1},
                      )
                    : null,
                child: const Text('Confirm'),
              ),
            ],
          );
        },
      );
    },
  );
}

/// Max HP, part by part: each level's Hit Die result (level 1 is the
/// die's maximum; later levels are a recorded roll or the average - both
/// editable here), Constitution per level, bonuses from features and
/// items, and a hand adjustment.
Future<void> _showMaxHpDialog(
  BuildContext context,
  Character character,
  VoidCallback onChanged,
) async {
  final sides = int.tryParse(character.hitDiceDie.substring(1)) ?? 8;
  final average = rules.averageHitDieResult(character);
  final rolls = {...character.hitPointRolls};
  final adjustmentController = TextEditingController(
    text: '${character.maxHpAdjustment}',
  );
  final conMod = rules.modifierOf(character, 'con');
  final bonus = rules.maxHpBonus(character);

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final dice = [
          for (var l = 1; l <= character.level; l++)
            l == 1 ? sides : rolls[l] ?? average,
        ];
        final adjustment = int.tryParse(adjustmentController.text.trim()) ?? 0;
        final perLevel = [
          for (final d in dice) (d + conMod) < 1 ? 1 : d + conMod,
        ];
        final total = perLevel.fold(0, (a, b) => a + b) + bonus + adjustment;
        return AlertDialog(
          title: Text('Max HP: ${total < 1 ? 1 : total}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                Text(
                  '${character.hitDiceDie} per level '
                  '${rules.formatModifier(conMod)} Con each (at least 1 per '
                  'level).',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                for (var l = 1; l <= character.level; l++)
                  Row(
                    children: [
                      SizedBox(width: 70, child: Text('Level $l')),
                      if (l == 1)
                        Text('$sides (maximum)')
                      else
                        DropdownButton<int?>(
                          value: rolls[l],
                          items: [
                            DropdownMenuItem(
                              value: null,
                              child: Text('Average ($average)'),
                            ),
                            for (var n = 1; n <= sides; n++)
                              DropdownMenuItem(
                                value: n,
                                child: Text('Rolled $n'),
                              ),
                          ],
                          onChanged: (v) => setState(() {
                            if (v == null) {
                              rolls.remove(l);
                            } else {
                              rolls[l] = v;
                            }
                          }),
                        ),
                      const Spacer(),
                      Text(
                        '+${perLevel[l - 1]}',
                        style: LedgerTheme.dataStyle(fontSize: 13),
                      ),
                    ],
                  ),
                if (bonus != 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Features, feats, and items: ${rules.formatModifier(bonus)}',
                    ),
                  ),
                const SizedBox(height: 6),
                TextField(
                  controller: adjustmentController,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Adjustment',
                    helperText: 'A DM ruling, a curse, anything else',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );
  if (saved != true) return;
  final before = character.maxHp;
  character.hitPointRolls = rolls;
  character.maxHpAdjustment =
      int.tryParse(adjustmentController.text.trim()) ?? 0;
  rules.refreshMaxHp(character);
  if (character.maxHp != before) {
    rules.logHistory(character, 'Max HP: $before → ${character.maxHp}');
  }
  onChanged();
}

/// Sets (never adds to) Temporary Hit Points - see rules.setTempHp for why
/// a new grant replaces rather than stacks. Shows the current amount so
/// the player can decide whether the new grant is actually worth taking.
Future<void> _showTempHpDialog(
  BuildContext context,
  Character character,
  VoidCallback onChanged,
) async {
  final controller = TextEditingController(
    text: character.tempHp > 0 ? '${character.tempHp}' : '',
  );

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Temporary Hit Points'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (character.tempHp > 0)
            Text(
              'Currently ${character.tempHp}.',
              style: const TextStyle(color: LedgerColors.inkDim),
            ),
          const SizedBox(height: 8),
          const Text(
            "Temporary Hit Points don't stack - a new grant replaces what "
            "you have, it doesn't add to it. They're lost first when you "
            'take damage, and they last until depleted or you finish a '
            'Long Rest.',
            style: TextStyle(color: LedgerColors.inkDim, fontSize: 12),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'New amount'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            controller.text = '0';
            Navigator.of(context).pop(true);
          },
          child: const Text('Clear'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Save'),
        ),
      ],
    ),
  );

  if (saved == true) {
    rules.setTempHp(character, int.tryParse(controller.text.trim()) ?? 0);
    onChanged();
  }
}

/// Lets the player enter raw incoming damage plus its type (and whether
/// it's from a magical source) and applies the actual HP loss after any
/// matching resistance/reduction - see rules.computeDamageTaken. Shows
/// every step that changed the number (e.g. "Draconic Resistance: half"),
/// not just the final total, so it's clear why the applied amount isn't
/// the raw one typed in.
Future<void> _showTakeDamageDialog(
  BuildContext context,
  Character character,
  VoidCallback onChanged,
) async {
  final amountController = TextEditingController();
  var damageTypeKey = srdCatalog.damageTypes.isNotEmpty
      ? srdCatalog.damageTypes.first.key
      : 'bludgeoning';
  var magical = false;
  var halfOnSave = false;

  final apply = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final rawAmount = int.tryParse(amountController.text.trim()) ?? 0;
        final result = rules.computeDamageTaken(
          character,
          rawAmount,
          damageTypeKey,
          magical: magical,
          halfOnSave: halfOnSave,
        );
        return AlertDialog(
          title: const Text('Take Damage'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: amountController,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    hintText: 'The full rolled damage, before any save',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: damageTypeKey,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Damage Type'),
                  items: [
                    for (final dt in srdCatalog.damageTypes)
                      DropdownMenuItem(value: dt.key, child: Text(dt.name)),
                  ],
                  onChanged: (v) {
                    if (v != null) setState(() => damageTypeKey = v);
                  },
                ),
                CheckboxListTile(
                  title: const Text('Passed a save (half damage)'),
                  subtitle: const Text(
                    'For an effect that halves damage on a successful '
                    'save (e.g. Fireball) - a different thing from '
                    'resistance, and applies on top of it.',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: halfOnSave,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => halfOnSave = v ?? false),
                ),
                CheckboxListTile(
                  title: const Text('From a magical source'),
                  subtitle: const Text(
                    'Matters for resistance/reduction to nonmagical '
                    'Bludgeoning/Piercing/Slashing (e.g. Heavy Armor '
                    'Master, Rage).',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: magical,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => magical = v ?? false),
                ),
                if (rawAmount > 0) ...[
                  const Divider(),
                  for (final step in result.steps)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 2),
                      child: Text(
                        step,
                        style: const TextStyle(
                          fontSize: 12,
                          color: LedgerColors.inkDim,
                        ),
                      ),
                    ),
                  const SizedBox(height: 4),
                  Text(
                    'Final: ${result.finalAmount} HP',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  if (character.spellcasting?.concentratingOn != null &&
                      result.finalAmount > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        'Concentration: Con save DC '
                        '${rules.concentrationSaveDc(result.finalAmount)} '
                        'to keep it (it ends outright at 0 HP).',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: rawAmount > 0
                  ? () => Navigator.of(context).pop(true)
                  : null,
              child: const Text('Apply'),
            ),
          ],
        );
      },
    ),
  );

  if (apply == true) {
    final rawAmount = int.tryParse(amountController.text.trim()) ?? 0;
    final result = rules.computeDamageTaken(
      character,
      rawAmount,
      damageTypeKey,
      magical: magical,
      halfOnSave: halfOnSave,
    );
    rules.applyDamageOrHeal(character, -result.finalAmount);
    onChanged();
  }
}

/// Lets the player manually add a tracked resource outside the SRD-driven
/// class/species recalculation - e.g. a homebrew magic item's "1/Day"
/// charge (a "Bottomless Tankard"), or a finite consumable that never
/// recharges (a "Jar of Pickles," 6 uses, gone for good once spent).
/// Nothing in this app auto-rolls or auto-applies a resource's effect
/// (Second Wind's own hint is plain text too) - [hint] is exactly where
/// the player keeps their own note on what it currently does.
Future<void> _showAddResourceDialog(
  BuildContext context,
  Character character,
  VoidCallback onChanged,
) async {
  final nameController = TextEditingController();
  final maxController = TextEditingController(text: '1');
  final hintController = TextEditingController();
  var shortRestRecovery = 'none';

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: const Text('Add Resource'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Bottomless Tankard',
                ),
                // The "Add" button's enabled state depends on this text -
                // without this, typing wouldn't rebuild the dialog and the
                // button would stay disabled from its initial (empty) build.
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: maxController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Uses'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: shortRestRecovery,
                decoration: const InputDecoration(labelText: 'Short Rest'),
                items: const [
                  DropdownMenuItem(value: 'none', child: Text('No recovery')),
                  DropdownMenuItem(value: 'full', child: Text('Full recovery')),
                  DropdownMenuItem(
                    value: 'partial',
                    child: Text('+1 use recovers'),
                  ),
                ],
                onChanged: (v) =>
                    setState(() => shortRestRecovery = v ?? 'none'),
              ),
              const SizedBox(height: 4),
              const Text(
                'Always fully recovers on a Long Rest, same as every '
                'other resource.',
                style: TextStyle(fontSize: 11, color: LedgerColors.inkDim),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: hintController,
                maxLines: null,
                minLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'What it does / what it currently holds',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: nameController.text.trim().isEmpty
                ? null
                : () => Navigator.of(context).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );

  if (saved == true) {
    character.resources = [
      ...character.resources,
      Resource(
        key: 'custom_${const Uuid().v4()}',
        name: nameController.text.trim(),
        max: int.tryParse(maxController.text.trim()) ?? 1,
        used: 0,
        hint: hintController.text.trim(),
        shortRestRecovery: shortRestRecovery,
      ),
    ];
    onChanged();
  }
}

Future<void> _showSpendHitDieDialog(
  BuildContext context,
  Character character,
  VoidCallback onChanged,
) async {
  final conMod = rules.modifierOf(character, 'con');
  var roll = rules.rollableAverage(character.hitDiceDie);

  await showDialog<void>(
    context: context,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Spend a Hit Die'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Roll ${character.hitDiceDie}, enter the result, and we'll add your Constitution modifier "
                  '(${rules.formatModifier(conMod)}) and apply the total to your current HP.',
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    IconButton(
                      onPressed: roll > 1 ? () => setState(() => roll--) : null,
                      icon: const Icon(Icons.remove_circle_outline),
                    ),
                    Text('$roll', style: LedgerTheme.dataStyle(fontSize: 20)),
                    IconButton(
                      onPressed: () => setState(() => roll++),
                      icon: const Icon(Icons.add_circle_outline),
                    ),
                  ],
                ),
                Text(
                  'Heals ${(roll + conMod).clamp(0, 999999)} HP.',
                  style: const TextStyle(color: LedgerColors.inkDim),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  rules.spendHitDie(character, roll);
                  onChanged();
                  Navigator.of(context).pop();
                },
                child: const Text('Apply'),
              ),
            ],
          );
        },
      );
    },
  );
}

class _DeathSaves extends StatelessWidget {
  const _DeathSaves({required this.character, required this.onChanged});
  final Character character;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    Widget row(String label, int count, Color color, void Function(int) onSet) {
      return Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(
              label,
              style: const TextStyle(color: LedgerColors.inkDim, fontSize: 13),
            ),
          ),
          for (var n = 1; n <= 3; n++)
            IconButton(
              onPressed: () => onSet(count >= n ? n - 1 : n),
              icon: Icon(
                count >= n ? Icons.circle : Icons.circle_outlined,
                size: 20,
                color: count >= n ? color : LedgerColors.inkDim,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        row('Successes', character.deathSaveSuccesses, LedgerColors.accent, (
          n,
        ) {
          character.deathSaveSuccesses = n;
          onChanged();
        }),
        row('Failures', character.deathSaveFailures, LedgerColors.danger, (n) {
          character.deathSaveFailures = n;
          onChanged();
        }),
      ],
    );
  }
}

class _ExhaustionRow extends StatelessWidget {
  const _ExhaustionRow({required this.character, required this.onChanged});
  final Character character;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: character.exhaustionLevel > 0
              ? () {
                  character.exhaustionLevel--;
                  onChanged();
                }
              : null,
          icon: const Icon(Icons.remove_circle_outline, size: 18),
          color: LedgerColors.inkDim,
        ),
        Text(
          'Level ${character.exhaustionLevel} / 6',
          style: LedgerTheme.dataStyle(fontSize: 14),
        ),
        IconButton(
          onPressed: character.exhaustionLevel < 6
              ? () {
                  character.exhaustionLevel++;
                  onChanged();
                }
              : null,
          icon: const Icon(Icons.add_circle_outline, size: 18),
          color: LedgerColors.inkDim,
        ),
      ],
    );
  }
}

/// The 12 standard actions (and Bonus Action / Reaction / Opportunity
/// Attacks) with their SRD Rules Glossary text - what you can do on a turn,
/// without reaching for the book.
class _ActionsReference extends StatelessWidget {
  const _ActionsReference();

  static const _names = [
    'Attack',
    'Dash',
    'Disengage',
    'Dodge',
    'Help',
    'Hide',
    'Influence',
    'Magic',
    'Ready',
    'Search',
    'Study',
    'Utilize',
    'Bonus Action',
    'Reaction',
    'Opportunity Attacks',
  ];

  @override
  Widget build(BuildContext context) {
    final byName = {for (final t in srdCatalog.rulesGlossary) t.name: t};
    return ExpandableGroup(
      builder: (context, group) => Column(
        children: [
          for (final name in _names)
            if (byName[name] case final term?)
              ExpandableRow(
                group: group,
                groupId: name,
                title: name,
                tag: term.tag == 'Action' ? 'Action' : null,
                body: MarkdownText(term.desc),
              ),
        ],
      ),
    );
  }
}

class _ConditionsSection extends StatelessWidget {
  const _ConditionsSection({required this.character, required this.onChanged});
  final Character character;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in srdCatalog.conditionNames)
              _ConditionChip(
                label: name,
                active: character.activeConditions.contains(name),
                onTap: () {
                  if (character.activeConditions.contains(name)) {
                    character.activeConditions = character.activeConditions
                        .where((c) => c != name)
                        .toList();
                  } else {
                    character.activeConditions = [
                      ...character.activeConditions,
                      name,
                    ];
                  }
                  onChanged();
                },
              ),
          ],
        ),
        if (character.activeConditions.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpandableGroup(
            builder: (context, group) => Column(
              children: [
                for (final name in character.activeConditions)
                  ExpandableRow(
                    group: group,
                    groupId: name,
                    title: name,
                    body: MarkdownText(
                      srdCatalog.conditionDescriptions[name] ?? '',
                    ),
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _ConditionChip extends StatelessWidget {
  const _ConditionChip({
    required this.label,
    required this.active,
    required this.onTap,
  });
  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: active ? LedgerColors.accent : LedgerColors.rule,
          ),
          color: active
              ? LedgerColors.accent.withValues(alpha: 0.18)
              : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: active ? LedgerColors.accent : LedgerColors.inkDim,
          ),
        ),
      ),
    );
  }
}

class _SpendRestore extends StatelessWidget {
  const _SpendRestore({
    required this.remaining,
    required this.max,
    this.onSpend,
    this.onRestore,
  });
  final int remaining;
  final int max;
  final VoidCallback? onSpend;
  final VoidCallback? onRestore;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: onSpend,
          icon: const Icon(Icons.remove_circle_outline, size: 18),
          color: LedgerColors.inkDim,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          tooltip: 'Spend a use',
        ),
        Text('$remaining/$max', style: LedgerTheme.dataStyle(fontSize: 13)),
        IconButton(
          onPressed: onRestore,
          icon: const Icon(Icons.add_circle_outline, size: 18),
          color: LedgerColors.inkDim,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          tooltip: 'Restore a use',
        ),
      ],
    );
  }
}

class _InnateAttackRow extends StatelessWidget {
  const _InnateAttackRow({
    required this.character,
    required this.attack,
    required this.onChanged,
    this.group,
  });
  final Character character;
  final InnateAttack attack;
  final VoidCallback onChanged;
  final ExpandableGroupController? group;

  @override
  Widget build(BuildContext context) {
    final resource = character.resources.firstWhere(
      (r) => r.key == attack.resourceKey,
    );
    final species = character.speciesKey != null
        ? srdCatalog.speciesByKey[character.speciesKey]
        : null;
    // The verbatim SRD trait text (species.json), not a hand-written
    // paraphrase - falls back to the stored desc if this character's
    // species isn't cataloged (homebrew) or has no matching trait.
    final traitMatches =
        species?.traits.where((t) => t.name == attack.name) ?? const [];
    final traitDesc = traitMatches.isNotEmpty
        ? traitMatches.first.desc
        : attack.desc;

    final info = rules.innateAttackInfo(character, attack);
    final damageType = rules.innateAttackDamageType(character, attack);
    final detail = [
      '${info.diceCount}${info.dieType} $damageType',
      if (attack.saveDcFormula.isNotEmpty) 'DC ${info.saveDc}',
    ].join(' · ');

    return ExpandableRow(
      group: group,
      groupId: attack.name,
      title: attack.name,
      subtitle: Text(
        detail,
        style: LedgerTheme.dataStyle(fontSize: 13, color: LedgerColors.inkDim),
      ),
      trailing: _SpendRestore(
        remaining: resource.max - resource.used,
        max: resource.max,
        onSpend: resource.used < resource.max
            ? () {
                resource.used++;
                onChanged();
              }
            : null,
        onRestore: resource.used > 0
            ? () {
                resource.used--;
                onChanged();
              }
            : null,
      ),
      body: MarkdownText(traitDesc),
    );
  }
}

/// A resource row's body: the features that use it, each with its short
/// text, so there's no need to go find them on the Features tab - or the
/// resource's own hint when nothing mentions it (a hand-added resource
/// keeps its hint either way).
List<Widget> _resourceUseLines(Character character, Resource resource) {
  final uses = rules.resourceUses(character, resource);
  final showHint =
      resource.hint.isNotEmpty &&
      (uses.isEmpty || rules.isCustomResource(character, resource));
  return [
    if (showHint) Text(resource.hint),
    for (final (name, text) in uses)
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: MarkdownText('**$name.** $text'),
      ),
  ];
}

class _WeaponRow extends StatelessWidget {
  const _WeaponRow({
    required this.character,
    required this.weapon,
    required this.onChanged,
    this.onRemove,
    this.group,
  });
  final Character character;
  final Weapon weapon;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;
  final ExpandableGroupController? group;

  Future<void> _addSpecialFeature(BuildContext context) async {
    final text = await _showTextDialog(
      context,
      title: 'Add Special Feature',
      hint: "e.g. a homebrew magic weapon's unique ability",
    );
    if (text == null || text.isEmpty) return;
    weapon.specialFeatures = [...weapon.specialFeatures, text];
    onChanged();
  }

  Future<void> _editSpecialFeature(BuildContext context, int index) async {
    final text = await _showTextDialog(
      context,
      title: 'Edit Special Feature',
      initial: weapon.specialFeatures[index],
    );
    if (text == null) return;
    final updated = [...weapon.specialFeatures];
    updated[index] = text;
    weapon.specialFeatures = updated;
    onChanged();
  }

  void _removeSpecialFeature(int index) {
    final updated = [...weapon.specialFeatures]..removeAt(index);
    weapon.specialFeatures = updated;
    onChanged();
  }

  Future<void> _editWeapon(BuildContext context) async {
    final changed = await _showEditWeaponDialog(context, weapon);
    if (changed) onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final attack = rules.attackFor(character, weapon);
    final damage = rules.damageFor(character, weapon);
    final damageEffects = rules.matchingEffects(
      character,
      'damageRoll',
      weapon: weapon,
    );

    return ExpandableRow(
      group: group,
      groupId: weapon.name,
      title: weapon.name,
      subtitle: Text(
        '${rules.formatModifier(attack.bonus)} / ${damage.text}',
        style: LedgerTheme.dataStyle(fontSize: 13, color: LedgerColors.inkDim),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${weapon.damageType.substring(0, 1).toUpperCase()}${weapon.damageType.substring(1)} · ${weapon.properties.join(', ')}',
          ),
          Text('Attack: ${attack.breakdown} · Damage: ${damage.breakdown}'),
          for (final (property, note) in rules.weaponPropertyNotes(weapon))
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: MarkdownText('**$property.** $note'),
            ),
          if (rules.masteryApplies(character, weapon)) ...[
            const SizedBox(height: 4),
            _Chip('${weapon.mastery!.toUpperCase()} MASTERY'),
            const SizedBox(height: 4),
            MarkdownText(weapon.masteryDesc ?? ''),
          ] else if (weapon.mastery != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '${weapon.mastery} mastery - not one of your Weapon Mastery '
                'picks.',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          if (!weapon.proficient)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Not proficient - no Proficiency Bonus on the attack.',
                style: TextStyle(fontSize: 12, color: LedgerColors.danger),
              ),
            ),
          for (final (label, amount) in damageEffects) ...[
            const SizedBox(height: 4),
            _Chip('${label.toUpperCase()} (${rules.formatModifier(amount)})'),
          ],
          for (final (index, feature) in weapon.specialFeatures.indexed) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => _editSpecialFeature(context, index),
                    child: _NoteLine(feature),
                  ),
                ),
                IconButton(
                  onPressed: () => _removeSpecialFeature(index),
                  icon: const Icon(Icons.delete_outline, size: 16),
                  color: LedgerColors.inkDim,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                ),
              ],
            ),
          ],
          if (weapon.specialFeatures.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Text(
                  'Consecutive hits on this target: ',
                  style: TextStyle(fontSize: 12, color: LedgerColors.inkDim),
                ),
                IconButton(
                  onPressed: weapon.hitStreak > 0
                      ? () {
                          weapon.hitStreak--;
                          onChanged();
                        }
                      : null,
                  icon: const Icon(Icons.remove, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                ),
                Text('${weapon.hitStreak}'),
                IconButton(
                  onPressed: () {
                    weapon.hitStreak++;
                    onChanged();
                  },
                  icon: const Icon(Icons.add, size: 16),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 26,
                    minHeight: 26,
                  ),
                ),
                TextButton(
                  onPressed: weapon.hitStreak > 0
                      ? () {
                          weapon.hitStreak = 0;
                          onChanged();
                        }
                      : null,
                  child: const Text('Reset', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          TextButton(
            onPressed: () => _addSpecialFeature(context),
            child: const Text('+ Add Special Feature'),
          ),
          Row(
            children: [
              TextButton(
                onPressed: () => _editWeapon(context),
                child: const Text('Edit'),
              ),
              const Spacer(),
              if (onRemove != null)
                TextButton(
                  onPressed: onRemove,
                  style: TextButton.styleFrom(
                    foregroundColor: LedgerColors.danger,
                  ),
                  child: const Text('Remove'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

Future<String?> _showTextDialog(
  BuildContext context, {
  required String title,
  String? hint,
  String? initial,
}) {
  final controller = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLines: 4,
        minLines: 1,
        decoration: InputDecoration(hintText: hint),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Edits an already-added weapon's own stats in place - proficiency,
/// magic bonus, and Finesse commonly change after the fact (a feat, a
/// found +1 weapon, a DM ruling), and damage dice/type are worth
/// correcting too, not just for a homebrew pick. Returns true if the
/// player saved a change, so the caller knows whether to persist.
Future<bool> _showEditWeaponDialog(BuildContext context, Weapon weapon) async {
  final stats = WeaponStats(
    damageDice: weapon.damageDice,
    damageType: weapon.damageType,
    category: rules.weaponCategory(weapon) ?? 'Simple Melee Weapons',
    properties: [...weapon.properties],
    mastery: weapon.mastery,
  );
  final magicBonusController = TextEditingController(
    text: '${weapon.magicBonus}',
  );
  var proficient = weapon.proficient;

  final saved = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(weapon.name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ...weaponStatsFields(stats, setState),
              const SizedBox(height: 8),
              TextField(
                controller: magicBonusController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Magic bonus',
                  hintText: 'e.g. 1 for a +1 weapon',
                ),
              ),
              CheckboxListTile(
                title: const Text('Proficient'),
                value: proficient,
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setState(() => proficient = v ?? false),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              weapon
                ..damageDice = stats.damageDice
                ..damageType = stats.damageType
                ..category = stats.category
                ..magicBonus = int.tryParse(magicBonusController.text) ?? 0
                ..proficient = proficient
                ..finesse = stats.properties.contains('Finesse')
                ..properties = [...stats.properties]
                ..mastery = stats.mastery
                ..masteryDesc = stats.mastery != null
                    ? srdCatalog.weaponPropertiesByName[stats.mastery]?.desc
                    : null;
              Navigator.of(context).pop(true);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    ),
  );
  return saved ?? false;
}

/// Collects the stats for a homebrew (or otherwise uncataloged) weapon -
/// there's no SRD record to read them from. The picks are saved on the
/// homebrew entry, so the next character to add it skips this.
Future<WeaponStats?> _showHomebrewWeaponDialog(
  BuildContext context,
  String name,
) {
  final stats = WeaponStats();
  return showDialog<WeaponStats>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: weaponStatsFields(stats, setState),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(stats),
            child: const Text('Add'),
          ),
        ],
      ),
    ),
  );
}

class _HomebrewArmorResult {
  const _HomebrewArmorResult({
    required this.isShield,
    required this.stats,
    this.armor,
  });
  final bool isShield;
  final ArmorStats stats;
  final EquippedArmor? armor;
}

/// Collects the stats for homebrew (or uncataloged) armor - category, base
/// AC and how Dex applies, Strength requirement, Stealth - from dropdowns.
/// Also edits already-equipped armor ([initial]). A homebrew entry's picks
/// are saved on it, so it isn't asked again.
Future<_HomebrewArmorResult?> _showHomebrewArmorDialog(
  BuildContext context,
  String name, {
  EquippedArmor? initial,
}) {
  final stats = initial == null
      ? ArmorStats()
      : ArmorStats.fromFormula(
          initial.armorClassFormula,
          category: initial.category,
          strength: initial.strengthRequirement,
          stealth: initial.stealth,
        );
  final acController = TextEditingController(text: '${stats.baseAc}');

  return showDialog<_HomebrewArmorResult>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(name),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: stats.category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: const [
                  DropdownMenuItem(value: 'Light', child: Text('Light')),
                  DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                  DropdownMenuItem(value: 'Heavy', child: Text('Heavy')),
                  DropdownMenuItem(
                    value: 'Shield',
                    child: Text('Shield (+2 AC)'),
                  ),
                ],
                onChanged: (v) => setState(() {
                  stats.category = v!;
                  stats.dexMode = switch (v) {
                    'Medium' => 'max2',
                    'Heavy' => 'none',
                    _ => 'full',
                  };
                }),
              ),
              if (!stats.isShield) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: acController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Base AC'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: stats.dexMode,
                        decoration: const InputDecoration(labelText: 'Dex'),
                        items: const [
                          DropdownMenuItem(value: 'full', child: Text('+ Dex')),
                          DropdownMenuItem(
                            value: 'max2',
                            child: Text('+ Dex (max 2)'),
                          ),
                          DropdownMenuItem(
                            value: 'none',
                            child: Text('No Dex'),
                          ),
                        ],
                        onChanged: (v) => setState(() => stats.dexMode = v!),
                      ),
                    ),
                  ],
                ),
                DropdownButtonFormField<String?>(
                  initialValue: stats.strength,
                  decoration: const InputDecoration(
                    labelText: 'Strength requirement',
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    for (final s in {'Str 13', 'Str 15', ?stats.strength})
                      DropdownMenuItem(value: s, child: Text(s)),
                  ],
                  onChanged: (v) => setState(() => stats.strength = v),
                ),
                CheckboxListTile(
                  title: const Text('Stealth Disadvantage'),
                  value: stats.stealth,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => stats.stealth = v ?? false),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              stats.baseAc =
                  int.tryParse(acController.text.trim()) ?? stats.baseAc;
              Navigator.of(context).pop(
                _HomebrewArmorResult(
                  isShield: stats.isShield,
                  stats: stats,
                  armor: stats.isShield ? null : stats.toArmor(name),
                ),
              );
            },
            child: Text(initial == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    ),
  );
}

/// Collects a mount's own AC/HP/Speed by hand - there's no creature stat
/// block data bundled with this app to pull from (mounts.json is just a
/// carrying-capacity/cost reference table), so the player enters what
/// their DM told them, the same as a homebrew weapon's mechanics.
Future<Currency?> _showCurrencyDialog(BuildContext context, Currency current) {
  final controllers = {
    'CP': TextEditingController(text: '${current.cp}'),
    'SP': TextEditingController(text: '${current.sp}'),
    'EP': TextEditingController(text: '${current.ep}'),
    'GP': TextEditingController(text: '${current.gp}'),
    'PP': TextEditingController(text: '${current.pp}'),
  };
  int read(String key) => int.tryParse(controllers[key]!.text.trim()) ?? 0;

  return showDialog<Currency>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Edit Currency'),
      // A Wrap instead of a Row of Expanded fields: 5 fields squeezed into
      // one row overflow/clip on a narrow phone in portrait. This wraps to
      // 2-3 per row instead, however narrow the dialog ends up.
      content: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final key in controllers.keys)
            SizedBox(
              width: 72,
              child: TextField(
                controller: controllers[key],
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                decoration: InputDecoration(labelText: key),
              ),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(
            Currency(
              cp: read('CP'),
              sp: read('SP'),
              ep: read('EP'),
              gp: read('GP'),
              pp: read('PP'),
            ),
          ),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}

/// Add Mount dialog - also reused to edit an already-added mount in
/// place (pass [initial] to pre-fill); the caller copies the returned
/// Mount's fields onto the real one rather than replacing the object, so
/// its identity (used to find/remove it in the list) doesn't change.
Future<Mount?> _showMountDialog(BuildContext context, {Mount? initial}) {
  final nameController = TextEditingController(text: initial?.name ?? '');
  final acController = TextEditingController(
    text: '${initial?.armorClass ?? 10}',
  );
  final hpController = TextEditingController(
    text: initial != null ? '${initial.maxHp}' : '',
  );
  final speedController = TextEditingController(
    text: '${initial?.speed ?? 30}',
  );
  final notesController = TextEditingController(text: initial?.notes ?? '');

  return showDialog<Mount>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(initial == null ? 'Add Mount' : 'Edit Mount'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Warhorse',
                // The SRD's mounts (names only - their stat blocks aren't
                // in the bundled SRD data, so AC/HP/Speed stay typed).
                suffixIcon: PopupMenuButton<String>(
                  tooltip: 'SRD mounts',
                  icon: const Icon(Icons.arrow_drop_down),
                  onSelected: (name) => nameController.text = name,
                  itemBuilder: (_) => [
                    for (final m in srdCatalog.mountsAndVehicles)
                      PopupMenuItem(value: m.name, child: Text(m.name)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            // A Wrap, not a Row of Expanded fields: 3 fields squeezed into
            // one row overflow/clip on a narrow phone in portrait.
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: acController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'AC'),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: hpController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Max HP'),
                  ),
                ),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: speedController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Speed'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: notesController,
              maxLines: 3,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Notes (optional)',
                hintText: 'Attacks, traits, tack equipped, ...',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final name = nameController.text.trim();
            if (name.isEmpty) return;
            final maxHp = int.tryParse(hpController.text) ?? 1;
            Navigator.of(context).pop(
              Mount(
                name: name,
                armorClass: int.tryParse(acController.text) ?? 10,
                maxHp: maxHp,
                currentHp: initial?.currentHp,
                speed: int.tryParse(speedController.text) ?? 30,
                notes: notesController.text.trim(),
              ),
            );
          },
          child: Text(initial == null ? 'Add' : 'Save'),
        ),
      ],
    ),
  );
}

class _MountRow extends StatelessWidget {
  const _MountRow({
    required this.mount,
    required this.onChanged,
    required this.onRemove,
    this.group,
  });
  final Mount mount;
  final VoidCallback onChanged;
  final VoidCallback onRemove;
  final ExpandableGroupController? group;

  @override
  Widget build(BuildContext context) {
    return ExpandableRow(
      group: group,
      groupId: mount.name,
      title: mount.name,
      tag: mount.disappeared
          ? 'GONE'
          : mount.active
          ? 'MOUNTED'
          : null,
      trailing: Padding(
        padding: const EdgeInsets.only(top: 1),
        child: Text(
          'AC ${mount.armorClass} · ${mount.currentHp}/${mount.maxHp} HP',
          style: LedgerTheme.dataStyle(
            fontSize: 13,
            color: LedgerColors.inkDim,
          ),
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Speed ${mount.speed} ft.'
            '${mount.flySpeed > 0 ? ', Fly ${mount.flySpeed} ft.' : ''}',
          ),
          if (mount.disappeared) ...[
            const SizedBox(height: 4),
            const Text(
              'Disappeared at 0 HP - cast Find Steed again to bring it '
              'back.',
              style: TextStyle(color: LedgerColors.inkDim),
            ),
          ],
          if (mount.traits.isNotEmpty) ...[
            const SizedBox(height: 6),
            MarkdownText(mount.traits),
          ],
          if (mount.rechargeAction != null) ...[
            const SizedBox(height: 6),
            FilterChip(
              label: Text(
                mount.rechargeActionUsed
                    ? '${mount.rechargeAction} - used'
                    : '${mount.rechargeAction} - available',
              ),
              selected: mount.rechargeActionUsed,
              onSelected: (v) {
                mount.rechargeActionUsed = v;
                onChanged();
              },
            ),
          ],
          if (mount.notes.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(mount.notes),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              IconButton(
                onPressed: mount.currentHp > 0
                    ? () {
                        mount.currentHp = (mount.currentHp - 1).clamp(
                          0,
                          mount.maxHp,
                        );
                        if (mount.disappeared) mount.active = false;
                        onChanged();
                      }
                    : null,
                icon: const Icon(Icons.remove, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
              Text('${mount.currentHp} / ${mount.maxHp} HP'),
              IconButton(
                onPressed: mount.currentHp < mount.maxHp
                    ? () {
                        mount.currentHp = (mount.currentHp + 1).clamp(
                          0,
                          mount.maxHp,
                        );
                        onChanged();
                      }
                    : null,
                icon: const Icon(Icons.add, size: 18),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
              ),
            ],
          ),
          Row(
            children: [
              TextButton(
                onPressed: () {
                  mount.active = !mount.active;
                  onChanged();
                },
                child: Text(mount.active ? 'Dismount' : 'Mount up'),
              ),
              TextButton(
                onPressed: () => _editMount(context),
                child: const Text('Edit'),
              ),
              const Spacer(),
              TextButton(
                onPressed: onRemove,
                style: TextButton.styleFrom(
                  foregroundColor: LedgerColors.danger,
                ),
                child: const Text('Remove'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _editMount(BuildContext context) async {
    final updated = await _showMountDialog(context, initial: mount);
    if (updated == null) return;
    mount
      ..name = updated.name
      ..armorClass = updated.armorClass
      ..maxHp = updated.maxHp
      ..currentHp = updated.currentHp.clamp(0, updated.maxHp)
      ..speed = updated.speed
      ..notes = updated.notes;
    onChanged();
  }
}

class _FeaturesTab extends StatelessWidget {
  const _FeaturesTab({required this.character, required this.onChanged});
  final Character character;
  final VoidCallback onChanged;

  Future<void> _addFeat(BuildContext context) =>
      _pickAndGrantFeat(context, character, onChanged, category: null);

  Future<void> _addPendingChoice(BuildContext context) async {
    final controller = TextEditingController();
    final label = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add a Pending Choice'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'e.g. Level 7: Additional Fighting Style',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (label == null || label.isEmpty) return;
    character.pendingChoices = [
      ...character.pendingChoices,
      PendingChoice(id: const Uuid().v4(), label: label),
    ];
    onChanged();
  }

  void _removePendingChoice(String id) {
    character.pendingChoices = character.pendingChoices
        .where((p) => p.id != id)
        .toList();
    onChanged();
  }

  Future<void> _resolvePendingChoice(
    BuildContext context,
    PendingChoice choice,
  ) {
    if (choice.kind == 'subclass') {
      return _resolveSubclassChoice(context, choice);
    }
    if (choice.kind == 'option') {
      return _resolveOptionChoice(context, choice);
    }
    // Falls back to the label for a choice saved before 'asi' existed as
    // a kind - pendingChoicesForLevelUp always phrases it exactly this
    // way ("Level N: Ability Score Improvement"), and a character's
    // already-persisted Pending Choices don't get rewritten just because
    // the app that computes new ones was updated.
    if (choice.kind == 'asi' ||
        choice.label.endsWith('Ability Score Improvement')) {
      return _resolveAsiOrFeatChoice(context, choice);
    }
    return _pickAndGrantFeat(
      context,
      character,
      onChanged,
      category: choice.featCategory,
      pendingChoiceId: choice.id,
    );
  }

  /// The real 2024 rule at an Ability Score Improvement level: take the
  /// ASI itself, or a General Feat instead - offered as its own direct
  /// choice up front, rather than sending the player into the full feat
  /// picker to search for "Ability Score Improvement" by name (it's a
  /// real General Feat catalog entry, just one name among every other
  /// feat there - easy to overlook, not impossible to find).
  Future<void> _resolveAsiOrFeatChoice(
    BuildContext context,
    PendingChoice choice,
  ) async {
    final pickedAsi = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(choice.label),
        content: const Text(
          'Increase your ability scores, or take a General Feat instead.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Choose a Feat'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Ability Score Improvement'),
          ),
        ],
      ),
    );
    if (pickedAsi == null) return;
    if (!context.mounted) return;

    if (pickedAsi) {
      final deltas = await _showAsiDialog(context);
      if (deltas == null) return; // cancelled - resolve nothing
      rules.resolvePendingChoice(
        character,
        choice.id,
        GrantedFeature(name: 'Ability Score Improvement', source: 'feat'),
        abilityScoreDeltas: deltas,
      );
      onChanged();
    } else {
      await _pickAndGrantFeat(
        context,
        character,
        onChanged,
        category: 'General Feat',
        pendingChoiceId: choice.id,
        excludeName: 'Ability Score Improvement',
      );
    }
  }

  /// Opens a picker over the character's class's subclass options (just
  /// one in the free SRD - Champion for Fighter, Evoker for Wizard, ...) -
  /// shown even with a single option, since the point is that the player
  /// explicitly picks it rather than it being auto-assigned.
  /// A feature's picks (Expertise, Weapon Mastery, Invocations, ...) -
  /// through the option picker; the Pending Choice goes away once the set
  /// has all its picks (rules.chooseOptions).
  Future<void> _resolveOptionChoice(
    BuildContext context,
    PendingChoice choice,
  ) async {
    final set = rules.featureOptionSet(character, choice.optionSet ?? '');
    if (set == null) {
      // Whatever granted it is gone (a class change) - nothing to pick.
      _removePendingChoice(choice.id);
      return;
    }
    final picks = await showOptionPicker(
      context,
      character,
      set,
      count: choice.count,
    );
    if (picks == null) return;
    character.pendingChoices = character.pendingChoices
        .where((p) => p.id != choice.id)
        .toList();
    rules.chooseOptions(character, set, picks);
    onChanged();
  }

  Future<void> _resolveSubclassChoice(
    BuildContext context,
    PendingChoice choice,
  ) async {
    final options = rules
        .subclassOptionsFor(character)
        .map((s) => SrdRefItem(key: s.key, name: s.name))
        .toList();
    final picked = await Navigator.of(context).push<SrdRefItem>(
      MaterialPageRoute(
        builder: (_) =>
            CatalogPickerScreen(title: 'Subclass', options: options),
      ),
    );
    if (picked == null) return;
    rules.resolveSubclassChoice(character, choice.id, picked.key);
    onChanged();
  }

  void _removeFeat(String name) {
    character.feats = character.feats.where((f) => f.name != name).toList();
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: _tabPadding,
      children: [
        const SectionLabel('Pending Choices'),
        if (character.pendingChoices.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'Nothing open right now.',
              style: TextStyle(color: LedgerColors.inkDim),
            ),
          ),
        for (final choice in character.pendingChoices)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: LedgerColors.rule)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    choice.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                TextButton(
                  onPressed: () => _resolvePendingChoice(context, choice),
                  child: const Text('Choose'),
                ),
                IconButton(
                  onPressed: () => _removePendingChoice(choice.id),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: LedgerColors.inkDim,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 30,
                    minHeight: 30,
                  ),
                ),
              ],
            ),
          ),
        TextButton(
          onPressed: () => _addPendingChoice(context),
          child: const Text('+ Add one manually'),
        ),
        const SectionLabel('Features & Traits'),
        if (character.features.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'None recorded.',
              style: TextStyle(color: LedgerColors.inkDim),
            ),
          ),
        ExpandableGroup(
          builder: (context, group) => Column(
            children: [
              for (final f in character.features)
                ExpandableRow(
                  group: group,
                  groupId: f.name,
                  title: f.name,
                  tag: f.source,
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarkdownText(
                        rules.liveFeatureText(character, f) ??
                            'No description recorded.',
                      ),
                      FeatureOptionsBlock(
                        character: character,
                        featureName: f.name,
                        onChanged: onChanged,
                      ),
                      _SheetTextBlock(character: character, feature: f),
                    ],
                  ),
                ),
            ],
          ),
        ),
        SectionLabel(
          'Feats',
          trailing: TextButton(
            onPressed: () => _addFeat(context),
            child: const Text('+ Add Feat'),
          ),
        ),
        ExpandableGroup(
          builder: (context, group) => Column(
            children: [
              for (final f in character.feats)
                ExpandableRow(
                  group: group,
                  groupId: f.name,
                  title: f.name,
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      MarkdownText(
                        rules.liveFeatureText(character, f) ??
                            'No description recorded.',
                      ),
                      FeatureOptionsBlock(
                        character: character,
                        featureName: f.name,
                        onChanged: onChanged,
                      ),
                      if (f.name != 'Ability Score Improvement')
                        _SheetTextBlock(character: character, feature: f),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => _removeFeat(f.name),
                            style: TextButton.styleFrom(
                              foregroundColor: LedgerColors.danger,
                            ),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// The short text the exported PDF sheet prints for [feature]
/// (rules.sheetText), under its full rules text, with an Edit button. An
/// edit is saved globally (sheetTextRepo), not on this character, so it
/// applies to everyone with the same feature - the same way a homebrew
/// feat's text does. Saving an empty box, or the default text unchanged,
/// resets to the default instead of storing a copy of it.
class _SheetTextBlock extends StatelessWidget {
  const _SheetTextBlock({required this.character, required this.feature});
  final Character character;
  final GrantedFeature feature;

  Future<void> _edit(BuildContext context) async {
    final key = rules.sheetTextKey(character, feature);
    final defaultText = rules.defaultSheetText(character, feature);
    final controller = TextEditingController(
      text: rules.sheetText(character, feature),
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${feature.name}: sheet text'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "What the exported PDF prints for this - keep it to a line or "
              "two, the sheet's boxes are small. Applies to every "
              'character with it.',
              style: TextStyle(fontSize: 12, color: LedgerColors.inkDim),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: null,
              minLines: 3,
            ),
          ],
        ),
        actions: [
          if (sheetTextRepo[key] != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop(''),
              child: const Text('Reset to Default'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null) return;
    if (result.trim().isEmpty || result.trim() == defaultText) {
      sheetTextRepo.reset(key);
    } else {
      sheetTextRepo.set(key, result);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sheetTextRepo,
      builder: (context, _) {
        final edited =
            sheetTextRepo[rules.sheetTextKey(character, feature)] != null;
        return Container(
          margin: const EdgeInsets.only(top: 10),
          padding: const EdgeInsets.only(left: 8),
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: LedgerColors.accentSoft, width: 2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    edited ? 'ON THE PDF SHEET · EDITED' : 'ON THE PDF SHEET',
                    style: const TextStyle(
                      fontSize: 10,
                      letterSpacing: 1,
                      fontWeight: FontWeight.w600,
                      color: LedgerColors.accent,
                    ),
                  ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => _edit(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 28),
                    ),
                    child: const Text('Edit'),
                  ),
                ],
              ),
              Text(
                rules.sheetText(character, feature),
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        );
      },
    );
  }
}

String? _inventoryCaption(InventoryEntry item) {
  final parts = [
    if (item.attuned) 'Attuned',
    if (item.caption != null) item.caption!,
  ];
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Kind selector + catalog-backed (or freeform "Custom") name picker +
/// quantity, for the Carried section's "+ Add Item." Mirrors the web app's
/// InventorySection Add Item dialog: Gear/Tool/Magic Item pull from the
/// bundled SRD catalogs, Custom is a typed one-off name.
class _AddItemDialog extends StatefulWidget {
  const _AddItemDialog();

  @override
  State<_AddItemDialog> createState() => _AddItemDialogState();
}

class _AddItemDialogState extends State<_AddItemDialog> {
  String _kind = 'gear';
  String? _selectedName;
  final _customNameController = TextEditingController();
  final _quantityController = TextEditingController(text: '1');

  static const _kindLabels = {
    'gear': 'Gear',
    'tool': 'Tool',
    'magicItem': 'Magic Item',
    'custom': 'Custom',
  };

  List<SrdRefItem> get _catalogOptions => switch (_kind) {
    'gear' => srdCatalog.gear,
    'tool' => srdCatalog.tools,
    'magicItem' => srdCatalog.magicItems,
    _ => const [],
  };

  @override
  void dispose() {
    _customNameController.dispose();
    _quantityController.dispose();
    super.dispose();
  }

  Future<void> _pickFromCatalog() async {
    final picked = await Navigator.of(context).push<SrdRefItem>(
      MaterialPageRoute(
        builder: (_) => CatalogPickerScreen(
          title: 'Choose Item',
          options: _catalogOptions,
          homebrewKind: _kind == 'custom' ? null : _kind,
        ),
      ),
    );
    if (picked != null) setState(() => _selectedName = picked.name);
  }

  @override
  Widget build(BuildContext context) {
    final name = _kind == 'custom'
        ? _customNameController.text.trim()
        : _selectedName;
    final canAdd = name != null && name.isNotEmpty;

    return AlertDialog(
      title: const Text('Add Item'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            children: [
              for (final entry in _kindLabels.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: _kind == entry.key,
                  onSelected: (_) => setState(() {
                    _kind = entry.key;
                    _selectedName = null;
                  }),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (_kind == 'custom')
            TextField(
              controller: _customNameController,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Item name'),
              onChanged: (_) => setState(() {}),
            )
          else
            OutlinedButton(
              onPressed: _pickFromCatalog,
              child: Text(_selectedName ?? 'Choose Item…'),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _quantityController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(labelText: 'Quantity'),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: canAdd
              ? () {
                  final qty = int.tryParse(_quantityController.text) ?? 1;
                  Navigator.of(context).pop(
                    InventoryEntry(name: name, quantity: qty < 1 ? 1 : qty),
                  );
                }
              : null,
          child: const Text('Add'),
        ),
      ],
    );
  }
}

class _ItemsTab extends StatelessWidget {
  const _ItemsTab({required this.character, required this.onChanged});
  final Character character;
  final VoidCallback onChanged;

  /// Logs an AC-relevant equipment change to History with a before/after
  /// AC, so the audit trail can answer "why was my AC X at some point" -
  /// not just what's currently equipped. Callers capture [beforeAc] via
  /// rules.armorClassFor right before mutating equippedArmor/
  /// shieldEquipped, then call this right after.
  void _logAcChange(String label, int beforeAc) {
    rules.logHistory(
      character,
      label,
      detail: 'AC: $beforeAc → ${rules.armorClassFor(character)}.',
    );
  }

  Future<void> _addArmor(BuildContext context) async {
    final picked = await Navigator.of(context).push<SrdRefItem>(
      MaterialPageRoute(
        builder: (_) => CatalogPickerScreen(
          title: 'Add Armor',
          options: srdCatalog.armorOptions,
          homebrewKind: 'armor',
        ),
      ),
    );
    if (picked == null) return;
    final beforeAc = rules.armorClassFor(character);
    final armor = srdCatalog.armorByKey[picked.key];
    if (armor == null) {
      // Homebrew (or otherwise unresolved) pick - no SRD mechanics to
      // pull from, so ask for them by hand instead of silently dropping
      // the add.
      final entry = picked.isHomebrew ? homebrewById(picked.key) : null;
      final saved = entry != null ? ArmorStats.fromData(entry.data) : null;
      _HomebrewArmorResult? result;
      if (saved != null) {
        result = _HomebrewArmorResult(
          isShield: saved.isShield,
          stats: saved,
          armor: saved.isShield ? null : saved.toArmor(picked.name),
        );
      } else {
        if (!context.mounted) return;
        result = await _showHomebrewArmorDialog(context, picked.name);
        if (result == null) return;
        if (entry != null) saveHomebrewData(entry.id, result.stats.toData());
      }
      if (result.isShield) {
        character.shieldEquipped = true;
        _logAcChange('Equipped a Shield', beforeAc);
      } else {
        character.equippedArmor = result.armor;
        _logAcChange('Equipped ${result.armor!.name}', beforeAc);
      }
      onChanged();
      return;
    }
    if (armor.category.contains('Shield')) {
      character.shieldEquipped = true;
      _logAcChange('Equipped a Shield', beforeAc);
    } else {
      character.equippedArmor = EquippedArmor(
        name: armor.name,
        armorClassFormula: armor.armorClass,
        strengthRequirement: armor.strength,
        stealth: armor.stealth,
        category: armor.simpleCategory,
      );
      _logAcChange('Equipped ${armor.name}', beforeAc);
    }
    onChanged();
  }

  void _unequipArmor() {
    final beforeAc = rules.armorClassFor(character);
    final name = character.equippedArmor?.name;
    character.equippedArmor = null;
    _logAcChange('Unequipped ${name ?? 'armor'}', beforeAc);
    onChanged();
  }

  Future<void> _editArmor(BuildContext context) async {
    final current = character.equippedArmor;
    if (current == null) return;
    final result = await _showHomebrewArmorDialog(
      context,
      current.name,
      initial: current,
    );
    if (result == null) return;
    final beforeAc = rules.armorClassFor(character);
    if (result.isShield) {
      character.equippedArmor = null;
      character.shieldEquipped = true;
      _logAcChange('Changed ${current.name} to a Shield', beforeAc);
    } else {
      character.equippedArmor = result.armor;
      _logAcChange('Updated ${current.name}', beforeAc);
    }
    onChanged();
  }

  void _unequipShield() {
    final beforeAc = rules.armorClassFor(character);
    character.shieldEquipped = false;
    _logAcChange('Unequipped Shield', beforeAc);
    onChanged();
  }

  void _removeItem(String name) {
    character.inventory = character.inventory
        .where((i) => i.name != name)
        .toList();
    onChanged();
  }

  Future<void> _addInventoryItem(BuildContext context) async {
    final entry = await showDialog<InventoryEntry>(
      context: context,
      builder: (context) => const _AddItemDialog(),
    );
    if (entry == null) return;
    character.inventory = [...character.inventory, entry];
    onChanged();
  }

  Future<void> _editInventoryItem(
    BuildContext context,
    InventoryEntry item,
  ) async {
    final nameController = TextEditingController(text: item.name);
    final quantityController = TextEditingController(text: '${item.quantity}');
    final captionController = TextEditingController(text: item.caption ?? '');

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Edit Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: quantityController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Quantity'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: captionController,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                  ),
                ),
                CheckboxListTile(
                  title: const Text('Equipped'),
                  value: item.equipped,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (v) => setState(() => item.equipped = v ?? false),
                ),
                CheckboxListTile(
                  title: const Text('Attuned'),
                  subtitle: Text(
                    '${rules.attunedCount(character)}/'
                    '${rules.attunementLimit(character)} attuned'
                    '${rules.itemInfo(item.name)?.requiresAttunement == true ? ' · this item requires attunement' : ''}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: item.attuned,
                  contentPadding: EdgeInsets.zero,
                  // At the limit, another item can't be attuned until one
                  // is un-attuned.
                  onChanged:
                      item.attuned ||
                          rules.attunedCount(character) <
                              rules.attunementLimit(character)
                      ? (v) => setState(() => item.attuned = v ?? false)
                      : null,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                if (nameController.text.trim().isNotEmpty) {
                  item.name = nameController.text.trim();
                }
                item.quantity =
                    int.tryParse(quantityController.text) ?? item.quantity;
                item.caption = captionController.text.trim().isEmpty
                    ? null
                    : captionController.text.trim();
                Navigator.of(context).pop();
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final armor = character.equippedArmor;
    return ListView(
      padding: _tabPadding,
      children: [
        SectionLabel(
          'Armor',
          trailing: TextButton(
            onPressed: () => _addArmor(context),
            child: const Text('+ Add Armor'),
          ),
        ),
        if (armor == null && !character.shieldEquipped)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'Unarmored - AC computes as 10 + Dex modifier.',
              style: TextStyle(color: LedgerColors.inkDim),
            ),
          ),
        if (armor != null)
          GestureDetector(
            onTap: () => _editArmor(context),
            child: FactRow(
              label: armor.name,
              value: 'AC ${armor.armorClassFormula}',
              caption: [
                if (armor.category != null) armor.category!,
                if (armor.stealth) 'Stealth Disadvantage',
                if (armor.strengthRequirement != null)
                  'Requires ${armor.strengthRequirement}',
                'tap to edit',
              ].join(' · '),
              onDelete: _unequipArmor,
            ),
          ),
        if (character.shieldEquipped)
          FactRow(label: 'Shield', value: 'AC +2', onDelete: _unequipShield),
        SectionLabel(
          'Carried',
          trailing: TextButton(
            onPressed: () => _addInventoryItem(context),
            child: const Text('+ Add Item'),
          ),
        ),
        if (character.inventory.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'Nothing else carried.',
              style: TextStyle(color: LedgerColors.inkDim),
            ),
          ),
        ExpandableGroup(
          builder: (context, group) => Column(
            children: [
              for (final item in character.inventory)
                Builder(
                  builder: (context) {
                    final info = rules.itemInfo(item.name);
                    final facts = [
                      ?info?.kind,
                      ?info?.rarity,
                      if (info?.requiresAttunement ?? false)
                        'Requires attunement',
                      if (info?.weight != null) info!.weight!,
                      if (info?.cost != null) info!.cost!,
                    ];
                    return ExpandableRow(
                      group: group,
                      groupId: item,
                      title: item.name,
                      tag: item.quantity > 1 ? '×${item.quantity}' : null,
                      leading: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Tally(on: item.equipped),
                      ),
                      subtitle: _inventoryCaption(item) == null
                          ? null
                          : Text(
                              _inventoryCaption(item)!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: LedgerColors.inkDim,
                              ),
                            ),
                      body: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (facts.isNotEmpty) Text(facts.join(' · ')),
                          if (info != null && info.desc.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            MarkdownText(info.desc),
                          ],
                          if (info == null)
                            const Text('No catalog entry for this item.'),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              TextButton(
                                onPressed: () =>
                                    _editInventoryItem(context, item),
                                child: const Text('Edit'),
                              ),
                              TextButton(
                                onPressed: () => _removeItem(item.name),
                                style: TextButton.styleFrom(
                                  foregroundColor: LedgerColors.danger,
                                ),
                                child: const Text('Remove'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
        SectionLabel(
          'Currency',
          trailing: TextButton(
            onPressed: () => _editCurrency(context),
            child: const Text('Edit'),
          ),
        ),
        GestureDetector(
          onTap: () => _editCurrency(context),
          child: StatGrid(
            cells: [
              StatCell('${character.currency.cp}', 'CP'),
              StatCell('${character.currency.sp}', 'SP'),
              StatCell('${character.currency.ep}', 'EP'),
              StatCell('${character.currency.gp}', 'GP'),
              StatCell('${character.currency.pp}', 'PP'),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Future<void> _editCurrency(BuildContext context) async {
    final currency = await _showCurrencyDialog(context, character.currency);
    if (currency == null) return;
    character.currency = currency;
    onChanged();
  }
}

class _SpellsTab extends StatelessWidget {
  const _SpellsTab({required this.character, required this.onChanged});
  final Character character;
  final VoidCallback onChanged;

  /// "Level 3 Evocation · Sorcerer, Wizard" / "Cantrip · Evocation · ..." -
  /// the picker's caption line, with the class lists included so the
  /// "every class" view still shows whose list a spell is really on.
  static String _pickerDetail(SrdSpellRef s) => [
    s.level == 0 ? 'Cantrip · ${s.school}' : 'Level ${s.level} ${s.school}',
    if (s.classes.isNotEmpty) s.classes.join(', '),
  ].join(' · ');

  /// Opens the spell picker - by default only the character's own class
  /// spell list, and (for a leveled spell) only levels they have a slot
  /// for, with a toggle to widen it to every SRD spell. A character with
  /// no SRD class (spellcasting turned on by hand) just gets everything.
  /// Already-known spells are left out. A homebrew spell is asked for its
  /// level, since there's no SRD record to read one from.
  Future<void> _addSpell(BuildContext context, {required bool cantrip}) async {
    final sc = character.spellcasting;
    if (sc == null) return;
    final known = {...sc.cantripsKnown, ...sc.spells.map((s) => s.spellKey)};
    final all =
        srdCatalog.spells
            .where((s) => cantrip ? s.level == 0 : s.level >= 1)
            .where((s) => !known.contains(s.key))
            .toList()
          ..sort(
            (a, b) => a.level != b.level
                ? a.level.compareTo(b.level)
                : a.name.compareTo(b.name),
          );
    final className = rules.spellListClassName(character);
    final maxLevel = rules.highestSlotLevel(character).clamp(1, 9);
    final classList = className == null
        ? null
        : all
              .where(
                (s) =>
                    s.classes.contains(className) &&
                    (cantrip || s.level <= maxLevel),
              )
              .toList();
    SrdRefItem toItem(SrdSpellRef s) =>
        SrdRefItem(key: s.key, name: s.name, detail: _pickerDetail(s));

    final picked = await Navigator.of(context).push<SrdRefItem>(
      MaterialPageRoute(
        builder: (_) => CatalogPickerScreen(
          title: cantrip ? 'Add Cantrip' : 'Add Spell',
          options: (classList ?? all).map(toItem).toList(),
          broaderOptions: classList == null ? null : all.map(toItem).toList(),
          broaderLabel: 'Show spells from every class',
          homebrewKind: 'spell',
        ),
      ),
    );
    if (picked == null || known.contains(picked.key)) return;
    if (cantrip) {
      sc.cantripsKnown = [...sc.cantripsKnown, picked.key];
    } else {
      int? level;
      if (picked.isHomebrew) {
        if (!context.mounted) return;
        level = await _pickHomebrewSpellLevel(context, picked.name);
        if (level == null) return;
      }
      // A new spell starts prepared only while there's room under the
      // class's limit - past it, it's added to the list unprepared (a
      // Wizard's spellbook holding more than they can ready at once).
      final limit = rules.preparedSpellLimit(character);
      final prepared =
          limit == null || rules.preparedSpellCount(character) < limit;
      sc.spells = [
        ...sc.spells,
        KnownSpell(spellKey: picked.key, prepared: prepared, level: level),
      ];
    }
    onChanged();
  }

  Future<int?> _pickHomebrewSpellLevel(BuildContext context, String name) =>
      showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text('What level is $name?'),
          children: [
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                for (var level = 1; level <= 9; level++)
                  OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(level),
                    child: Text('$level'),
                  ),
              ],
            ),
          ],
        ),
      );

  Future<void> _changeAbility(BuildContext context) async {
    final sc = character.spellcasting;
    if (sc == null) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Spellcasting Ability'),
        children: [
          for (final entry in _abilityLabels.entries)
            SimpleDialogOption(
              onPressed: () => Navigator.of(context).pop(entry.key),
              child: Text(
                entry.value,
                style: TextStyle(
                  fontWeight: entry.key == sc.ability
                      ? FontWeight.w700
                      : FontWeight.normal,
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null) return;
    sc.ability = picked;
    onChanged();
  }

  void _removeCantrip(String key) {
    final sc = character.spellcasting;
    if (sc == null) return;
    sc.cantripsKnown = sc.cantripsKnown.where((k) => k != key).toList();
    if (sc.concentratingOn == key) sc.concentratingOn = null;
    onChanged();
  }

  void _removeSpell(String key) {
    final sc = character.spellcasting;
    if (sc == null) return;
    sc.spells = sc.spells.where((s) => s.spellKey != key).toList();
    if (sc.concentratingOn == key) sc.concentratingOn = null;
    onChanged();
  }

  /// "Cantrips 2/3" - just "Cantrips 2" when the class table has no limit
  /// to show (or there's no SRD class to read one from).
  static String _countLabel(String label, int count, int? limit) =>
      limit == null ? '$label ($count)' : '$label ($count/$limit)';

  @override
  Widget build(BuildContext context) {
    final sc = character.spellcasting;
    if (sc == null) {
      return ListView(
        padding: _tabPadding,
        children: [
          const SectionLabel('Spellcasting'),
          const Padding(
            padding: EdgeInsets.only(bottom: 10),
            child: Text(
              'Not set up for this character. Only needed for a spellcasting class.',
              style: TextStyle(color: LedgerColors.inkDim),
            ),
          ),
          OutlinedButton(
            onPressed: () {
              rules.enableSpellcasting(character);
              onChanged();
            },
            child: const Text('Enable Spellcasting'),
          ),
        ],
      );
    }

    final slotLevels = sc.slots.keys.toList()..sort();
    final pactMagic = rules.usesPactMagic(character);
    final cantripLimit = rules.cantripLimit(character);
    final preparedLimit = rules.preparedSpellLimit(character);
    final preparedCount = rules.preparedSpellCount(character);
    final overPrepared = preparedLimit != null && preparedCount > preparedLimit;

    final spellsByLevel = <int, List<(KnownSpell, SrdSpellRef?)>>{};
    final grantedCantrips = <(KnownSpell, SrdSpellRef?)>[];
    for (final known in sc.spells) {
      final ref = rules.knownSpellRef(known);
      if (known.source != null && ref?.level == 0) {
        grantedCantrips.add((known, ref));
        continue;
      }
      spellsByLevel.putIfAbsent(ref?.level ?? 1, () => []).add((known, ref));
    }
    for (final group in spellsByLevel.values) {
      group.sort((a, b) => (a.$2?.name ?? '').compareTo(b.$2?.name ?? ''));
    }

    return ListView(
      padding: _tabPadding,
      children: [
        SectionLabel(
          'Spellcasting',
          trailing: TextButton(
            onPressed: () => _changeAbility(context),
            child: Text(_abilityLabels[sc.ability] ?? sc.ability),
          ),
        ),
        StatGrid(
          cells: [
            StatCell(sc.ability.toUpperCase(), 'Ability'),
            StatCell(
              rules.formatModifier(rules.spellcastingModifier(character)),
              'Mod',
            ),
            StatCell('${rules.spellSaveDc(character)}', 'Save DC'),
            StatCell(
              rules.formatModifier(rules.spellAttackBonus(character)),
              'Spell Atk',
            ),
          ],
        ),
        if (sc.concentratingOn != null) ...[
          const SizedBox(height: 12),
          _ConcentrationBanner(character: character, onChanged: onChanged),
        ],
        SectionLabel(pactMagic ? 'Pact Magic Slots' : 'Spell Slots'),
        if (pactMagic)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'All come back on a Short or Long Rest.',
              style: TextStyle(color: LedgerColors.inkDim, fontSize: 12),
            ),
          ),
        if (slotLevels.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'No spell slots yet.',
              style: TextStyle(color: LedgerColors.inkDim),
            ),
          )
        else
          for (final level in slotLevels)
            _SlotRow(
              level: level,
              slot: sc.slots[level]!,
              onChanged: onChanged,
            ),
        SectionLabel(
          _countLabel('Cantrips', sc.cantripsKnown.length, cantripLimit),
          trailing: TextButton(
            onPressed: () => _addSpell(context, cantrip: true),
            child: const Text('+ Add Cantrip'),
          ),
        ),
        if (sc.cantripsKnown.isEmpty && grantedCantrips.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: Text(
              'None known.',
              style: TextStyle(color: LedgerColors.inkDim),
            ),
          ),
        ExpandableGroup(
          builder: (context, group) => Column(
            children: [
              for (final key in sc.cantripsKnown)
                _SpellRow(
                  character: character,
                  spellKey: key,
                  spell: rules.spellRefFor(key, homebrewLevel: 0),
                  onRemove: () => _removeCantrip(key),
                  onChanged: onChanged,
                  group: group,
                ),
              for (final (known, ref) in grantedCantrips)
                _SpellRow(
                  character: character,
                  spellKey: known.spellKey,
                  spell: ref,
                  known: known,
                  onRemove: () {},
                  onChanged: onChanged,
                  group: group,
                ),
            ],
          ),
        ),
        SectionLabel(
          _countLabel('Prepared Spells', preparedCount, preparedLimit),
          trailing: TextButton(
            onPressed: () => _addSpell(context, cantrip: false),
            child: const Text('+ Add Spell'),
          ),
        ),
        if (preparedLimit != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              overPrepared
                  ? '${preparedCount - preparedLimit} more prepared than '
                        'your limit of $preparedLimit - untick some.'
                  : 'Tick a spell to prepare it. Always-prepared spells '
                        "(starred) don't count toward the limit.",
              style: TextStyle(
                fontSize: 12,
                color: overPrepared ? LedgerColors.danger : LedgerColors.inkDim,
              ),
            ),
          ),
        if (sc.spells.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'None known.',
              style: TextStyle(color: LedgerColors.inkDim),
            ),
          ),
        ExpandableGroup(
          builder: (context, group) => Column(
            children: [
              for (final level in spellsByLevel.keys.toList()..sort()) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 2),
                  child: Text(
                    'Level $level',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: LedgerColors.inkDim,
                    ),
                  ),
                ),
                for (final (known, ref) in spellsByLevel[level]!)
                  _SpellRow(
                    character: character,
                    spellKey: known.spellKey,
                    spell: ref,
                    known: known,
                    onRemove: () => _removeSpell(known.spellKey),
                    onChanged: onChanged,
                    group: group,
                  ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

/// One slot level as a row of tappable pips - filled = still available.
/// Tapping a filled pip spends a slot; tapping an empty one gets one back
/// (the same two actions as a resource's spend/restore buttons, just laid
/// out the way slots are ticked off on paper).
class _SlotRow extends StatelessWidget {
  const _SlotRow({
    required this.level,
    required this.slot,
    required this.onChanged,
  });
  final int level;
  final SpellSlot slot;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final remaining = slot.max - slot.used;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          SizedBox(width: 64, child: Text('Level $level')),
          Expanded(
            child: Wrap(
              spacing: 4,
              children: [
                for (var i = 0; i < slot.max; i++)
                  InkWell(
                    onTap: () {
                      slot.used = i < remaining ? slot.used + 1 : slot.used - 1;
                      onChanged();
                    },
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: LedgerColors.accent,
                            width: 1.4,
                          ),
                          color: i < remaining
                              ? LedgerColors.accent
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            '$remaining/${slot.max}',
            style: LedgerTheme.dataStyle(fontSize: 13),
          ),
        ],
      ),
    );
  }
}

/// "Concentrating on Bless - End" - shown on the Spells tab and at the top
/// of the Combat tab, since Concentration is what damage threatens.
class _ConcentrationBanner extends StatelessWidget {
  const _ConcentrationBanner({
    required this.character,
    required this.onChanged,
  });
  final Character character;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final key = character.spellcasting?.concentratingOn;
    if (key == null) return const SizedBox.shrink();
    final name = rules.spellRefFor(key)?.name ?? key;
    return Container(
      padding: const EdgeInsets.only(left: 10),
      decoration: BoxDecoration(
        border: Border.all(color: LedgerColors.accent),
        color: LedgerColors.accent.withValues(alpha: 0.12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.center_focus_strong_outlined,
            size: 18,
            color: LedgerColors.accent,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Concentrating on $name',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const Text(
                  'Taking damage: Con save, DC 10 or half the damage.',
                  style: TextStyle(fontSize: 11, color: LedgerColors.inkDim),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () {
              rules.endConcentration(character);
              onChanged();
            },
            child: const Text('End'),
          ),
        ],
      ),
    );
  }
}

/// A cantrip ([known] null) or a known spell - name, school/Concentration/
/// Ritual tag, a one-line casting summary, and (expanded) the full SRD
/// text. A known spell also carries its prepared toggle (a star instead when
/// always prepared) and the always-prepared switch. "Cast" shows for a
/// prepared spell, and for a cantrip only when it needs Concentration -
/// casting any other cantrip changes nothing this sheet tracks.
class _SpellRow extends StatelessWidget {
  const _SpellRow({
    required this.character,
    required this.spellKey,
    required this.spell,
    required this.onRemove,
    required this.onChanged,
    this.known,
    this.group,
  });
  final Character character;
  final String spellKey;
  final SrdSpellRef? spell;
  final KnownSpell? known;
  final VoidCallback onRemove;
  final VoidCallback onChanged;
  final ExpandableGroupController? group;

  static String _detailText(SrdSpellRef s) => [
    '${s.castingTime} · ${s.range} · ${s.components}',
    '${s.duration}${s.concentration ? ' (Concentration)' : ''}${s.ritual ? ' · Ritual' : ''}',
    '',
    s.desc,
    if (s.higherLevel != null) '\n**At Higher Levels.** ${s.higherLevel}',
  ].join('\n');

  bool get _canCast {
    final s = spell;
    if (s == null) return false;
    final k = known;
    if (k == null || s.level == 0) return s.concentration;
    if (!k.prepared && !k.alwaysPrepared) return false;
    final free = rules.freeCastsLeft(k);
    return s.ritual ||
        (free != null && free != 0) ||
        rules.castableSlotLevels(character, s.level).isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final s = spell;
    final k = known;
    final freeLeft = k != null ? rules.freeCastsLeft(k) : null;
    final freeText = freeLeft == null
        ? ''
        : freeLeft == rules.atWill
        ? 'at will'
        : '$freeLeft/${k!.freeCasts} free '
              '${k.freeCastRecovery == 'short' ? 'per Short Rest' : 'per Long Rest'}';
    final summary = s == null
        ? ''
        : [
            // "Bonus Action, which you take..." -> "Bonus Action"; "Action
            // or Ritual" -> "Action" (the tag already says Ritual).
            if (s.castingTime.isNotEmpty)
              s.castingTime.split(RegExp(r',| or Ritual')).first,
            if (s.range.isNotEmpty) s.range,
            rules.spellSummary(character, s, ability: k?.abilityOverride),
            freeText,
          ].where((part) => part.isNotEmpty).join(' · ');
    final tag = s == null
        ? null
        : [
            s.school,
            if (s.concentration) 'Conc.',
            if (s.ritual) 'Ritual',
            if (k?.source != null) k!.source!,
          ].join(' · ');

    return ExpandableRow(
      group: group,
      groupId: spellKey,
      title: s?.name ?? spellKey,
      tag: tag,
      leading: k == null
          ? null
          : k.alwaysPrepared
          ? const Padding(
              padding: EdgeInsets.only(top: 1),
              child: Icon(Icons.star, size: 14, color: LedgerColors.accent),
            )
          : InkWell(
              onTap: () {
                k.prepared = !k.prepared;
                onChanged();
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 4, 2, 8),
                child: Tally(on: k.prepared),
              ),
            ),
      subtitle: summary.isEmpty
          ? null
          : Text(
              summary,
              style: const TextStyle(fontSize: 12, color: LedgerColors.inkDim),
            ),
      trailing: _canCast
          ? TextButton(
              onPressed: () =>
                  _showCastDialog(context, character, s!, onChanged, known: k),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                minimumSize: const Size(0, 30),
              ),
              child: const Text('Cast'),
            )
          : null,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          MarkdownText(
            s != null
                ? _detailText(s)
                : 'This spell no longer resolves - its homebrew entry may '
                      'have been deleted.',
          ),
          const SizedBox(height: 8),
          if (k?.source != null)
            Text(
              'From ${k!.source} - always prepared; it goes away if that '
              'does.',
              style: const TextStyle(fontSize: 12),
            )
          else
            Row(
              children: [
                if (k != null)
                  FilterChip(
                    label: const Text('Always prepared'),
                    selected: k.alwaysPrepared,
                    onSelected: (v) {
                      k.alwaysPrepared = v;
                      if (v) k.prepared = true;
                      onChanged();
                    },
                  ),
                const Spacer(),
                TextButton(
                  onPressed: onRemove,
                  style: TextButton.styleFrom(
                    foregroundColor: LedgerColors.danger,
                  ),
                  child: const Text('Remove'),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// Casting a spell: pick which slot to spend (any available slot at or
/// above the spell's level - upcasting shows the spell's own "At Higher
/// Levels" text), or cast it as a Ritual for no slot if it allows that.
/// A cantrip skips straight to casting - it has no slot to choose. Warns
/// when a Concentration spell will end one already being held.
Future<void> _showCastDialog(
  BuildContext context,
  Character character,
  SrdSpellRef spell,
  VoidCallback onChanged, {
  KnownSpell? known,
}) async {
  const ritual = -1;
  const free = -2;
  final freeLeft = known != null ? rules.freeCastsLeft(known) : null;
  final messenger = ScaffoldMessenger.of(context);
  int? choice;
  final summonsSteed = spell.key == rules.findSteedKey;
  var steedType =
      rules.summonedMount(character, rules.findSteedKey)?.creatureType ??
      rules.steedCreatureTypes.first;

  if (spell.level > 0) {
    final levels = rules.castableSlotLevels(character, spell.level);
    choice = freeLeft != null && freeLeft != 0
        ? free
        : levels.isNotEmpty
        ? levels.first
        : (spell.ritual ? ritual : null);
    final current = character.spellcasting?.concentratingOn;
    final currentName = current == null
        ? null
        : rules.spellRefFor(current)?.name ?? current;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text('Cast ${spell.name}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (levels.isEmpty && (freeLeft == null || freeLeft == 0))
                  Text(
                    'No level ${spell.level}+ slots left.',
                    style: const TextStyle(color: LedgerColors.inkDim),
                  ),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (freeLeft != null && freeLeft != 0)
                      ChoiceChip(
                        label: Text(
                          freeLeft == rules.atWill
                              ? 'At will (no slot)'
                              : 'Free cast ($freeLeft left)',
                        ),
                        selected: choice == free,
                        onSelected: (_) => setState(() => choice = free),
                      ),
                    for (final level in levels)
                      ChoiceChip(
                        label: Text(
                          'Level $level '
                          '(${character.spellcasting!.slots[level]!.max - character.spellcasting!.slots[level]!.used} left)',
                        ),
                        selected: choice == level,
                        onSelected: (_) => setState(() => choice = level),
                      ),
                    if (spell.ritual)
                      ChoiceChip(
                        label: const Text('As a Ritual (no slot)'),
                        selected: choice == ritual,
                        onSelected: (_) => setState(() => choice = ritual),
                      ),
                  ],
                ),
                if (summonsSteed) ...[
                  const SizedBox(height: 12),
                  const Text(
                    'Steed creature type',
                    style: TextStyle(fontSize: 12, color: LedgerColors.inkDim),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final type in rules.steedCreatureTypes)
                        ChoiceChip(
                          label: Text(type),
                          selected: steedType == type,
                          onSelected: (_) => setState(() => steedType = type),
                        ),
                    ],
                  ),
                ],
                if (choice == ritual)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'Takes 10 minutes longer than its normal casting time.',
                      style: TextStyle(
                        fontSize: 12,
                        color: LedgerColors.inkDim,
                      ),
                    ),
                  ),
                if (choice != null &&
                    choice! > spell.level &&
                    spell.higherLevel != null &&
                    !summonsSteed)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      'Upcast: ${spell.higherLevel}',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                if (spell.concentration)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Text(
                      currentName != null && current != spell.key
                          ? 'Needs Concentration - this ends your '
                                'Concentration on $currentName.'
                          : 'Needs Concentration.',
                      style: const TextStyle(
                        fontSize: 12,
                        color: LedgerColors.inkDim,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: choice == null
                  ? null
                  : () => Navigator.of(context).pop(true),
              child: const Text('Cast'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
  }

  final slotLevel = choice == null || choice! < 0 ? null : choice;
  final ended = rules.castSpell(
    character,
    spell,
    slotLevel: slotLevel,
    freeCastFrom: choice == free ? known : null,
  );
  final steed = summonsSteed
      ? rules.summonSteed(
          character,
          spellLevel: slotLevel ?? spell.level,
          creatureType: steedType,
          ability: known?.abilityOverride,
        )
      : null;
  onChanged();
  final how = slotLevel != null
      ? ' with a level $slotLevel slot'
      : choice == ritual
      ? ' as a Ritual'
      : choice == free
      ? ' without a slot'
      : '';
  final endedText = ended == null
      ? ''
      : ' - ended Concentration on ${rules.spellRefFor(ended)?.name ?? ended}';
  final steedText = steed == null
      ? ''
      : ' - ${steed.name} is under Mounts on the Combat tab';
  messenger.showSnackBar(
    SnackBar(content: Text('Cast ${spell.name}$how$endedText$steedText.')),
  );
}

/// A feat's own ability score increase: applied straight away when it can
/// only go to one ability (Great Weapon Master's Strength), otherwise the
/// player picks which (Grappler's Strength or Dexterity, an Epic Boon's
/// any). Scores already at the feat's maximum can't be picked. Null if
/// cancelled.
Future<Map<String, int>?> _pickFeatAbilityIncrease(
  BuildContext context,
  Character character,
  String featName,
  rules.FeatAbilityIncrease increase,
) async {
  final scores = character.abilityScores;
  if (increase.abilities.length == 1) {
    return {increase.abilities.single: increase.amount};
  }
  return showDialog<Map<String, int>>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text('$featName: increase which score?'),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
          child: Text(
            '+${increase.amount}, to a maximum of ${increase.max}.',
            style: const TextStyle(fontSize: 12, color: LedgerColors.inkDim),
          ),
        ),
        for (final key in increase.abilities)
          SimpleDialogOption(
            onPressed: scores.of(key) >= increase.max
                ? null
                : () => Navigator.of(context).pop({key: increase.amount}),
            child: Text(
              '${_abilityLabels[key] ?? key}  ${scores.of(key)}'
              '${scores.of(key) >= increase.max ? ' (at maximum)' : ' → ${(scores.of(key) + increase.amount).clamp(0, increase.max)}'}',
              style: TextStyle(
                color: scores.of(key) >= increase.max
                    ? LedgerColors.inkDim
                    : LedgerColors.ink,
              ),
            ),
          ),
      ],
    ),
  );
}

/// Armor training, weapon, and tool proficiencies: what the class and
/// background grant (locked), plus extras added here or by a feature
/// choice (Protector, Warden). Changing weapons re-checks every weapon's
/// proficiency.
class _ProficienciesSection extends StatelessWidget {
  const _ProficienciesSection({
    required this.character,
    required this.onChanged,
  });
  final Character character;
  final VoidCallback onChanged;

  void _changed() {
    rules.refreshWeaponProficiency(character);
    onChanged();
  }

  Future<void> _addWeapon(BuildContext context) async {
    final picked = await Navigator.of(context).push<SrdRefItem>(
      MaterialPageRoute(
        builder: (_) => CatalogPickerScreen(
          title: 'Weapon Proficiency',
          options: [
            for (final w in srdCatalog.weaponOptions)
              if (!character.extraWeaponProficiencies.contains(w.name)) w,
          ],
          homebrewKind: 'weapon',
        ),
      ),
    );
    if (picked == null ||
        character.extraWeaponProficiencies.contains(picked.name)) {
      return;
    }
    character.extraWeaponProficiencies = [
      ...character.extraWeaponProficiencies,
      picked.name,
    ];
    _changed();
  }

  Future<void> _addTool(BuildContext context) async {
    final picked = await Navigator.of(context).push<SrdRefItem>(
      MaterialPageRoute(
        builder: (_) => CatalogPickerScreen(
          title: 'Tool Proficiency',
          options: srdCatalog.tools,
          homebrewKind: 'tool',
        ),
      ),
    );
    if (picked == null ||
        character.extraToolProficiencies.contains(picked.name)) {
      return;
    }
    character.extraToolProficiencies = [
      ...character.extraToolProficiencies,
      picked.name,
    ];
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final fromClass = rules.classArmorTraining(character);
    final training = rules.armorTraining(character);
    final classCategories = rules.classWeaponCategories(character);
    final classCondition = rules.classWeaponCondition(character);
    const categories = ['Simple weapons', 'Martial weapons'];
    final baseTools = rules
        .toolProficiencies(character)
        .where((t) => !character.extraToolProficiencies.contains(t))
        .toList();
    const label = TextStyle(fontSize: 12, color: LedgerColors.inkDim);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Armor Training', style: label),
        Wrap(
          spacing: 6,
          children: [
            for (final category in const [
              'Light',
              'Medium',
              'Heavy',
              'Shields',
            ])
              FilterChip(
                label: Text(category),
                selected: training.contains(category),
                // Class-granted training can't be switched off here.
                onSelected: fromClass.contains(category)
                    ? null
                    : (v) {
                        character.extraArmorTraining = v
                            ? [...character.extraArmorTraining, category]
                            : character.extraArmorTraining
                                  .where((a) => a != category)
                                  .toList();
                        onChanged();
                      },
              ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Expanded(child: Text('Weapons', style: label)),
            TextButton(
              onPressed: () => _addWeapon(context),
              child: const Text('+ Add'),
            ),
          ],
        ),
        Wrap(
          spacing: 6,
          children: [
            for (final category in categories)
              FilterChip(
                label: Text(category.replaceFirst(' weapons', '')),
                selected:
                    classCategories.contains(category) ||
                    character.extraWeaponProficiencies.contains(category),
                // Class-granted categories can't be switched off here.
                onSelected: classCategories.contains(category)
                    ? null
                    : (v) {
                        character.extraWeaponProficiencies = v
                            ? [...character.extraWeaponProficiencies, category]
                            : character.extraWeaponProficiencies
                                  .where((w) => w != category)
                                  .toList();
                        _changed();
                      },
              ),
          ],
        ),
        if (classCondition != null &&
            !character.extraWeaponProficiencies.contains('Martial weapons'))
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 4),
            child: Text(
              'Plus $classCondition (from your class).',
              style: const TextStyle(fontSize: 12, color: LedgerColors.inkDim),
            ),
          ),
        Wrap(
          spacing: 6,
          children: [
            for (final w in character.extraWeaponProficiencies)
              if (!categories.contains(w))
                InputChip(
                  label: Text(w),
                  onDeleted: () {
                    character.extraWeaponProficiencies = character
                        .extraWeaponProficiencies
                        .where((x) => x != w)
                        .toList();
                    _changed();
                  },
                ),
          ],
        ),
        Row(
          children: [
            const Expanded(child: Text('Tools', style: label)),
            TextButton(
              onPressed: () => _addTool(context),
              child: const Text('+ Add'),
            ),
          ],
        ),
        if (baseTools.isNotEmpty) MarkdownText(baseTools.join(', ')),
        Wrap(
          spacing: 6,
          children: [
            for (final t in character.extraToolProficiencies)
              InputChip(
                label: Text(t),
                onDeleted: () {
                  character.extraToolProficiencies = character
                      .extraToolProficiencies
                      .where((x) => x != t)
                      .toList();
                  onChanged();
                },
              ),
          ],
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(border: Border.all(color: LedgerColors.accent)),
      child: Text(
        label,
        style: LedgerTheme.dataStyle(
          fontSize: 10,
          weight: FontWeight.w600,
          color: LedgerColors.accent,
        ),
      ),
    );
  }
}

class _NoteLine extends StatelessWidget {
  const _NoteLine(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.only(left: 8),
      decoration: const BoxDecoration(
        border: Border(
          left: BorderSide(color: LedgerColors.accentSoft, width: 2),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontStyle: FontStyle.italic,
          color: LedgerColors.inkDim,
        ),
      ),
    );
  }
}
