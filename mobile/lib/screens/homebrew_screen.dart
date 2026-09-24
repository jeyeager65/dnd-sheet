import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/character_repository.dart';
import '../data/export_bundle.dart';
import '../data/homebrew_repository.dart';
import '../data/srd_catalog.dart';
import '../domain/rules.dart' as rules;
import '../models/effect.dart';
import '../models/homebrew.dart';
import '../theme/ledger_theme.dart';
import '../widgets/layout.dart';
import '../widgets/ledger_bits.dart';
import 'homebrew_rules_editor.dart';
import 'share_json.dart';

const _kindLabels = {
  'spell': 'Spells',
  'species': 'Species',
  'background': 'Backgrounds',
  'feat': 'Feats',
  'class': 'Classes',
  'subclass': 'Subclasses',
  'weapon': 'Weapons',
  'armor': 'Armor',
  'gear': 'Gear',
  'tool': 'Tools',
  'magicItem': 'Magic Items',
  'language': 'Languages',
};

String _kindLabel(String kind) => _kindLabels[kind] ?? kind;

/// Row subtitle for the list screen - Source, plus (for a feat) its
/// Category and Prerequisite when set, so both are visible at a glance
/// without opening the editor.
String _entrySubtitle(HomebrewEntry entry) {
  final parts = [
    entry.source == 'official' ? 'Official (non-SRD)' : 'Homebrew',
  ];
  if (entry.kind == 'feat') {
    if (entry.category != null) parts.add(entry.category!);
    if (entry.prerequisite != null) {
      parts.add('Prerequisite: ${entry.prerequisite}');
    }
  }
  return parts.join(' · ');
}

/// Browse/edit UI for the player's own homebrew content -
/// [HomebrewEntry] previously had no dedicated screen at all, only inline
/// "type a name" quick-add pickers (catalog_picker_screen.dart). Reached
/// from ReferenceScreen's "My Content" group, since Reference is already
/// the one screen open from both the character list and an open
/// character sheet.
class HomebrewListScreen extends StatefulWidget {
  const HomebrewListScreen({super.key});

  @override
  State<HomebrewListScreen> createState() => _HomebrewListScreenState();
}

class _HomebrewListScreenState extends State<HomebrewListScreen> {
  /// Prompts for a kind + name and creates a new entry directly from this
  /// screen, then opens it in the editor to fill in details - previously
  /// the only way to create homebrew was to type a name into a catalog
  /// picker on a character sheet first.
  Future<void> _add() async {
    var kind = 'feat';
    final nameController = TextEditingController();

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Homebrew'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: kind,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Kind'),
                items: [
                  for (final entry in _kindLabels.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (v) {
                  if (v != null) setDialogState(() => kind = v);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Name'),
                onChanged: (_) => setDialogState(() {}),
              ),
            ],
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

    if (created != true) return;
    final entry = homebrewRepo.create(kind, nameController.text.trim());
    setState(() {});
    await _edit(entry);
  }

  Future<void> _delete(HomebrewEntry entry) async {
    final referencing = charactersRepo.charactersReferencing(entry);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${entry.name}?'),
        content: Text(
          referencing.isEmpty
              ? 'This permanently deletes the homebrew entry. It cannot be undone.'
              : 'Used by ${referencing.join(', ')} - deleting this removes its '
                    "effects from ${referencing.length == 1 ? 'that character' : 'those characters'}; "
                    "the item itself stays, it just stops granting anything. Delete anyway?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: LedgerColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      homebrewRepo.delete(entry.id);
      setState(() {});
    }
  }

