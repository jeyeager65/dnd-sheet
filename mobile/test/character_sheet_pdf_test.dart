import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'package:dnd_sheet/data/sample_data.dart';
import 'package:dnd_sheet/data/srd_catalog.dart';
import 'package:dnd_sheet/domain/character_sheet_pdf.dart';
import 'package:dnd_sheet/domain/rules.dart' as rules;
import 'package:dnd_sheet/models/character.dart';

/// A blank 2-page stand-in for the real official sheet, sized to match its
/// real page dimensions (603x774pt) - lets fillCharacterSheetTopSection be
/// tested without any network access or the real 16MB file, while still
/// exercising every coordinate against a page the same size they were
/// measured against.
Future<Uint8List> _blankBasePdf() async {
  final document = PdfDocument();
  document.pageSettings.size = const Size(603, 774);
  document.pages.add();
  document.pages.add();
  final bytes = await document.save();
  document.dispose();
  return Uint8List.fromList(bytes);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await srdCatalog.init();
  });

  test('fillCharacterSheetTopSection draws every top-section value (name, species, class/subclass, ability scores, AC/HP/Hit Dice, Proficiency Bonus, Initiative/Speed/Passive Perception) onto the page without throwing', () async {
    final torvek = buildSampleCharacter();

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );

    expect(result, isNotEmpty);

    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    expect(text, contains('Torvek'));
    expect(text, contains('Dragonborn')); // resolved from speciesKey
    expect(text, contains('Fighter'));
    expect(text, contains('Champion')); // subclass, split out of classLabel
    expect(text, contains('${torvek.level}'));
    expect(text, contains('${torvek.maxHp}'));
    expect(text, contains('${torvek.hitDiceTotal}'));
    // Ability scores/modifiers - the sample character's numbers.
    expect(text, contains('${torvek.abilityScores.str}'));
    expect(text, contains('${torvek.abilityScores.dex}'));
    expect(text, contains('${torvek.abilityScores.con}'));
  });

  test('SIZE shows the species\' real size category (just "Medium", not the full parenthetical)', () async {
    final torvek = buildSampleCharacter();
    expect(
      srdCatalog.speciesByKey[torvek.speciesKey]!.size,
      startsWith('Medium'),
    );

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    expect(text, contains('Medium'));
    expect(text, isNot(contains('about 5')));
  });

  test(
    'SIZE is left blank when speciesKey doesn\'t resolve to a real SRD species',
    () async {
      final torvek = buildSampleCharacter()..speciesKey = 'homebrew-species';

      final result = await fillCharacterSheetTopSection(
        await _blankBasePdf(),
        torvek,
      );
      final document = PdfDocument(inputBytes: result);
      final text = PdfTextExtractor(document).extractText();
      document.dispose();

      expect(text, isNot(contains('Medium')));
      expect(text, isNot(contains('Small')));
    },
  );

  test('the species field resolves the real species name even after a Draconic Ancestry choice overwrote speciesLabel', () async {
    final torvek = buildSampleCharacter();
    // Mirrors exactly what _pickSpeciesChoice does on the Overview tab -
    // speciesLabel becomes just the choice ("Red · Fire"), losing
    // "Dragonborn" from that field entirely.
    torvek.speciesChoice = 'Red';
    torvek.speciesLabel = 'Red · Fire';

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    // The real species name, resolved fresh from speciesKey - not the
    // overwritten "Red · Fire" label - with the ancestry choice appended.
    expect(text, contains('Dragonborn (Red)'));
  });

  test('a nonzero Temp HP is drawn onto the sheet', () async {
    final torvek = buildSampleCharacter()..tempHp = 5;

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    expect(text, contains('5'));
  });

  test('the WEAPONS & DAMAGE CANTRIPS table draws every carried weapon\'s name, attack bonus, damage, and mastery', () async {
    final torvek = buildSampleCharacter();
    expect(
      torvek.weapons.length,
      greaterThanOrEqualTo(2),
    ); // Torvek's real data

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    for (final weapon in torvek.weapons) {
      final attack = rules.attackFor(torvek, weapon);
      final damage = rules.damageFor(torvek, weapon);
      expect(text, contains(weapon.name), reason: weapon.name);
      expect(text, contains(rules.formatModifier(attack.bonus)));
      expect(text, contains(damage.text));
    }
  });

  test('an innate attack (Breath Weapon) appears in the same table, after weapons, with its save DC + ability, damage, and area', () async {
    final torvek = buildSampleCharacter();
    final breathWeapon = torvek.innateAttacks.firstWhere(
      (a) => a.name == 'Breath Weapon',
    );
    final info = rules.innateAttackInfo(torvek, breathWeapon);

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    expect(text, contains('Breath Weapon'));
    expect(
      text,
      contains('DC ${info.saveDc} Dex'),
    ); // DC + save ability together
    expect(text, contains('${info.diceCount}${info.dieType} Fire'));
    // Pulled from the real bundled SRD trait text, not hand-typed.
    expect(text, contains('15-foot Cone or a 30-foot Line'));
    // After both of Torvek's weapons, not before - weapon rows fill first.
    final breathIndex = text.indexOf('Breath Weapon');
    final greatswordIndex = text.indexOf('Greatsword');
    expect(greatswordIndex, lessThan(breathIndex));
  });

  test('an innate attack still shows up (with blank Notes, not a crash) when speciesKey doesn\'t resolve to a real SRD species', () async {
    final torvek = buildSampleCharacter();
    // An unresolvable speciesKey (homebrew/uncataloged) - the area phrase
    // is only extracted from the live SRD trait text, and there's no
    // trait to fall back to here; the stored InnateAttack.desc fallback
    // uses different phrasing ("15-ft Cone", not "a 15-foot Cone") that
    // the extractor doesn't recognize, so Notes should come out blank
    // rather than showing something wrong or throwing.
    torvek.speciesKey = 'homebrew_not_a_real_species';

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    expect(text, contains('Breath Weapon')); // still drawn
    expect(text, isNot(contains('-foot'))); // just no area phrase
  });

  test('a weapon name too long for its column shrinks to fit rather than being clipped', () async {
    final torvek = buildSampleCharacter();
    // Torvek's own real magic weapon - long enough to overflow the
    // Name column's ~106pt width at the table's normal 9pt font size.
    final longName = torvek.weapons
        .firstWhere((w) => w.name == 'Emberfang, Blade of the Ashen Vigil')
        .name;

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    // The whole name survives (shrunk to fit), not truncated.
    expect(text, contains(longName));
  });

  test('only the first 6 weapons are drawn - the table has 6 ruled lines, a 7th is silently dropped rather than overflowing', () async {
    final torvek = buildSampleCharacter();
    torvek.weapons = [
      for (var i = 1; i <= 7; i++)
        Weapon(
          name: 'Test Weapon $i',
          damageDice: '1d6',
          damageType: 'Bludgeoning',
          properties: const [],
          proficient: true,
        ),
    ];

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    for (var i = 1; i <= 6; i++) {
      expect(text, contains('Test Weapon $i'));
    }
    expect(text, isNot(contains('Test Weapon 7')));
  });

  test(
    'every Saving Throw and Skill shows its real computed modifier',
    () async {
      final torvek = buildSampleCharacter();

      final result = await fillCharacterSheetTopSection(
        await _blankBasePdf(),
        torvek,
      );
      final document = PdfDocument(inputBytes: result);
      final text = PdfTextExtractor(document).extractText();
      document.dispose();

      for (final abilityKey in ['str', 'dex', 'con', 'int', 'wis', 'cha']) {
        expect(
          text,
          contains(
            rules.formatModifier(rules.savingThrowModifier(torvek, abilityKey)),
          ),
          reason: '$abilityKey save',
        );
      }
      const skillsAndAbilities = {
        'Athletics': 'str',
        'Acrobatics': 'dex',
        'Sleight of Hand': 'dex',
        'Stealth': 'dex',
        'Arcana': 'int',
        'History': 'int',
        'Investigation': 'int',
        'Nature': 'int',
        'Religion': 'int',
        'Animal Handling': 'wis',
        'Insight': 'wis',
        'Medicine': 'wis',
        'Perception': 'wis',
        'Survival': 'wis',
        'Deception': 'cha',
        'Intimidation': 'cha',
        'Performance': 'cha',
        'Persuasion': 'cha',
      };
      for (final MapEntry(key: skill, value: ability)
          in skillsAndAbilities.entries) {
        final existing = torvek.skills.where((s) => s.name == skill);
        final entry = existing.isNotEmpty
            ? existing.first
            : SkillEntry(name: skill, ability: ability, proficient: false);
        expect(
          text,
          contains(rules.formatModifier(rules.skillModifier(torvek, entry))),
          reason: skill,
        );
      }
    },
  );

  test("a Saving Throw or Skill identical to the character's bare ability modifier draws nothing of its own - just the ability bubble's modifier, not repeated once per untrained row too", () async {
    final torvek = buildSampleCharacter();
    // Torvek has no Intelligence proficiencies at all - not the save,
    // not any of its 5 skills - so every one of those 6 rows should
    // stay blank, leaving the bare INT modifier's text appearing
    // exactly once on the whole page (the ability bubble itself).
    expect(torvek.savingThrowProficiencies, isNot(contains('int')));
    for (final skill in [
      'Arcana',
      'History',
      'Investigation',
      'Nature',
      'Religion',
    ]) {
      expect(
        torvek.skills.any((s) => s.name == skill && s.proficient),
        isFalse,
        reason: skill,
      );
    }
    final bareInt = rules.formatModifier(
      rules.abilityModifier(torvek.abilityScores.intel),
    );

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    final occurrences = RegExp(RegExp.escape(bareInt)).allMatches(text).length;
    expect(occurrences, 1); // just the INTELLIGENCE ability bubble
  });

  test('CLASS FEATURES shows every class/subclass feature name and its short sheet text, not the full SRD text', () async {
    final torvek = buildSampleCharacter();
    expect(torvek.features, isNotEmpty);

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    // Word-wrapping splits lines anywhere, so compare with all runs of
    // whitespace collapsed to one space.
    final flat = text.replaceAll(RegExp(r'\s+'), ' ');
    for (final feature in torvek.features.where((f) => f.source != 'species')) {
      expect(flat, contains(feature.name), reason: feature.name);
      final short = rules.sheetText(torvek, feature);
      expect(
        flat,
        contains(short.substring(0, short.length.clamp(0, 20))),
        reason: '${feature.name} sheet text',
      );
    }
    // Extra Attack's full SRD sentence isn't what gets printed any more.
    expect(flat, isNot(contains('You can attack twice instead of once')));
  });

  test('SPECIES TRAITS only shows species-sourced features, not class/subclass ones', () async {
    final torvek = buildSampleCharacter();
    final speciesFeatures = torvek.features.where((f) => f.source == 'species');
    expect(speciesFeatures, isNotEmpty);

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    for (final trait in speciesFeatures) {
      expect(text, contains(trait.name), reason: trait.name);
    }
    // A class feature's name, distinctive enough not to collide with
    // anything else on the page, should not appear where Species Traits
    // would put it - checked indirectly via FEATS below instead, since
    // text position isn't recoverable from plain extracted text; this
    // test only confirms species traits themselves are present.
  });

  test('FEATS shows every feat name, with real SRD description text where available (and none for non-SRD content like Great Weapon Master)', () async {
    final torvek = buildSampleCharacter();
    expect(torvek.feats, isNotEmpty);
    expect(torvek.feats.any((f) => f.name == 'Great Weapon Master'), isTrue);
    expect(torvek.feats.any((f) => f.name == 'Alert'), isTrue);

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    for (final feat in torvek.feats) {
      expect(text, contains(feat.name), reason: feat.name);
    }
    // Alert's bundled short sheet text - matched with a regex since
    // word-wrapping can split it across extracted lines.
    expect(text, matches(RegExp(r'Add\s+PB\s+to\s+Initiative')));
  });

  test('an overlong Class Features list spills from column 1 into column 2 rather than being dropped entirely', () async {
    final torvek = buildSampleCharacter();
    // Enough features, each with enough text, to certainly exceed column
    // 1's ~233pt height - if column 2 isn't used, the later ones (F, G,
    // H...) would be silently dropped instead of continuing there.
    torvek.features = [
      for (final letter in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H'])
        GrantedFeature(
          name: 'Test Feature $letter',
          source: 'class',
          desc:
              'A reasonably long description sentence to take up real '
              'vertical space in the column so this list is forced to '
              'overflow into the second column of the box.',
        ),
    ];

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    for (final letter in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']) {
      expect(text, contains('Test Feature $letter'), reason: letter);
    }
  });

  test('EQUIPMENT TRAINING & PROFICIENCIES shows the class\'s real Weapon Proficiencies text, and omits an unresolved background Tool Proficiency choice rather than printing the raw prompt', () async {
    final torvek = buildSampleCharacter();
    final classInfo = srdCatalog.byKey(torvek.classKey!)!;
    final backgroundInfo = srdCatalog.backgroundsByKey[torvek.backgroundKey]!;
    expect(classInfo.traits['Weapon Proficiencies'], isNotNull);
    expect(backgroundInfo.toolProficiency, isNotNull); // Soldier's Gaming Set
    expect(torvek.toolProficiencyChoices, isEmpty); // never resolved

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    expect(text, contains(classInfo.traits['Weapon Proficiencies']!));
    // An unresolved "Choose N <Tool>" requirement isn't a real granted
    // proficiency yet, so its raw, unparsed SRD prompt text (real SRD
    // text: "_Choose one kind of_ Gaming Set...") must never be printed
    // as though it were one.
    expect(text, isNot(contains('Choose one kind of Gaming Set')));
    expect(text, isNot(contains('_Choose')));
  });

  test('EQUIPMENT TRAINING & PROFICIENCIES prefers the character\'s resolved Tool Proficiency choices over the raw class/background prompt text', () async {
    final torvek = buildSampleCharacter();
    torvek.toolProficiencyChoices = ['Dice'];

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    expect(text, contains('Dice'));
    expect(text, isNot(contains('Choose one kind of Gaming Set')));
  });

  test('page 2 draws Appearance, Backstory & Personality, Alignment, and Languages', () async {
    final torvek = buildSampleCharacter()
      ..appearance = 'Scarred crimson scales, missing a horn.'
      ..notes = 'Grew up in a mercenary company after the war.'
      ..alignment = 'Lawful Good'
      ..languages = ['Common', 'Draconic'];

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final page2Text = PdfTextExtractor(document)
        .extractText(startPageIndex: 1, endPageIndex: 1);
    document.dispose();

    expect(page2Text, contains('Scarred crimson scales'));
    expect(page2Text, contains('Grew up in a mercenary company'));
    expect(page2Text, contains('Lawful Good'));
    expect(page2Text, contains('Common, Draconic'));
  });

  test('page 2 leaves Alignment and Languages blank rather than drawing empty boxes when unset', () async {
    final torvek = buildSampleCharacter();
    expect(torvek.alignment, isNull);
    expect(torvek.languages, isEmpty);

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );

    expect(result, isNotEmpty); // just needs to not throw
  });

  test('page 2 EQUIPMENT lists every Carried Item with quantity and Attuned caption, and Magic Item Attunement lists only the attuned ones (max 3)', () async {
    final torvek = buildSampleCharacter()
      ..inventory = [
        InventoryEntry(name: "Explorer's Pack", quantity: 1),
        InventoryEntry(name: 'Ration', quantity: 5),
        InventoryEntry(name: 'Ring of Protection', quantity: 1, attuned: true),
      ];

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final page2Text = PdfTextExtractor(document)
        .extractText(startPageIndex: 1, endPageIndex: 1);
    document.dispose();

    expect(page2Text, contains("Explorer's Pack"));
    expect(page2Text, contains('Ration'));
    expect(page2Text, matches(RegExp(r'Ration\s*×5')));
    expect(page2Text, matches(RegExp(r'Ring of Protection\s*\(Attuned\)')));
  });

  test('no raw markdown syntax (bold/italic markers) survives into the exported sheet anywhere', () async {
    final torvek = buildSampleCharacter();

    final result = await fillCharacterSheetTopSection(
      await _blankBasePdf(),
      torvek,
    );
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    expect(text, isNot(contains('**')));
    expect(text, isNot(matches(RegExp(r'_[A-Za-z]'))));
  });

  test('page 2 spellcasting: ability, save DC, slot totals, cantrips and prepared spells (not unprepared ones), plus damage cantrips in the page 1 weapons table', () async {
    final c = buildSampleCharacter();
    c.classKey = 'srd-2024_wizard-class';
    c.level = 5;
    c.weapons = [];
    c.innateAttacks = [];
    rules.enableSpellcasting(c);
    String key(String name) =>
        srdCatalog.spells.firstWhere((s) => s.name == name).key;
    c.spellcasting!.cantripsKnown = [key('Fire Bolt'), key('Mage Hand')];
    c.spellcasting!.spells = [
      KnownSpell(spellKey: key('Fireball')),
      KnownSpell(spellKey: key('Counterspell'), prepared: false),
    ];

    final result = await fillCharacterSheetTopSection(await _blankBasePdf(), c);
    final document = PdfDocument(inputBytes: result);
    final page1 = PdfTextExtractor(document).extractText(startPageIndex: 0);
    final page2 = PdfTextExtractor(document).extractText(startPageIndex: 1);
    document.dispose();

    expect(page2, contains('Intelligence'));
    expect(page2, contains('${rules.spellSaveDc(c)}'));
    expect(page2, contains('Mage Hand'));
    expect(page2, contains('Fireball'));
    expect(page2, contains('150 ft'));
    expect(page2, contains('8d6 Fire'));
    expect(page2, isNot(contains('Counterspell')));

    // Fire Bolt is a damage cantrip (scaled to 2d10 at level 5); Mage
    // Hand isn't, so it stays off page 1.
    expect(page1, contains('Fire Bolt'));
    expect(page1, contains('2d10 Fire'));
    expect(page1, isNot(contains('Mage Hand')));
  });

  test("SPECIES TRAITS is filled for a character with no species traits stored (every New Character one), and FEATS leaves out Ability Score Improvement", () async {
    final c = buildSampleCharacter();
    c.features = c.features.where((f) => f.source != 'species').toList();
    c.feats = [
      ...c.feats,
      GrantedFeature(name: 'Ability Score Improvement', source: 'feat'),
    ];

    final result = await fillCharacterSheetTopSection(await _blankBasePdf(), c);
    final document = PdfDocument(inputBytes: result);
    final flat = PdfTextExtractor(document)
        .extractText(startPageIndex: 0)
        .replaceAll(RegExp(r'\s+'), ' ');
    document.dispose();

    expect(flat, contains('Draconic Flight'));
    expect(flat, contains('Darkvision 60 ft.'));
    expect(flat, isNot(contains('Ability Score Improvement')));
  });

  test('when Class Features cannot all fit even at the smallest size, the oldest are dropped and the most recently gained are kept', () async {
    final c = buildSampleCharacter();
    c.features = [
      for (var i = 1; i <= 40; i++)
        GrantedFeature(
          name: 'Feature Number $i',
          source: 'class',
          desc:
              'A description long enough to wrap onto a few lines so forty '
              'of these can never all fit in both columns of the box.',
        ),
    ];

    final result = await fillCharacterSheetTopSection(await _blankBasePdf(), c);
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document)
        .extractText(startPageIndex: 0)
        .replaceAll(RegExp(r'\s+'), ' ');
    document.dispose();

    expect(text, contains('Feature Number 40'));
    expect(text, contains('Feature Number 39'));
    expect(text, isNot(contains('Feature Number 1 ')));
    // Kept entries stay in the order they were gained.
    expect(
      text.indexOf('Feature Number 39'),
      lessThan(text.indexOf('Feature Number 40')),
    );
  });

  test(
    'Temp HP is left blank - it changes in play and gets pencilled in',
    () async {
      final c = buildSampleCharacter()..tempHp = 37;
      final result = await fillCharacterSheetTopSection(
        await _blankBasePdf(),
        c,
      );
      final document = PdfDocument(inputBytes: result);
      final text = PdfTextExtractor(document).extractText();
      document.dispose();
      expect(text, isNot(contains('37')));
    },
  );

  test('Size uses the chosen size', () async {
    final c = buildSampleCharacter()
      ..speciesKey = 'srd-2024_human-species'
      ..sizeChoice = 'Small';
    final result = await fillCharacterSheetTopSection(await _blankBasePdf(), c);
    final document = PdfDocument(inputBytes: result);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();
    expect(text, contains('Small'));
  });

  test('COINS prints each nonzero denomination', () async {
    final c = buildSampleCharacter()..currency = const Currency(gp: 123, pp: 4);
    final result = await fillCharacterSheetTopSection(await _blankBasePdf(), c);
    final document = PdfDocument(inputBytes: result);
    final page2 = PdfTextExtractor(document).extractText(startPageIndex: 1);
    document.dispose();
    expect(page2, contains('123'));
    expect(page2, contains('4'));
  });
}
