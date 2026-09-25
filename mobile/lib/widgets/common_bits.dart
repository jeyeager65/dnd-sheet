import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Small shared pieces that don't warrant their own file: a section label
/// ("RESOURCES" style heading, underlined to separate it from what's
/// above), a tally-mark square (proficiency / use-remaining indicator),
/// and a plain non-expandable fact row (saving throws, skills, inventory)
/// - things read once, not tapped into.

class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key, this.trailing});
  final String text;

  /// An action for this section (e.g. "+ Add Weapon"), laid out at the
  /// row's far end so the underline below still spans the full width -
  /// callers should pass it here rather than wrapping SectionLabel in
  /// their own spaceBetween Row.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 22, bottom: 10),
      padding: const EdgeInsets.only(bottom: 6),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.accentSoft, width: 2),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              text.toUpperCase(),
              style: const TextStyle(
                fontSize: 14,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
                color: AppColors.accent,
              ),
            ),
          ),
          ?trailing,
        ],
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
        border: Border.all(color: AppColors.accent, width: 1.4),
        color: on ? AppColors.accent : Colors.transparent,
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
        border: Border(bottom: BorderSide(color: AppColors.rule)),
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
                    color: AppColors.ink,
                  ),
                ),
              ),
              Text(value, style: AppTheme.dataStyle(fontSize: 14)),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline, size: 18),
                  color: AppColors.inkDim,
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
                style: const TextStyle(fontSize: 12, color: AppColors.inkDim),
              ),
            ),
        ],
      ),
    );
  }
}
