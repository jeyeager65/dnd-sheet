# Building D&D Sheet

How the code is laid out, how to build it yourself, and how the CI
builds and releases work. For what the app does and how to install it,
see the [README](README.md).

## Repository layout

| Path | What it is |
|---|---|
| [`mobile/`](mobile) | The Flutter app for Android and Windows. |
| [`mobile/lib/domain/`](mobile/lib/domain) | Game rules: modifiers, leveling, resources, spellcasting, rests, PDF filling. |
| [`mobile/lib/data/`](mobile/lib/data) | The SRD catalog, storage (Hive), homebrew, import and export. |
| [`mobile/lib/screens/`](mobile/lib/screens) | The UI. |
| [`mobile/assets/srd/`](mobile/assets/srd) | SRD 5.2.1 data as JSON, plus `sheet-text.json` (short feature text for the PDF). |
| [`mobile/assets/official/`](mobile/assets/official) | An optional, gitignored place for your own non-SRD content. |
| [`srd-data-pull/`](srd-data-pull) | Scripts that turn the SRD markdown into the JSON in `mobile/assets/srd/`. |
| [`.github/workflows/`](.github/workflows) | CI: tests and Android and Windows builds. |
| [`docs/screenshots/`](docs/screenshots) | Screenshots used in the README. |

## Building locally

Requirements:
- [Flutter](https://docs.flutter.dev/get-started/install) 3.47 or later
  (stable channel).
- **Android:** the Android SDK and JDK 17 or later. Android Studio
  includes both.
- **Windows:** Visual Studio 2022 with the *Desktop development with
  C++* workload.

```sh
cd mobile
flutter pub get
flutter analyze
flutter test

# Android: only the arm64-v8a APK
flutter build apk --release --split-per-abi --target-platform android-arm64
# -> build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# Windows
flutter build windows --release
# -> build/windows/x64/runner/Release/  (the whole folder is the app)
```

If Flutter can't find the Android SDK or Java, set `ANDROID_HOME` to the
SDK folder and `JAVA_HOME` to a JDK. Android Studio's bundled JDK is in
its `jbr` folder.

**PDF export license.** PDF export uses
[Syncfusion Flutter PDF](https://pub.dev/packages/syncfusion_flutter_pdf),
which isn't open source. If you build or redistribute the app yourself,
you need your own
[Syncfusion license](https://www.syncfusion.com/products/communitylicense),
either the free Community License if you qualify or a commercial one.

### Android signing

Release APKs are signed with a permanent release key, so each new
version installs over the last. Android only accepts an update signed
with the same key as the installed app.

- **Where the key lives:** a keystore outside the repo, in
  `%USERPROFILE%\.dnd-sheet-signing\`. **Back that folder up.** If it's
  lost, no future APK can install over the existing app.
- **Setting it up (once):** run
  [`mobile/tool/setup_android_signing.ps1`](mobile/tool/setup_android_signing.ps1).
  It creates the keystore with a random password, or reuses the existing
  one. It then writes `mobile/android/key.properties` (gitignored) for
  local builds and stores the keystore and passwords as repository
  secrets for CI with the GitHub CLI. It's safe to rerun, for example
  on a new computer after restoring the folder.
- **How builds use it:**
  [`build.gradle.kts`](mobile/android/app/build.gradle.kts) signs release
  builds with the key in `key.properties`. CI writes that file from the
  `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD` secrets, and fails if
  they're missing. The exception is a pull request from a fork, which
  can't see secrets and gets a debug-signed APK. The build log's "Show
  signing certificate" step prints the certificate's SHA-256 digest.
- **Without `key.properties`,** a local release build falls back to the
  debug key. That APK won't install over a release-signed one, and vice
  versa.
- **Version codes:** a local build uses the build number from
  `pubspec.yaml` (`+1`), while CI uses its run number. So a local build
  usually can't install over a CI build, because Android sees it as a
  downgrade. Pass `--build-number` with a higher number if you need to.

## Building with GitHub Actions

[`.github/workflows/build.yml`](.github/workflows/build.yml) runs on
every push and pull request to `main`, and can also be started by hand
from the Actions tab.

1. **Test:** `flutter analyze` and `flutter test`.
2. **Android:** builds the arm64-v8a release APK.
3. **Windows:** builds the release and zips the `Release` folder.

Each run's APK and zip are attached to it as downloadable artifacts.

### Versioning and releases

The version number is set in one place: the `version:` line in
[`mobile/pubspec.yaml`](mobile/pubspec.yaml), for example `1.2.0`. CI
builds with that version and uses the workflow run number as the build
number. The build number is Android's `versionCode`, so each CI build
installs over the previous one.

- **Ordinary builds** are labeled with the run number, for example
  `dnd-sheet-1.2.0-build.57-android-arm64.apk`.
- **Releases:** bump `version:` in `pubspec.yaml`, commit, and push a
  matching tag:

  ```sh
  git tag v1.2.0
  git push origin v1.2.0
  ```

  The files are then named with just the version (for example
  `dnd-sheet-1.2.0-android-arm64.apk`), and a GitHub Release is created
  with both attached. If the tag doesn't match `pubspec.yaml`, the build
  fails.

## Updating the SRD data

The JSON in `mobile/assets/srd/` is generated from a markdown copy of
SRD 5.2.1 in `srd-data-pull/source/srd-markdown/`. Each
`srd-data-pull/scripts/parse-*.js` script reads one part of it and writes
JSON to `srd-data-pull/data/`. To regenerate:

```sh
cd srd-data-pull
node scripts/parse-spells.js    # or whichever parse-*.js script you changed
# then copy the updated file(s) from data/ to ../mobile/assets/srd/
```

`sheet-text.json` isn't generated. It's short, hand-written summaries of
SRD features for the PDF sheet.

## Content rules for contributors

Only SRD 5.2.1 content may be added to `mobile/assets/srd/` or hardcoded
into the rules code. Never add text or mechanics from the Player's
Handbook, Dungeon Master's Guide or any other book beyond the SRD, even
for a single feat or item. That content can only ever be entered by a
user as their own homebrew. See [Content and
licensing](README.md#content-and-licensing) in the README and
[`mobile/assets/official/README.md`](mobile/assets/official/README.md).
