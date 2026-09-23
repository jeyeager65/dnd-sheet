import 'package:flutter/material.dart';

import '../theme/ledger_theme.dart';

/// A ledger entry that collapses to one line and expands on tap - the same
/// pattern used for weapons, resources, features, and feats on the Combat
/// and Features tabs. Kept generic (header/value/body slots) rather than
/// one widget per content type, since the collapse/expand mechanics and
/// chevron rotation are identical everywhere it's used.
class ExpandableRow extends StatefulWidget {
  const ExpandableRow({
    super.key,
    required this.title,
    this.tag,
    this.value,
    this.trailing,
    this.subtitle,
    required this.body,
    this.leading,
  });

  final String title;
  final String? tag;
  final String? value;

  /// Overrides [value] with arbitrary content (e.g. spend/restore icon
  /// buttons for a resource) - kept separate from the row's own tap-to-
  /// expand gesture since it holds its own tappable controls.
  final Widget? trailing;

  /// A second line under the title, in the header itself (not the
  /// collapsible [body]) - for a row whose title alone doesn't leave room
  /// for a useful one-line summary (e.g. a weapon's "+8 / 2d6+8 slashing"
  /// next to a long name like "Sword of the Failed Dragon Slayer", which
  /// otherwise crowds out or gets crowded out by [trailing]).
  final Widget? subtitle;
  final Widget body;
  final Widget? leading;

  @override
  State<ExpandableRow> createState() => _ExpandableRowState();
}

class _ExpandableRowState extends State<ExpandableRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: LedgerColors.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (widget.leading != null) ...[
                    widget.leading!,
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              widget.title,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                color: LedgerColors.ink,
                              ),
                            ),
                            if (widget.tag != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                widget.tag!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: LedgerColors.inkDim,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (widget.subtitle != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: widget.subtitle!,
                          ),
                      ],
                    ),
                  ),
                  if (widget.trailing != null)
                    widget.trailing!
                  else if (widget.value != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 1),
                      child: Text(
                        widget.value!,
                        style: LedgerTheme.dataStyle(
                          fontSize: 13,
                          color: LedgerColors.inkDim,
                        ),
                      ),
                    ),
                  AnimatedRotation(
                    turns: _open ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6, top: 2),
                      child: Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: _open
                            ? LedgerColors.accent
                            : LedgerColors.inkDim,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity, height: 0),
            secondChild: Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DefaultTextStyle(
                style: const TextStyle(
                  fontSize: 13,
                  color: LedgerColors.inkDim,
                  height: 1.4,
                ),
                child: widget.body,
              ),
            ),
            crossFadeState: _open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 150),
            sizeCurve: Curves.easeInOut,
          ),
        ],
      ),
    );
  }
}
