import 'package:flutter/material.dart';

import '../data/homebrew_catalog.dart';
import '../data/homebrew_repository.dart';
import '../data/srd_catalog.dart';
import '../theme/app_theme.dart';
import '../widgets/common_bits.dart';
import '../widgets/weapon_stats_fields.dart';

/// The rules fields for a homebrew entry, by kind - what makes a homebrew
/// spell, weapon, armor, magic item, species, background, class, or
/// subclass work in the app the way an SRD one does (see
/// data/homebrew_catalog.dart for the data keys). Every field that has an
/// SRD list behind it is a dropdown or chip picker. Reports each change
/// through [onChanged] with the whole updated data map.
class HomebrewRulesEditor extends StatefulWidget {
  const HomebrewRulesEditor({
    super.key,
    required this.kind,
    required this.entryId,
    required this.data,
    required this.onChanged,
  });

  final String kind;
  final String entryId;
  final Map<String, dynamic> data;
  final ValueChanged<Map<String, dynamic>> onChanged;

  static const supportedKinds = {
    'feat',
    'spell',
    'weapon',
    'armor',
    'magicItem',
    'species',
    'background',
    'class',
    'subclass',
  };

  @override
  State<HomebrewRulesEditor> createState() => _HomebrewRulesEditorState();
}

const _abilityKeys = ['str', 'dex', 'con', 'int', 'wis', 'cha'];
const _abilityNames = {
  'str': 'Strength',
  'dex': 'Dexterity',
  'con': 'Constitution',
  'int': 'Intelligence',
  'wis': 'Wisdom',
  'cha': 'Charisma',
};

const _castingTimes = [
  'Action',
  'Bonus Action',
  'Reaction',
  '1 minute',
  '10 minutes',
  '1 hour',
  '8 hours',
];
const _ranges = [
  'Self',
  'Touch',
  '5 feet',
  '10 feet',
  '30 feet',
  '60 feet',
  '90 feet',
  '120 feet',
  '150 feet',
  '300 feet',
  '1 mile',
  'Sight',
  'Unlimited',
];
const _durations = [
  'Instantaneous',
  '1 round',
  '1 minute',
  '10 minutes',
  '1 hour',
  '8 hours',
  '24 hours',
  'Until dispelled',
];
const _itemCategories = [
  'Armor',
  'Potion',
  'Ring',
  'Rod',
  'Scroll',
  'Staff',
  'Wand',
  'Weapon',
  'Wondrous Item',
];
const _rarities = [
  'Common',
  'Uncommon',
  'Rare',
  'Very Rare',
  'Legendary',
  'Artifact',
];

class _HomebrewRulesEditorState extends State<HomebrewRulesEditor> {
  late Map<String, dynamic> _d;

  @override
  void initState() {
    super.initState();
    _d = {...widget.data};
  }

  void _set(String key, Object? value) {
    setState(() => _d[key] = value);
    widget.onChanged({..._d});
  }

  List<String> _list(String key) => (_d[key] as List?)?.cast<String>() ?? [];

  List<Map<String, dynamic>> _maps(String key) => [
    for (final m in (_d[key] as List?) ?? const [])
      (m as Map).cast<String, dynamic>(),
  ];

  // ---- small field builders -------------------------------------------

  Widget _dropdown<T>(
    String label,
    T? value,
    List<T> options,
    ValueChanged<T?> onChanged, {
    String Function(T)? display,
  }) {
    final all = {...options, ?value}.toList();
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DropdownButtonFormField<T>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label, isDense: true),
        items: [
          for (final o in all)
            DropdownMenuItem(
              value: o,
              child: Text(display != null ? display(o) : '$o'),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _text(String key, String label, {int lines = 1, String? hint}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextFormField(
          initialValue: _d[key] as String? ?? '',
          maxLines: lines == 1 ? 1 : null,
          minLines: lines,
          decoration: InputDecoration(labelText: label, hintText: hint),
          onChanged: (v) => _set(key, v),
        ),
      );

  Widget _number(String key, String label, {int fallback = 0}) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: TextFormField(
      initialValue: '${_d[key] ?? fallback}',
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      onChanged: (v) => _set(key, int.tryParse(v.trim()) ?? fallback),
    ),
  );

  Widget _switch(String key, String label) => SwitchListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    title: Text(label),
    value: _d[key] as bool? ?? false,
    onChanged: (v) => _set(key, v),
  );

