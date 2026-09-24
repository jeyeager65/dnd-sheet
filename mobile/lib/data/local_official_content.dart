import 'package:flutter/services.dart' show rootBundle;

import '../models/homebrew.dart';
import 'export_bundle.dart';
import 'homebrew_repository.dart';

/// Parses assets/official/content.json - a My Homebrew export file (see
/// export_bundle.dart's buildHomebrewBundle). Pure/synchronous (no asset
/// I/O) so it's testable without a Flutter binding. Anything else yields
/// an empty list rather than throwing - a broken local file should never
/// crash startup.
List<HomebrewEntry> parseLocalOfficialContent(String raw) {
  try {
    return parseHomebrewBundle(raw);
  } catch (_) {
    return const [];
  }
}

/// Merges any locally-bundled "official" (real 2024 content not in the
/// free SRD) into homebrewRepo on startup, via importEntry's usual
/// dedup-safe merge - never overwrites an entry already tuned locally.
///
/// This app's shared/public source never bundles non-SRD content (see
/// rules.dart's _builtinFeatEffects doc comment for the licensing
/// reasoning) - that's exactly why "My Homebrew" has a `source: 'official'`
/// category at all: the player transcribes content they already legally
/// own themselves, into their own local data.
///
/// assets/official/content.json is gitignored (see assets/official/
/// README.md) and entirely optional: on a fresh clone the file doesn't
/// exist and this silently does nothing, so a shared/public build never
/// carries anyone's transcribed content. It only exists on a machine
/// where its owner has put their own file there, so *their own* future
/// builds restore it automatically instead of re-typing it into "My
/// Homebrew" after every reinstall - export the current catalog from "My
/// Homebrew"'s Export button, save it as assets/official/content.json,
/// rebuild.
Future<void> loadLocalOfficialContent() async {
  String raw;
  try {
    raw = await rootBundle.loadString('assets/official/content.json');
  } catch (_) {
    return; // not present in this build - the common/shared case.
  }
  for (final entry in parseLocalOfficialContent(raw)) {
    homebrewRepo.importEntry(entry);
  }
}
