import 'package:flutter/material.dart';

import '../data/character_factory.dart';
import '../data/starting_equipment.dart';
import '../widgets/background_ability_picker.dart';
import '../data/character_repository.dart';
import '../data/srd_catalog.dart';
import '../domain/rules.dart' as rules;
import '../models/character.dart';
import '../theme/ledger_theme.dart';
import '../widgets/layout.dart';
import 'catalog_picker_screen.dart';

enum CharacterFormMode { create, edit }

/// One screen, two modes - matching the real app's CharacterIdentityForm,
/// which is reused for both creating and editing rather than having two
/// separate forms drift apart.
///
/// Create is one scrollable page (the original 3-step wizard mockup was
/// collapsed down once it was clear 6 short ability score fields don't
/// need their own step): Name, searchable Species/Background/Class
/// pickers backed by the SRD catalog, the class's real "choose N skills"
/// grant (plus whatever the background gives outright), and ability
/// scores, ending in a real Create Character that persists a new level-1
/// character - see data/character_factory.dart for exactly what is and
/// isn't computed (Fighter gets a real starting-equipment choice; no
/// species traits granted yet).
///
/// Edit is a single prefilled page that saves Name and Level back to the
/// character; Species/Class stay read-only there - changing an existing
/// character's species or class touches more (subclass, hit die, granted
/// features) than this form tracks yet.
class CharacterFormScreen extends StatefulWidget {
  const CharacterFormScreen({super.key, required this.mode, this.character});

  final CharacterFormMode mode;
  final Character? character;

  @override
  State<CharacterFormScreen> createState() => _CharacterFormScreenState();
}

