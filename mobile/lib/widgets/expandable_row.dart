import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Coordinates a set of sibling [ExpandableRow]s so opening one collapses
/// whichever other one in the group was open - one instance per group,
/// created by [ExpandableGroup] (not constructed directly by callers,
/// since a plain local variable wouldn't survive a rebuild - see its doc
/// comment).
class ExpandableGroupController extends ChangeNotifier {
  Object? _openId;
  bool isOpen(Object id) => _openId == id;

  void toggle(Object id) {
    _openId = _openId == id ? null : id;
    notifyListeners();
  }
}

/// Wraps a set of [ExpandableRow]s that should behave as an accordion (at
/// most one open at a time) - one per section (Resources, Weapons, Mounts,
/// ...), not shared across sections. A [StatefulWidget] rather than a
/// plain controller handed out by the caller's build method, so the
/// controller survives the section's parent (typically a stateless tab
/// widget) rebuilding for unrelated reasons - the same way ExpandableRow's
/// own open/closed state already does, via normal element reuse.
class ExpandableGroup extends StatefulWidget {
  const ExpandableGroup({super.key, required this.builder});

  final Widget Function(BuildContext context, ExpandableGroupController group)
  builder;

  @override
  State<ExpandableGroup> createState() => _ExpandableGroupState();
}

class _ExpandableGroupState extends State<ExpandableGroup> {
  final _group = ExpandableGroupController();

  @override
  void dispose() {
    _group.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _group);
}

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
    this.group,
    this.groupId,
  }) : assert(
         group == null || groupId != null,
         'groupId is required when group is set',
       );

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

  /// When set (with [groupId]), this row's open/closed state is driven by
  /// [ExpandableGroupController] instead of its own local state, so
  /// opening it collapses whichever sibling in the same group was open -
  /// see [ExpandableGroup]. Left null, a row opens/closes independently,
  /// same as before groups existed.
  final ExpandableGroupController? group;

  /// This row's identity within [group] - e.g. the item's name or id.
  /// Must be stable across rebuilds (the same object, or an equal one)
  /// for the same item, and distinct from every other row in the group.
  final Object? groupId;

  @override
  State<ExpandableRow> createState() => _ExpandableRowState();
}

class _ExpandableRowState extends State<ExpandableRow> {
  bool _open = false;

  bool get _isOpen =>
      widget.group != null ? widget.group!.isOpen(widget.groupId!) : _open;

  void _toggle() {
    if (widget.group != null) {
      widget.group!.toggle(widget.groupId!);
    } else {
      setState(() => _open = !_open);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.group?.addListener(_onGroupChanged);
  }

  @override
  void didUpdateWidget(covariant ExpandableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group != widget.group) {
      oldWidget.group?.removeListener(_onGroupChanged);
      widget.group?.addListener(_onGroupChanged);
    }
  }

  @override
  void dispose() {
    widget.group?.removeListener(_onGroupChanged);
    super.dispose();
  }

  void _onGroupChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                // A two-line title+subtitle block aligns from the top,
                // like the chevron does - a single-line title centers
                // against taller leading/trailing content instead (e.g.
                // a resource's spend/restore buttons), rather than
                // hugging the top of the row.
                crossAxisAlignment: widget.subtitle != null
                    ? CrossAxisAlignment.start
                    : CrossAxisAlignment.center,
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
                                color: AppColors.ink,
                              ),
                            ),
                            if (widget.tag != null) ...[
                              const SizedBox(width: 6),
                              Text(
                                widget.tag!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.inkDim,
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
                      padding: EdgeInsets.only(
                        left: 8,
                        top: widget.subtitle != null ? 1 : 0,
                      ),
                      child: Text(
                        widget.value!,
                        style: AppTheme.dataStyle(
                          fontSize: 13,
                          color: AppColors.inkDim,
                        ),
                      ),
                    ),
                  AnimatedRotation(
                    turns: _isOpen ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Padding(
                      padding: EdgeInsets.only(
                        left: 6,
                        top: widget.subtitle != null ? 2 : 0,
                      ),
                      child: Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: _isOpen ? AppColors.accent : AppColors.inkDim,
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
                  color: AppColors.inkDim,
                  height: 1.4,
                ),
                child: widget.body,
              ),
            ),
            crossFadeState: _isOpen
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
