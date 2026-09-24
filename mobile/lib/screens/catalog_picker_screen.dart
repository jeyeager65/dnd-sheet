import 'package:flutter/material.dart';

import '../data/homebrew_repository.dart';
import '../data/srd_catalog.dart';
import '../models/homebrew.dart';
import '../theme/ledger_theme.dart';

/// A searchable full-screen picker over a list of SRD catalog entries -
/// used for Species/Background/Class in New Character, and every "add X"
/// picker on the sheet. Returns the selected [SrdRefItem] via
/// Navigator.pop, or null if the user backs out. Generic on purpose: one
/// picker screen serves every catalog list rather than a bespoke dropdown
/// per field.
///
/// Pass [homebrewKind] to also let the player type a name that isn't in
/// the SRD and save it as reusable homebrew content (a reflavored spell, a
/// DM's custom item, ...) - it's merged into the list (tagged "Homebrew")
/// and offered again next time. Omit it for a picker where that wouldn't
/// make sense (nothing homebrew-able, e.g. a language).
class CatalogPickerScreen extends StatefulWidget {
  const CatalogPickerScreen({
    super.key,
    required this.title,
    required this.options,
    this.homebrewKind,
    this.homebrewFilter,
    this.onHomebrewCreated,
    this.broaderOptions,
    this.broaderLabel,
    this.unavailableReason,
  });

  final String title;
  final List<SrdRefItem> options;
  final String? homebrewKind;

  /// Restricts which existing homebrew entries of [homebrewKind] are
  /// offered, on top of the kind match - e.g. only feats tagged with a
  /// particular category. An entry this rejects simply doesn't appear,
  /// same as if it didn't exist for this picker. Null means no
  /// restriction beyond kind (the default, and what every non-feat
  /// picker still gets).
  final bool Function(HomebrewEntry entry)? homebrewFilter;

  /// Called right after a brand-new homebrew entry is quick-created from
  /// this picker's own search box, so the caller can stamp on whatever
  /// extra classification this specific picker cares about that
  /// homebrewRepo.create's bare kind+name doesn't capture - e.g. a
  /// homebrew feat quick-added while resolving a "Choose a Fighting
  /// Style" Pending Choice is tagged with that category immediately,
  /// instead of landing uncategorized and then failing [homebrewFilter]
  /// the next time this same picker opens.
  final void Function(HomebrewEntry entry)? onHomebrewCreated;

  /// A wider list the player can switch to with a toggle above the
  /// results, labeled [broaderLabel] - e.g. Add Spell defaults to the
  /// character's own class spell list at levels they can cast, and this
  /// holds every SRD spell (for Magic Initiate, a multiclass dip, a DM's
  /// allowance). Null means [options] is the whole list, no toggle.
  final List<SrdRefItem>? broaderOptions;
  final String? broaderLabel;

  /// Why an option can't be picked (an unmet feat prerequisite), or null
  /// if it can. Unavailable options are listed last, greyed out, with the
  /// reason under the name.
  final String? Function(SrdRefItem item)? unavailableReason;

  @override
  State<CatalogPickerScreen> createState() => _CatalogPickerScreenState();
}

class _CatalogPickerScreenState extends State<CatalogPickerScreen> {
  final _searchController = TextEditingController();
  String _query = '';
  bool _broad = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _addHomebrew() {
    final name = _query.trim();
    if (name.isEmpty || widget.homebrewKind == null) return;
    final entry = homebrewRepo.create(widget.homebrewKind!, name);
    widget.onHomebrewCreated?.call(entry);
    Navigator.of(context)
        .pop(SrdRefItem(key: entry.id, name: entry.name, isHomebrew: true));
  }

  @override
  Widget build(BuildContext context) {
    final allOptions = [
      for (final o in (_broad ? widget.broaderOptions! : widget.options))
        if (!(widget.homebrewKind != null && o.key.startsWith('homebrew_'))) o,
      if (widget.homebrewKind != null)
        for (final entry in homebrewRepo.byKind(widget.homebrewKind!))
          if (widget.homebrewFilter == null || widget.homebrewFilter!(entry))
            SrdRefItem(key: entry.id, name: entry.name, isHomebrew: true),
    ];
    final matching = _query.isEmpty
        ? allOptions
        : allOptions
              .where((o) => o.name.toLowerCase().contains(_query.toLowerCase()))
              .toList();
    // Ones that can't be picked go last, keeping their order otherwise.
    final unavailable = widget.unavailableReason;
    final filtered = unavailable == null
        ? matching
        : [
            ...matching.where((o) => unavailable(o) == null),
            ...matching.where((o) => unavailable(o) != null),
          ];
    final exactMatch = allOptions.any(
      (o) => o.name.toLowerCase() == _query.trim().toLowerCase(),
    );
    final offerHomebrew =
        widget.homebrewKind != null && _query.trim().isNotEmpty && !exactMatch;

    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
              child: TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                style: const TextStyle(color: LedgerColors.ink),
                decoration: InputDecoration(
                  hintText: 'Search…',
                  hintStyle: const TextStyle(color: LedgerColors.inkDim),
                  prefixIcon: const Icon(
                    Icons.search,
                    color: LedgerColors.inkDim,
                    size: 20,
                  ),
                  filled: true,
                  fillColor: LedgerColors.paper2,
                  border: const UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: LedgerColors.inkDim,
                      width: 2,
                    ),
                  ),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: LedgerColors.rule),
                  ),
                  focusedBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(
                      color: LedgerColors.accent,
                      width: 2,
                    ),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
            if (widget.broaderOptions != null)
              SwitchListTile(
                dense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 18),
                title: Text(widget.broaderLabel ?? 'Show everything'),
                value: _broad,
                onChanged: (v) => setState(() => _broad = v),
              ),
            if (offerHomebrew)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 6),
                child: OutlinedButton.icon(
                  onPressed: _addHomebrew,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text('Add "${_query.trim()}" as homebrew'),
                ),
              ),
            Expanded(
              child: filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(18),
                      child: Text(
                        'Nothing matches that search.',
                        style: TextStyle(color: LedgerColors.inkDim),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 18),
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final item = filtered[i];
                        final reason = widget.unavailableReason?.call(item);
                        final caption = [
                          if (item.isHomebrew) 'Homebrew',
                          if (!item.isHomebrew && item.detail != null)
                            item.detail!,
                          ?reason,
                        ].join(' Â· ');
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          enabled: reason == null,
                          title: Text(
                            item.name,
                            style: TextStyle(
                              color: reason == null
                                  ? LedgerColors.ink
                                  : LedgerColors.inkDim,
                            ),
                          ),
                          subtitle: caption.isEmpty
                              ? null
                              : Text(
                                  caption,
                                  style: const TextStyle(
                                    color: LedgerColors.inkDim,
                                    fontSize: 11,
                                  ),
                                ),
                          onTap: () => Navigator.of(context).pop(item),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
