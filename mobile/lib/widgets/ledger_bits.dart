import 'package:flutter/material.dart';

import '../theme/ledger_theme.dart';

/// Small shared pieces that don't warrant their own file: a section label
/// (the "§ Resources" style heading), a tally-mark square (proficiency /
/// use-remaining indicator), and a plain non-expandable fact row (saving
/// throws, skills, inventory) - things read once, not tapped into.

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 18, bottom: 8),
      child: Text(
        '§ ${text.toUpperCase()}',
        style: const TextStyle(
          fontSize: 12,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w600,
          color: LedgerColors.accent,
        ),
      ),
    );
  }
}

class Tally extends StatelessWidget {
  const Tally({super.key, required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 9,
      height: 9,
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        border: Border.all(color: LedgerColors.accent, width: 1.4),
        color: on ? LedgerColors.accent : Colors.transparent,
      ),
    );
  }
}

class FactRow extends StatelessWidget {
  const FactRow({
    super.key,
    required this.label,
    required this.value,
    this.caption,
    this.tally,
    this.onDelete,
  });

  final String label;
  final String value;
  final String? caption;
  final bool? tally;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: LedgerColors.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (tally != null) Tally(on: tally!),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: LedgerColors.ink,
                  ),
                ),
              ),
              Text(value, style: LedgerTheme.dataStyle(fontSize: 14)),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
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
          if (caption != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                caption!,
                style: const TextStyle(
                  fontSize: 12,
                  color: LedgerColors.inkDim,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
