# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

D&D Sheet: a Flutter character sheet app for D&D 5th Edition (2024 rules), for Android and Windows. Built entirely on the free SRD 5.2.1 (CC BY 4.0) — no Player's Handbook content is bundled. Offline-only: characters and homebrew live on-device in Hive, no account or server.

All real app code is under `mobile/` (the Flutter project). `srd-data-pull/` is a one-off Node tool that generates `mobile/assets/srd/*.json` from a markdown copy of the SRD; it's not part of the app's runtime. `app/` is a gitignored, untracked, abandoned Quasar/Vue scaffold — ignore it entirely, it's not part of this project.

## Commands

All from `mobile/`:

```sh
flutter pub get
flutter analyze                 # lint/static analysis — CI runs this, must be clean
flutter test                    # all tests
flutter test test/rules_test.dart              # single file
flutter test test/rules_test.dart -n "some test name"   # single test by name

# Android: only the arm64-v8a APK is built (nearly all current devices)
flutter build apk --release --split-per-abi --target-platform android-arm64
# -> build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# Windows
flutter build windows --release
# -> build/windows/x64/runner/Release/  (the whole folder is the app)
```

Requires Flutter 3.47+ stable. If the Android SDK/Java aren't found, set `ANDROID_HOME` and `JAVA_HOME` (Android Studio's bundled JDK is in its `jbr` folder).

Regenerating SRD data (only needed when the SRD markdown source changes), from `srd-data-pull/`:
```sh
node scripts/parse-spells.js    # or whichever parse-*.js matches what changed
# then copy the updated file(s) from data/ to ../mobile/assets/srd/
```
`mobile/assets/srd/sheet-text.json` is hand-written (short feature summaries for the PDF), not generated.

CI (`.github/workflows/build.yml`) runs `flutter analyze` + `flutter test` on every push/PR to `main`, then builds Android arm64 and Windows. Pushing a tag `vX.Y.Z` (must match `mobile/pubspec.yaml`'s `version:`) also cuts a GitHub Release. The version number lives in exactly one place: `version:` in `mobile/pubspec.yaml`.

## Architecture

Layering (`mobile/lib/`): `models/` → `domain/` → `data/` → `screens/`/`widgets/`. Lower layers don't depend on upper ones.

- **`models/`** — plain data classes with `toJson`/`fromJson`, no logic beyond small helpers. `character.dart` is the character schema (a trimmed port of an earlier Quasar/TypeScript app's model — extend it only for fields something actually reads). `effect.dart` defines `Effect`, the data-driven unit for a feat/item/feature's numeric contribution (target + formula string + optional condition) — deliberately narrow: only flat modifiers to the character's own rolls/DCs/incoming damage, never advantage/disadvantage or dice rolls, which stay as plain description text instead. `homebrew.dart` is the homebrew entry schema.

- **`domain/rules.dart`** (+ `rules_character.dart`, `rules_granted_spells.dart`, `rules_options.dart`, joined via `part`/`part of`) — pure functions ported from the original Quasar app's `domain/rules.ts`. This is where all game math and character mutation logic lives (modifiers, AC, HP, leveling, resources, rests, spellcasting, the `Effect`-formula evaluator). Kept as free functions over a `Character`, not methods on it, so the model stays a plain data holder and rules stay trivially testable. `character_sheet_pdf.dart` fills the official PDF sheet from a `Character`.
  - A small hardcoded table (`_builtinFeatEffects`) supplies mechanics for real SRD feats whose numeric effect isn't derivable from `feats.json`'s prose (e.g. Alert, Archery, Defense). This table must **never** encode a non-SRD feat's mechanics — see its doc comment for the licensing reasoning. `liveFeatureEffects` resolves a granted feature's effects live (not cached at grant time) and prefers a same-named **homebrew** entry over the built-in table, so a player's house rule or transcription of real (non-SRD) content always wins, deliberately and visibly (the homebrew editor warns on name collisions).
  - History log: every mutating function appends to `Character.history` via `logHistory`, the single place anything writes to it, so all writers (ability edits, feat grants, level changes) produce entries in one consistent shape.

- **`data/`** — persistence and catalogs.
  - `srd_catalog.dart` loads and parses all of `assets/srd/*.json` (classes, species, backgrounds, feats, spells, equipment, reference tables) into typed `Srd*` classes at startup.
  - `homebrew_catalog.dart` turns a `HomebrewEntry`'s free-form `data` map into the same typed shapes the SRD catalog uses (e.g. `WeaponStats.fromData`), so homebrew species/classes/spells/items work everywhere an SRD one does. `homebrew_repository.dart` persists homebrew entries (Hive) and, on change, homebrew species/classes/backgrounds/subclasses are re-registered into the live catalog (wired in `main.dart`).
  - `character_repository.dart` — Hive-backed character storage, one box, each character as a JSON string keyed by id (`Character.toJson`/`fromJson`; no Hive codegen/TypeAdapters, deliberately, to skip build_runner for a schema still in flux). Uses `getApplicationSupportDirectory`, not the Hive default docs directory — on Windows that default is often OneDrive-redirected and OneDrive's sync lock collides with Hive's file lock.
  - `export_bundle.dart` defines the character-export and homebrew-export JSON shapes (versioned `format`/`version` fields) used for sharing/backup and for `assets/official/content.json` (see below).
  - `local_official_content.dart` — at startup, merges a gitignored, machine-local `assets/official/content.json` into the homebrew catalog if present; a no-op on any shared/public build. This is the sanctioned way to add real, non-SRD 2024 content (e.g. Great Weapon Master) you personally own: transcribe it as homebrew with `source: official` in the app, export it, drop it at that path. See `mobile/assets/official/README.md` for the full mechanism — this is a licensing boundary, not a preference, and matters when touching anything related to feat/content licensing.
  - `starting_equipment.dart`, `character_factory.dart`, `sample_data.dart`, `sheet_text_repository.dart`, `official_sheet_cache.dart` (caches the downloaded official 2024 PDF sheet template) round out this layer.

- **`screens/`** and **`widgets/`** — the UI (Flutter Material, `theme/ledger_theme.dart`). Desktop-width layouts move the sheet's tabs and Reference categories into a left-side panel.

## Content & licensing constraints (important when editing rules/data)

- Only SRD 5.2.1 content may be bundled/shipped in `assets/srd/` or hardcoded into `domain/rules.dart` tables like `_builtinFeatEffects`. Never add real mechanics or text for content that's only in the Player's Handbook/DMG/other non-free books.
- Non-SRD ("Official") content a user owns is entered by them as homebrew and lives only in their local, gitignored data (`assets/official/content.json`) — never add such content to tracked files.
- The official 2024 character sheet PDF itself isn't redistributed in the repo; it's downloaded from D&D Beyond on first export and cached on-device (`official_sheet_cache.dart`).

## Tests

`mobile/test/` mirrors the `lib/` structure roughly 1:1 (`rules_test.dart`, `character_factory_test.dart`, `character_options_test.dart`, `character_repository_test.dart`, `character_sheet_pdf_test.dart`, `export_bundle_test.dart`, `homebrew_catalog_test.dart`, `homebrew_repository_test.dart`, `srd_catalog_test.dart`, `markdown_text_test.dart`, `widget_test.dart`). `CharacterRepository`'s `Box` is nullable rather than `late` specifically so widget tests can seed `characters` directly and skip `init()` (Hive's plugin channel isn't available in the test environment).
