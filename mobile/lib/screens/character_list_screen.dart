import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../data/character_repository.dart';
import '../models/character.dart';
import '../theme/ledger_theme.dart';
import 'about.dart';
import 'character_form_screen.dart';
import 'character_sheet_screen.dart';
import 'reference_screen.dart';
import 'share_json.dart';

/// A safe-ish file name from free text - strips anything that isn't a
/// letter, digit, space, or dash, and collapses spaces to underscores.
String _sanitizeFileName(String name) {
  final cleaned = name
      .replaceAll(RegExp(r'[^A-Za-z0-9 \-]'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_');
  return cleaned.isEmpty ? 'character' : cleaned;
}

/// Opens a file picker for a previously-exported .json file, imports
/// whatever characters it contains, and reports the result via a
/// SnackBar - a parse failure (not valid JSON, or not shaped like an
/// export) is reported rather than crashing, since the file could be
/// anything the user happened to pick.
Future<void> _importCharacters(BuildContext context) async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: ['json'],
  );
  if (picked == null) return;
  if (!context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  try {
    final raw = utf8.decode(await picked.readAsBytes());
    final imported = await charactersRepo.importFromJson(raw);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          imported.length == 1
              ? 'Imported ${imported.first.name}.'
              : 'Imported ${imported.length} characters.',
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(content: Text("Couldn't import that file: $e")),
    );
  }
}

class CharacterListScreen extends StatelessWidget {
  const CharacterListScreen({super.key});

  Future<void> _confirmDelete(BuildContext context, Character c) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${c.name}?'),
        content: const Text(
          'This permanently deletes the character. It cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: LedgerColors.danger),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await charactersRepo.delete(c.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Characters'),
        actions: [
          IconButton(
            tooltip: 'Import',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: () => _importCharacters(context),
          ),
          IconButton(
            tooltip: 'Export All (Backup)',
            icon: const Icon(Icons.file_download_outlined),
            onPressed: charactersRepo.characters.isEmpty
                ? null
                : () => shareJson(
                    context,
                    charactersRepo.exportAll(),
                    'dnd_sheet_backup_${DateTime.now().toIso8601String().split('T').first}.json',
                  ),
          ),
          IconButton(
            tooltip: 'Reference',
            icon: const Icon(Icons.menu_book_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const ReferenceScreen())),
          ),
          IconButton(
            tooltip: 'About',
            icon: const Icon(Icons.info_outline),
            onPressed: () => showAppAbout(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: charactersRepo,
          builder: (context, _) {
            final families = charactersRepo.listFamilies();
            return ListView(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
              children: [
                if (families.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'No characters yet. Add one below.',
                      style: TextStyle(color: LedgerColors.inkDim),
                    ),
                  ),
                for (final family in families)
                  _CharacterFamilyCard(
                    key: ValueKey(family.first.familyId),
                    family: family,
                    onDelete: (c) => _confirmDelete(context, c),
                  ),
                const SizedBox(height: 20),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CharacterFormScreen(
                        mode: CharacterFormMode.create,
                      ),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                  ),
                  child: const Text('+ New Character'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One character family - the current snapshot as the primary row, any
/// older levels (automatic backups from Level Up - see
/// character_sheet_screen.dart's Level Up action) listed underneath, and
/// a Duplicate action. A family with just one snapshot (the common case,
/// before any level-up has happened) renders identically to a flat
/// character row. Older levels are collapsed under a "Previous levels"
/// toggle, newest first.
class _CharacterFamilyCard extends StatefulWidget {
  const _CharacterFamilyCard({
    super.key,
    required this.family,
    required this.onDelete,
  });

  final List<Character> family;
  final ValueChanged<Character> onDelete;

  @override
  State<_CharacterFamilyCard> createState() => _CharacterFamilyCardState();
}

class _CharacterFamilyCardState extends State<_CharacterFamilyCard> {
  bool _expanded = false;

  List<Character> get family => widget.family;
  ValueChanged<Character> get onDelete => widget.onDelete;

  Character get _current => family.where((c) => c.isCurrent).isEmpty
      ? family.first
      : family.where((c) => c.isCurrent).first;

  Future<void> _duplicate(BuildContext context) async {
    final controller = TextEditingController(text: '${_current.name} (copy)');
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Duplicate as New Character'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'New character name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Duplicate'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await charactersRepo.duplicateAsNewCharacter(_current.id, name);
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    // Newest level first.
    final others = family.where((c) => c.id != current.id).toList()
      ..sort((a, b) => b.level.compareTo(a.level));

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: LedgerColors.rule)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CharacterRow(
            name: current.name,
            meta: 'Lv.${current.level} ${current.classLabel}',
            bordered: false,
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CharacterSheetScreen(characterId: current.id),
              ),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    size: 20,
                    color: LedgerColors.inkDim,
                  ),
                  onSelected: (value) {
                    if (value == 'duplicate') _duplicate(context);
                    if (value == 'export') {
                      shareJson(
                        context,
                        charactersRepo.exportFamily(current.familyId),
                        '${_sanitizeFileName(current.name)}.json',
                      );
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'duplicate',
                      child: Text('Duplicate as New Character'),
                    ),
                    PopupMenuItem(value: 'export', child: Text('Export')),
                  ],
                ),
                IconButton(
                  onPressed: () => onDelete(current),
                  icon: const Icon(Icons.delete_outline, size: 20),
                  color: LedgerColors.inkDim,
                ),
              ],
            ),
          ),
          if (others.isNotEmpty)
            InkWell(
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.only(left: 12, bottom: 8),
                child: Row(
                  children: [
                    Icon(
                      _expanded ? Icons.expand_more : Icons.chevron_right,
                      size: 18,
                      color: LedgerColors.inkDim,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Previous levels (${others.length})',
                      style: const TextStyle(
                        fontSize: 13,
                        color: LedgerColors.inkDim,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (others.isNotEmpty && _expanded)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final snapshot in others)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => CharacterSheetScreen(
                                    characterId: snapshot.id,
                                  ),
                                ),
                              ),
                              child: Text(
                                snapshot.snapshotStatusLabel,
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: LedgerColors.inkDim,
                                ),
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                charactersRepo.promoteToCurrent(snapshot.id),
                            child: const Text(
                              'Promote',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          IconButton(
                            onPressed: () => onDelete(snapshot),
                            icon: const Icon(Icons.delete_outline, size: 18),
                            color: LedgerColors.inkDim,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 26,
                              minHeight: 26,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CharacterRow extends StatelessWidget {
  const _CharacterRow({
    required this.name,
    required this.meta,
    this.onTap,
    this.trailing,
    this.bordered = true,
  });

  final String name;
  final String meta;
  final VoidCallback? onTap;
  final Widget? trailing;
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: bordered
            ? const BoxDecoration(
                border: Border(bottom: BorderSide(color: LedgerColors.rule)),
              )
            : null,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: LedgerTheme.nameStyle(fontSize: 17)
                        .copyWith(color: LedgerColors.ink),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    meta,
                    style: const TextStyle(
                      fontSize: 13,
                      color: LedgerColors.inkDim,
                    ),
                  ),
                ],
              ),
            ),
            trailing ?? const SizedBox.shrink(),
          ],
        ),
      ),
    );
  }
}