  Future<void> _edit(HomebrewEntry entry) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => HomebrewEditScreen(entry: entry)));
    setState(() {});
  }

  /// Merges a My Homebrew export file - entries this device already has
  /// (same kind and name) are left as they are, never overwritten.
  Future<void> _import() async {
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (picked == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final entries = parseHomebrewBundle(
        utf8.decode(await picked.readAsBytes()),
      );
      final before = homebrewRepo.entries.length;
      mergeHomebrew(entries);
      final added = homebrewRepo.entries.length - before;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Imported $added new '
            '${added == 1 ? 'entry' : 'entries'}'
            '${entries.length > added ? ' (${entries.length - added} already here)' : ''}.',
          ),
        ),
      );
      setState(() {});
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text("Couldn't import that file: $e")),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final byKind = <String, List<HomebrewEntry>>{};
    for (final e in homebrewRepo.entries) {
      (byKind[e.kind] ??= []).add(e);
    }
    final kinds = byKind.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Homebrew'),
        actions: [
          IconButton(
            onPressed: homebrewRepo.entries.isEmpty
                ? null
                : () => shareJson(
                    context,
                    buildHomebrewBundle(homebrewRepo.entries),
                    'my_homebrew.json',
                  ),
            tooltip:
                'Export - save this to keep your own homebrew/official '
                'content across reinstalls (see assets/official/README.md '
                'to have it restored automatically in your own builds)',
            icon: const Icon(Icons.file_download_outlined),
          ),
          IconButton(
            onPressed: _import,
            tooltip: 'Import homebrew from an export file',
            icon: const Icon(Icons.file_upload_outlined),
          ),
          TextButton(onPressed: _add, child: const Text('+ Add')),
          const SizedBox(width: 6),
        ],
      ),
      body: ReadableWidth(
        child: SafeArea(
          child: byKind.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(18),
                  child: Text(
                    'No homebrew content yet. Tap "+ Add" above to create '
                    'one, or type a name into any "Add" picker on a '
                    'character sheet.',
                    style: TextStyle(color: LedgerColors.inkDim),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 8,
                  ),
                  children: [
                    for (final kind in kinds) ...[
                      SectionLabel(_kindLabel(kind)),
                      for (final entry
                          in byKind[kind]!
                            ..sort((a, b) => a.name.compareTo(b.name)))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            entry.name,
                            style: const TextStyle(
                              color: LedgerColors.ink,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            _entrySubtitle(entry),
                            style: const TextStyle(
                              color: LedgerColors.inkDim,
                              fontSize: 12,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () => _delete(entry),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 20,
                                ),
                                color: LedgerColors.inkDim,
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: LedgerColors.inkDim,
                              ),
                            ],
                          ),
                          onTap: () => _edit(entry),
                        ),
                      const Divider(height: 1),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}

/// The target categories an Effect can pick, and how they map to/from the
/// flat `target` string - kept as a small closed set (not free text) so
/// every option in the UI is guaranteed to actually match something
/// rules.matchingEffects/rules.computeDamageTaken checks for.
enum _EffectCategory {
  initiative,
  attackRoll,
  damageRoll,
  spellAttack,
  spellSaveDc,
  ac,
  speed,
  maxHp,
  setScore,
  save,
  skill,
  damageResistance,
  damageReduction,
}

_EffectCategory _categoryOf(String target) {
  if (target.startsWith('save:')) return _EffectCategory.save;
  if (target.startsWith('setScore:')) return _EffectCategory.setScore;
  if (target.startsWith('skill:')) return _EffectCategory.skill;
  if (target.startsWith('damageResistance:')) {
    return _EffectCategory.damageResistance;
  }
  if (target.startsWith('damageReduction:')) {
    return _EffectCategory.damageReduction;
  }
  return switch (target) {
    'attackRoll' => _EffectCategory.attackRoll,
    'damageRoll' => _EffectCategory.damageRoll,
    'spellAttack' => _EffectCategory.spellAttack,
    'spellSaveDc' => _EffectCategory.spellSaveDc,
    'ac' => _EffectCategory.ac,
    'speed' => _EffectCategory.speed,
    'maxHp' => _EffectCategory.maxHp,
    _ => _EffectCategory.initiative,
  };
}