class _CharacterFormScreenState extends State<CharacterFormScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _levelController;
  late final TextEditingController _newNameController;
  late final TextEditingController _playerNameController;
  late final TextEditingController _notesController;
  late final TextEditingController _appearanceController;
  late final Map<String, TextEditingController> _abilityControllers;

  SrdRefItem? _selectedSpecies;
  SrdRefItem? _selectedBackground;
  SrdRefItem? _selectedClass;
  final Set<String> _chosenSkills = {};
  String? _classEquipment; // 'A', 'B', ... from the class's packages
  String? _backgroundEquipment; // ... and the background's
  Map<String, int> _bgIncreases = const {};

  // Edit mode: a new species/class/background picked here is applied on
  // Save (rules.changeSpecies/changeClass/changeBackground), not the
  // moment it's picked, so Cancel still backs out of it.
  SrdRefItem? _newSpecies;
  SrdRefItem? _newClass;
  SrdRefItem? _newBackground;
  Map<String, int> _newBgIncreases = const {};
  late final TextEditingController _speedController;
  late final TextEditingController _acOverrideController;
  late final TextEditingController _initiativeController;
  late final TextEditingController _hpAdjustmentController;
  String? _hitDie;
  String? _sizeChoice;
  // The picked option from the species' own embedded choice table (e.g.
  // Dragonborn's Draconic Ancestry: "Red", "Fire") - null if the species
  // has no such table, or one hasn't been picked yet.
  SpeciesChoiceOption? _selectedSpeciesChoice;
  String? _selectedAlignment;
  late List<String> _languages;

  /// Picked variants for a "Choose N `<Tool>`" requirement, keyed by the
  /// tool's own SRD key (e.g. Gaming Set, Musical Instrument) - works for
  /// both New Character (background/class just picked) and Edit (an
  /// existing character's already-fixed background/class, resolved
  /// retroactively) since both read from the same
  /// rules.toolChoiceRequirementsFor*. Pre-populated from the character's
  /// own toolProficiencyChoices in edit mode.
  final Map<String, Set<String>> _toolChoiceSelections = {};
  late final TextEditingController _customToolProficiencyController;

  static const _abilityKeys = ['str', 'dex', 'con', 'int', 'wis', 'cha'];
  static const _abilityLabels = {
    'str': 'Strength',
    'dex': 'Dexterity',
    'con': 'Constitution',
    'int': 'Intelligence',
    'wis': 'Wisdom',
    'cha': 'Charisma',
  };

  bool get isEdit => widget.mode == CharacterFormMode.edit;

  @override
  void initState() {
    super.initState();
    final c = widget.character;
    _nameController = TextEditingController(text: c?.name ?? '');
    _levelController = TextEditingController(
      text: c != null ? '${c.level}' : '',
    );
    _newNameController = TextEditingController();
    _playerNameController = TextEditingController(text: c?.playerName ?? '');
    _selectedAlignment = c?.alignment;
    _languages = [...?c?.languages];
    _notesController = TextEditingController(text: c?.notes ?? '');
    _appearanceController = TextEditingController(text: c?.appearance ?? '');
    _abilityControllers = {
      for (final key in _abilityKeys) key: TextEditingController(text: '10'),
    };
    _customToolProficiencyController = TextEditingController();
    _speedController = TextEditingController(text: '${c?.speed ?? 30}');
    _acOverrideController = TextEditingController(
      text: c?.armorClassOverride != null ? '${c!.armorClassOverride}' : '',
    );
    _initiativeController = TextEditingController(
      text: '${c?.initiativeBonus ?? 0}',
    );
    _hpAdjustmentController = TextEditingController(
      text: '${c?.maxHpAdjustment ?? 0}',
    );
    _hitDie = c?.hitDiceDie;
    _sizeChoice = c?.sizeChoice;
    if (c != null) {
      final requirements = rules.toolChoiceRequirementsForKeys(
        c.backgroundKey,
        c.classKey,
      );
      final remaining = [...c.toolProficiencyChoices];
      for (final req in requirements) {
        final matched = <String>{};
        for (final variant in req.tool.variants) {
          if (remaining.remove(variant)) matched.add(variant);
        }
        _toolChoiceSelections[req.tool.key] = matched;
      }
      if (remaining.isNotEmpty) {
        _customToolProficiencyController.text = remaining.join(', ');
      }
    }
  }

  List<rules.ToolChoiceRequirement> get _toolChoiceRequirements =>
      rules.toolChoiceRequirementsForKeys(
        isEdit ? widget.character?.backgroundKey : _selectedBackground?.key,
        isEdit ? widget.character?.classKey : _selectedClass?.key,
      );

  void _toggleToolVariant(String toolKey, String variant, int maxCount) {
    setState(() {
      final selected = _toolChoiceSelections.putIfAbsent(toolKey, () => {});
      if (selected.contains(variant)) {
        selected.remove(variant);
      } else {
        if (selected.length >= maxCount) return;
        selected.add(variant);
      }
    });
  }

  /// Every resolved tool proficiency pick - chip selections plus the
  /// free-text fallback (for homebrew backgrounds/classes with no
  /// parseable "Choose N" text, or a choice like Rogue's dual-category one
  /// that parseToolChoice deliberately declines to resolve).
  List<String> get _resolvedToolProficiencyChoices {
    final result = <String>[
      for (final selections in _toolChoiceSelections.values) ...selections,
    ];
    final custom = _customToolProficiencyController.text.trim();
    if (custom.isNotEmpty) {
      result.addAll(
        custom.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty),
      );
    }
    return result;
  }

  Future<void> _pickSpecies() async {
    final result = await Navigator.of(context).push<SrdRefItem>(
      MaterialPageRoute(
        builder: (_) => CatalogPickerScreen(
          title: 'Species',
          options: srdCatalog.species,
          homebrewKind: 'species',
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _selectedSpecies = result;
        // A different species may have a different choice table (or none
        // at all) - never carry a stale pick across a species change.
        _selectedSpeciesChoice = null;
      });
    }
  }

  /// The selected species' own embedded choice table (Dragonborn's
  /// Draconic Ancestry, Elf's Elven Lineages, ...), or null if it isn't
  /// cataloged or has no such table - most species don't.
  SrdSpeciesTable? get _speciesChoiceTable {
    final key = _selectedSpecies?.key;
    if (key == null) return null;
    final species = srdCatalog.speciesByKey[key];
    if (species == null || species.tables.isEmpty) return null;
    return species.tables.first;
  }

  Future<void> _pickBackground() async {
    final result = await Navigator.of(context).push<SrdRefItem>(
      MaterialPageRoute(
        builder: (_) => CatalogPickerScreen(
          title: 'Background',
          options: srdCatalog.backgroundOptions,
          homebrewKind: 'background',
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _selectedBackground = result;
        _bgIncreases = const {};
        _backgroundEquipment = null;
      });
    }
  }

  Future<SrdRefItem?> _pick(
    String title,
    List<SrdRefItem> options,
    String homebrewKind,
  ) => Navigator.of(context).push<SrdRefItem>(
    MaterialPageRoute(
      builder: (_) => CatalogPickerScreen(
        title: title,
        options: options,
        homebrewKind: homebrewKind,
      ),
    ),
  );

  Future<void> _pickNewSpecies() async {
    final result = await _pick('Species', srdCatalog.species, 'species');
    if (result != null) {
      setState(() {
        _newSpecies = result;
        _sizeChoice = null;
        _speedController.text =
            '${rules.speciesBaseSpeed(result.key) ?? widget.character!.speed}';
      });
    }
  }

  Future<void> _pickNewClass() async {
    final result = await _pick('Class', srdCatalog.classOptions, 'class');
    if (result != null) {
      setState(() {
        _newClass = result;
        _hitDie =
            rules.parseHitDie(
              srdCatalog.byKey(result.key)?.traits['Hit Point Die'],
            ) ??
            _hitDie;
      });
    }
  }

  Future<void> _pickNewBackground() async {
    final result = await _pick(
      'Background',
      srdCatalog.backgroundOptions,
      'background',
    );
    if (result != null) {
      setState(() {
        _newBackground = result;
        _newBgIncreases = const {};
      });
    }
  }

  Future<void> _pickClass() async {
    final result = await Navigator.of(context).push<SrdRefItem>(
      MaterialPageRoute(
        builder: (_) => CatalogPickerScreen(
          title: 'Class',
          options: srdCatalog.classOptions,
          homebrewKind: 'class',
        ),
      ),
    );
    if (result != null) {
      setState(() {
        _selectedClass = result;
        _chosenSkills.clear(); // eligible list depends on the class
        _classEquipment = null;
        // Defaults the ability score fields to the 2024 PHB's Standard
        // Array by Class suggestion for this class (still freely
        // editable afterward) - a no-op for a homebrew/uncataloged class
        // name, which just leaves whatever was already entered.
        final standardArray = standardArrayByClass[result.name];
        if (standardArray != null) {
          _abilityControllers['str']!.text = '${standardArray.str}';
          _abilityControllers['dex']!.text = '${standardArray.dex}';
          _abilityControllers['con']!.text = '${standardArray.con}';
          _abilityControllers['int']!.text = '${standardArray.intel}';
          _abilityControllers['wis']!.text = '${standardArray.wis}';
          _abilityControllers['cha']!.text = '${standardArray.cha}';
        }
      });
    }
  }

  Future<void> _pickLanguage() async {
    final alreadyKnown = _languages.toSet();
    final result = await Navigator.of(context).push<SrdRefItem>(
      MaterialPageRoute(
        builder: (_) => CatalogPickerScreen(
          title: 'Language',
          options: srdCatalog.languages
              .where((l) => !alreadyKnown.contains(l.name))
              .toList(),
          homebrewKind: 'language',
        ),
      ),
    );
    if (result != null && !_languages.contains(result.name)) {
      setState(() => _languages.add(result.name));
    }
  }

  void _removeLanguage(String name) {
    setState(() => _languages.remove(name));
  }

  void _toggleSkill(String skill, int maxCount) {
    setState(() {
      if (_chosenSkills.contains(skill)) {
        _chosenSkills.remove(skill);
      } else if (_chosenSkills.length < maxCount) {
        _chosenSkills.add(skill);
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _levelController.dispose();
    _newNameController.dispose();
    _playerNameController.dispose();
    _notesController.dispose();
    _appearanceController.dispose();
    for (final controller in _abilityControllers.values) {
      controller.dispose();
    }
    _customToolProficiencyController.dispose();
    _speedController.dispose();
    _acOverrideController.dispose();
    _initiativeController.dispose();
    _hpAdjustmentController.dispose();
    super.dispose();
  }

  void _save() {
    final c = widget.character;
    if (c == null) return;
    c.name = _nameController.text.trim().isEmpty
        ? c.name
        : _nameController.text.trim();
    c.playerName = _playerNameController.text.trim();
    c.alignment = _selectedAlignment;
    c.languages = [..._languages];
    c.notes = _notesController.text;
    c.appearance = _appearanceController.text;
    c.toolProficiencyChoices = _resolvedToolProficiencyChoices;
    final parsedLevel = int.tryParse(_levelController.text);
    if (parsedLevel != null &&
        parsedLevel >= 1 &&
        parsedLevel <= 20 &&
        parsedLevel != c.level) {
      final oldLevel = c.level;
      final oldMaxHp = c.maxHp;
      c.level = parsedLevel;
      // Recomputing HP/Hit Dice here is a correction (mislabeled level,
      // hand-built starting character), not a "level up in play" moment -
      // it's always safe to call and doesn't try to guess at resource
      // maximums the way a real level-up would (see recalculateHp's doc).
      rules.recalculateHp(c);
      // Class and species resource maximums ARE known (read from the real
      // classes.json/species.json level tables), so those get corrected too.
      rules.recalculateClassResources(c);
      // Crossing an Ability Score Improvement level surfaces a Pending
      // Choice on the Features tab, same as a real level-up would.
      final newChoices = rules.pendingChoicesForLevelUp(
        c,
        oldLevel,
        parsedLevel,
      );
      c.pendingChoices = [...c.pendingChoices, ...newChoices];
      // Grants any newly-reached class features (Extra Attack,
      // Indomitable, ...) straight from classes.json.
      final newClassFeatures = rules.classFeaturesForLevelUp(
        c,
        oldLevel,
        parsedLevel,
      );
      c.features = [...c.features, ...newClassFeatures];
      // Surfaces a Pending Choice at level 3 for the player to explicitly
      // pick a subclass (never auto-assigned), and grants newly-reached
      // subclass features once one is already chosen.
      final newSubclassChoices = rules.subclassPendingChoices(
        c,
        oldLevel,
        parsedLevel,
      );
      c.pendingChoices = [...c.pendingChoices, ...newSubclassChoices];
      // Surfaces a Pending Choice for any newly-reached choice-driven class
      // or subclass feature (Fighting Style, Additional Fighting Style,
      // Epic Boon, ...) instead of silently granting it as an inert
      // feature - classFeaturesForLevelUp/subclassFeaturesForLevelUp both
      // skip these on purpose.
      final newFeatChoices = rules.featChoicePendingChoices(
        c,
        oldLevel,
        parsedLevel,
      );
      c.pendingChoices = [...c.pendingChoices, ...newFeatChoices];
      final featureNamesBefore = c.features.map((f) => f.name).toSet();
      rules.subclassFeaturesForLevelUp(c, oldLevel, parsedLevel);
      final newSubclassFeatureNames = c.features
          .where((f) => !featureNamesBefore.contains(f.name))
          .map((f) => f.name);
      // Spell slot maximums, for a caster.
      rules.recalculateSpellSlots(c);
      final newFeatureNames = [
        ...newClassFeatures.map((f) => f.name),
        ...newSubclassFeatureNames,
      ];
      final allNewChoices = [
        ...newChoices,
        ...newSubclassChoices,
        ...newFeatChoices,
      ];
      rules.logHistory(
        c,
        parsedLevel > oldLevel
            ? 'Leveled up: $oldLevel → $parsedLevel'
            : 'Level corrected: $oldLevel → $parsedLevel',
        detail:
            'Max HP: $oldMaxHp → ${c.maxHp}. Hit Dice and resources '
            'recalculated.'
            '${newFeatureNames.isEmpty ? '' : ' New features: ${newFeatureNames.join(', ')}.'}'
            '${allNewChoices.isEmpty ? '' : ' New choices to make: ${allNewChoices.map((p) => p.label).join(', ')}.'}',
      );
    }
    // Species / class / background changes, in that order (a class change
    // rebuilds features for the level just set above).
    if (_newClass != null && _newClass!.key != c.classKey) {
      rules.changeClass(c, _newClass!.key, _newClass!.name);
    }
    if (_newSpecies != null && _newSpecies!.key != c.speciesKey) {
      rules.changeSpecies(c, _newSpecies!.key, _newSpecies!.name);
    }
    if (_newBackground != null && _newBackground!.key != c.backgroundKey) {
      rules.changeBackground(
        c,
        _newBackground!.key,
        _newBackground!.name,
        _newBgIncreases,
      );
    }
    c.speed = int.tryParse(_speedController.text.trim()) ?? c.speed;
    c.armorClassOverride = int.tryParse(_acOverrideController.text.trim());
    c.initiativeBonus =
        int.tryParse(_initiativeController.text.trim()) ?? c.initiativeBonus;
    c.maxHpAdjustment =
        int.tryParse(_hpAdjustmentController.text.trim()) ?? c.maxHpAdjustment;
    c.sizeChoice = _sizeChoice;
    if (_hitDie != null && _hitDie != c.hitDiceDie) {
      c.hitDiceDie = _hitDie!;
      c.hitPointRolls = const {}; // rolls of the old die no longer apply
    }
    rules.refreshMaxHp(c);
    charactersRepo.save(c);
    Navigator.of(context).pop();
  }

  /// A background change needs its ability increases picked before Save.
  bool get _editBackgroundReady =>
      _newBackground == null ||
      validBackgroundIncreases(
        _newBgIncreases,
        rules.backgroundAbilityOptions(_newBackground!.key),
      );

  void _createCharacter() {
    final name = _newNameController.text.trim();
    if (name.isEmpty ||
        _selectedSpecies == null ||
        _selectedBackground == null ||
        _selectedClass == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Name, Species, Background, and Class are all required.',
          ),
        ),
      );
      return;
    }

    final skillChoice = srdCatalog.skillChoiceFor(_selectedClass!.key);
    if (skillChoice != null && _chosenSkills.length != skillChoice.count) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Choose exactly ${skillChoice.count} skill${skillChoice.count == 1 ? '' : 's'}.',
          ),
        ),
      );
      return;
    }

    if ((classEquipmentOptions(_selectedClass!.key).isNotEmpty &&
            _classEquipment == null) ||
        (backgroundEquipmentOptions(_selectedBackground!.key).isNotEmpty &&
            _backgroundEquipment == null)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Choose your class and background starting equipment.'),
        ),
      );
      return;
    }

    if (!validBackgroundIncreases(
      _bgIncreases,
      rules.backgroundAbilityOptions(_selectedBackground!.key),
    )) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Choose your background's ability score increases."),
        ),
      );
      return;
    }

    final speciesTable = _speciesChoiceTable;
    if (speciesTable != null && _selectedSpeciesChoice == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Choose your ${speciesTable.caption}.')),
      );
      return;
    }

    final scores = AbilityScores(
      str: int.tryParse(_abilityControllers['str']!.text) ?? 10,
      dex: int.tryParse(_abilityControllers['dex']!.text) ?? 10,
      con: int.tryParse(_abilityControllers['con']!.text) ?? 10,
      intel: int.tryParse(_abilityControllers['int']!.text) ?? 10,
      wis: int.tryParse(_abilityControllers['wis']!.text) ?? 10,
      cha: int.tryParse(_abilityControllers['cha']!.text) ?? 10,
    );

    final character = buildNewCharacter(
      name: name,
      species: _selectedSpecies!,
      background: _selectedBackground!,
      srdClass: _selectedClass!,
      abilityScores: scores,
      chosenClassSkills: _chosenSkills.toList(),
      backgroundAbilityIncreases: _bgIncreases,
      classEquipmentOption: _classEquipment,
      backgroundEquipmentOption: _backgroundEquipment,
    );
    character.playerName = _playerNameController.text.trim();
    character.alignment = _selectedAlignment;
    character.languages = [..._languages];
    character.notes = _notesController.text;
    character.appearance = _appearanceController.text;
    character.toolProficiencyChoices = _resolvedToolProficiencyChoices;
    // Same assignment the Overview tab's own species-choice picker makes
    // (character_sheet_screen.dart's _pickSpeciesChoice) - asked up front
    // here instead of leaving it to be discovered (or missed) later.
    final speciesChoice = _selectedSpeciesChoice;
    if (speciesChoice != null) {
      character.speciesChoice = speciesChoice.name;
      character.speciesLabel = speciesChoice.detail.isEmpty
          ? speciesChoice.name
          : '${speciesChoice.name} · ${speciesChoice.detail}';
    }
    charactersRepo.save(character);
    Navigator.of(context).pop();
  }

  Widget _buildSkillChoice() {
    final choice = srdCatalog.skillChoiceFor(_selectedClass!.key);
    if (choice == null) return const SizedBox.shrink();
    final eligible =
        choice.choices ?? (srdCatalog.skillsByName.keys.toList()..sort());

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'SKILL PROFICIENCIES — CHOOSE ${choice.count}',
            style: _fieldLabelStyle,
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final skill in eligible)
                _SkillChip(
                  label: skill,
                  selected: _chosenSkills.contains(skill),
                  onTap: () => _toggleSkill(skill, choice.count),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '${_chosenSkills.length} / ${choice.count} chosen',
            style: const TextStyle(fontSize: 12, color: LedgerColors.inkDim),
          ),
        ],
      ),
    );
  }

  Widget _buildToolChoiceSection() {
    if (!isEdit && _selectedBackground == null && _selectedClass == null) {
      return const SizedBox.shrink();
    }
    final requirements = _toolChoiceRequirements;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final req in requirements)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${req.tool.name.toUpperCase()} — CHOOSE ${req.count}',
                    style: _fieldLabelStyle,
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final variant in req.tool.variants)
                        _SkillChip(
                          label: variant,
                          selected:
                              _toolChoiceSelections[req.tool.key]?.contains(
                                variant,
                              ) ??
                              false,
                          onTap: () => _toggleToolVariant(
                            req.tool.key,
                            variant,
                            req.count,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_toolChoiceSelections[req.tool.key]?.length ?? 0} / ${req.count} chosen',
                    style: const TextStyle(
                      fontSize: 12,
                      color: LedgerColors.inkDim,
                    ),
                  ),
                ],
              ),
            ),
          _EditableField(
            label: 'Other Tool Proficiency (optional)',
            controller: _customToolProficiencyController,
          ),
          const Padding(
            padding: EdgeInsets.only(bottom: 4),
            child: Text(
              'For a homebrew background or class, or a choice above that '
              "doesn't list a fixed set of options (e.g. Artisan's Tools or "
              'a Musical Instrument), enter it here instead. Separate '
              'multiple entries with commas.',
              style: TextStyle(
                fontSize: 12,
                color: LedgerColors.inkDim,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSpeciesChoiceSection() {
    final table = _speciesChoiceTable;
    if (table == null) return const SizedBox.shrink();
    final options = flattenSpeciesTableOptions(table);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(table.caption.toUpperCase(), style: _fieldLabelStyle),
          const SizedBox(height: 6),
          RadioGroup<String>(
            groupValue: _selectedSpeciesChoice?.name,
            onChanged: (value) => setState(() {
              _selectedSpeciesChoice = options.firstWhere(
                (o) => o.name == value,
              );
            }),
            child: Column(
              children: [
                for (final option in options)
                  RadioListTile<String>(
                    value: option.name,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      option.detail.isEmpty
                          ? option.name
                          : '${option.name} — ${option.detail}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEquipmentChoice(
    String label,
    List<EquipmentOption> options,
    String? selected,
    ValueChanged<String?> onChanged,
  ) {
    if (options.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _fieldLabelStyle),
          const SizedBox(height: 6),
          RadioGroup<String>(
            groupValue: selected,
            onChanged: onChanged,
            child: Column(
              children: [
                for (final option in options)
                  RadioListTile<String>(
                    value: option.id,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      '(${option.id}) ${option.summary}',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField(
    String label,
    TextEditingController controller, {
    String? helper,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, helperText: helper),
    ),
  );

  /// Edit mode's stats not derived from anything else: base Speed (the
  /// species' speed - class bonuses are added on top), an AC override,
  /// the Initiative misc bonus, Hit Die, a Max HP adjustment, and size
  /// where the species
  /// offers a choice.
  Widget _buildEditStats(Character c) {
    final speciesKey = _newSpecies?.key ?? c.speciesKey;
    final sizes = rules.speciesSizeOptions(speciesKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('STATS', style: _fieldLabelStyle),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _numberField(
                'Base Speed (ft)',
                _speedController,
                helper: 'Class bonuses add on top',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _numberField(
                'AC override',
                _acOverrideController,
                helper: 'Blank = ${rules.computeArmorClass(c)} (computed)',
              ),
            ),
          ],
        ),
        Row(
          children: [
            Expanded(
              child: _numberField(
                'Initiative misc bonus',
                _initiativeController,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: DropdownButtonFormField<String>(
                  initialValue: _hitDie,
                  decoration: const InputDecoration(labelText: 'Hit Die'),
                  items: [
                    for (final die in const ['d6', 'd8', 'd10', 'd12'])
                      DropdownMenuItem(value: die, child: Text(die)),
                  ],
                  onChanged: (v) => setState(() => _hitDie = v),
                ),
              ),
            ),
          ],
        ),
        _numberField(
          'Max HP adjustment',
          _hpAdjustmentController,
          helper:
              'Added on top of Hit Dice, Con, and bonuses - see Max HP on '
              'the Combat tab for the full breakdown',
        ),
        if (sizes.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: DropdownButtonFormField<String>(
              initialValue: sizes.contains(_sizeChoice) ? _sizeChoice : null,
              decoration: const InputDecoration(labelText: 'Size'),
              items: [
                for (final s in sizes)
                  DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: (v) => setState(() => _sizeChoice = v),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.character;
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit ${c?.name ?? ''}' : 'New Character'),
      ),
      body: ReadableWidth(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isEdit && c != null) ...[
                    _EditableField(
                      label: 'Character Name',
                      controller: _nameController,
                    ),
                    _EditableField(
                      label: 'Level (1–20)',
                      controller: _levelController,
                      numeric: true,
                    ),
                    const Padding(
                      padding: EdgeInsets.only(bottom: 14, top: 2),
                      child: Text(
                        'Changing this recalculates Max HP, Hit Dice, and class/species resource uses, grants any newly-reached class or subclass features, and surfaces a Pending Choice for any Ability Score Improvement or subclass level crossed.',
                        style: TextStyle(
                          fontSize: 12,
                          color: LedgerColors.inkDim,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    _PickerField(
                      label: 'Species',
                      value: _newSpecies?.name ?? c.speciesLabel,
                      placeholder: 'Choose a species…',
                      onTap: _pickNewSpecies,
                    ),
                    _PickerField(
                      label: 'Class',
                      value: _newClass?.name ?? c.classLabel,
                      placeholder: 'Choose a class…',
                      onTap: _pickNewClass,
                    ),
                    if (_newClass != null && _newClass!.key != c.classKey)
                      const _Note(
                        'Changing class rebuilds features, saving throws, Hit '
                        'Die, resources, spell slots, and Max HP for this '
                        'level, and asks for the new class\'s choices again. '
                        'Feats, skills, and gear stay.',
                      ),
                    _PickerField(
                      label: 'Background',
                      value: _newBackground?.name ?? c.backgroundLabel,
                      placeholder: 'Choose a background…',
                      onTap: _pickNewBackground,
                    ),
                    if (_newBackground != null &&
                        _newBackground!.key != c.backgroundKey) ...[
                      const _Note(
                        "The old background's skills, feat, and ability "
                        'increases come off; the new one\'s go on.',
                      ),
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: BackgroundAbilityPicker(
                          options: rules.backgroundAbilityOptions(
                            _newBackground!.key,
                          ),
                          onChanged: (m) => setState(() => _newBgIncreases = m),
                        ),
                      ),
                    ],
                    _buildEditStats(c),
                    _buildToolChoiceSection(),
                    const SizedBox(height: 10),
                    OutlinedButton(
                      onPressed: () {
                        rules.recalculateHp(c);
                        rules.recalculateClassResources(c);
                        rules.recalculateSpellSlots(c);
                        charactersRepo.save(c);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Recalculated Max HP, Hit Dice, and resources for the current level.',
                            ),
                          ),
                        );
                      },
                      child: const Text('Recalculate Derived Stats'),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4, bottom: 14),
                      child: Text(
                        'If HP, Hit Dice, or resources look wrong for your actual level (e.g. after a hand-built starting level or a missed level-up), this fixes them - without changing level, inventory, or feats. Not something you need often, which is why it lives here instead of on the sheet.',
                        style: TextStyle(
                          fontSize: 12,
                          color: LedgerColors.inkDim,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                  ] else ...[
                    _EditableField(
                      label: 'Character Name',
                      controller: _newNameController,
                    ),
                    _PickerField(
                      label: 'Species',
                      value: _selectedSpecies?.name,
                      placeholder: 'Choose a species…',
                      onTap: _pickSpecies,
                    ),
                    _PickerField(
                      label: 'Background',
                      value: _selectedBackground?.name,
                      placeholder: 'Choose a background…',
                      onTap: _pickBackground,
                    ),
                    if (_selectedBackground != null &&
                        rules
                            .backgroundAbilityOptions(_selectedBackground!.key)
                            .isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 14),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'BACKGROUND ABILITY SCORES',
                              style: _fieldLabelStyle,
                            ),
                            const SizedBox(height: 4),
                            BackgroundAbilityPicker(
                              key: ValueKey(_selectedBackground!.key),
                              options: rules.backgroundAbilityOptions(
                                _selectedBackground!.key,
                              ),
                              onChanged: (m) =>
                                  setState(() => _bgIncreases = m),
                            ),
                          ],
                        ),
                      ),
                    _PickerField(
                      label: 'Class',
                      value: _selectedClass?.name,
                      placeholder: 'Choose a class…',
                      onTap: _pickClass,
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4, bottom: 10),
                      child: Text(
                        'Background grants its skills, feat, and ability increases (added to the scores below when the character is created). Class and species features, resources, and spells are filled in; choices they offer (Expertise, a lineage\'s ability, ...) show up as Pending Choices on the Features tab.',
                        style: TextStyle(
                          fontSize: 12,
                          color: LedgerColors.inkDim,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ),
                    _buildSpeciesChoiceSection(),
                    if (_selectedClass != null) _buildSkillChoice(),
                    _buildEquipmentChoice(
                      'CLASS STARTING EQUIPMENT',
                      classEquipmentOptions(_selectedClass?.key),
                      _classEquipment,
                      (v) => setState(() => _classEquipment = v),
                    ),
                    _buildEquipmentChoice(
                      'BACKGROUND STARTING EQUIPMENT',
                      backgroundEquipmentOptions(_selectedBackground?.key),
                      _backgroundEquipment,
                      (v) => setState(() => _backgroundEquipment = v),
                    ),
                    _buildToolChoiceSection(),
                    Text('ABILITY SCORES', style: _fieldLabelStyle),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final key in _abilityKeys)
                          SizedBox(
                            width: 96,
                            child: _EditableField(
                              label: _abilityLabels[key]!,
                              controller: _abilityControllers[key]!,
                              numeric: true,
                            ),
                          ),
                      ],
                    ),
                  ],
                  _EditableField(
                    label: 'Player Name (optional)',
                    controller: _playerNameController,
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'ALIGNMENT (OPTIONAL)',
                          style: _fieldLabelStyle,
                        ),
                        const SizedBox(height: 4),
                        Container(
                          decoration: const BoxDecoration(
                            color: LedgerColors.paper2,
                            border: _fieldBorder,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButtonFormField<String?>(
                              initialValue: _selectedAlignment,
                              isExpanded: true,
                              style: const TextStyle(color: LedgerColors.ink),
                              decoration: const InputDecoration(
                                border: InputBorder.none,
                                isDense: true,
                                contentPadding: EdgeInsets.symmetric(
                                  vertical: 10,
                                ),
                              ),
                              items: [
                                const DropdownMenuItem(
                                  value: null,
                                  child: Text(
                                    'None',
                                    style: TextStyle(
                                      color: LedgerColors.inkDim,
                                    ),
                                  ),
                                ),
                                for (final a in srdCatalog.alignments)
                                  DropdownMenuItem(
                                    value: a.name,
                                    child: Text(a.name),
                                  ),
                              ],
                              onChanged: (v) =>
                                  setState(() => _selectedAlignment = v),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'LANGUAGES (OPTIONAL)',
                          style: _fieldLabelStyle,
                        ),
                        const SizedBox(height: 4),
                        if (_languages.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                for (final language in _languages)
                                  InputChip(
                                    label: Text(language),
                                    onDeleted: () => _removeLanguage(language),
                                  ),
                              ],
                            ),
                          ),
                        OutlinedButton.icon(
                          onPressed: _pickLanguage,
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Add Language'),
                        ),
                      ],
                    ),
                  ),
                  _EditableField(
                    label: 'Appearance (optional)',
                    controller: _appearanceController,
                    multiline: true,
                  ),
                  _EditableField(
                    label: 'Backstory & Personality (optional)',
                    controller: _notesController,
                    multiline: true,
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: isEdit
                            ? (_editBackgroundReady ? _save : null)
                            : _createCharacter,
                        child: Text(
                          isEdit ? 'Save Changes' : 'Create Character',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

const _fieldLabelStyle = TextStyle(
  fontSize: 11,
  letterSpacing: 0.8,
  color: LedgerColors.inkDim,
);
const _fieldBorder = Border(
  top: BorderSide(color: LedgerColors.rule),
  left: BorderSide(color: LedgerColors.rule),
  right: BorderSide(color: LedgerColors.rule),
  bottom: BorderSide(color: LedgerColors.inkDim, width: 2),
);

/// A real, editable field - underlying data a Save actually writes back.
class _EditableField extends StatelessWidget {
  const _EditableField({
    required this.label,
    required this.controller,
    this.numeric = false,
    this.multiline = false,
  });
  final String label;
  final TextEditingController controller;
  final bool numeric;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: _fieldLabelStyle),
          const SizedBox(height: 4),
          Container(
            decoration: const BoxDecoration(
              color: LedgerColors.paper2,
              border: _fieldBorder,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: TextField(
              controller: controller,
              keyboardType: numeric ? TextInputType.number : TextInputType.text,
              style: const TextStyle(color: LedgerColors.ink),
              maxLines: multiline ? 4 : 1,
              minLines: 1,
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A field that opens a [CatalogPickerScreen] on tap - Species/Background/
/// Class in New Character, each backed by real SRD data now.
class _Note extends StatelessWidget {
  const _Note(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 0, bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        color: LedgerColors.inkDim,
        fontStyle: FontStyle.italic,
      ),
    ),
  );
}

class _PickerField extends StatelessWidget {
  const _PickerField({
    required this.label,
    required this.value,
    required this.placeholder,
    required this.onTap,
  });
  final String label;
  final String? value;
  final String placeholder;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: _fieldLabelStyle),
          const SizedBox(height: 4),
          InkWell(
            onTap: onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: const BoxDecoration(
                color: LedgerColors.paper2,
                border: _fieldBorder,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value ?? placeholder,
                      style: TextStyle(
                        color: value != null
                            ? LedgerColors.ink
                            : LedgerColors.inkDim,
                        fontStyle: value != null
                            ? FontStyle.normal
                            : FontStyle.italic,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: LedgerColors.inkDim,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A toggleable skill choice for New Character's skill-proficiency step -
/// visually distinct from the read-only ledger chip used elsewhere
/// (Heavy Weapon Mastery, mastery names): this one is tappable.
class _SkillChip extends StatelessWidget {
  const _SkillChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? LedgerColors.accent : LedgerColors.rule,
          ),
          color: selected
              ? LedgerColors.accent.withValues(alpha: 0.18)
              : Colors.transparent,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? LedgerColors.accent : LedgerColors.inkDim,
          ),
        ),
      ),
    );
  }
}
