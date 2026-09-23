import 'package:flutter/material.dart';

import '../theme/ledger_theme.dart';

/// The boxed "totals" row from the ledger mockup - reused for ability
/// scores, combat stats, and currency alike, since a real ledger would
/// tally all three the same way: ruled cells with a value over a label.
class StatCell {
  const StatCell(this.value, this.label);
  final String value;
  final String label;
}

class StatGrid extends StatelessWidget {
  const StatGrid({super.key, required this.cells});

  final List<StatCell> cells;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: LedgerColors.ink, width: 2),
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
                        : const BorderSide(color: LedgerColors.rule),
                  ),
                ),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
                child: Column(
                  children: [
                    Text(
                      cells[i].value,
                      style: LedgerTheme.dataStyle(
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
                        color: LedgerColors.inkDim,
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