/// Damage type key/label pairs for the resistance/reduction pickers -
/// every real srdCatalog.damageTypes entry, plus the synthetic "physical"
/// bucket rules.computeDamageTaken treats as Bludgeoning/Piercing/
/// Slashing from a nonmagical source (Heavy Armor Master's own wording).
List<(String, String)> get _damageTypeOptions => [
  for (final dt in srdCatalog.damageTypes) (dt.key, dt.name),
  ('physical', 'Physical (nonmagical B/P/S)'),
];

const _abilityLabels = {
  'str': 'Strength',
  'dex': 'Dexterity',
  'con': 'Constitution',
  'int': 'Intelligence',
  'wis': 'Wisdom',
  'cha': 'Charisma',
};

const _conditionLabels = {
  'heavyWeapon': 'Heavy Weapon',
  // Deliberately plain, not an invented status name - only "Bloodied" is
  // a real 5e term; different tables have their own word for this tier
  // (this app's own example: "scratched").
  'anyDamage': 'Below Max HP (any damage taken)',
  'bloodied': 'Bloodied',
  'heavyArmor': 'Wearing Heavy Armor',
  'wearingArmor': 'Wearing Any Armor',
  'noArmor': 'Wearing No Armor',
  'rangedWeapon': 'Ranged Weapon',
  'meleeWeapon': 'Melee Weapon',
};

const _fullNameToAbilityKey = {
  'strength': 'str',
  'dexterity': 'dex',
  'constitution': 'con',
  'intelligence': 'int',
  'wisdom': 'wis',
  'charisma': 'cha',
};

/// The three term shapes rules.evaluateFormula actually recognizes (see
/// its doc comment in domain/rules.dart) - kept in exact sync with that
/// grammar, since this editor's whole point is to make it impossible to
/// type a term the evaluator won't understand.
enum _TermKind { flat, proficiencyBonus, abilityModifier }

/// One signed piece of a formula (e.g. "+ 2", "- Wisdom modifier"). A
/// [customText] means the original formula had a term that didn't match
/// any recognized shape - preserved verbatim (rather than dropped) so an
/// already-saved formula from before this editor existed, or a
/// hand-edited/imported one, isn't silently corrupted; it evaluates to 0
/// until re-typed into a recognized kind.
class _FormulaTerm {
  const _FormulaTerm({
    required this.negative,
    required this.kind,
    this.flatValue = 1,
    this.abilityKey = 'str',
    this.customText,
  });
  final bool negative;
  final _TermKind kind;
  final int flatValue;
  final String abilityKey;
  final String? customText;

  String get _bareText =>
      customText ??
      switch (kind) {
        _TermKind.flat => '$flatValue',
        _TermKind.proficiencyBonus => 'Proficiency Bonus',
        _TermKind.abilityModifier => '${_abilityLabels[abilityKey]} modifier',
      };

  String get displayLabel => '${negative ? '−' : '+'} $_bareText';
}

_FormulaTerm _parseTerm(bool negative, String text) {
  final asInt = int.tryParse(text);
  if (asInt != null) {
    return _FormulaTerm(
      negative: negative,
      kind: _TermKind.flat,
      flatValue: asInt.abs(),
    );
  }
  if (text.toLowerCase() == 'proficiency bonus') {
    return _FormulaTerm(negative: negative, kind: _TermKind.proficiencyBonus);
  }
  final m = RegExp(
    r'^(\w+)\s+modifier$',
    caseSensitive: false,
  ).firstMatch(text);
  final key = m != null
      ? _fullNameToAbilityKey[m.group(1)!.toLowerCase()]
      : null;
  if (key != null) {
    return _FormulaTerm(
      negative: negative,
      kind: _TermKind.abilityModifier,
      abilityKey: key,
    );
  }
  return _FormulaTerm(
    negative: negative,
    kind: _TermKind.flat,
    customText: text,
  );
}

