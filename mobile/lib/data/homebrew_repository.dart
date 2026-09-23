import 'dart:convert';

import 'package:hive_flutter/hive_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/homebrew.dart';

const _uuid = Uuid();

/// Local persistence for homebrew content, one Hive box holding every
/// entry (any kind) as a JSON string keyed by id - mirrors
/// CharacterRepository's plain-JSON-no-codegen approach. A single flat
/// list is filtered by kind at read time rather than one box per kind,
/// since the whole catalog is small enough that this never needs an index.
class HomebrewRepository {
  static const _boxName = 'homebrew';
  // Nullable rather than `late`: widget tests never call init() (same
  // reasoning as CharacterRepository) - create() still works there, it
  // just skips persisting.
  Box<String>? _box;
  final List<HomebrewEntry> entries = [];

  /// Called after any change to [entries] - main.dart points it at
  /// homebrew_catalog.dart's registerHomebrewInCatalog, so a homebrew
  /// species/class/background/subclass shows up in the catalog (and every
  /// picker/rule reading it) the moment it's saved.
  void Function()? afterChange;

  Future<void> init() async {
    final box = await Hive.openBox<String>(_boxName);
    _box = box;
    entries.clear();
    for (final key in box.keys) {
      final raw = box.get(key);
      if (raw == null) continue;
      entries.add(
        HomebrewEntry.fromJson(jsonDecode(raw) as Map<String, dynamic>),
      );
    }
  }

  List<HomebrewEntry> byKind(String kind) =>
      entries.where((e) => e.kind == kind).toList();

  /// Creates and persists a new homebrew entry, reusing an existing one of
  /// the same kind+name (case-insensitive) instead of creating a
  /// duplicate if the player types a name that's already there.
  HomebrewEntry create(String kind, String name) {
    final existing = entries.where(
      (e) => e.kind == kind && e.name.toLowerCase() == name.toLowerCase(),
    );
    if (existing.isNotEmpty) return existing.first;

    final entry = HomebrewEntry(
      id: 'homebrew_${_uuid.v4()}',
      kind: kind,
      name: name,
    );
    entries.add(entry);
    _box?.put(entry.id, jsonEncode(entry.toJson()));
    afterChange?.call();
    return entry;
  }

  /// Persists edits to an existing entry (desc/source/effects) - the "My
  /// Homebrew" editor's save action. `name` is never changed this way
  /// (see HomebrewEntry's doc comment) - a no-op if [updated.id] isn't
  /// found.
  void update(HomebrewEntry updated) {
    final idx = entries.indexWhere((e) => e.id == updated.id);
    if (idx == -1) return;
    entries[idx] = updated;
    _box?.put(updated.id, jsonEncode(updated.toJson()));
    afterChange?.call();
  }

  /// Permanently removes an entry. Irreversible - callers should confirm
  /// with the player first, and (since effects/text are matched by name,
  /// not id) check CharacterRepository.charactersReferencing first so a
  /// delete that silently stops a character's item/feat from working is
  /// never a surprise.
  void delete(String id) {
    entries.removeWhere((e) => e.id == id);
    _box?.delete(id);
    afterChange?.call();
  }

  /// The whole catalog as pretty-printed JSON - the counterpart to
  /// importEntry, and to loadLocalOfficialContent's file shape
  /// (data/local_official_content.dart). Meant for saving your own
  /// homebrew/official content outside the app - e.g. into a gitignored
  /// local asset file (see assets/official/README.md) so your own future
  /// builds restore it automatically, without ever bundling that content
  /// in the app's shared source.
  String exportAll() =>
      const JsonEncoder.withIndent('  ')
          .convert(entries.map((e) => e.toJson()).toList());

  /// Merges an imported homebrew entry into the local catalog - reuses an
  /// existing entry of the same kind+name (case-insensitive), same dedup
  /// rule as create(). Never overwrites a local entry with the imported
  /// version, so importing a character never silently changes homebrew
  /// content already tuned locally - only fills in what's missing.
  void importEntry(HomebrewEntry incoming) {
    final exists = entries.any(
      (e) =>
          e.kind == incoming.kind &&
          e.name.toLowerCase() == incoming.name.toLowerCase(),
    );
    if (exists) return;
    entries.add(incoming);
    _box?.put(incoming.id, jsonEncode(incoming.toJson()));
    afterChange?.call();
  }
}

/// A single shared instance - simple app, simple DI, same as charactersRepo.
final homebrewRepo = HomebrewRepository();
