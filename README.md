# D&D Sheet

A character sheet app for **Dungeons & Dragons 5th Edition (2024 rules)**,
for Android and Windows. It is built on the free
[System Reference Document 5.2.1](https://www.dndbeyond.com/srd), so you
can build, level and play a character without opening the Player's
Handbook. It can also print your character onto the official 2024
character sheet.

It works offline. Characters and homebrew are stored on your device, with
no account or server.

## Features

**Building and leveling characters**
- Create a character from the SRD species, backgrounds, classes and
  subclasses, including starting equipment, background ability score
  increases and skill choices.
- Level up with the choices each level brings: Ability Score Improvement
  or a feat, subclass, Fighting Style, Weapon Mastery, Eldritch
  Invocations, Metamagic and other class options.
- Feat prerequisites are enforced, and a feat's own ability score
  increase is applied when you take it.
- Hit points can be rolled or averaged per level. Each level keeps a
  snapshot, so you can look back at earlier versions of a character.

**Playing**
- Track HP, Temporary HP, damage (resistances included), death saves,
  exhaustion and Hit Dice.
- Short and Long Rests show what they'll restore before you confirm.
- Limited-use resources (Channel Divinity, Focus Points, Rages, ...)
  list the features you can spend them on.
- Weapons show attack and damage breakdowns, what each weapon property
  does, and your Weapon Mastery effects.
- Spellcasting covers slots, Pact Magic, prepared spells, rituals,
  Concentration, and free casts from features and feats.
- Mounts can be tracked, and casting *Find Steed* summons your
  Otherworldly Steed with its stats worked out.
- Inventory has currency, attunement and magic items.
- A searchable **Reference** covers the SRD rules, spells, equipment,
  conditions and more.

**Character sheet PDF**
- Export your character onto the official 2024 character sheet. Long
  feature text is shortened to fit, and you can edit the short text per
  feature.

**Homebrew**
- Create your own species, backgrounds, classes, subclasses, feats,
  spells, weapons, armor, gear, tools, magic items and languages.
  Homebrew can carry real mechanics: bonuses, resistances, granted
  spells, ability score increases and option choices.
- Mark an entry as **Official** to type in content from books you own
  that isn't in the SRD (see [Content and licensing](#content-and-licensing)).

**Sharing and backup**
- Export and import characters and homebrew as JSON files. A character
  export includes the homebrew it uses.

**Desktop**
- On a wide window, the sheet's tabs and the Reference categories move
  into a panel on the left.

## Download

Builds are produced by GitHub Actions (see [Building with GitHub
Actions](#building-with-github-actions)):

- **Android:** `dnd-sheet-<version>-android-arm64.apk`, for 64-bit ARM
  phones and tablets (nearly all current Android devices).
- **Windows:** `dnd-sheet-<version>-windows-x64.zip`. Unzip it and run
  `dnd_sheet.exe`.

The version the app is running is shown under **About** (the ⓘ button
on My Characters).

The Android build is signed with a debug key (see [Android
signing](#android-signing)). If an install over an earlier build fails
with a signature error, uninstall the old app first. Export your
characters before you do, because uninstalling deletes them.

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

### Android signing

Release APKs are currently signed with the debug key, as set in
[`mobile/android/app/build.gradle.kts`](mobile/android/app/build.gradle.kts).
That's fine for personal use and sideloading. A Play Store release would
need a real signing key.

## Building with GitHub Actions

[`.github/workflows/build.yml`](.github/workflows/build.yml) runs on
every push and pull request to `main`, and can also be started by hand
from the Actions tab.

1. **Test:** `flutter analyze` and `flutter test`.
2. **Android:** builds the arm64-v8a release APK.
3. **Windows:** builds the release and zips the `Release` folder.

Each run's APK and zip are attached to it as downloadable artifacts.

### Versioning

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

## Content and licensing

**SRD content.** This work includes material from the System Reference
Document 5.2.1 ("SRD 5.2.1") by Wizards of the Coast LLC, available at
<https://www.dndbeyond.com/srd>. The SRD 5.2.1 is licensed under the
Creative Commons Attribution 4.0 International License, available at
<https://creativecommons.org/licenses/by/4.0/legalcode>.

The app shows this attribution under **About**, along with the licenses
of the packages it uses.

**Where the data comes from.** All game content comes from
[dnd-5e-srd-markdown](https://github.com/downfallx/dnd-5e-srd-markdown)
by downfallx, a Markdown conversion of SRD 5.2.1 that is itself licensed
under CC BY 4.0. It's copied into `srd-data-pull/source/srd-markdown/`,
and the scripts in `srd-data-pull/scripts/` convert it to the JSON the
app uses. That JSON is restructured from the SRD text, and the short
feature summaries in `sheet-text.json` are condensed from it.

**Non-SRD content isn't included.** The app ships only SRD content: no
text or mechanics from the Player's Handbook or other books beyond the
SRD. Content you own that isn't in the SRD, such as Great Weapon Master,
can be entered as your own **Official** homebrew. It stays in your local
data, and the optional `mobile/assets/official/content.json` is
gitignored so it's never committed. See
[`mobile/assets/official/README.md`](mobile/assets/official/README.md).
Your character and homebrew exports include whatever you've entered, so
think about that before sharing them.

**The official character sheet isn't redistributed.** Wizards of the
Coast publishes the 2024 character sheet as a free download. The app
downloads it from D&D Beyond the first time you export a PDF and caches
it on your device. It isn't included in this repository or in the builds.

**Not affiliated.** This is unofficial fan-made software. It isn't
affiliated with, endorsed, sponsored or approved by Wizards of the Coast.
Dungeons & Dragons and D&D are trademarks of Wizards of the Coast LLC.

**Third-party libraries.** PDF export uses
[Syncfusion Flutter PDF](https://pub.dev/packages/syncfusion_flutter_pdf),
which isn't open source and isn't covered by this project's MIT License.
This project's builds are made under a Syncfusion Essential Studio
Community License. If you build or redistribute the app yourself, you
need your own
[Syncfusion license](https://www.syncfusion.com/products/communitylicense),
either the free Community License if you qualify or a commercial one.
Other dependencies are listed in [`mobile/pubspec.yaml`](mobile/pubspec.yaml),
and their licenses are shown in the app under **About > View licenses**.

## License

This project's source code is licensed under the [MIT License](LICENSE).

The game content isn't covered by the MIT License. That's everything in
`mobile/assets/srd/`, `srd-data-pull/source/` and `srd-data-pull/data/`.
It's derived from the SRD and stays under
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/legalcode), with
the attribution above.