/// Mirrors rules.evaluateFormula's own term-splitting regex, so parsing
/// here always agrees with how the formula will actually be evaluated.
List<_FormulaTerm> _parseFormula(String formula) {
  final terms = <_FormulaTerm>[];
  for (final m in RegExp(r'([+-]?)\s*([^+-]+)').allMatches(formula)) {
    final text = m.group(2)!.trim();
    if (text.isEmpty) continue;
    terms.add(_parseTerm(m.group(1) == '-', text));
  }
  return terms;
}

String _composeFormula(List<_FormulaTerm> terms) {
  final buffer = StringBuffer();
  for (final term in terms) {
    final text = term._bareText.trim();
    if (text.isEmpty) continue;
    if (buffer.isEmpty) {
      buffer.write(term.negative ? '-$text' : text);
    } else {
      buffer.write(term.negative ? ' - $text' : ' + $text');
    }
  }
  return buffer.toString();
}

/// A structured builder for evaluateFormula's flat-sum grammar - replaces
/// hand-typing the formula string term by term. A typo in free text
/// degrades silently to 0 rather than erroring (see evaluateFormula's doc
/// comment), which made it easy to end up with a homebrew bonus that
/// quietly did nothing; picking terms from a closed set makes that
/// mistake impossible for anything added here.
class _FormulaEditor extends StatelessWidget {
  const _FormulaEditor({required this.formula, required this.onChanged});
  final String formula;
  final ValueChanged<String> onChanged;

  Future<void> _editTerm(
    BuildContext context,
    List<_FormulaTerm> terms,
    int? index,
  ) async {
    final result = await showDialog<_FormulaTerm>(
      context: context,
      builder: (context) =>
          _FormulaTermDialog(initial: index != null ? terms[index] : null),
    );
    if (result == null) return;
    final next = [...terms];
    if (index != null) {
      next[index] = result;
    } else {
      next.add(result);
    }
    onChanged(_composeFormula(next));
  }

  void _removeTerm(List<_FormulaTerm> terms, int index) {
    final next = [...terms]..removeAt(index);
    onChanged(_composeFormula(next));
  }

  @override
  Widget build(BuildContext context) {
    final terms = _parseFormula(formula);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (terms.isEmpty)
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              'No terms yet - always evaluates to 0.',
              style: TextStyle(fontSize: 12, color: LedgerColors.inkDim),
            ),
          )
        else
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (index, term) in terms.indexed)
                InputChip(
                  label: Text(term.displayLabel),
                  backgroundColor: term.customText != null
                      ? LedgerColors.accent.withValues(alpha: 0.15)
                      : null,
                  onPressed: () => _editTerm(context, terms, index),
                  onDeleted: () => _removeTerm(terms, index),
                ),
            ],
          ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: () => _editTerm(context, terms, null),
          child: const Text('+ Term'),
        ),
      ],
    );
  }
}

class _FormulaTermDialog extends StatefulWidget {
  const _FormulaTermDialog({this.initial});
  final _FormulaTerm? initial;

  @override
  State<_FormulaTermDialog> createState() => _FormulaTermDialogState();
}

