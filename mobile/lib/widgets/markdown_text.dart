import 'package:flutter/material.dart';

import '../theme/ledger_theme.dart';

/// Renders the SRD's lightweight Markdown subset as styled text -
/// Flutter's plain Text widget shows the raw asterisks/underscores/
/// hashes literally, which is the bug this fixes. Deliberately
/// hand-rolled rather than pulling in a full Markdown package: a scan of
/// every bundled SRD file found a small, fixed set of constructs in use -
/// **bold**, _italic_, **_bold italic_** (Monk's "**_Flurry of Blows._**"
/// and similar named sub-effects), "- " bullet lists, "##"/"###" headers
/// (e.g. a spell's "At Higher Levels" callout, "> " blockquote callout/
/// sidebar boxes (e.g. a Paladin's "Breaking Your Oath"), a class's
/// spell-list header), and a handful of simple `<table>` blocks (no
/// colspan/rowspan/nested tags - verified against every one in
/// classes.json and magic-items.json) for things like a class's spell
/// list or a random item-effect roll table - so a full CommonMark+HTML
/// parser would be a lot of unused surface for one well-scoped job.
class MarkdownText extends StatelessWidget {
  const MarkdownText(this.data, {super.key, this.style});
  final String data;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final baseStyle = style ?? DefaultTextStyle.of(context).style;
    final blocks = <Widget>[];
    for (final piece in _splitOutTables(data)) {
      if (piece.isTable) {
        blocks.add(_buildTable(piece.text, baseStyle));
      } else {
        for (final block in piece.text.split('\n\n')) {
          blocks.addAll(_buildBlock(block, baseStyle));
        }
      }
    }
    // Rules text can be selected and copied - drag with a mouse on the
    // desktop build, long-press on a phone.
    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: blocks,
      ),
    );
  }

  /// Splits the raw text into alternating non-table/table pieces, so a
  /// `<table>...</table>` block (which can span many lines with no blank
  /// line inside it) is pulled out and rendered as an actual table
  /// instead of falling into the paragraph/bullet/header logic below,
  /// which only understands plain Markdown, not HTML.
  List<_TextPiece> _splitOutTables(String text) {
    final pattern = RegExp(r'<table[\s\S]*?</table>', caseSensitive: false);
    final pieces = <_TextPiece>[];
    var last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) {
        pieces.add(_TextPiece(text.substring(last, m.start), isTable: false));
      }
      pieces.add(_TextPiece(m.group(0)!, isTable: true));
      last = m.end;
    }
    if (last < text.length) {
      pieces.add(_TextPiece(text.substring(last), isTable: false));
    }
    return pieces;
  }

  List<Widget> _buildBlock(String block, TextStyle baseStyle) {
    final lines = block.split('\n').where((l) => l.trim().isNotEmpty).toList();
    if (lines.isEmpty) return const [];

    // A block of "> " lines is a blockquote/callout box (e.g. a Paladin's
    // "Breaking Your Oath" sidebar) - a bare ">" marker line never
    // actually splits the block at the top level (it isn't a true blank
    // line), so the whole callout, marker-only paragraph breaks
    // included, always arrives here as one block. Strip the "> " marker,
    // turn each now-empty marker line back into a real paragraph break,
    // and recurse so bold/italic/headers inside the callout still work,
    // wrapped in a left-rule to set it apart from the surrounding text.
    if (lines.every((l) => l.trimLeft().startsWith('>'))) {
      final dequoted = [
        for (final l in lines)
          l.trimLeft().substring(1).replaceFirst(RegExp(r'^ '), ''),
      ].join('\n');
      return [
        Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.only(left: 12),
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: LedgerColors.accent, width: 3),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final inner in dequoted.split('\n\n'))
                ..._buildBlock(inner, baseStyle),
            ],
          ),
        ),
      ];
    }

    // A block of "- " lines is a bullet list - shown as its own group,
    // never mixed line-by-line with paragraph text.
    if (lines.every((l) => l.trimLeft().startsWith('- '))) {
      return [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final line in lines)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('•  ', style: baseStyle),
                      Expanded(
                        child: Text.rich(
                          TextSpan(
                            style: baseStyle,
                            children: _inlineSpans(
                              line.trimLeft().substring(2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ];
    }

    final widgets = <Widget>[];
    for (final line in lines) {
      final headerMatch = RegExp(r'^(#{1,4})\s+(.*)').firstMatch(line);
      if (headerMatch != null) {
        final level = headerMatch.group(1)!.length;
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 4),
            child: Text(
              headerMatch.group(2)!,
              style: baseStyle.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: (baseStyle.fontSize ?? 13) + (level <= 2 ? 3 : 1),
              ),
            ),
          ),
        );
      } else {
        widgets.add(
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text.rich(
              TextSpan(style: baseStyle, children: _inlineSpans(line)),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  /// Splits one line into spans, applying bold+italic for `**_x_**`
  /// (checked first, since it fully contains the plain bold pattern and
  /// would otherwise be swallowed by it), bold for `**x**`, and italic
  /// for `_x_` - the only inline constructs the source data uses.
  List<InlineSpan> _inlineSpans(String text) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'\*\*_(.+?)_\*\*|\*\*(.+?)\*\*|_(.+?)_');
    var last = 0;
    for (final m in pattern.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      if (m.group(1) != null) {
        spans.add(
          TextSpan(
            text: m.group(1),
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontStyle: FontStyle.italic,
            ),
          ),
        );
      } else if (m.group(2) != null) {
        spans.add(
          TextSpan(
            text: m.group(2),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      } else {
        spans.add(
          TextSpan(
            text: m.group(3),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      }
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    if (spans.isEmpty) spans.add(TextSpan(text: text));
    return spans;
  }

  /// Renders a `<table>` block (a class's spell list, an item's roll
  /// table, ...) as an actual grid - horizontally scrollable, since some
  /// run wider than a phone screen. Cell text itself is plain (no bold/
  /// italic seen inside any `<td>`/`<th>` across the bundled data), just
  /// HTML-tag-stripped.
  Widget _buildTable(String html, TextStyle baseStyle) {
    final rowPattern = RegExp(r'<tr>([\s\S]*?)</tr>', caseSensitive: false);
    final cellPattern = RegExp(
      r'<t[hd][^>]*>([\s\S]*?)</t[hd]>',
      caseSensitive: false,
    );
    final rows = <(bool isHeader, List<String> cells)>[];
    for (final rowMatch in rowPattern.allMatches(html)) {
      final rowHtml = rowMatch.group(1)!;
      final cells = [
        for (final cellMatch in cellPattern.allMatches(rowHtml))
          _stripTags(cellMatch.group(1)!),
      ];
      if (cells.isEmpty) continue;
      rows.add((RegExp(r'<th', caseSensitive: false).hasMatch(rowHtml), cells));
    }
    if (rows.isEmpty) return const SizedBox.shrink();

    final columnCount = rows.first.$2.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Table(
          defaultColumnWidth: const IntrinsicColumnWidth(),
          border: TableBorder.symmetric(
            inside: BorderSide(
              color: (baseStyle.color ?? const Color(0xFF000000)).withValues(
                alpha: 0.25,
              ),
            ),
          ),
          children: [
            for (final (isHeader, cells) in rows)
              TableRow(
                children: [
                  for (var i = 0; i < columnCount; i++)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 4,
                        horizontal: 8,
                      ),
                      child: Text(
                        i < cells.length ? cells[i] : '',
                        style: isHeader
                            ? baseStyle.copyWith(fontWeight: FontWeight.bold)
                            : baseStyle,
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _stripTags(String html) =>
      html.replaceAll(RegExp(r'<[^>]+>'), '').trim();
}

class _TextPiece {
  const _TextPiece(this.text, {required this.isTable});
  final String text;
  final bool isTable;
}
