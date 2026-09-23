import 'package:flutter/material.dart';

import '../domain/rules.dart' as rules;
import '../models/character.dart';
import '../theme/ledger_theme.dart';
import '../widgets/markdown_text.dart';

/// Lets the player pick from a feature's options (rules.FeatureOptionSet):
/// Expertise skills, Weapon Mastery weapons, Eldritch Invocations, a Giant
/// Ancestry boon, Magic Initiate's spells... Shows each option's own rules
/// text, greys out what can't be taken (a prerequisite not met, already
/// picked), and has a search box for the long lists. [replace] starts from
/// the current picks and lets them be swapped (a changeable set, like
/// Weapon Mastery after a Long Rest); otherwise it picks [count] new ones.
/// Returns the picks, or null if cancelled.
Future<List<String>?> showOptionPicker(
  BuildContext context,
  Character c,
  rules.FeatureOptionSet set, {
  int? count,
  bool replace = false,
}) {
  final max = replace
      ? rules.optionCount(c, set)
      : (count ?? rules.optionCount(c, set) - rules.optionPicks(c, set).length);
  final options = rules.optionsFor(c, set);
  final current = rules.optionPicks(c, set).toSet();
  final selected = <String>{if (replace) ...current};
  var query = '';

  return showDialog<List<String>>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) {
        final visible = options
            .where(
              (o) =>
                  query.isEmpty ||
                  o.name.toLowerCase().contains(query.toLowerCase()),
            )
            .toList();
        bool enabled(rules.FeatureOption o) =>
            selected.contains(o.name) ||
            (replace && current.contains(o.name)) ||
            rules.optionAvailable(c, set, o);
        return AlertDialog(
          title: Text(set.label),
          contentPadding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          content: SizedBox(
            width: double.maxFinite,
            height: 440,
            child: Column(
              children: [
                Text(
                  max == 1
                      ? 'Choose one.'
                      : 'Choose $max (${selected.length} chosen).',
                  style: const TextStyle(
                    fontSize: 12,
                    color: LedgerColors.inkDim,
                  ),
                ),
                if (options.length > 8)
                  TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search…',
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                    ),
                    onChanged: (v) => setState(() => query = v),
                  ),
                const SizedBox(height: 6),
                Expanded(
                  child: options.isEmpty
                      ? const Center(
                          child: Text(
                            'Nothing to choose from yet.',
                            style: TextStyle(color: LedgerColors.inkDim),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final o in visible)
                              CheckboxListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                value: selected.contains(o.name),
                                onChanged: enabled(o)
                                    ? (v) => setState(() {
                                        if (v == true) {
                                          if (max == 1) selected.clear();
                                          if (selected.length < max) {
                                            selected.add(o.name);
                                          }
                                        } else {
                                          selected.remove(o.name);
                                        }
                                      })
                                    : null,
                                title: Text(o.name),
                                subtitle: o.desc.isEmpty
                                    ? (o.minLevel > c.level
                                          ? Text('Level ${o.minLevel}+')
                                          : null)
                                    : MarkdownText(o.desc),
                              ),
                          ],
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
            FilledButton(
              onPressed: selected.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(selected.toList()),
              child: const Text('Choose'),
            ),
          ],
        );
      },
    ),
  );
}

/// The picks a feature's option sets have (e.g. under Divine Order:
/// "Protector"; under Eldritch Invocations: the invocations), with a
/// Choose/Change button - shown in the feature's expanded row, so an
/// existing character can make choices that were never asked for, and a
/// changeable one (Weapon Mastery, Hunter's Prey) can be swapped.
class FeatureOptionsBlock extends StatelessWidget {
  const FeatureOptionsBlock({
    super.key,
    required this.character,
    required this.featureName,
    required this.onChanged,
  });
  final Character character;
  final String featureName;
  final VoidCallback onChanged;

  Future<void> _choose(
    BuildContext context,
    rules.FeatureOptionSet set,
    bool replace,
  ) async {
    final picks = await showOptionPicker(
      context,
      character,
      set,
      replace: replace,
    );
    if (picks == null) return;
    rules.chooseOptions(character, set, picks, replace: replace);
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final sets = rules
        .featureOptionSetsFor(character)
        .where((s) => s.featureName == featureName)
        .toList();
    if (sets.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final set in sets)
          Builder(
            builder: (context) {
              final picks = rules.optionPicks(character, set);
              final count = rules.optionCount(character, set);
              final missing = count - picks.length;
              return Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        picks.isEmpty
                            ? '${set.label} - none chosen yet.'
                            : '${set.label}: ${picks.join(', ')}'
                                  '${missing > 0 ? ' ($missing more to choose)' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    if (missing > 0)
                      TextButton(
                        onPressed: () => _choose(context, set, false),
                        child: const Text('Choose'),
                      )
                    else if (set.changeable && picks.isNotEmpty)
                      TextButton(
                        onPressed: () => _choose(context, set, true),
                        child: const Text('Change'),
                      ),
                  ],
                ),
              );
            },
          ),
      ],
    );
  }
}
