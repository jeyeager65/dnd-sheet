import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:dnd_sheet/data/character_repository.dart';
import 'package:dnd_sheet/data/homebrew_repository.dart';
import 'package:dnd_sheet/data/sample_data.dart';
import 'package:dnd_sheet/data/sheet_text_repository.dart';
import 'package:dnd_sheet/data/srd_catalog.dart';
import 'package:dnd_sheet/domain/rules.dart' as rules;
import 'package:dnd_sheet/main.dart';
import 'package:dnd_sheet/models/character.dart';
import 'package:dnd_sheet/models/effect.dart';
import 'package:dnd_sheet/models/homebrew.dart';
import 'package:dnd_sheet/screens/character_form_screen.dart';
import 'package:dnd_sheet/screens/homebrew_screen.dart';
import 'package:dnd_sheet/widgets/expandable_row.dart';
import 'package:dnd_sheet/widgets/common_bits.dart';

void main() {
  // Bypasses charactersRepo.init() (which needs Hive/path_provider plugin
  // channels the widget-test environment doesn't provide) and seeds the
  // in-memory list directly - that's all the screens actually read from.
  // srdCatalog.init() only reads bundled JSON assets, which works fine in
  // the test environment, and the Overview tab's Skills section needs it
  // populated to render anything.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await srdCatalog.init();
  });

  setUp(() {
    charactersRepo.characters
      ..clear()
      ..add(buildSampleCharacter());
    homebrewRepo.entries.clear();
  });

  testWidgets('About shows the version and the SRD attribution', (
    WidgetTester tester,
  ) async {
    PackageInfo.setMockInitialValues(
      appName: 'D&D Sheet',
      packageName: 'dev.yeager.dndsheet',
      version: '1.2.0',
      buildNumber: '57',
      buildSignature: '',
    );
    await tester.pumpWidget(const DndSheetApp());
    await tester.tap(find.byTooltip('About'));
    await tester.pumpAndSettle();
    expect(find.text('1.2.0 (build 57)'), findsOneWidget);
    expect(
      find.textContaining('System Reference Document 5.2.1'),
      findsOneWidget,
    );
  });

  testWidgets('shows the character list with Torvek in it', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DndSheetApp());

    expect(find.text('My Characters'), findsOneWidget);
    expect(find.text('Torvek'), findsAtLeastNWidgets(1));
  });

  testWidgets('tapping Torvek opens the sheet on the Combat tab', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DndSheetApp());

    await tester.tap(find.text('Torvek').first);
    await tester.pumpAndSettle();

    // Weapons sits below the stat grid and Hit Points, so it may be off
    // the default test viewport - scroll it into view rather than
    // assuming everything fits on screen.
    await tester.dragUntilVisible(
      find.text('Greatsword'),
      find.byType(ListView),
      const Offset(0, -400),
    );

    expect(find.textContaining('WEAPONS'), findsOneWidget);
    expect(find.text('Greatsword'), findsOneWidget);
  });

  testWidgets('a rest asks first, listing what it would recover', (
    WidgetTester tester,
  ) async {
    final torvek = charactersRepo.characters.first;
    torvek.currentHp = torvek.maxHp - 10;
    await tester.pumpWidget(const DndSheetApp());
    await tester.tap(find.text('Torvek').first);
    await tester.pumpAndSettle();

    // Rests now sits below Hit Points/Weapons/Resources/Mounts, off the
    // default test viewport - scroll it into view first.
    await tester.dragUntilVisible(
      find.text('Long Rest'),
      find.byType(ListView),
      const Offset(0, -400),
    );
    await tester.tap(find.text('Long Rest'));
    await tester.pumpAndSettle();
    expect(find.text('Take a Long Rest?'), findsOneWidget);
    expect(
      find.text(
        '• HP: ${torvek.maxHp - 10} → ${torvek.maxHp} of ${torvek.maxHp}',
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(torvek.currentHp, torvek.maxHp - 10);

    await tester.tap(find.text('Long Rest'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Take Long Rest'));
    await tester.pumpAndSettle();
    expect(find.text('Take a Long Rest?'), findsNothing);
    expect(torvek.currentHp, torvek.maxHp);
  });

  testWidgets('the sheet AppBar offers an Export PDF action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DndSheetApp());

    await tester.tap(find.text('Torvek').first);
    await tester.pumpAndSettle();

    expect(find.byTooltip('Export PDF'), findsOneWidget);
  });

  testWidgets(
    "a weapon row's collapsed header shows its attack/damage as a subtitle, and expanding it reveals Edit/Remove for that weapon specifically",
    (WidgetTester tester) async {
      // The default 800x600 test surface is tall enough for
      // dragUntilVisible to consider Greatsword "visible" the moment its
      // top pixel enters view, but not tall enough for its full row -
      // leaving a tap at the row's (off-viewport) center silently
      // missing. A taller surface keeps the whole row on screen.
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const DndSheetApp());

      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Greatsword'),
        find.byType(ListView),
        const Offset(0, -400),
      );

      // Collapsed: the attack/damage line shows as a subtitle right under
      // the name - computed live from the real character rather than a
      // hardcoded number, since a weapon's attack/damage bonus depends on
      // ability scores, proficiency, and any magic bonus.
      final torvek = charactersRepo.byId('torvek');
      final greatsword = torvek.weapons.firstWhere(
        (w) => w.name == 'Greatsword',
      );
      final attack = rules.attackFor(torvek, greatsword);
      final damage = rules.damageFor(torvek, greatsword);
      expect(
        find.text('${rules.formatModifier(attack.bonus)} / ${damage.text}'),
        findsOneWidget,
      );

      // Expanding reveals this weapon's own Edit/Remove, scoped to its
      // row specifically (there's always exactly one other "Edit" on
      // screen already, the sheet's own AppBar button, so this checks the
      // weapon row's subtree rather than a raw global count).
      final greatswordRow = find.ancestor(
        of: find.text('Greatsword'),
        matching: find.byType(ExpandableRow),
      );
      await tester.tap(find.text('Greatsword'));
      await tester.pumpAndSettle();

      expect(
        find.descendant(of: greatswordRow, matching: find.text('Edit')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: greatswordRow, matching: find.text('Remove')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    "shows Breath Weapon's live level-scaled damage (2d10 at Torvek's level 9), not a stale hardcoded value",
    (WidgetTester tester) async {
      await tester.pumpWidget(const DndSheetApp());

      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();

      // "d10" alone would also match the Hit Dice section's "d10
      // remaining" text higher up the tab, stopping the scroll too early
      // - target the Breath Weapon row's own title instead.
      await tester.dragUntilVisible(
        find.text('Breath Weapon'),
        find.byType(ListView),
        const Offset(0, -300),
      );

      // The row's own computed tag (e.g. "2d10 Fire · DC 14"), derived the
      // same way the widget derives it - the collapsed body below it is
      // the verbatim SRD trait text, which legitimately mentions every
      // tier (1d10/2d10/3d10/4d10) in one scaling sentence, so asserting
      // "3d10 nowhere on screen" would fail against correct real text.
      final torvek = charactersRepo.byId('torvek');
      final breathWeapon = torvek.innateAttacks.firstWhere(
        (a) => a.name == 'Breath Weapon',
      );
      final info = rules.innateAttackInfo(torvek, breathWeapon);
      expect(
        find.textContaining(
          '${info.diceCount}${info.dieType} Fire · DC ${info.saveDc}',
        ),
        findsOneWidget,
      );
      expect(info.diceCount, 2);
    },
  );

  testWidgets(
    'Overview tab shows all 18 skills and lets you toggle saving throws and skill proficiency/expertise',
    (WidgetTester tester) async {
      // The Overview ListView is taller than any real phone screen once
      // every saving throw and all 18 skills are shown - enlarge the test
      // viewport so the whole thing lays out in one frame instead of
      // juggling scroll positions per assertion (a real ListView only
      // builds elements within its viewport + cache extent, so anything
      // still off-screen genuinely isn't findable).
      tester.view.physicalSize = const Size(1080, 6000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const DndSheetApp());

      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();

      // Combat is the default tab - switch to Overview.
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();

      // All 18 real skills are listed, not just Torvek's pre-existing
      // sparse 5-entry list (matches the PWA's always-show-all behavior).
      for (final name in const [
        'Acrobatics',
        'Animal Handling',
        'Arcana',
        'Athletics',
        'Deception',
        'History',
        'Insight',
        'Intimidation',
        'Investigation',
        'Medicine',
        'Nature',
        'Perception',
        'Performance',
        'Persuasion',
        'Religion',
        'Sleight of Hand',
        'Stealth',
        'Survival',
      ]) {
        expect(find.textContaining(name), findsOneWidget, reason: name);
      }

      final torvek = charactersRepo.byId('torvek');

      // Saving Throws' and Skills' checkboxes are each locked until that
      // section's own Edit is tapped. Scoped to the section specifically,
      // since the sheet's own AppBar also has an unrelated "Edit" button
      // (opens Edit Character) that a bare find.text('Edit') would match
      // first.
      Future<void> tapSectionEdit(String sectionLabel) async {
        final header = find.ancestor(
          of: find.text(sectionLabel),
          matching: find.byType(SectionLabel),
        );
        await tester.tap(
          find.descendant(
            of: header,
            matching: find.widgetWithText(TextButton, 'Edit'),
          ),
        );
        await tester.pumpAndSettle();
      }

      await tapSectionEdit('SAVING THROWS');
      expect(find.text('Done'), findsOneWidget);

      // Saving throws: Torvek starts proficient in Str and Con only -
      // toggle Dex on via its checkbox.
      expect(torvek.savingThrowProficiencies, isNot(contains('dex')));
      final dexRow = find.ancestor(
        of: find.text('Dexterity'),
        matching: find.byType(Row),
      );
      await tester.tap(
        find.descendant(of: dexRow, matching: find.byType(Checkbox)).first,
      );
      await tester.pumpAndSettle();
      expect(torvek.savingThrowProficiencies, contains('dex'));

      // Skills has its own separate Edit/Done toggle - Saving Throws
      // being unlocked doesn't unlock it too.
      await tapSectionEdit('SKILLS');
      expect(find.text('Done'), findsNWidgets(2));

      // Skills: Torvek isn't proficient in Stealth - toggle it on, then
      // toggle Expertise on too, then verify unchecking Proficient also
      // clears Expertise (can't have expertise without proficiency).
      expect(torvek.skills.where((s) => s.name == 'Stealth'), isEmpty);
      final stealthRow = find.ancestor(
        of: find.textContaining('Stealth'),
        matching: find.byType(Row),
      );
      final stealthChecks = find.descendant(
        of: stealthRow,
        matching: find.byType(Checkbox),
      );
      await tester.tap(stealthChecks.at(0));
      await tester.pumpAndSettle();
      expect(
        torvek.skills.firstWhere((s) => s.name == 'Stealth').proficient,
        isTrue,
      );

      await tester.tap(stealthChecks.at(1));
      await tester.pumpAndSettle();
      expect(
        torvek.skills.firstWhere((s) => s.name == 'Stealth').expertise,
        isTrue,
      );

      await tester.tap(stealthChecks.at(0));
      await tester.pumpAndSettle();
      expect(torvek.skills.where((s) => s.name == 'Stealth'), isEmpty);
    },
  );

  testWidgets(
    'editing an ability score on the Overview tab updates it and logs a history entry',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const DndSheetApp());

      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();

      final torvek = charactersRepo.byId('torvek');
      expect(torvek.abilityScores.str, 19);
      expect(torvek.history, isEmpty);

      await tester.tap(find.text('Edit Scores'));
      await tester.pumpAndSettle();
      expect(find.text('Edit Ability Scores'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'STR'), '21');
      await tester.enterText(
        find.widgetWithText(TextField, 'Reason (optional)'),
        'Belt of Storm Giant Strength',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(torvek.abilityScores.str, 21);
      expect(torvek.history, hasLength(1));
      expect(torvek.history.first.label, 'Belt of Storm Giant Strength');
      expect(torvek.history.first.detail, 'STR 19 → 21');

      // The History section renders the new entry.
      expect(find.text('Belt of Storm Giant Strength'), findsOneWidget);
    },
  );

  testWidgets(
    'Reference is reachable from an open character sheet, grouped into sections, and returns to the character',
    (WidgetTester tester) async {
      // The Reference landing list has 18 categories across 4 section
      // headers - taller than any real phone screen, so enlarge the test
      // viewport rather than juggle scroll positions per assertion (a
      // plain ListView only builds elements within its viewport + cache
      // extent). Phone width: this is the phone layout's landing list.
      tester.view.physicalSize = const Size(600, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const DndSheetApp());

      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();
      expect(find.text('Lv.9 Dragonborn Fighter · Champion'), findsOneWidget);

      // The book icon in the character sheet's own AppBar opens Reference
      // without leaving the character screen behind on the stack.
      await tester.tap(find.byTooltip('Reference'));
      await tester.pumpAndSettle();
      expect(find.text('Reference'), findsOneWidget);

      // Categories are grouped under section headers (SectionLabel
      // uppercases the text), not one flat list.
      expect(find.text('CHARACTER OPTIONS'), findsOneWidget);
      expect(find.text('EQUIPMENT'), findsOneWidget);
      expect(find.text('RULES'), findsOneWidget);
      expect(find.text('TABLES'), findsOneWidget);

      // A "chapters" category (a handful of long sections) opens a table
      // of contents, not the search-box item list "items" categories get.
      await tester.tap(find.text('Playing the Game'));
      await tester.pumpAndSettle();
      expect(find.text('Playing the Game'), findsOneWidget);
      expect(find.byType(TextField), findsNothing); // no search box
      expect(find.text('Combat'), findsOneWidget);

      await tester.tap(find.text('Combat'));
      await tester.pumpAndSettle();
      // The section opens as its own full page, titled after the section.
      expect(
        find.descendant(of: find.byType(AppBar), matching: find.text('Combat')),
        findsOneWidget,
      );
      expect(find.textContaining('Opportunity Attacks'), findsWidgets);

      // Back three times (detail -> table of contents -> Reference ->
      // character sheet) lands right back on Torvek's sheet.
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('Lv.9 Dragonborn Fighter · Champion'), findsOneWidget);
    },
  );

  testWidgets(
    'Temp HP can be granted, is spent before real HP, and a new grant replaces rather than stacks',
    (WidgetTester tester) async {
      await tester.pumpWidget(const DndSheetApp());

      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();

      final torvek = charactersRepo.byId('torvek');
      torvek.currentHp = torvek.maxHp;
      expect(torvek.tempHp, 0);

      await tester.dragUntilVisible(
        find.text('Temp HP'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.tap(find.text('Temp HP'));
      await tester.pumpAndSettle();
      expect(find.text('Temporary Hit Points'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'New amount'), '5');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(torvek.tempHp, 5);

      // Damage is absorbed by Temp HP first.
      await tester.tap(find.text('-1'));
      await tester.pumpAndSettle();
      expect(torvek.tempHp, 4);
      expect(torvek.currentHp, torvek.maxHp);

      // A second, smaller grant replaces the remaining 4, it doesn't add
      // to it.
      await tester.tap(find.text('Temp HP'));
      await tester.pumpAndSettle();
      expect(find.text('Currently 4.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'New amount'), '2');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(torvek.tempHp, 2);
    },
  );

  testWidgets(
    "Take Damage shows a breakdown of what changed the raw amount and applies only the final total (Torvek's Draconic Resistance halves Fire)",
    (WidgetTester tester) async {
      await tester.pumpWidget(const DndSheetApp());

      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();

      final torvek = charactersRepo.byId('torvek');
      torvek.currentHp = torvek.maxHp;

      await tester.dragUntilVisible(
        find.text('Take Damage'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.tap(find.text('Take Damage'));
      await tester.pumpAndSettle();
      expect(find.text('Take Damage'), findsNWidgets(2)); // button + title

      await tester.enterText(find.widgetWithText(TextField, 'Amount'), '19');
      await tester.pumpAndSettle();

      // Switch the damage type to Fire.
      await tester.tap(
        find.widgetWithText(
          DropdownButtonFormField<String>,
          srdCatalog.damageTypes.first.name,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fire').last);
      await tester.pumpAndSettle();

      // The breakdown names the source and shows the halved total, not
      // just the raw amount typed in.
      expect(find.textContaining('Draconic Resistance'), findsOneWidget);
      expect(find.text('Final: 9 HP'), findsOneWidget); // (19 / 2).floor()

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      // Only the computed 9, not the raw 19, actually came off HP.
      expect(torvek.currentHp, torvek.maxHp - 9);
    },
  );

  testWidgets(
    "Take Damage's \"Passed a save\" checkbox halves damage independently of (and on top of) resistance",
    (WidgetTester tester) async {
      await tester.pumpWidget(const DndSheetApp());

      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();

      final torvek = charactersRepo.byId('torvek');
      torvek.currentHp = torvek.maxHp;

      await tester.dragUntilVisible(
        find.text('Take Damage'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.tap(find.text('Take Damage'));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextField, 'Amount'), '19');
      await tester.pumpAndSettle();

      await tester.tap(
        find.widgetWithText(
          DropdownButtonFormField<String>,
          srdCatalog.damageTypes.first.name,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fire').last);
      await tester.pumpAndSettle();

      await tester.tap(find.text('Passed a save (half damage)'));
      await tester.pumpAndSettle();

      // Halved for the save (19 -> 9), then halved again for Draconic
      // Resistance (9 -> 4) - a quarter of the raw roll, not just a half.
      expect(find.text('Passed a save: half → 9'), findsOneWidget);
      expect(find.textContaining('Draconic Resistance'), findsOneWidget);
      expect(find.text('Final: 4 HP'), findsOneWidget);

      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();
      expect(torvek.currentHp, torvek.maxHp - 4);
    },
  );

  testWidgets(
    'deleting a character requires confirmation and then removes it',
    (WidgetTester tester) async {
      await tester.pumpWidget(const DndSheetApp());

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      expect(find.text('Delete Torvek?'), findsOneWidget);

      // Cancel first - the character should still be there.
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('Torvek'), findsAtLeastNWidgets(1));

      // Now actually delete it.
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Torvek'), findsNothing);
      expect(find.text('No characters yet. Add one below.'), findsOneWidget);
    },
  );

  testWidgets(
    'Level Up advances the sheet by one level, leaves an automatic backup at the old level in the character list, and that backup can be promoted back',
    (WidgetTester tester) async {
      // Phone layout: back to the list is the AppBar's back arrow.
      tester.view.physicalSize = const Size(600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(const DndSheetApp());

      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();
      final torvek = charactersRepo.byId('torvek');
      expect(torvek.level, 9);

      await tester.tap(find.byTooltip('Level Up'));
      await tester.pumpAndSettle();
      expect(find.text('Level Up to 10?'), findsOneWidget);
      await tester.tap(find.text('Level Up').last);
      await tester.pumpAndSettle();

      // The result dialog always shows Max HP, plus either "Resolve Now"
      // (new Pending Choices at this level) or "Done" (none) - handle
      // both without hardcoding whether level 10 happens to have one.
      expect(find.textContaining('Level 10!'), findsOneWidget);
      final resolveNow = find.text('Resolve Now');
      await tester.tap(
        resolveNow.evaluate().isNotEmpty ? resolveNow : find.text('Done'),
      );
      await tester.pumpAndSettle();

      expect(torvek.id, 'torvek'); // same character, advanced in place
      expect(torvek.level, 10);
      expect(torvek.isCurrent, isTrue);

      // Back on the character list, the old Level 9 state is preserved as
      // an automatic, non-current backup - no separate "snapshot" step
      // was needed.
      await tester.pageBack();
      await tester.pumpAndSettle();
      // Previous levels start collapsed under their character.
      expect(find.text('Level 9 (previous)'), findsNothing);
      await tester.tap(find.text('Previous levels (1)'));
      await tester.pumpAndSettle();
      expect(find.text('Level 9 (previous)'), findsOneWidget);

      // Promoting the backup demotes the (now Level 10) live character to
      // history instead - reversible, not a one-way mutation.
      await tester.tap(find.text('Promote'));
      await tester.pumpAndSettle();
      expect(find.text('Level 10 (previous)'), findsOneWidget);
      expect(torvek.isCurrent, isFalse);
    },
  );

  testWidgets(
    'creating a homebrew feat, opening its editor, adding an Effect, and saving persists it to homebrewRepo',
    (WidgetTester tester) async {
      // The Effects section (and its "+ Term" button once a row is added)
      // sits below Source/Description and is off the default 600px test
      // viewport - a plain ListView only builds elements within its
      // viewport + cache extent, so enlarge it rather than scroll.
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final entry = homebrewRepo.create('feat', 'Test Feat');

      await tester.pumpWidget(
        MaterialApp(home: HomebrewEditScreen(entry: entry)),
      );

      await tester.tap(find.text('+ Add Effect'));
      await tester.pumpAndSettle();

      // "Affects" is grouped, and explains the pick under the field.
      expect(find.text('Attack rolls'), findsOneWidget);
      expect(
        find.text('Added to weapon and Unarmed Strike attack rolls.'),
        findsOneWidget,
      );
      await tester.tap(find.text('Attack rolls'));
      await tester.pumpAndSettle();
      expect(find.text('DEFENSE AND HEALTH'), findsOneWidget);
      await tester.tap(find.text('Damage rolls').last);
      await tester.pumpAndSettle();
      expect(find.text('Added to weapon damage.'), findsOneWidget);

      // Weapon conditions are offered for a damage roll.
      await tester.tap(find.text('Always'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Using a Heavy weapon').last);
      await tester.pumpAndSettle();

      // The formula editor builds terms via a dialog rather than free
      // text - add a single "Proficiency Bonus" term.
      await tester.tap(find.text('+ Term'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Prof. Bonus'));
      await tester.pumpAndSettle();
      // The term dialog's own Save (FilledButton) is the only one on
      // screen while it's open - the AppBar's Save (TextButton) is a
      // second "Save" text underneath it, so this disambiguates by type.
      await tester.tap(find.byType(FilledButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = homebrewRepo
          .byKind('feat')
          .firstWhere((e) => e.id == entry.id);
      expect(saved.effects, hasLength(1));
      expect(saved.effects.first.formula, 'Proficiency Bonus');
      expect(saved.effects.first.target, 'damageRoll');
      expect(saved.effects.first.condition, 'heavyWeapon');
    },
  );

  testWidgets(
    'a homebrew feat\'s editor lets you set a Category (restricting which choice pickers offer it) and a free-text Prerequisite',
    (WidgetTester tester) async {
      final entry = homebrewRepo.create('feat', 'Test Categorized Feat');
      expect(entry.category, isNull);
      expect(entry.prerequisite, isNull);

      await tester.pumpWidget(
        MaterialApp(home: HomebrewEditScreen(entry: entry)),
      );

      // Category is a closed dropdown, not free text - starts as
      // "Uncategorized" and offers exactly the 4 real SRD feat categories.
      expect(find.text('Uncategorized'), findsOneWidget);
      await tester.tap(find.text('Uncategorized'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fighting Style Feat').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(
          TextField,
          'Optional, e.g. "Level 4+" - display-only, not enforced.',
        ),
        'Fighting Style Feature',
      );

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = homebrewRepo
          .byKind('feat')
          .firstWhere((e) => e.id == entry.id);
      expect(saved.category, 'Fighting Style Feat');
      expect(saved.prerequisite, 'Fighting Style Feature');
    },
  );

  testWidgets(
    'Category and Prerequisite are hidden for a non-feat homebrew entry (only feats have a category to restrict)',
    (WidgetTester tester) async {
      // A tool: no feat Category, and no rules fields of its own that
      // would have their own "Category" (weapons and items do).
      final entry = homebrewRepo.create('tool', 'Test Tool');

      await tester.pumpWidget(
        MaterialApp(home: HomebrewEditScreen(entry: entry)),
      );

      expect(find.text('Category'), findsNothing);
      expect(find.text('Prerequisite'), findsNothing);
    },
  );

  testWidgets(
    '+ Add Resource creates a custom resource that survives a long rest and class-resource recalculation',
    (WidgetTester tester) async {
      await tester.pumpWidget(const DndSheetApp());

      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('+ Add Resource'),
        find.byType(ListView),
        const Offset(0, -400),
      );
      await tester.tap(find.text('+ Add Resource'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Bottomless Tankard',
      );
      await tester.enterText(find.widgetWithText(TextField, 'Uses'), '1');
      await tester.enterText(
        find.widgetWithText(TextField, 'Note'),
        'Currently filled: Healing Potion (8d4+8)',
      );
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      final torvek = charactersRepo.byId('torvek');
      expect(
        torvek.resources.any((r) => r.name == 'Bottomless Tankard'),
        isTrue,
      );
      final resource = torvek.resources.firstWhere(
        (r) => r.name == 'Bottomless Tankard',
      );
      expect(resource.max, 1);
      expect(rules.isCustomResource(torvek, resource), isTrue);

      resource.used = 1;
      rules.applyLongRest(torvek);
      expect(torvek.resources.firstWhere((r) => r.key == resource.key).used, 0);

      // A manually-added resource isn't a recognized class/species key, so
      // recalculateClassResources must leave it alone rather than dropping
      // it (same reasoning as isCustomResource's managedNames check).
      rules.recalculateClassResources(torvek);
      expect(
        torvek.resources.any((r) => r.name == 'Bottomless Tankard'),
        isTrue,
      );
    },
  );

  testWidgets(
    'deleting a homebrew feat granted to a character warns which character uses it before deleting',
    (WidgetTester tester) async {
      final entry = homebrewRepo.create('feat', 'Test Homebrew Feat');
      final torvek = charactersRepo.byId('torvek');
      torvek.feats.add(
        GrantedFeature(name: 'Test Homebrew Feat', source: 'homebrew'),
      );

      await tester.pumpWidget(const DndSheetApp());
      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Reference'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Homebrew'));
      await tester.pumpAndSettle();

      expect(find.text('Test Homebrew Feat'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      expect(find.text('Delete Test Homebrew Feat?'), findsOneWidget);
      expect(find.textContaining('Used by Torvek'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Test Homebrew Feat'), findsOneWidget);
      expect(homebrewRepo.entries.any((e) => e.id == entry.id), isTrue);
    },
  );

  testWidgets(
    "a homebrew feat named exactly like a real feat shows the override warning banner, a uniquely-named one doesn't",
    (WidgetTester tester) async {
      final collision = homebrewRepo.create('feat', 'Alert');
      final unique = homebrewRepo.create('feat', 'Totally Unique Feat Name');

      await tester.pumpWidget(
        MaterialApp(home: HomebrewEditScreen(entry: collision)),
      );
      expect(find.byIcon(Icons.warning_amber_outlined), findsOneWidget);
      expect(find.textContaining('will be used instead'), findsOneWidget);

      await tester.pumpWidget(
        MaterialApp(home: HomebrewEditScreen(entry: unique)),
      );
      expect(find.byIcon(Icons.warning_amber_outlined), findsNothing);
    },
  );

  testWidgets(
    'the formula term editor renders a multi-term formula as chips and removing one recomposes the formula correctly',
    (WidgetTester tester) async {
      // The Effects section (with its formula chips) sits below Source/
      // Description and is off the default 600px test viewport - a plain
      // ListView only builds elements within its viewport + cache extent,
      // so enlarge it rather than juggle scroll positions.
      tester.view.physicalSize = const Size(1080, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      // Simulates an effect saved before the term editor existed (or
      // imported from elsewhere) - a real multi-term formula in the raw
      // string shape rules.evaluateFormula expects. HomebrewEntry is
      // immutable, so the widget must be built from the entry update()
      // returns/stores, not the pre-update local.
      final created = homebrewRepo.create('feat', 'Multi Term Feat');
      homebrewRepo.update(
        HomebrewEntry(
          id: created.id,
          kind: created.kind,
          name: created.name,
          effects: const [
            Effect(
              target: 'attackRoll',
              formula: '8 + Proficiency Bonus + Constitution modifier',
            ),
          ],
        ),
      );
      final entry = homebrewRepo
          .byKind('feat')
          .firstWhere((e) => e.id == created.id);

      await tester.pumpWidget(
        MaterialApp(home: HomebrewEditScreen(entry: entry)),
      );

      // Each term renders as its own chip.
      expect(find.text('+ 8'), findsOneWidget);
      expect(find.text('+ Proficiency Bonus'), findsOneWidget);
      expect(find.text('+ Constitution modifier'), findsOneWidget);

      // Delete the flat "8" term via its chip's delete icon - the label
      // itself has no icon, so the only Icon inside the chip is the
      // delete affordance.
      final eightChip = find.ancestor(
        of: find.text('+ 8'),
        matching: find.byType(InputChip),
      );
      await tester.tap(
        find.descendant(of: eightChip, matching: find.byType(Icon)),
      );
      await tester.pumpAndSettle();

      expect(find.text('+ 8'), findsNothing);
      expect(find.text('+ Proficiency Bonus'), findsOneWidget);
      expect(find.text('+ Constitution modifier'), findsOneWidget);

      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      final saved = homebrewRepo
          .byKind('feat')
          .firstWhere((e) => e.id == entry.id);
      expect(
        saved.effects.first.formula,
        'Proficiency Bonus + Constitution modifier',
      );
    },
  );

  testWidgets(
    'tapping + Add on My Homebrew creates an entry of the chosen kind and opens it in the editor',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: HomebrewListScreen()));

      // Empty-state copy points at the new "+ Add" affordance.
      expect(find.textContaining('Tap "+ Add"'), findsOneWidget);

      await tester.tap(find.text('+ Add'));
      await tester.pumpAndSettle();

      // Defaults to 'feat' - switch the kind to 'magicItem' to confirm the
      // dropdown selection actually drives what gets created.
      await tester.tap(find.text('Feats'));
      await tester.pumpAndSettle();
      // The kind list is longer than the menu - scroll the item into view.
      await tester.ensureVisible(find.text('Magic Items').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Magic Items').last);
      await tester.pumpAndSettle();

      await tester.enterText(
        find.widgetWithText(TextField, 'Name'),
        'Bottomless Tankard',
      );
      await tester.pump();
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      // Lands directly in the editor for the new entry.
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.text('Bottomless Tankard'),
        ),
        findsOneWidget,
      );
      final created = homebrewRepo.byKind('magicItem').single;
      expect(created.name, 'Bottomless Tankard');

      await tester.pageBack();
      await tester.pumpAndSettle();

      expect(find.text('Bottomless Tankard'), findsOneWidget);
      expect(find.text('MAGIC ITEMS'), findsOneWidget);
    },
  );

  testWidgets(
    'editing a character lets you pick an alignment from a real list and add/remove languages, instead of typing free text',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final torvek = charactersRepo.byId('torvek');
      expect(torvek.alignment, isNull);
      expect(torvek.languages, isEmpty);

      await tester.pumpWidget(
        MaterialApp(
          home: CharacterFormScreen(
            mode: CharacterFormMode.edit,
            character: torvek,
          ),
        ),
      );

      // Alignment: a dropdown over the real 9 alignments, not a text field.
      await tester.tap(find.text('None').last);
      await tester.pumpAndSettle();
      final realAlignment = srdCatalog.alignments.first.name;
      await tester.tap(find.text(realAlignment).last);
      await tester.pumpAndSettle();

      // Languages: pick one from the real SRD list via the picker.
      await tester.tap(find.text('Add Language'));
      await tester.pumpAndSettle();
      final firstLanguage = srdCatalog.languages.first.name;
      await tester.tap(find.text(firstLanguage));
      await tester.pumpAndSettle();
      expect(find.text(firstLanguage), findsOneWidget);

      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(torvek.alignment, realAlignment);
      expect(torvek.languages, [firstLanguage]);
    },
  );

  testWidgets(
    "editing a character resolves their background's tool proficiency choice via a chip picker, retroactively",
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final torvek = charactersRepo.byId('torvek');
      expect(torvek.backgroundKey, isNotNull);
      expect(torvek.toolProficiencyChoices, isEmpty);

      await tester.pumpWidget(
        MaterialApp(
          home: CharacterFormScreen(
            mode: CharacterFormMode.edit,
            character: torvek,
          ),
        ),
      );

      // Soldier's real choice: one kind of Gaming Set.
      expect(find.textContaining('CHOOSE 1'), findsOneWidget);
      await tester.tap(find.text('Dice'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(torvek.toolProficiencyChoices, ['Dice']);
    },
  );

  testWidgets(
    'editing a character can record a free-text tool proficiency for a choice with no fixed option list',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final torvek = charactersRepo.byId('torvek');

      await tester.pumpWidget(
        MaterialApp(
          home: CharacterFormScreen(
            mode: CharacterFormMode.edit,
            character: torvek,
          ),
        ),
      );

      final labelFinder = find.text('OTHER TOOL PROFICIENCY (OPTIONAL)');
      final fieldFinder = find.descendant(
        of: find.ancestor(of: labelFinder, matching: find.byType(Column)).first,
        matching: find.byType(TextField),
      );
      await tester.enterText(fieldFinder, "Artisan's Tools");
      await tester.tap(find.text('Save Changes'));
      await tester.pumpAndSettle();

      expect(torvek.toolProficiencyChoices, ["Artisan's Tools"]);
    },
  );

  testWidgets(
    'a Pending Choice saved before "asi" existed as a kind (kind: null) still gets the direct ASI-or-Feat dialog, matched by its label instead',
    (WidgetTester tester) async {
      final torvek = charactersRepo.byId('torvek');
      // Simulates a character whose Pending Choice was created and
      // persisted by an older build of the app, before PendingChoice.kind
      // supported 'asi' - reinstalling/updating never rewrites data
      // already saved to the device.
      final legacyChoice = PendingChoice(
        id: 'legacy-asi-4',
        label: 'Level 4: Ability Score Improvement',
      );
      expect(legacyChoice.kind, isNull);
      torvek.pendingChoices = [legacyChoice];

      await tester.pumpWidget(const DndSheetApp());
      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Features'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();

      // The direct choice, not the old generic feat browser.
      expect(find.text('Choose a Feat'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Ability Score Improvement'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'resolving an Ability Score Improvement Pending Choice offers a direct "ASI or a Feat?" choice instead of a feat browser',
    (WidgetTester tester) async {
      final torvek = charactersRepo.byId('torvek');
      torvek.level = 3;
      final asiChoice = rules.pendingChoicesForLevelUp(torvek, 3, 4).single;
      expect(asiChoice.kind, 'asi');
      torvek.level = 4;
      torvek.pendingChoices = [asiChoice];
      final beforeStr = torvek.abilityScores.str;

      await tester.pumpWidget(const DndSheetApp());
      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Features'));
      await tester.pumpAndSettle();

      expect(find.text(asiChoice.label), findsOneWidget);
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();

      // The direct choice, not a search screen over every feat in the SRD.
      expect(find.text('Choose a Feat'), findsOneWidget);
      expect(
        find.widgetWithText(FilledButton, 'Ability Score Improvement'),
        findsOneWidget,
      );

      // Taking the ASI opens the +2/+1+1 split dialog directly.
      await tester.tap(
        find.widgetWithText(FilledButton, 'Ability Score Improvement'),
      );
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Increase one ability by 2, or two abilities by 1 each (max 20).',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();

      expect(
        torvek.feats.any((f) => f.name == 'Ability Score Improvement'),
        isTrue,
      );
      expect(torvek.pendingChoices, isEmpty);
      // Default dialog selection is +2 Strength - clamped at 20 (19 + 2
      // would be 21), same as AbilityScores.increase always clamps.
      expect(beforeStr, 19);
      expect(torvek.abilityScores.str, 20);
    },
  );

  testWidgets(
    'choosing "Choose a Feat" instead opens the General Feat picker, with Ability Score Improvement excluded (it already has its own button)',
    (WidgetTester tester) async {
      final torvek = charactersRepo.byId('torvek');
      torvek.level = 3;
      final asiChoice = rules.pendingChoicesForLevelUp(torvek, 3, 4).single;
      torvek.level = 4;
      torvek.pendingChoices = [asiChoice];

      await tester.pumpWidget(const DndSheetApp());
      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Features'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose a Feat'));
      await tester.pumpAndSettle();

      expect(find.text('Feat'), findsOneWidget); // the picker's AppBar title
      // Ability Score Improvement is a real General Feat catalog entry,
      // but is deliberately hidden from this list since the previous
      // screen already offers it as its own dedicated button - search for
      // it directly rather than scrolling to find it.
      expect(find.text('Ability Score Improvement'), findsNothing);
      await tester.enterText(find.byType(TextField), 'Ability Score');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches that search.'), findsOneWidget);

      // Alert, a real General Feat, is still a valid pick.
      await tester.enterText(find.byType(TextField), 'Alert');
      await tester.pumpAndSettle();
      expect(find.text('Alert'), findsOneWidget);
    },
  );

  testWidgets(
    'a category-restricted feat picker only offers homebrew feats tagged with that same category, and quick-adding one there stamps it automatically',
    (WidgetTester tester) async {
      homebrewRepo.create('feat', 'Homebrew General Pick');
      homebrewRepo.update(
        HomebrewEntry(
          id: homebrewRepo.byKind('feat').single.id,
          kind: 'feat',
          name: 'Homebrew General Pick',
          category: 'General Feat',
        ),
      );
      homebrewRepo.create('feat', 'Homebrew Style Pick');
      homebrewRepo.update(
        HomebrewEntry(
          id: homebrewRepo
              .byKind('feat')
              .firstWhere((e) => e.name == 'Homebrew Style Pick')
              .id,
          kind: 'feat',
          name: 'Homebrew Style Pick',
          category: 'Fighting Style Feat',
        ),
      );
      homebrewRepo.create('feat', 'Homebrew Uncategorized Pick');

      final torvek = charactersRepo.byId('torvek');
      torvek.level = 3;
      final asiChoice = rules.pendingChoicesForLevelUp(torvek, 3, 4).single;
      torvek.level = 4;
      torvek.pendingChoices = [asiChoice];

      await tester.pumpWidget(const DndSheetApp());
      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Features'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose a Feat')); // category: General Feat
      await tester.pumpAndSettle();

      // Only the General-Feat-tagged homebrew entry shows up here - the
      // Fighting-Style-tagged and uncategorized ones don't belong in a
      // General Feat list.
      expect(find.text('Homebrew General Pick'), findsOneWidget);
      expect(find.text('Homebrew Style Pick'), findsNothing);
      expect(find.text('Homebrew Uncategorized Pick'), findsNothing);

      // Quick-adding a brand-new one from inside this restricted picker
      // tags it with the same category automatically.
      await tester.enterText(find.byType(TextField), 'Fresh Homebrew Feat');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add "Fresh Homebrew Feat" as homebrew'));
      await tester.pumpAndSettle();

      final created = homebrewRepo
          .byKind('feat')
          .firstWhere((e) => e.name == 'Fresh Homebrew Feat');
      expect(created.category, 'General Feat');
    },
  );

  testWidgets(
    'New Character defaults the ability score fields to the Standard Array by Class once a class is picked',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const DndSheetApp());
      await tester.tap(find.text('+ New Character'));
      await tester.pumpAndSettle();

      // Untouched, before any class is chosen: every field still shows
      // the plain "10" it starts with.
      expect(find.widgetWithText(TextField, '10'), findsNWidgets(6));

      await tester.tap(find.text('Choose a class…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fighter'));
      await tester.pumpAndSettle();

      // Fighter's Standard Array assignment: Str 15, Dex 14, Con 13, Int
      // 8, Wis 10, Cha 12 - straight from the bundled SRD's own table.
      expect(find.widgetWithText(TextField, '15'), findsOneWidget);
      expect(find.widgetWithText(TextField, '14'), findsOneWidget);
      expect(find.widgetWithText(TextField, '13'), findsOneWidget);
      expect(find.widgetWithText(TextField, '8'), findsOneWidget);
      expect(find.widgetWithText(TextField, '10'), findsOneWidget);
      expect(find.widgetWithText(TextField, '12'), findsOneWidget);

      // Still freely editable afterward - this is a default, not a lock.
      await tester.enterText(find.widgetWithText(TextField, '15'), '18');
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, '18'), findsOneWidget);
    },
  );

  testWidgets(
    'New Character asks for a species with an embedded choice table (Dragonborn Draconic Ancestry) up front, and refuses to create without an answer',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 3400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const DndSheetApp());
      await tester.tap(find.text('+ New Character'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose a species…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dragonborn'));
      await tester.pumpAndSettle();

      // The species' own embedded choice table shows up immediately,
      // right on the New Character form - not left for the player to
      // discover later on the sheet.
      expect(find.text('DRACONIC ANCESTORS'), findsOneWidget);
      expect(find.text('Red — Fire'), findsOneWidget);

      await tester.tap(find.text('Choose a background…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Soldier'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose a class…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Fighter'));
      await tester.pumpAndSettle();

      // Character Name is the first TextField on the create form (the
      // species/background/class pickers above it aren't TextFields).
      await tester.enterText(find.byType(TextField).first, 'Ancestry Test');
      await tester.tap(find.text('Athletics'));
      await tester.tap(find.text('Perception'));
      await tester.pumpAndSettle();
      // Class and background starting equipment, and the background's
      // ability score increases.
      await tester.tap(find.textContaining('(A)').at(0));
      await tester.tap(find.textContaining('(A)').at(1));
      await tester.tap(find.text('+1 / +1 / +1'));
      await tester.pumpAndSettle();

      // Every other required field is filled in, but Draconic Ancestors
      // isn't picked yet - creation is refused with a specific message,
      // not silently allowed to proceed with speciesChoice left null.
      await tester.tap(find.text('Create Character'));
      await tester.pumpAndSettle();
      expect(find.text('Choose your Draconic Ancestors.'), findsOneWidget);
      expect(charactersRepo.characters.length, 1); // still just Torvek

      await tester.tap(find.text('Red — Fire'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Create Character'));
      await tester.pumpAndSettle();

      final created = charactersRepo.characters.firstWhere(
        (c) => c.name == 'Ancestry Test',
      );
      expect(created.speciesChoice, 'Red');
      expect(created.speciesLabel, 'Red · Fire');
    },
  );

  testWidgets(
    'unequipping armor logs a History entry with the before/after AC, auditable later on the Overview tab',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final torvek = charactersRepo.byId('torvek');
      final beforeAc = rules.armorClassFor(torvek);
      expect(torvek.history, isEmpty);

      await tester.pumpWidget(const DndSheetApp());
      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Items'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline).first);
      await tester.pumpAndSettle();

      final afterAc = rules.armorClassFor(torvek);
      expect(torvek.equippedArmor, isNull);
      expect(torvek.history, hasLength(1));
      expect(torvek.history.first.label, 'Unequipped Half Plate Armor');
      expect(torvek.history.first.detail, 'AC: $beforeAc → $afterAc.');

      // Auditable afterward from the Overview tab's History section.
      await tester.tap(find.text('Overview'));
      await tester.pumpAndSettle();
      expect(find.text('Unequipped Half Plate Armor'), findsOneWidget);
      await tester.tap(find.text('Unequipped Half Plate Armor'));
      await tester.pumpAndSettle();
      expect(find.text('AC: $beforeAc → $afterAc.'), findsOneWidget);
    },
  );

  testWidgets(
    'the Spells tab shows save DC/attack, and casting a Concentration spell spends the chosen slot and shows the Concentration banner',
    (WidgetTester tester) async {
      final wizard = charactersRepo.characters.single
        ..classKey = 'srd-2024_wizard-class'
        ..level = 5;
      rules.enableSpellcasting(wizard);
      final bless = srdCatalog.spells.firstWhere((s) => s.name == 'Bless');
      wizard.spellcasting!.spells = [KnownSpell(spellKey: bless.key)];

      await tester.pumpWidget(const DndSheetApp());
      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Spells'));
      await tester.pumpAndSettle();

      expect(find.text('Save DC'), findsOneWidget);
      expect(find.text('${rules.spellSaveDc(wizard)}'), findsOneWidget);
      expect(find.textContaining('PREPARED SPELLS (1/9)'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('Bless'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      await tester.tap(find.widgetWithText(TextButton, 'Cast'));
      await tester.pumpAndSettle();
      expect(find.text('Cast Bless'), findsOneWidget);

      // Upcast with a level 2 slot instead of the default level 1.
      await tester.tap(find.text('Level 2 (3 left)'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Cast'));
      await tester.pumpAndSettle();

      expect(wizard.spellcasting!.slots[1]!.used, 0);
      expect(wizard.spellcasting!.slots[2]!.used, 1);
      expect(wizard.spellcasting!.concentratingOn, bless.key);

      await tester.dragUntilVisible(
        find.text('Concentrating on Bless'),
        find.byType(ListView),
        const Offset(0, 300),
      );
      await tester.tap(find.widgetWithText(TextButton, 'End'));
      await tester.pumpAndSettle();
      expect(wizard.spellcasting!.concentratingOn, isNull);
    },
  );

  testWidgets(
    "editing a feature's PDF sheet text on the Features tab saves it for every character with that feature",
    (WidgetTester tester) async {
      sheetTextRepo.overrides.clear();
      await tester.pumpWidget(const DndSheetApp());
      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Features'));
      await tester.pumpAndSettle();

      await tester.dragUntilVisible(
        find.text('Extra Attack'),
        find.byType(ListView),
        const Offset(0, -300),
      );
      // Collapsed rows still build their (hidden) bodies, so look only
      // inside Extra Attack's own row.
      final row = find.ancestor(
        of: find.text('Extra Attack'),
        matching: find.byType(ExpandableRow),
      );
      Finder inRow(Finder f) => find.descendant(of: row, matching: f);
      await tester.tap(find.text('Extra Attack'));
      await tester.pumpAndSettle();
      expect(inRow(find.text('ON THE PDF SHEET')), findsOneWidget);
      expect(
        inRow(find.text('Attack twice when you take the Attack action.')),
        findsOneWidget,
      );

      await tester.tap(inRow(find.widgetWithText(TextButton, 'Edit')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Two swings per Attack.');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(inRow(find.text('ON THE PDF SHEET · EDITED')), findsOneWidget);
      expect(inRow(find.text('Two swings per Attack.')), findsOneWidget);
      expect(
        sheetTextRepo['srd-2024_fighter-class|Extra Attack'],
        'Two swings per Attack.',
      );
      sheetTextRepo.overrides.clear();
    },
  );

  testWidgets(
    'Level Up lets you record a Hit Die roll instead of the average',
    (WidgetTester tester) async {
      final torvek = charactersRepo.characters.single;
      final before = torvek.maxHp;
      await tester.pumpWidget(const DndSheetApp());
      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Level Up'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Take the average: 6'), findsOneWidget);
      await tester.tap(find.text('I rolled: '));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(DropdownButton<int>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('9').last);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Level Up'));
      await tester.pumpAndSettle();

      final leveled = charactersRepo.characters.firstWhere(
        (c) => c.isCurrent && c.name == 'Torvek',
      );
      expect(leveled.level, 10);
      expect(leveled.hitPointRolls[10], 9);
      expect(leveled.maxHp, before + 9 + 2);
    },
  );

  testWidgets(
    'on a wide window the sheet uses a side rail with My Characters at its top, and Reference shows categories beside their entries',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const DndSheetApp());
      await tester.tap(find.text('Torvek').first);
      await tester.pumpAndSettle();

      expect(find.byType(NavigationRail), findsOneWidget);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      await tester.tap(find.text('Spells'));
      await tester.pumpAndSettle();
      expect(find.text('Enable Spellcasting'), findsOneWidget);

      // Reference: categories on the left, entries on the right.
      await tester.tap(find.byTooltip('Reference'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Species'));
      await tester.pumpAndSettle();
      expect(find.text('Dwarf'), findsOneWidget);
      await tester.tap(find.text('Back'));
      await tester.pumpAndSettle();

      // My Characters, from the top of the rail.
      await tester.tap(find.text('My Characters').last);
      await tester.pumpAndSettle();
      expect(find.text('+ New Character'), findsOneWidget);
    },
  );
}
