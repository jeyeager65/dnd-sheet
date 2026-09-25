import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// The boxed "totals" row from the ledger mockup - reused for ability
/// scores, combat stats, and currency alike, since a real ledger would
/// tally all three the same way: ruled cells with a value over a label.
class StatCell {
  const StatCell(this.value, this.label);
  final String value;
  final String label;
}

/// One cell for [BigStatGrid]: [label] caption on top, [value] leads
/// (large, bold, accented) since it's the number actually used at the
/// table, and an optional [secondary] value (e.g. an ability's raw
/// score under its modifier) in smaller text underneath.
class BigStatCell {
  const BigStatCell(this.value, this.label, {this.secondary});
  final String value;
  final String label;
  final String? secondary;
}

/// A bolder variant of [StatGrid] for stats prominent enough to lead a
/// tab (Ability Scores, the Combat tab's HP/AC/Init/Spd/Prof row) - same
/// ruled-cell look, but with a larger, accented lead value and room for
/// an optional smaller secondary value underneath it.
class BigStatGrid extends StatelessWidget {
  const BigStatGrid({super.key, required this.cells});

  final List<BigStatCell> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.ink, width: 2),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    right: i == cells.length - 1
                        ? BorderSide.none
                        : const BorderSide(color: AppColors.rule),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                child: Column(
                  children: [
                    Text(
                      cells[i].label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 13,
                        letterSpacing: 0.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.inkDim,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // A long value (HP climbs to "100/100" at higher
                    // levels) would otherwise wrap to a second line in a
                    // cell this narrow - shrink it to fit instead.
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        cells[i].value,
                        maxLines: 1,
                        style: AppTheme.dataStyle(
                          fontSize: 24,
                          weight: FontWeight.w800,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                    if (cells[i].secondary != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        cells[i].secondary!,
                        style: AppTheme.dataStyle(
                          fontSize: 15,
                          color: AppColors.inkDim,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.cells});

  final List<StatCell> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.ink, width: 2),
      ),
      child: Row(
        children: [
          for (var i = 0; i < cells.length; i++)
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  border: Border(
                    right: i == cells.length - 1
                        ? BorderSide.none
                        : const BorderSide(color: AppColors.rule),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                child: Column(
                  children: [
                    Text(
                      cells[i].value,
                      style: AppTheme.dataStyle(
                        fontSize: 15,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      cells[i].label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.5,
                        color: AppColors.inkDim,
                      ),
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