class _FormulaTermDialogState extends State<_FormulaTermDialog> {
  late bool _negative;
  late _TermKind _kind;
  late final TextEditingController _flatController;
  late String _abilityKey;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _negative = initial?.negative ?? false;
    _kind = initial?.kind ?? _TermKind.flat;
    _flatController = TextEditingController(
      text: initial == null || initial.customText != null
          ? '1'
          : '${initial.flatValue}',
    );
    _abilityKey = initial?.abilityKey ?? 'str';
  }

  @override
  void dispose() {
    _flatController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final wasCustom = widget.initial?.customText != null;

    return AlertDialog(
      title: Text(widget.initial == null ? 'Add Term' : 'Edit Term'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (wasCustom) ...[
            Text(
              'Original text "${widget.initial!.customText}" doesn\'t '
              "match a recognized formula piece, so it currently "
              'evaluates to 0. Pick a type below to fix it.',
              style: const TextStyle(fontSize: 12, color: LedgerColors.accent),
            ),
            const SizedBox(height: 12),
          ],
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('+')),
              ButtonSegment(value: true, label: Text('−')),
            ],
            selected: {_negative},
            onSelectionChanged: (s) => setState(() => _negative = s.first),
          ),
          const SizedBox(height: 12),
          SegmentedButton<_TermKind>(
            segments: const [
              ButtonSegment(value: _TermKind.flat, label: Text('Number')),
              ButtonSegment(
                value: _TermKind.proficiencyBonus,
                label: Text('Prof. Bonus'),
              ),
              ButtonSegment(
                value: _TermKind.abilityModifier,
                label: Text('Ability Mod'),
              ),
            ],
            selected: {_kind},
            onSelectionChanged: (s) => setState(() => _kind = s.first),
          ),
          const SizedBox(height: 12),
          if (_kind == _TermKind.flat)
            TextField(
              controller: _flatController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Amount'),
            ),
          if (_kind == _TermKind.abilityModifier)
            DropdownButtonFormField<String>(
              initialValue: _abilityKey,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ability'),
              items: [
                for (final entry in _abilityLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _abilityKey = v);
              },
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            Navigator.of(context).pop(
              _FormulaTerm(
                negative: _negative,
                kind: _kind,
                flatValue: int.tryParse(_flatController.text.trim()) ?? 0,
                abilityKey: _abilityKey,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// One generic edit form, kind-conditional sections - not a form-builder
/// per kind. Every kind gets name/source/desc; only 'feat' and
/// 'magicItem' get an Effects section, since those are the only two
/// rules.matchingEffects actually reads.
class HomebrewEditScreen extends StatefulWidget {
  const HomebrewEditScreen({super.key, required this.entry});
  final HomebrewEntry entry;

  @override
  State<HomebrewEditScreen> createState() => _HomebrewEditScreenState();
}

class _HomebrewEditScreenState extends State<HomebrewEditScreen> {
  late String _source;
  late final TextEditingController _descController;
  late List<Effect> _effects;
  late String? _category;
  late final TextEditingController _prerequisiteController;
  late final TextEditingController _shortDescController;
  late Map<String, dynamic> _data;

  @override
  void initState() {
    super.initState();
    _source = widget.entry.source;
    _descController = TextEditingController(text: widget.entry.desc);
    _effects = [...widget.entry.effects];
    _category = widget.entry.category;
    _prerequisiteController = TextEditingController(
      text: widget.entry.prerequisite ?? '',
    );
    _shortDescController = TextEditingController(text: widget.entry.shortDesc);
    _data = {...widget.entry.data};
  }

  @override
  void dispose() {
    _descController.dispose();
    _prerequisiteController.dispose();
    _shortDescController.dispose();
    super.dispose();
  }

  bool get _isFeat => widget.entry.kind == 'feat';

  bool get _supportsEffects => _isFeat || widget.entry.kind == 'magicItem';

  /// Non-blocking heads-up when this entry's name collides with real
  /// SRD/built-in content - the override is allowed (homebrew wins, see
  /// rules.liveFeatureEffects), this just makes sure it's visible rather
  /// than a silent surprise. Only feats can collide (magic items have no
  /// built-in effects table and aren't matched against srdCatalog text).
  String? get _overrideWarning {
    if (widget.entry.kind != 'feat') return null;
    final name = widget.entry.name;
    if (rules.builtinFeatEffectNames.contains(name)) {
      return 'This name matches $name\'s built-in behavior - your version '
          'below will be used instead whenever this feat is granted.';
    }
    final srdMatch = srdCatalog.featsByKey.values.any(
      (f) => f.name.toLowerCase() == name.toLowerCase(),
    );
    if (srdMatch) {
      return 'This name matches a real SRD feat - your version below will '
          'be used instead whenever this feat is granted.';
    }
    return null;
  }

  void _save() {
    homebrewRepo.update(
      HomebrewEntry(
        id: widget.entry.id,
        kind: widget.entry.kind,
        name: widget.entry.name,
        desc: _descController.text,
        source: _source,
        effects: _effects,
        category: _isFeat ? _category : null,
        prerequisite: _isFeat && _prerequisiteController.text.trim().isNotEmpty
            ? _prerequisiteController.text.trim()
            : null,
        shortDesc: _isFeat ? _shortDescController.text.trim() : '',
        data: _data,
      ),
    );
    Navigator.of(context).pop();
  }

  void _addEffect() {
    setState(() {
      _effects = [..._effects, const Effect(target: 'attackRoll', formula: '')];
    });
  }

  void _removeEffect(int index) {
    setState(() => _effects = [..._effects]..removeAt(index));
  }

  void _updateEffect(int index, Effect updated) {
    setState(() {
      final next = [..._effects];
      next[index] = updated;
      _effects = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    final warning = _overrideWarning;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry.name),
        actions: [
          TextButton(onPressed: _save, child: const Text('Save')),
          const SizedBox(width: 6),
        ],
      ),
      body: ReadableWidth(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(18),
            children: [
              if (warning != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: LedgerColors.accent.withValues(alpha: 0.15),
                    border: Border.all(color: LedgerColors.accent),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_outlined,
                        color: LedgerColors.accent,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          warning,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
              const SectionLabel('Source'),
              // Wrap, not Row: the two chips don't fit side by side on a
              // narrow phone.
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Homebrew'),
                    selected: _source == 'homebrew',
                    onSelected: (_) => setState(() => _source = 'homebrew'),
                  ),
                  ChoiceChip(
                    label: const Text('Official (non-SRD)'),
                    selected: _source == 'official',
                    onSelected: (_) => setState(() => _source = 'official'),
                  ),
                ],
              ),
              if (_isFeat) ...[
                const SectionLabel('Category'),
                const Text(
                  'Which feat-choice pickers this offers itself in (a '
                  '"Choose a Fighting Style" or "Choose an Epic Boon" '
                  'Pending Choice, say) - matches how a real SRD feat\'s own '
                  'category works. Leave uncategorized and it only shows up '
                  'in the unrestricted "+ Add Feat" list.',
                  style: TextStyle(fontSize: 12, color: LedgerColors.inkDim),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String?>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(isDense: true),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Uncategorized'),
                    ),
                    for (final category in homebrewFeatCategories)
                      DropdownMenuItem(value: category, child: Text(category)),
                  ],
                  onChanged: (v) => setState(() => _category = v),
                ),
                const SectionLabel('Prerequisite'),
                TextField(
                  controller: _prerequisiteController,
                  decoration: const InputDecoration(
                    hintText:
                        'Optional, e.g. "Level 4+" - display-only, not '
                        'enforced.',
                  ),
                ),
              ],
              const SectionLabel('Description'),
              TextField(
                controller: _descController,
                maxLines: null,
                minLines: 3,
                decoration: const InputDecoration(
                  hintText:
                      'Rules text / flavor - shown wherever this '
                      'entry appears on the sheet.',
                ),
              ),
              HomebrewRulesEditor(
                kind: widget.entry.kind,
                entryId: widget.entry.id,
                data: _data,
                onChanged: (d) => _data = d,
              ),
              if (_isFeat) ...[
                const SectionLabel('Sheet Text'),
                TextField(
                  controller: _shortDescController,
                  maxLines: null,
                  minLines: 2,
                  decoration: const InputDecoration(
                    hintText:
                        'A one- or two-line summary for the exported PDF '
                        "sheet's Feats box. Leave blank to use the full "
                        'description.',
                  ),
                ),
              ],
              if (_supportsEffects) ...[
                const SectionLabel('Effects'),
                Text(
                  widget.entry.kind == 'magicItem'
                      ? 'Effects only apply while this item is marked '
                            'Attuned in inventory.'
                      : 'Numeric bonuses this grants when the feat is on '
                            'the sheet.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: LedgerColors.inkDim,
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Every effect changes something about the wearer/holder '
                  'themselves - "Damage You Deal" only ever adds to damage '
                  'this character deals, and "Resistance/Reduction to '
                  'Damage You Take" only ever changes damage this character '
                  'receives (applied via the Combat tab\'s Take Damage '
                  'dialog). There\'s no way to affect a different creature.',
                  style: TextStyle(
                    fontSize: 11,
                    color: LedgerColors.inkDim,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'For a bonus that changes at an HP threshold, add one '
                  'effect per tier with just that tier\'s extra amount, not '
                  'the running total - e.g. +1 while below max HP and +1 '
                  'more while Bloodied, for a total of +2 when Bloodied.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: LedgerColors.inkDim,
                    fontStyle: FontStyle.italic,
                  ),
                ),
                const SizedBox(height: 12),
                for (final (index, effect) in _effects.indexed)
                  _EffectRow(
                    effect: effect,
                    onChanged: (updated) => _updateEffect(index, updated),
                    onRemove: () => _removeEffect(index),
                  ),
                TextButton(
                  onPressed: _addEffect,
                  child: const Text('+ Add Effect'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EffectRow extends StatelessWidget {
  const _EffectRow({
    required this.effect,
    required this.onChanged,
    required this.onRemove,
  });
  final Effect effect;
  final ValueChanged<Effect> onChanged;
  final VoidCallback onRemove;

  void _setCategory(_EffectCategory category) {
    final target = switch (category) {
      _EffectCategory.initiative => 'initiative',
      _EffectCategory.attackRoll => 'attackRoll',
      _EffectCategory.damageRoll => 'damageRoll',
      _EffectCategory.spellAttack => 'spellAttack',
      _EffectCategory.spellSaveDc => 'spellSaveDc',
      _EffectCategory.ac => 'ac',
      _EffectCategory.speed => 'speed',
      _EffectCategory.maxHp => 'maxHp',
      _EffectCategory.save => 'save:str',
      _EffectCategory.setScore => 'setScore:str',
      _EffectCategory.skill =>
        'skill:${srdCatalog.skillsByName.values.first.name}',
      _EffectCategory.damageResistance =>
        'damageResistance:${_damageTypeOptions.first.$1}',
      _EffectCategory.damageReduction =>
        'damageReduction:${_damageTypeOptions.first.$1}',
    };
    onChanged(
      Effect(
        target: target,
        formula: effect.formula,
        condition: effect.condition,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final category = _categoryOf(effect.target);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(border: Border.all(color: LedgerColors.rule)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<_EffectCategory>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Applies to',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: _EffectCategory.initiative,
                      child: Text('Your Initiative'),
                    ),
                    DropdownMenuItem(
                      value: _EffectCategory.attackRoll,
                      child: Text('Your Attack Roll'),
                    ),
                    DropdownMenuItem(
                      value: _EffectCategory.damageRoll,
                      child: Text('Damage You Deal'),
                    ),
                    DropdownMenuItem(
                      value: _EffectCategory.spellAttack,
                      child: Text('Your Spell Attack Bonus'),
                    ),
                    DropdownMenuItem(
                      value: _EffectCategory.spellSaveDc,
                      child: Text('Your Spell Save DC'),
                    ),
                    DropdownMenuItem(
                      value: _EffectCategory.ac,
                      child: Text('Your Armor Class'),
                    ),
                    DropdownMenuItem(
                      value: _EffectCategory.speed,
                      child: Text('Your Speed'),
                    ),
                    DropdownMenuItem(
                      value: _EffectCategory.maxHp,
                      child: Text('Your Hit Point Maximum'),
                    ),
                    DropdownMenuItem(
                      value: _EffectCategory.setScore,
                      child: Text('Sets an Ability Score'),
                    ),
                    DropdownMenuItem(
                      value: _EffectCategory.save,
                      child: Text('Your Saving Throw'),
                    ),
                    DropdownMenuItem(
                      value: _EffectCategory.skill,
                      child: Text('Your Skill Check'),
                    ),
                    DropdownMenuItem(
                      value: _EffectCategory.damageResistance,
                      child: Text('Resistance to Damage You Take'),
                    ),
                    DropdownMenuItem(
                      value: _EffectCategory.damageReduction,
                      child: Text('Reduction to Damage You Take'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) _setCategory(v);
                  },
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.delete_outline, size: 20),
                color: LedgerColors.inkDim,
              ),
            ],
          ),
          if (category == _EffectCategory.setScore)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'Sets the score to a single number (e.g. 21 for a Belt of '
                'Giant Strength) - only if higher than the score the character '
                'already has. Use one flat number, no modifiers.',
                style: TextStyle(fontSize: 11, color: LedgerColors.inkDim),
              ),
            ),
          if (category == _EffectCategory.save ||
              category == _EffectCategory.setScore)
            DropdownButtonFormField<String>(
              initialValue: effect.target.split(':').last,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Ability',
                isDense: true,
              ),
              items: [
                for (final entry in _abilityLabels.entries)
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
              ],
              onChanged: (v) {
                if (v == null) return;
                onChanged(
                  Effect(
                    target: category == _EffectCategory.setScore
                        ? 'setScore:$v'
                        : 'save:$v',
                    formula: effect.formula,
                    condition: effect.condition,
                  ),
                );
              },
            ),
          if (category == _EffectCategory.skill)
            DropdownButtonFormField<String>(
              initialValue: effect.target.split(':').last,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Skill',
                isDense: true,
              ),
              items: [
                for (final skill
                    in srdCatalog.skillsByName.values.toList()
                      ..sort((a, b) => a.name.compareTo(b.name)))
                  DropdownMenuItem(value: skill.name, child: Text(skill.name)),
              ],
              onChanged: (v) {
                if (v == null) return;
                onChanged(
                  Effect(
                    target: 'skill:$v',
                    formula: effect.formula,
                    condition: effect.condition,
                  ),
                );
              },
            ),
          if (category == _EffectCategory.damageResistance ||
              category == _EffectCategory.damageReduction)
            DropdownButtonFormField<String>(
              initialValue: effect.target.split(':').last,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Damage Type',
                isDense: true,
              ),
              items: [
                for (final (key, label) in _damageTypeOptions)
                  DropdownMenuItem(value: key, child: Text(label)),
              ],
              onChanged: (v) {
                if (v == null) return;
                final prefix = category == _EffectCategory.damageResistance
                    ? 'damageResistance'
                    : 'damageReduction';
                onChanged(
                  Effect(
                    target: '$prefix:$v',
                    formula: effect.formula,
                    condition: effect.condition,
                  ),
                );
              },
            ),
          if (category == _EffectCategory.damageResistance)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'Halves that damage type when taken (rounded down) - no '
                'formula needed.',
                style: TextStyle(fontSize: 12, color: LedgerColors.inkDim),
              ),
            )
          else ...[
            const SizedBox(height: 8),
            const Text(
              'Formula',
              style: TextStyle(fontSize: 12, color: LedgerColors.inkDim),
            ),
            const SizedBox(height: 4),
            _FormulaEditor(
              formula: effect.formula,
              onChanged: (v) => onChanged(
                Effect(
                  target: effect.target,
                  formula: v,
                  condition: effect.condition,
                ),
              ),
            ),
          ],
          const SizedBox(height: 8),
          DropdownButtonFormField<String?>(
            initialValue: effect.condition,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Condition',
              isDense: true,
            ),
            items: [
              const DropdownMenuItem(value: null, child: Text('None')),
              for (final entry in _conditionLabels.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (v) => onChanged(
              Effect(
                target: effect.target,
                formula: effect.formula,
                condition: v,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
