import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:dnd_sheet/widgets/markdown_text.dart';

void main() {
  Future<void> pump(WidgetTester tester, String data) =>
      tester.pumpWidget(MaterialApp(home: Scaffold(body: MarkdownText(data))));

  testWidgets(
    'renders **bold** text with the asterisks stripped and bold style applied',
    (tester) async {
      await pump(tester, '**Audible Alarm.** The alarm produces a sound.');

      expect(find.textContaining('**'), findsNothing);
      final span = tester.widget<Text>(find.byType(Text).first).textSpan!;
      final boldSpan = (span as TextSpan).children!.first as TextSpan;
      expect(boldSpan.text, 'Audible Alarm.');
      expect(boldSpan.style!.fontWeight, FontWeight.bold);
    },
  );

  testWidgets(
    'renders _italic_ text with the underscores stripped and italic style applied',
    (tester) async {
      await pump(tester, '_Damage Resistance._ You have Resistance.');

      expect(find.textContaining('_Damage'), findsNothing);
      final span = tester.widget<Text>(find.byType(Text).first).textSpan!;
      final italicSpan = (span as TextSpan).children!.first as TextSpan;
      expect(italicSpan.text, 'Damage Resistance.');
      expect(italicSpan.style!.fontStyle, FontStyle.italic);
    },
  );

  testWidgets(
    'renders a "- " bullet block as one bullet per line, dashes stripped',
    (tester) async {
      await pump(
        tester,
        '- Make an attack roll against an enemy.\n- Force an enemy to make a saving throw.',
      );

      expect(find.text('•  '), findsNWidgets(2));
      expect(
        find.textContaining('Make an attack roll against an enemy.'),
        findsOneWidget,
      );
      expect(find.textContaining('- Make'), findsNothing);
    },
  );

  testWidgets('renders a "##"/"###" header as bold text, hashes stripped', (
    tester,
  ) async {
    await pump(tester, '### Bard Spell List\n\nSome text below it.');

    expect(find.text('Bard Spell List'), findsOneWidget);
    expect(find.textContaining('###'), findsNothing);
    final headerText = tester.widget<Text>(find.text('Bard Spell List'));
    expect(headerText.style!.fontWeight, FontWeight.bold);
  });

  testWidgets('plain text with no markdown renders unchanged', (tester) async {
    await pump(tester, 'Just a plain sentence with no markup.');

    expect(
      find.textContaining('Just a plain sentence with no markup.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'renders **_bold italic_** as a single span with both styles, markers stripped',
    (tester) async {
      await pump(tester, '**_Flurry of Blows._** You can spend Focus Points.');

      expect(find.textContaining('**_'), findsNothing);
      expect(find.textContaining('_**'), findsNothing);
      final span = tester.widget<Text>(find.byType(Text).first).textSpan!;
      final combinedSpan = (span as TextSpan).children!.first as TextSpan;
      expect(combinedSpan.text, 'Flurry of Blows.');
      expect(combinedSpan.style!.fontWeight, FontWeight.bold);
      expect(combinedSpan.style!.fontStyle, FontStyle.italic);
    },
  );

  testWidgets(
    'renders an HTML <table> as a real Table, tags stripped, header bolded',
    (tester) async {
      await pump(tester, '''
Some intro text.

<table>
  <thead>
    <tr>
      <th>Spell</th>
      <th>School</th>
    </tr>
  </thead>
  <tbody>
    <tr>
      <td>Light</td>
      <td>Evocation</td>
    </tr>
    <tr>
      <td>Mending</td>
      <td>Transmutation</td>
    </tr>
  </tbody>
</table>
''');

      expect(find.textContaining('<table'), findsNothing);
      expect(find.textContaining('<tr>'), findsNothing);
      expect(find.byType(Table), findsOneWidget);
      expect(find.text('Spell'), findsOneWidget);
      expect(find.text('Light'), findsOneWidget);
      expect(find.text('Mending'), findsOneWidget);
      expect(find.text('Some intro text.'), findsOneWidget);

      final header = tester.widget<Text>(find.text('Spell'));
      expect(header.style!.fontWeight, FontWeight.bold);
      final cell = tester.widget<Text>(find.text('Light'));
      expect(cell.style!.fontWeight, isNot(FontWeight.bold));
    },
  );

  testWidgets(
    'renders a "> " blockquote callout with the markers stripped, bold title and body as separate paragraphs, and a left rule',
    (tester) async {
      await pump(
        tester,
        '> **Unaligned Creatures**\n>\n> Sharks are savage predators, but they aren\'t evil; they are unaligned.',
      );

      expect(find.textContaining('>'), findsNothing);
      expect(find.text('Unaligned Creatures'), findsOneWidget);
      final titleText = tester.widget<Text>(find.text('Unaligned Creatures'));
      final titleSpan =
          (titleText.textSpan! as TextSpan).children!.first as TextSpan;
      expect(titleSpan.style!.fontWeight, FontWeight.bold);
      expect(
        find.textContaining('Sharks are savage predators'),
        findsOneWidget,
      );

      // Rendered as its own bordered block, not inline with surrounding
      // text - a Container with a left BorderSide is the marker.
      final container = tester.widget<Container>(find.byType(Container).first);
      final border = (container.decoration! as BoxDecoration).border! as Border;
      expect(border.left.width, greaterThan(0));
    },
  );

  testWidgets(
    'a "> ### Header" inside a blockquote still renders as a header, not literal text',
    (tester) async {
      await pump(tester, '> ### Breaking Your Oath\n>\n> Details here.');

      expect(find.text('Breaking Your Oath'), findsOneWidget);
      expect(find.textContaining('###'), findsNothing);
      final headerText = tester.widget<Text>(find.text('Breaking Your Oath'));
      expect(headerText.style!.fontWeight, FontWeight.bold);
    },
  );
}
