import 'package:flutter/material.dart';

import '../theme/ledger_theme.dart';

const _abilityNames = {
  'str': 'Strength',
  'dex': 'Dexterity',
  'con': 'Constitution',
  'int': 'Intelligence',
  'wis': 'Wisdom',
  'cha': 'Charisma',
};

/// Whether [increases] is a legal 2024 background split: +2 to one and +1
/// to another, or +1 to three - all among [options].
bool validBackgroundIncreases(
  Map<String, int> increases,
  List<String> options,
) {
  if (options.isEmpty) return true;
  if (increases.keys.any((k) => !options.contains(k))) return false;
  final values = increases.values.where((v) => v > 0).toList()..sort();
  return (values.length == 2 && values[0] == 1 && values[1] == 2) ||
      (values.length == 3 && values.every((v) => v == 1));
}

/// Picks a background's ability score increases: "+2 / +1" (two different
/// abilities) or "+1 / +1 / +1" (all three), from the background's own
/// three abilities ([options], ability keys). Reports every change through
/// [onChanged]; [validBackgroundIncreases] says when it's complete.
class BackgroundAbilityPicker extends StatefulWidget {
  const BackgroundAbilityPicker({
    super.key,
    required this.options,
    required this.onChanged,
    this.initial = const {},
  });

  final List<String> options;
  final Map<String, int> initial;
  final ValueChanged<Map<String, int>> onChanged;

  @override
  State<BackgroundAbilityPicker> createState() =>
      _BackgroundAbilityPickerState();
}

class _BackgroundAbilityPickerState extends State<BackgroundAbilityPicker> {
  late bool _spread; // true = +1/+1/+1
  String? _plusTwo;
  String? _plusOne;

  @override
  void initState() {
    super.initState();
    final init = widget.initial;
    _spread = init.length == 3;
    if (!_spread) {
      for (final e in init.entries) {
        if (e.value == 2) _plusTwo = e.key;
        if (e.value == 1) _plusOne = e.key;
      }
    }
  }

  void _emit() {
    widget.onChanged(
      _spread
          ? {for (final k in widget.options) k: 1}
          : {
              ?_plusTwo: 2,
              if (_plusOne != null && _plusOne != _plusTwo) _plusOne!: 1,
            },
    );
  }

  Widget _dropdown(String label, String? value, ValueChanged<String?> set) =>
      Expanded(
        child: DropdownButtonFormField<String>(
          initialValue: value,
          isExpanded: true,
          decoration: InputDecoration(labelText: label, isDense: true),
          items: [
            for (final k in widget.options)
              DropdownMenuItem(value: k, child: Text(_abilityNames[k] ?? k)),
          ],
          onChanged: (v) {
            setState(() => set(v));
            _emit();
          },
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.options.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Raise ${widget.options.map((k) => _abilityNames[k]).join(', ')} '
          '(max 20).',
          style: const TextStyle(fontSize: 12, color: LedgerColors.inkDim),
        ),
        const SizedBox(height: 6),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('+2 / +1')),
            ButtonSegment(value: true, label: Text('+1 / +1 / +1')),
          ],
          selected: {_spread},
          onSelectionChanged: (s) {
            setState(() => _spread = s.first);
            _emit();
          },
        ),
        if (!_spread) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              _dropdown('+2', _plusTwo, (v) => _plusTwo = v),
              const SizedBox(width: 10),
              _dropdown('+1', _plusOne, (v) => _plusOne = v),
            ],
          ),
          if (_plusTwo != null && _plusTwo == _plusOne)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Pick two different abilities.',
                style: TextStyle(fontSize: 12, color: LedgerColors.danger),
              ),
            ),
        ],
      ],
    );
  }
}
