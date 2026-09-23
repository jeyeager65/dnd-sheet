# Local "official" content

This app's shared source only bundles content from the free D&D SRD
(`assets/srd/`) - never real, non-SRD 2024 content (General Feats like
Great Weapon Master, magic items only described in the PHB/DMG, etc.).
That's a licensing boundary, not a preference: see `lib/domain/rules.dart`'s
`_builtinFeatEffects` doc comment for the full reasoning. The app has no
way to legally redistribute that content to someone who doesn't already
own it - but if *you* own the book, there's nothing wrong with you typing
your own copy of it into your own local data.

That's what this folder is for.

## How it works

1. In the app, go to **My Homebrew → + Add**, create the feat/item you
   want (name it exactly like the real thing), set **Source: Official**,
   and fill in its effects with the term editor - this is you
   transcribing content you already legally own, same as writing it on a
   paper character sheet.
2. Once you're happy with your homebrew catalog, tap **Export** on the
   My Homebrew screen. That shares a JSON file (a plain array of entries,
   the same shape `HomebrewRepository.exportAll()` produces).
3. Save that file as `assets/official/content.json` - right here, next
   to this README.
4. Add `assets/official/content.json` to your own `.gitignore` (it
   already is, in this repo's `.gitignore`) so it's never committed or
   shared.
5. From now on, every build *you* run bundles that file and
   `lib/data/local_official_content.dart` merges it into your local
   homebrew catalog automatically on first launch - no more re-typing it
   after a reinstall or a fresh `flutter build`.

## Why this is safe to share the rest of the app

- `content.json` is gitignored, so it never leaves your machine when you
  share this repo or its source.
- If the file isn't present (a fresh clone, or anyone else's checkout),
  the loader silently does nothing - the app builds and runs exactly the
  same, just without your personal content. Nothing in the shared source
  itself ever encodes real, non-SRD mechanics or text.
- Only `assets/official/content.json` (the file, singular) is ignored;
  this README stays tracked so the mechanism and the folder itself
  survive a fresh clone.

## File shape

A JSON array of `HomebrewEntry` objects - see `lib/models/homebrew.dart`.
Example shape (not real feat content - just illustrating the fields):

```json
[
  {
    "id": "homebrew_example-id",
    "kind": "feat",
    "name": "Some General Feat",
    "desc": "Your own transcription of its rules text.",
    "source": "official",
    "effects": [
      { "target": "damageRoll", "formula": "Proficiency Bonus", "condition": "heavyWeapon" }
    ]
  }
]
```
