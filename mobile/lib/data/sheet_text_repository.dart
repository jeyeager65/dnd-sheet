import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// The player's own rewrites of the short text the exported PDF sheet
/// shows for a feature, trait, or feat - replacing this app's bundled
/// default (assets/srd/sheet-text.json) or a homebrew feat's own sheet
/// text. Keyed by rules.sheetTextKey ("scope|name", e.g.
/// "srd-2024_wizard-class|Arcane Recovery"), so an edit applies to every
/// character with that feature, the same way a homebrew feat's text does.
/// Stored locally only (Hive), like homebrew content.
class SheetTextRepository extends ChangeNotifier {
  static const _boxName = 'sheetText';
  // Nullable rather than `late`: widget tests never call init() (same
  // reasoning as HomebrewRepository) - edits still work in memory there.
  Box<String>? _box;
  final Map<String, String> overrides = {};

  Future<void> init() async {
    final box = await Hive.openBox<String>(_boxName);
    _box = box;
    overrides.clear();
    for (final key in box.keys) {
      final value = box.get(key);
      if (value != null) overrides[key as String] = value;
    }
  }

  String? operator [](String key) => overrides[key];

  /// Saves [text] as the sheet text for [key]; an empty [text] resets it
  /// back to the default instead.
  void set(String key, String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      reset(key);
      return;
    }
    overrides[key] = trimmed;
    _box?.put(key, trimmed);
    notifyListeners();
  }

  void reset(String key) {
    overrides.remove(key);
    _box?.delete(key);
    notifyListeners();
  }
}

final sheetTextRepo = SheetTextRepository();