  Widget _chips(
    String key,
    String label,
    List<String> options, {
    int? max,
    String Function(String)? display,
  }) {
    final selected = _list(key);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            max == null ? label : '$label (choose $max)',
            style: const TextStyle(fontSize: 12, color: AppColors.inkDim),
          ),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final o in options)
                FilterChip(
                  label: Text(
                    display != null ? display(o) : o,
                    style: const TextStyle(fontSize: 12),
                  ),
                  selected: selected.contains(o),
                  onSelected: (v) {
                    if (v && max != null && selected.length >= max) return;
                    _set(
                      key,
                      v
                          ? [...selected, o]
                          : selected.where((x) => x != o).toList(),
                    );
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  /// A list of features/traits: [withLevel] adds a level dropdown. Each
  /// has a name, rules text, and a short PDF sheet line.
  Widget _featureList(String key, String label, {required bool withLevel}) {
    final items = _maps(key);
    void update(int i, String field, Object? value) {
      final next = [...items];
      next[i] = {...next[i], field: value};
      _set(key, next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: SectionLabel(label)),
            TextButton(
              onPressed: () => _set(key, [
                ...items,
                {
                  '_id': DateTime.now().microsecondsSinceEpoch,
                  if (withLevel) 'level': 1,
                  'name': '',
                  'desc': '',
                  'shortDesc': '',
                },
              ]),
              child: const Text('+ Add'),
            ),
          ],
        ),
        for (final (i, item) in items.indexed)
          Container(
            key: ValueKey(item['_id'] ?? '$i-${item['name']}'),
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.rule),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    if (withLevel)
                      SizedBox(
                        width: 90,
                        child: DropdownButtonFormField<int>(
                          initialValue: item['level'] as int? ?? 1,
                          decoration: const InputDecoration(
                            labelText: 'Level',
                            isDense: true,
                          ),
                          items: [
                            for (var l = 1; l <= 20; l++)
                              DropdownMenuItem(value: l, child: Text('$l')),
                          ],
                          onChanged: (v) => update(i, 'level', v),
                        ),
                      ),
                    if (withLevel) const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        initialValue: item['name'] as String? ?? '',
                        decoration: const InputDecoration(
                          labelText: 'Name',
                          isDense: true,
                        ),
                        onChanged: (v) => update(i, 'name', v),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _set(key, [...items]..removeAt(i)),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: AppColors.inkDim,
                    ),
                  ],
                ),
                TextFormField(
                  initialValue: item['desc'] as String? ?? '',
                  minLines: 2,
                  maxLines: null,
                  decoration: const InputDecoration(labelText: 'Rules text'),
                  onChanged: (v) => update(i, 'desc', v),
                ),
                TextFormField(
                  initialValue: item['shortDesc'] as String? ?? '',
                  decoration: const InputDecoration(
                    labelText: 'Sheet text (short, for the PDF)',
                  ),
                  onChanged: (v) => update(i, 'shortDesc', v),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Spells this entry grants (feats, species, classes): each with the
  /// level it arrives at, free casts per rest (none / 1 / at will, or
  /// Proficiency Bonus times), how those recharge, and the casting ability.
  Widget _grantedSpells({required String levelLabel}) {
    final rows = _maps('grantedSpells');
    void update(int i, String field, Object? value) {
      final next = [...rows];
      next[i] = {...next[i], field: value};
      _set('grantedSpells', next);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: SectionLabel('Granted spells')),
            TextButton(
              onPressed: () => _set('grantedSpells', [
                ...rows,
                {
                  '_id': DateTime.now().microsecondsSinceEpoch,
                  'level': 1,
                  'name': '',
                  'freeCasts': 0,
                  'recovery': 'long',
                },
              ]),
              child: const Text('+ Add'),
            ),
          ],
        ),
        if (rows.isEmpty)
          const Text(
            'Always prepared once granted; free casts need no slot.',
            style: TextStyle(fontSize: 12, color: AppColors.inkDim),
          ),
        for (final (i, row) in rows.indexed)
          Container(
            key: ValueKey(row['_id'] ?? '$i-${row['name']}'),
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.rule),
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Autocomplete<String>(
                        initialValue: TextEditingValue(
                          text: row['name'] as String? ?? '',
                        ),
                        optionsBuilder: (value) => value.text.isEmpty
                            ? const []
                            : [
                                for (final s in srdCatalog.spells)
                                  if (s.name.toLowerCase().contains(
                                    value.text.toLowerCase(),
                                  ))
                                    s.name,
                                for (final e in homebrewRepo.byKind('spell'))
                                  if (e.name.toLowerCase().contains(
                                    value.text.toLowerCase(),
                                  ))
                                    e.name,
                              ],
                        onSelected: (name) => update(i, 'name', name),
                        fieldViewBuilder:
                            (context, controller, focus, submit) => TextField(
                              controller: controller,
                              focusNode: focus,
                              decoration: const InputDecoration(
                                labelText: 'Spell',
                                isDense: true,
                              ),
                            ),
                      ),
                    ),
                    IconButton(
                      onPressed: () =>
                          _set('grantedSpells', [...rows]..removeAt(i)),
                      icon: const Icon(Icons.delete_outline, size: 18),
                      color: AppColors.inkDim,
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: row['level'] as int? ?? 1,
                        decoration: InputDecoration(
                          labelText: levelLabel,
                          isDense: true,
                        ),
                        items: [
                          for (var l = 1; l <= 20; l++)
                            DropdownMenuItem(value: l, child: Text('$l')),
                        ],
                        onChanged: (v) => update(i, 'level', v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        initialValue: row['freeCasts'] as int? ?? 0,
                        decoration: const InputDecoration(
                          labelText: 'Free casts',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(value: 0, child: Text('None')),
                          DropdownMenuItem(value: 1, child: Text('1')),
                          DropdownMenuItem(value: 2, child: Text('2')),
                          DropdownMenuItem(value: 3, child: Text('3')),
                          DropdownMenuItem(value: -1, child: Text('At will')),
                        ],
                        onChanged: (v) => update(i, 'freeCasts', v),
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: row['recovery'] as String? ?? 'long',
                        decoration: const InputDecoration(
                          labelText: 'Recharge',
                          isDense: true,
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'long',
                            child: Text('Long Rest'),
                          ),
                          DropdownMenuItem(
                            value: 'short',
                            child: Text('Short or Long Rest'),
                          ),
                        ],
                        onChanged: (v) => update(i, 'recovery', v),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: DropdownButtonFormField<String?>(
                        initialValue: row['ability'] as String?,
                        decoration: const InputDecoration(
                          labelText: 'Ability',
                          isDense: true,
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Class ability'),
                          ),
                          for (final k in const ['int', 'wis', 'cha'])
                            DropdownMenuItem(
                              value: k,
                              child: Text(_abilityNames[k]!),
                            ),
                        ],
                        onChanged: (v) => update(i, 'ability', v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _featChoice() => _dropdown<String>(
    'Grants a feat',
    _d['featChoice'] as String? ?? '',
    const [
      '',
      'any',
      'Origin Feat',
      'General Feat',
      'Fighting Style Feat',
      'Epic Boon Feat',
    ],
    (v) => _set('featChoice', v),
    display: (c) => switch (c) {
      '' => 'No',
      'any' => 'Yes - any feat',
      _ when 'AEIOU'.contains(c[0]) => 'Yes - an $c',
      _ => 'Yes - a $c',
    },
  );

  // ---- per kind ----------------------------------------------------------

  List<Widget> _feat() => [
    _switch('repeatable', 'Repeatable (can be taken more than once)'),
    _chips(
      'abilityIncrease',
      'Ability score increase: which scores it can raise (pick one when '
          'the feat is taken)',
      const ['str', 'dex', 'con', 'int', 'wis', 'cha'],
      display: (k) => _abilityNames[k] ?? k,
    ),
    if (_list('abilityIncrease').isNotEmpty)
      Row(
        children: [
          Expanded(
            child: _dropdown<int>(
              'Increase by',
              _d['abilityIncreaseAmount'] as int? ?? 1,
              const [1, 2],
              (v) => _set('abilityIncreaseAmount', v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _dropdown<int>(
              'To a maximum of',
              _d['abilityIncreaseMax'] as int? ?? 20,
              const [20, 30],
              (v) => _set('abilityIncreaseMax', v),
            ),
          ),
        ],
      ),
    _featChoice(),
    _grantedSpells(levelLabel: 'Character level'),
  ];

  List<Widget> _spell() {
    final components = (_d['components'] as String? ?? '').split(
      RegExp(r',\s*'),
    );
    final material = RegExp(r'M \((.*)\)')
        .firstMatch(_d['components'] as String? ?? '')
        ?.group(1);
    void setComponents({bool? v, bool? s, bool? m, String? mat}) {
      final hasV = v ?? components.contains('V');
      final hasS = s ?? components.contains('S');
      final hasM = m ?? (_d['components'] as String? ?? '').contains('M');
      final text = mat ?? material ?? '';
      _set(
        'components',
        [
          if (hasV) 'V',
          if (hasS) 'S',
          if (hasM) text.isEmpty ? 'M' : 'M ($text)',
        ].join(', '),
      );
    }

    final hasM = (_d['components'] as String? ?? '').contains('M');
    return [
      Row(
        children: [
          Expanded(
            child: _dropdown<int>(
              'Level',
              _d['level'] as int? ?? 1,
              [for (var l = 0; l <= 9; l++) l],
              (v) => _set('level', v),
              display: (l) => l == 0 ? 'Cantrip' : 'Level $l',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _dropdown<String>('School', _d['school'] as String?, [
              for (final s in srdCatalog.spellSchools) s.name,
            ], (v) => _set('school', v)),
          ),
        ],
      ),
      _dropdown<String>(
        'Casting time',
        _d['castingTime'] as String?,
        _castingTimes,
        (v) => _set('castingTime', v),
      ),
      _dropdown<String>(
        'Range',
        _d['range'] as String?,
        _ranges,
        (v) => _set('range', v),
      ),
      Row(
        children: [
          for (final (label, flag) in [
            ('V', components.contains('V')),
            ('S', components.contains('S')),
            ('M', hasM),
          ])
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilterChip(
                label: Text(label),
                selected: flag,
                onSelected: (sel) => setComponents(
                  v: label == 'V' ? sel : null,
                  s: label == 'S' ? sel : null,
                  m: label == 'M' ? sel : null,
                ),
              ),
            ),
        ],
      ),
      if (hasM)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: TextFormField(
            initialValue: material ?? '',
            decoration: const InputDecoration(
              labelText: 'Material component',
              hintText: 'e.g. a diamond worth 300+ GP',
            ),
            onChanged: (t) => setComponents(mat: t),
          ),
        ),
      _dropdown<String>(
        'Duration',
        _d['duration'] as String?,
        _durations,
        (v) => _set('duration', v),
      ),
      _switch('concentration', 'Concentration'),
      _switch('ritual', 'Ritual'),
      _chips('classes', 'Spell lists', [
        for (final c in srdCatalog.classesByKey.values)
          if (c.traits['Spellcasting Ability'] != null ||
              srdCatalog.spells.any((s) => s.classes.contains(c.name)))
            c.name,
      ]),
      _text('higherLevel', 'Using a higher-level spell slot', lines: 2),
    ];
  }

  List<Widget> _weapon() {
    final stats = WeaponStats.fromData(_d) ?? WeaponStats();
    return weaponStatsFields(stats, (fn) {
      fn();
      for (final e in stats.toData().entries) {
        _d[e.key] = e.value;
      }
      setState(() {});
      widget.onChanged({..._d});
    });
  }

  List<Widget> _armor() => [
    _dropdown<String>(
      'Category',
      _d['armorCategory'] as String? ?? 'Light',
      const ['Light', 'Medium', 'Heavy', 'Shield'],
      (v) => _set('armorCategory', v),
    ),
    if (_d['armorCategory'] != 'Shield') ...[
      _number('baseAc', 'Base AC', fallback: 11),
      _dropdown<String>(
        'Dex',
        _d['dexMode'] as String? ?? 'full',
        const ['full', 'max2', 'none'],
        (v) => _set('dexMode', v),
        display: (m) => switch (m) {
          'full' => '+ Dex',
          'max2' => '+ Dex (max 2)',
          _ => 'No Dex',
        },
      ),
      _dropdown<String?>(
        'Strength requirement',
        _d['strength'] as String?,
        const [null, 'Str 13', 'Str 15'],
        (v) => _set('strength', v),
        display: (s) => s ?? 'None',
      ),
      _switch('stealth', 'Disadvantage on Stealth'),
    ],
  ];

  List<Widget> _magicItem() => [
    _dropdown<String>(
      'Category',
      _d['itemCategory'] as String?,
      _itemCategories,
      (v) => _set('itemCategory', v),
    ),
    _dropdown<String>(
      'Rarity',
      _d['rarity'] as String?,
      _rarities,
      (v) => _set('rarity', v),
    ),
    _switch('requiresAttunement', 'Requires attunement'),
    _number('charges', 'Charges (0 = none)'),
    if ((_d['charges'] as int? ?? 0) > 0)
      _dropdown<String>(
        'Charges come back',
        _d['recharge'] as String? ?? 'long',
        const ['dawn', 'long', 'short', 'none'],
        (v) => _set('recharge', v),
        display: (r) => switch (r) {
          'dawn' => 'At dawn',
          'short' => 'On a Short or Long Rest',
          'none' => 'Never (consumable)',
          _ => 'On a Long Rest',
        },
      ),
  ];

  List<Widget> _species() => [
    _dropdown<String>('Size', _d['size'] as String? ?? 'Medium', const [
      'Small',
      'Medium',
      'Large',
      'Medium or Small',
    ], (v) => _set('size', v)),
    _number('speed', 'Speed (ft)', fallback: 30),
    _chips('resistances', 'Damage resistances', [
      for (final dt in srdCatalog.damageTypes) dt.name,
    ]),
    _featChoice(),
    _featureList('traits', 'Traits', withLevel: false),
    _grantedSpells(levelLabel: 'Character level'),
  ];

  List<Widget> _background() {
    final originFeats = [
      for (final f in srdCatalog.featsByKey.values)
        if (f.category == 'Origin Feat') f.name,
      for (final e in homebrewRepo.byKind('feat'))
        if (e.category == 'Origin Feat') e.name,
    ];
    return [
      _chips('abilityScores', 'Ability scores it can raise', [
        for (final k in _abilityKeys) _abilityNames[k]!,
      ], max: 3),
      _chips('skills', 'Skill proficiencies', [
        ...srdCatalog.skillsByName.keys.toList()..sort(),
      ], max: 2),
      _dropdown<String>('Tool proficiency', _d['tool'] as String?, [
        for (final t in srdCatalog.tools) t.name,
      ], (v) => _set('tool', v)),
      _dropdown<String>(
        'Origin feat',
        _d['feat'] as String?,
        originFeats,
        (v) => _set('feat', v),
      ),
      _text(
        'equipment',
        'Starting equipment',
        lines: 2,
        hint: 'Choose A or B: (A) Item, 2 Items, and 10 GP; or (B) 50 GP',
      ),
    ];
  }

  List<Widget> _class() {
    final caster = _d['casterType'] as String? ?? 'none';
    return [
      Row(
        children: [
          Expanded(
            child: _dropdown<String>(
              'Hit Die',
              _d['hitDie'] as String? ?? 'd8',
              const ['d6', 'd8', 'd10', 'd12'],
              (v) => _set('hitDie', v),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _dropdown<String>(
              'Primary ability',
              _d['primaryAbility'] as String?,
              _abilityKeys,
              (v) => _set('primaryAbility', v),
              display: (k) => _abilityNames[k]!,
            ),
          ),
        ],
      ),
      _chips(
        'saves',
        'Saving throw proficiencies',
        _abilityKeys,
        max: 2,
        display: (k) => _abilityNames[k]!,
      ),
      _dropdown<int>('Skills to choose', _d['skillCount'] as int? ?? 2, const [
        1,
        2,
        3,
        4,
      ], (v) => _set('skillCount', v)),
      _chips('skillChoices', 'Skills to choose from (none = any)', [
        ...srdCatalog.skillsByName.keys.toList()..sort(),
      ]),
      _chips('armorTraining', 'Armor training', const [
        'Light',
        'Medium',
        'Heavy',
        'Shields',
      ]),
      _dropdown<String>(
        'Weapon proficiencies',
        _d['weaponProficiencies'] as String? ?? 'Simple weapons',
        const [
          'Simple weapons',
          'Simple and Martial weapons',
          'Simple weapons and Martial weapons that have the Light property',
          'Simple weapons and Martial weapons that have the Finesse or Light property',
        ],
        (v) => _set('weaponProficiencies', v),
      ),
      _text('toolProficiencies', 'Tool proficiencies', hint: 'or None'),
      _dropdown<String>(
        'Spellcasting',
        caster,
        const ['none', 'full', 'half', 'pact'],
        (v) => _set('casterType', v),
        display: (t) => switch (t) {
          'full' => 'Full caster (Wizard progression)',
          'half' => 'Half caster (Paladin progression)',
          'pact' => 'Pact Magic (Warlock progression)',
          _ => 'None',
        },
      ),
      if (caster != 'none')
        _dropdown<String>(
          'Spellcasting ability',
          _d['spellAbility'] as String?,
          const ['int', 'wis', 'cha'],
          (v) => _set('spellAbility', v),
          display: (k) => _abilityNames[k]!,
        ),
      _dropdown<int>(
        'Subclass at level',
        _d['subclassLevel'] as int? ?? 3,
        const [1, 2, 3],
        (v) => _set('subclassLevel', v),
      ),
      SwitchListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        title: const Text('Standard feats (ASI at 4/8/12/16, Epic Boon at 19)'),
        value: _d['standardFeatLevels'] as bool? ?? true,
        onChanged: (v) => _set('standardFeatLevels', v),
      ),
      _text(
        'equipment',
        'Starting equipment',
        lines: 2,
        hint: 'Choose A or B: (A) Item, 2 Items, and 10 GP; or (B) 50 GP',
      ),
      _featureList('features', 'Features', withLevel: true),
      _grantedSpells(levelLabel: 'Class level'),
    ];
  }

  List<Widget> _subclass() {
    final classes = [
      for (final c in srdCatalog.classesByKey.values)
        if (c.key != widget.entryId) c,
    ];
    final spells = _maps('spells');
    return [
      _dropdown<String>(
        'Class',
        _d['parentClass'] as String?,
        [for (final c in classes) c.key],
        (v) => _set('parentClass', v),
        display: (k) => srdCatalog.byKey(k)?.name ?? k,
      ),
      _featureList('features', 'Features', withLevel: true),
      Row(
        children: [
          const Expanded(child: SectionLabel('Always-prepared spells')),
          TextButton(
            onPressed: () => _set('spells', [
              ...spells,
              {'level': 3, 'spells': <String>[]},
            ]),
            child: const Text('+ Add Level'),
          ),
        ],
      ),
      for (final (i, row) in spells.indexed)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Row(
            children: [
              SizedBox(
                width: 80,
                child: DropdownButtonFormField<int>(
                  initialValue: row['level'] as int? ?? 3,
                  decoration: const InputDecoration(
                    labelText: 'Level',
                    isDense: true,
                  ),
                  items: [
                    for (var l = 1; l <= 20; l++)
                      DropdownMenuItem(value: l, child: Text('$l')),
                  ],
                  onChanged: (v) {
                    final next = [...spells];
                    next[i] = {...row, 'level': v};
                    _set('spells', next);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Autocomplete<String>(
                  optionsBuilder: (value) => value.text.isEmpty
                      ? const []
                      : srdCatalog.spells
                            .map((s) => s.name)
                            .where(
                              (n) => n.toLowerCase().contains(
                                value.text.toLowerCase(),
                              ),
                            ),
                  onSelected: (name) {
                    final next = [...spells];
                    next[i] = {
                      ...row,
                      'spells': [...(row['spells'] as List? ?? const []), name],
                    };
                    _set('spells', next);
                  },
                  fieldViewBuilder: (context, controller, focus, submit) =>
                      TextField(
                        controller: controller,
                        focusNode: focus,
                        decoration: InputDecoration(
                          labelText: 'Add a spell',
                          helperText: (row['spells'] as List? ?? const []).join(
                            ', ',
                          ),
                          isDense: true,
                        ),
                      ),
                ),
              ),
              IconButton(
                onPressed: () => _set('spells', [...spells]..removeAt(i)),
                icon: const Icon(Icons.delete_outline, size: 18),
                color: AppColors.inkDim,
              ),
            ],
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final fields = switch (widget.kind) {
      'feat' => _feat(),
      'spell' => _spell(),
      'weapon' => _weapon(),
      'armor' => _armor(),
      'magicItem' => _magicItem(),
      'species' => _species(),
      'background' => _background(),
      'class' => _class(),
      'subclass' => _subclass(),
      _ => const <Widget>[],
    };
    if (fields.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [const SectionLabel('Rules'), ...fields],
    );
  }
}
