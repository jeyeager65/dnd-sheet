import 'dart:typed_data';
import 'dart:ui';

import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../data/official_sheet_cache.dart';
import '../data/srd_catalog.dart';
import '../models/character.dart';
import 'rules.dart' as rules;

/// One value's placement on page 1 of the official sheet - [x]/[top] are
/// in PDF points from the page's top-left corner (matching the sheet's
/// own 603x774pt page size), [top] being where the text's baseline sits,
/// same convention pdfplumber reports label positions in. Coordinates
/// below were found by extracting the official PDF's own label
/// positions (pdfplumber) and verified by rendering a sample-filled copy
/// to an image and checking it by eye - see the PDF export feasibility
/// discussion for how. There's no AcroForm in the official PDF (checked:
/// zero form fields) - every value here is drawn as new content on top
/// of the existing page, the same as printing it and filling it in by
/// hand.
class _Field {
  const _Field(
    this.x,
    this.top,
    this.fontSize, {
    this.align = PdfTextAlignment.left,
    this.width = 140,
  });
  final double x;
  final double top;
  final double fontSize;
  final PdfTextAlignment align;
  final double width;
}

/// Covers the top section (name/species/background/class/subclass/level,
/// AC/HP/Hit Dice, Proficiency Bonus, Initiative/Speed/Passive
/// Perception, Size, the six ability score blocks, all 6 Saving Throws and
/// 18 Skills), the WEAPONS & DAMAGE CANTRIPS table (weapons, innate
/// attacks, then damage cantrips), and the CLASS FEATURES/
/// SPECIES TRAITS/FEATS boxes (flowing name + short sheet text, shrunk
/// as needed to fit inside each box rather than overflowing it - see
/// [_drawFlowingBoxes]). Page 2 (spellcasting, appearance, backstory,
/// languages, equipment) is filled by [_fillPageTwo]. XP has
/// no field in this app's data model at all (not tracked anywhere, not
/// just unmapped here) so it's left blank rather than guessed; Death
/// Saves need per-pip coordinates (3 diamonds x 2 rows) not yet mapped, so
/// they're deferred too.
// The identity block (name/background/class/species/subclass/level/xp) is
// a ruled form, same as HIT POINTS/HIT DICE below it: a horizontal rule
// line, with the printed caption sitting right at/below that line -
// meaning the value belongs ABOVE the line, in the blank band between it
// and the row above, not inline next to the caption. Measured directly
// from the sheet's own rule lines (pdfplumber line extraction), same as
// every other coordinate here - the first pass had this block wrong,
// drawing values at the caption's own baseline instead.
const _fields = {
  'name': _Field(26, 27, 11, width: 220),
  'background': _Field(26, 48, 10, width: 115),
  'class': _Field(150, 48, 10, width: 95),
  'species': _Field(26, 70, 10, width: 115),
  'subclass': _Field(150, 70, 10, width: 105),
  'level': _Field(276, 44, 13, align: PdfTextAlignment.center, width: 30),
  // XP sits under LEVEL on the same kind of rule line (y 68.0, x 258.7-
  // 294.2), so the same "value above the line" placement.
  'xp': _Field(276.5, 65, 8, align: PdfTextAlignment.center, width: 36),

  'ac': _Field(339, 57, 22, align: PdfTextAlignment.center, width: 40),

  // TEMP HIT POINTS (448, 48) is deliberately never drawn - it changes in
  // play and gets pencilled in, like Current HP.
  'hpMax': _Field(446, 70, 14, align: PdfTextAlignment.center, width: 30),
  // A reference line under the HIT DICE heading (e.g. "d10 +2") - the die
  // and Constitution modifier used to heal when spending a Hit Die, since
  // neither is written anywhere else on this sheet.
  'hitDiceRef': _Field(509, 34, 9, align: PdfTextAlignment.center, width: 40),
  'hdMax': _Field(500, 70, 14, align: PdfTextAlignment.center, width: 30),

  // Was (120, 290) - measured against the actual icon graphic (a grid
  // overlay on the rendered page, not eyeballed like the original guess)
  // and found to be off by ~60pt right and ~140pt down; the icon itself
  // sits directly under the "PROFICIENCY BONUS" label, not lower down
  // the column.
  'proficiencyBonus': _Field(
    58,
    158,
    16,
    align: PdfTextAlignment.center,
    width: 40,
  ),

  'initiative': _Field(
    262.6,
    145,
    14,
    align: PdfTextAlignment.center,
    width: 50,
  ),
  'speed': _Field(356.2, 145, 14, align: PdfTextAlignment.center, width: 60),
  'size': _Field(451.2, 145, 14, align: PdfTextAlignment.center, width: 60),
  'passivePerception': _Field(
    546.6,
    145,
    14,
    align: PdfTextAlignment.center,
    width: 50,
  ),
};

/// Ability blocks: name -> (label's left edge, label's right edge,
/// label's baseline `top`) - the modifier/score bubbles sit a fixed
/// offset below each ability name label, verified the same way as
/// [_fields].
const _abilityBlocks = {
  'str': (36.7, 77.9, 193.9),
  'dex': (36.9, 77.5, 311.7),
  'con': (27.8, 86.8, 457.6),
  'int': (136.1, 190.9, 116.6),
  'wis': (146.8, 180.2, 290.5),
  'cha': (143.3, 183.6, 464.4),
};

/// One Saving Throw or Skill row: the governing ability, the skill name
/// (null for the ability's own Saving Throw row), the row's `top`
/// (matching the name label's own baseline - measured the same way as
/// every other coordinate here), and which of the two ability columns
/// (STR/DEX/CON on the left, INT/WIS/CHA on the right) it's in - the
/// proficiency circle and value both sit at a fixed x offset that only
/// depends on which column, not the individual row.
typedef _SkillRow = (
  String abilityKey,
  String? skillName,
  double top,
  bool leftColumn,
);

const _skillRows = <_SkillRow>[
  ('str', null, 262.2, true),
  ('str', 'Athletics', 282.2, true),
  ('dex', null, 380.0, true),
  ('dex', 'Acrobatics', 400.0, true),
  ('dex', 'Sleight of Hand', 414.0, true),
  ('dex', 'Stealth', 428.0, true),
  ('con', null, 525.9, true),
  ('int', null, 184.9, false),
  ('int', 'Arcana', 204.9, false),
  ('int', 'History', 218.9, false),
  ('int', 'Investigation', 232.9, false),
  ('int', 'Nature', 246.9, false),
  ('int', 'Religion', 260.9, false),
  ('wis', null, 358.8, false),
  ('wis', 'Animal Handling', 378.7, false),
  ('wis', 'Insight', 392.7, false),
  ('wis', 'Medicine', 406.7, false),
  ('wis', 'Perception', 420.7, false),
  ('wis', 'Survival', 434.7, false),
  ('cha', null, 532.7, false),
  ('cha', 'Deception', 552.7, false),
  ('cha', 'Intimidation', 566.7, false),
  ('cha', 'Performance', 580.7, false),
  ('cha', 'Persuasion', 594.7, false),
];

/// Center x of the proficiency circle and of the value's own small write
/// space, one pair per column - measured against the printed circle
/// outlines and the gap between them and the row's name text.
const _leftCircleX = 21.5;
const _leftValueX = 34.0;
const _rightCircleX = 127.8;
const _rightValueX = 142.0;

/// WEAPONS & DAMAGE CANTRIPS table - column left edges (a trailing entry
/// closes the last column) and the `top` of each ruled write-on line,
/// both measured the same way as [_fields] (pdfplumber line/word
/// extraction, cross-checked against the rendered page). Same "value
/// above the line" convention as the identity block/HIT POINTS.
const _weaponsColumnEdges = [228.2, 334.4, 382.1, 460.0, 586.8];
const _weaponsRowLines = [212.6, 232.1, 251.5, 271.0, 290.4, 309.8];

/// CLASS FEATURES/SPECIES TRAITS/FEATS boxes - each entry is (left,
/// contentTop, right, bottom), matched against the boxes' own printed
/// borders (pdfplumber line extraction, cross-checked visually - the
/// faint grid filling these boxes is decorative background texture, not
/// a functional per-line ruling, so text flows freely rather than
/// snapping to it). CLASS FEATURES has two columns, matching the
/// printed vertical divider; the other two boxes are single-column.
// The columns' bottom is where the printed divider between them stops
// (y ~552; the box's own bottom border is at ~558) - it was 583, which is
// below the border, inside the SPECIES TRAITS heading's band, so a full
// column spilled over it.
const _classFeaturesCol1 = (229.0, 350.0, 400.0, 552.0);
const _classFeaturesCol2 = (414.0, 350.0, 584.0, 552.0);
const _speciesTraitsBox = (229.0, 594.0, 392.0, 766.0);
const _featsBox = (414.0, 594.0, 584.0, 766.0);

/// EQUIPMENT TRAINING & PROFICIENCIES - the 4 Armor Training diamond icon
/// centers (Light/Medium/Heavy/Shields, in that order), and the free-form
/// text areas below the WEAPONS/TOOLS labels, all measured the same way
/// as everything else here.
const _armorTrainingDiamonds = [
  (63.15, 648.6),
  (97.25, 648.6),
  (141.45, 648.6),
  (178.75, 648.6),
];
const _weaponProficiencyArea = (16.0, 672.0, 207.0, 715.0);
const _toolProficiencyArea = (16.0, 732.0, 207.0, 764.0);

/// Page 2's free-text boxes (measured the same way as page 1's) -
/// APPEARANCE, BACKSTORY & PERSONALITY (with the ALIGNMENT label sharing
/// its box, drawn inline as its own [_Field] rather than a wrapped area),
/// LANGUAGES, and EQUIPMENT (with its MAGIC ITEM ATTUNEMENT sub-list -
/// three pre-printed lines, one per attuned item, matching the real 5e
/// 3-item attunement cap). COINS is still future work; the spellcasting
/// block is below.
const _appearanceArea = (411.4, 32.0, 586.8, 115.0);
const _backstoryArea = (411.4, 138.0, 586.8, 277.0);
const _alignmentField = _Field(415.0, 301.0, 9, width: 170);
const _languagesArea = (411.4, 341.0, 586.8, 376.0);
const _equipmentArea = (411.4, 409.0, 586.8, 585.0);
// Each attunement row's text sits beside its printed diamond (x 415.5-428.4,
// centered ~603/623/643), level with it rather than below its rule line.
const _attunementLineTops = [608.5, 628.5, 648.5];
const _attunementLineX = (433.0, 585.0);

/// COINS - the five boxes' centers, measured from their CP/SP/EP/GP/PP
/// labels' own x and the boxes' drawn outline (y ~705-724).
const _coinCenters = [
  ('cp', 428.4),
  ('sp', 464.2),
  ('ep', 499.6),
  ('gp', 534.8),
  ('pp', 569.9),
];
const _coinCenterY = 714.0;

const _attunementDiamonds = [(423.2, 603.25), (423.2, 623.25), (423.2, 643.25)];

/// Page 2's spellcasting block, measured the same way as everything else
/// here (pdfplumber rects/lines/curves, checked against a 10pt grid on
/// the rendered page). SPELLCASTING ABILITY is written above its rule
/// line (y 32.9); the modifier/save DC/attack bonus values are centered
/// in the three blank cells left of their labels (x 13-47, each row 27pt
/// tall).
const _spellcastingAbilityField = _Field(27, 31, 10, width: 104);
const _spellStatCenterX = 30.0;
const _spellModifierCenterY = 58.4;
const _spellSaveDcCenterY = 86.1;
const _spellAttackCenterY = 113.8;

/// SPELL SLOTS - the "Total" write-on line for each spell level: (center
/// x, line top). Three columns of three levels (1-3, 4-6, 7-9). The
/// "Expended" diamonds beside them are left blank, same as Current HP -
/// slots spent change in play.
const _slotTotalLines = {
  1: (189.0, 94.3),
  2: (189.0, 108.4),
  3: (189.0, 122.4),
  4: (277.1, 94.3),
  5: (277.1, 108.4),
  6: (277.1, 122.4),
  7: (355.6, 94.3),
  8: (355.6, 108.4),
  9: (355.6, 122.4),
};

/// CANTRIPS & PREPARED SPELLS - 30 ruled rows (the first line's top, then
/// a fixed pitch), each column's (left, right) edge, and the C/R/M
/// diamonds' center x - their center y sits a fixed offset above each
/// row's line.
const _spellRowFirstLine = 192.6;
const _spellRowPitch = 19.44;
const _spellRowCount = 30;
const _spellLevelColumn = (17.6, 37.8);
const _spellNameColumn = (42.4, 150.2);
const _spellCastingTimeColumn = (154.7, 184.1);
const _spellRangeColumn = (188.7, 229.8);
const _spellNotesColumn = (305.0, 390.8);
const _spellConcentrationDiamondX = 243.15;
const _spellRitualDiamondX = 265.03;
const _spellMaterialDiamondX = 286.72;
const _spellDiamondAboveLine = 7.48;

/// Strips this app's SRD source text down to plain text suitable for
/// drawing directly on the PDF - there's no rich-text rendering here
/// (unlike widgets/markdown_text.dart's full parser, built for a Flutter
/// widget tree this code doesn't have), just removing the markup
/// characters themselves so `**bold**`/`_italic_`/`<html>` tags don't
/// show up literally in the exported sheet the way they did for a
/// background's Tool Proficiencies text before this existed.
String _plainText(String text) {
  var result = text.replaceAll(RegExp(r'<[^>]+>'), '');
  result = result.replaceAllMapped(
    RegExp(r'\*\*_(.+?)_\*\*|\*\*(.+?)\*\*|_(.+?)_'),
    (m) => m.group(1) ?? m.group(2) ?? m.group(3) ?? '',
  );
  return result.trim();
}

/// The live SRD trait text for [attack] - resolved by name against the
/// character's own species traits, the same way rules.liveFeatureText
/// resolves a GrantedFeature's text, since InnateAttack has no equivalent
/// helper of its own. Falls back to the attack's stored `desc` for a
/// homebrew/uncataloged species or an unmatched name - that stored value
/// is documented as only a fallback in the first place (see
/// sample_data.dart's InnateAttack comment): the bundled SRD text is the
/// real source of truth wherever it resolves.
String _liveInnateAttackDesc(Character c, InnateAttack attack) {
  final species = c.speciesKey != null
      ? srdCatalog.speciesByKey[c.speciesKey]
      : null;
  for (final trait in species?.traits ?? const []) {
    if (trait.name == attack.name) return trait.desc;
  }
  return attack.desc;
}

/// Pulls a short area phrase ("15-foot Cone or a 30-foot Line") out of a
/// trait's full SRD text, for the weapons table's narrow Notes column -
/// read straight from the real bundled text rather than hand-typed, so it
/// can never drift from it. Returns '' if the text doesn't describe an
/// area in this recognized "a N-foot Shape" phrasing (most innate attacks
/// won't - this only matches what Breath Weapon's real SRD text says).
String _extractAreaPhrase(String desc) {
  final match = RegExp(
    r'in (?:either )?a (\d+-foot [A-Z][a-z]+(?: or a \d+-foot [A-Z][a-z]+)?)',
  ).firstMatch(desc);
  return match?.group(1) ?? '';
}

void _draw(PdfGraphics g, _Field f, String text) {
  if (text.isEmpty) return;
  final font = PdfStandardFont(PdfFontFamily.helvetica, f.fontSize);
  final left = f.align == PdfTextAlignment.center ? f.x - f.width / 2 : f.x;
  g.drawString(
    text,
    font,
    brush: PdfSolidBrush(PdfColor(30, 30, 30)),
    bounds: Rect.fromLTWH(left, f.top - f.fontSize, f.width, f.fontSize * 1.5),
    format: PdfStringFormat(alignment: f.align),
  );
}

/// Draws [text] word-wrapped inside [area] (left, top, right, bottom) -
/// used for every free-form block of prose on the sheet (Weapon/Tool
/// Proficiencies, and page 2's Appearance/Backstory/Languages/Equipment
/// boxes). `onePage` clips rather than spilling onto a new page if the
/// text runs long, since there's nowhere else on this sheet for it to go.
void _drawWrapped(
  PdfPage page,
  String text,
  (double, double, double, double) area, {
  double fontSize = 7.5,
}) {
  if (text.isEmpty) return;
  final (left, top, right, bottom) = area;
  PdfTextElement(
    text: text,
    font: PdfStandardFont(PdfFontFamily.helvetica, fontSize),
    brush: PdfSolidBrush(PdfColor(30, 30, 30)),
    format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
  ).draw(
    page: page,
    bounds: Rect.fromLTWH(left, top, right - left, bottom - top),
    format: PdfLayoutFormat(layoutType: PdfLayoutType.onePage),
  );
}

/// Same top-anchored placement as [_draw], but shrinks the font (down to
/// [minFontSize]) until [text] actually fits [maxWidth] - a weapon's full
/// name ("Sword of the Failed Dragon Slayer") can easily run past a
/// table cell's fixed printed width at the column's normal size, and
/// there's no room to widen the cell itself (it's bounded by the sheet's
/// own ruled lines). Cheaper than wrapping to a second line, which this
/// table has no vertical room for.
void _drawFitted(
  PdfGraphics g,
  double x,
  double top,
  double maxWidth,
  double baseFontSize,
  String text, {
  double minFontSize = 6,
}) {
  if (text.isEmpty) return;
  var size = baseFontSize;
  while (size > minFontSize) {
    final width = PdfStandardFont(
      PdfFontFamily.helvetica,
      size,
    ).measureString(text).width;
    if (width <= maxWidth) break;
    size -= 0.5;
  }
  _draw(g, _Field(x, top, size, width: maxWidth), text);
}

/// Font sizes tried, largest first, for the Features/Traits/Feats boxes -
/// each is the entry name's size; its description is drawn half a point
/// smaller.
const _flowingSizes = [8.0, 7.5, 7.0, 6.5, 6.0, 5.5];

PdfStringFormat get _wrapFormat =>
    PdfStringFormat(lineSpacing: 1, wordWrap: PdfWordWrapType.word);

/// How tall one entry (bold name line + wrapped description + gap below)
/// is at [nameSize], measured with the same fonts and wrapping it'll be
/// drawn with.
double _entryHeight(String desc, double width, double nameSize) {
  if (desc.isEmpty) return nameSize + 2 + 7;
  final descHeight = PdfStandardFont(
    PdfFontFamily.helvetica,
    nameSize - 0.5,
  ).measureString(desc, layoutArea: Size(width, 0), format: _wrapFormat).height;
  return nameSize + 2 + descHeight + 5;
}

/// Lays [entries] out top to bottom through [boxes] in order (Class
/// Features' two columns, or a single box) - an entry only starts where it
/// fits whole, otherwise it moves on to the next box. Draws them if [page]
/// is given; either way returns how many were placed.
int _placeFlowing(
  PdfPage? page,
  List<(String name, String desc)> entries,
  List<(double, double, double, double)> boxes,
  double nameSize,
) {
  final nameFont = PdfStandardFont(
    PdfFontFamily.helvetica,
    nameSize,
    style: PdfFontStyle.bold,
  );
  final descFont = PdfStandardFont(PdfFontFamily.helvetica, nameSize - 0.5);
  var placed = 0;
  for (final (left, top, right, bottom) in boxes) {
    final width = right - left;
    var y = top;
    while (placed < entries.length) {
      final (name, desc) = entries[placed];
      final height = _entryHeight(desc, width, nameSize);
      // The trailing gap may hang past the bottom; the text itself can't.
      if (y + height - 5 > bottom) break;
      if (page != null) {
        page.graphics.drawString(
          name,
          nameFont,
          brush: PdfSolidBrush(PdfColor(20, 20, 20)),
          bounds: Rect.fromLTWH(left, y, width, nameSize + 2),
        );
        if (desc.isNotEmpty) {
          page.graphics.drawString(
            desc,
            descFont,
            brush: PdfSolidBrush(PdfColor(70, 70, 70)),
            bounds: Rect.fromLTWH(left, y + nameSize + 2, width, height),
            format: _wrapFormat,
          );
        }
      }
      y += height;
      placed++;
    }
  }
  return placed;
}

/// Draws a bold name + wrapped description for each entry through
/// [boxes], at the largest of [_flowingSizes] where every entry fits -
/// shrinking the text rather than letting it spill past a box's printed
/// border (which is what happened before: an entry starting near the
/// bottom drew straight over the next box's heading).
///
/// When even the smallest size can't fit everything, the OLDEST entries
/// are dropped, not the newest: [entries] are in the order they were
/// gained (level-ups append), and by the time a character has that many
/// features the player knows their early ones by heart - it's the recent
/// ones they need written down. What's kept stays in level order.
void _drawFlowingBoxes(
  PdfPage page,
  List<(String name, String desc)> entries,
  List<(double, double, double, double)> boxes,
) {
  if (entries.isEmpty) return;
  for (final size in _flowingSizes) {
    if (_placeFlowing(null, entries, boxes, size) == entries.length) {
      _placeFlowing(page, entries, boxes, size);
      return;
    }
  }
  final smallest = _flowingSizes.last;
  var kept = entries;
  while (kept.length > 1 &&
      _placeFlowing(null, kept, boxes, smallest) < kept.length) {
    kept = kept.sublist(1);
  }
  _placeFlowing(page, kept, boxes, smallest);
}

/// Fills in the small printed diamond icon centered on (cx, cy) - the
/// Armor Training row's own proficiency marker (Light/Medium/Heavy/
/// Shields), same idea as the Saving Throw/Skill circles but diamond-
/// shaped to match what's actually printed there.
void _drawDiamond(PdfGraphics g, double cx, double cy, {double r = 4}) {
  g.drawPolygon([
    Offset(cx, cy - r),
    Offset(cx + r, cy),
    Offset(cx, cy + r),
    Offset(cx - r, cy),
  ], brush: PdfSolidBrush(PdfColor(30, 30, 30)));
}

/// Draws [text] truly centered - both horizontally and vertically - on
/// (centerX, centerY), using PdfVerticalAlignment.middle rather than
/// [_draw]'s default top-anchored box (drawString's default, which needs
/// guessing at font ascent/descent to land a number in the middle of a
/// shape like the ability score circle/tab). Used only for the ability
/// blocks so far - every other field was already calibrated against
/// [_draw]'s top-anchored behavior and shouldn't be disturbed.
void _drawCentered(
  PdfGraphics g,
  double centerX,
  double centerY,
  double fontSize,
  String text, {
  double width = 60,
  double height = 30,
}) {
  if (text.isEmpty) return;
  final font = PdfStandardFont(PdfFontFamily.helvetica, fontSize);
  g.drawString(
    text,
    font,
    brush: PdfSolidBrush(PdfColor(30, 30, 30)),
    bounds: Rect.fromLTWH(
      centerX - width / 2,
      centerY - height / 2,
      width,
      height,
    ),
    format: PdfStringFormat(
      alignment: PdfTextAlignment.center,
      lineAlignment: PdfVerticalAlignment.middle,
    ),
  );
}

/// The real species name ("Dragonborn"), with its ancestry/lineage choice
/// appended if one was made ("Dragonborn (Red)") - character.speciesLabel
/// alone isn't enough: picking a species choice (Draconic Ancestry, Elven
/// Lineage, ...) overwrites it with just the choice itself ("Red · Fire"),
/// same as the Overview tab's own species row does - see
/// character_sheet_screen.dart's _pickSpeciesChoice. The base species name
/// is only recoverable by resolving speciesKey against the catalog fresh.
String _speciesDisplay(Character c) {
  final resolved = c.speciesKey != null
      ? srdCatalog.speciesByKey[c.speciesKey]?.name
      : null;
  if (resolved == null) return c.speciesLabel; // homebrew/unresolved
  return c.speciesChoice != null ? '$resolved (${c.speciesChoice})' : resolved;
}

/// The real class name ("Fighter") and, if chosen, subclass name
/// ("Champion") - resolved fresh from the catalog rather than parsed out
/// of classLabel, which isn't reliably "just the class name": a
/// hand-seeded character (Jarson's own sample data) can have a classLabel
/// like "Dragonborn Fighter · Champion" that folds the species name in
/// too, for its own display purposes elsewhere (the AppBar title). Falls
/// back to splitting classLabel only when classKey doesn't resolve (a
/// homebrew/uncataloged class).
(String, String) _classAndSubclass(Character c) {
  final classInfo = c.classKey != null ? srdCatalog.byKey(c.classKey!) : null;
  if (classInfo == null) {
    final parts = c.classLabel.split(' · ');
    return (parts.first, parts.length > 1 ? parts.sublist(1).join(' · ') : '');
  }
  final subclassName = rules.chosenSubclass(c)?.name ?? '';
  return (classInfo.name, subclassName);
}

/// [c]'s own SkillEntry for [name] if they have one, or a synthetic
/// non-proficient default - `character.skills` only ever stores entries
/// with something actually set (proficient and/or expertise), same
/// "absent means untrained" convention the Overview tab's own
/// _skillEntryFor uses.
SkillEntry _skillEntryFor(Character c, String name, String abilityKey) {
  final existing = c.skills.where((s) => s.name == name);
  if (existing.isNotEmpty) return existing.first;
  return SkillEntry(name: name, ability: abilityKey, proficient: false);
}

String _passivePerception(Character c) {
  final entry = _skillEntryFor(c, 'Perception', 'wis');
  return '${10 + rules.skillModifier(c, entry)}';
}

/// Draws [c]'s top-section data (see [_fields]/[_abilityBlocks]) onto a
/// copy of the official sheet's page 1 and returns the resulting PDF's
/// bytes. Pure given [baseBytes] - no network access - so it's directly
/// testable against a small synthetic PDF, not just the real 16MB one.
Future<Uint8List> fillCharacterSheetTopSection(
  Uint8List baseBytes,
  Character c,
) async {
  final document = PdfDocument(inputBytes: baseBytes);
  final page = document.pages[0];
  final graphics = page.graphics;

  final (classOnly, subclassOnly) = _classAndSubclass(c);
  final values = {
    'name': c.name,
    'background': c.backgroundLabel ?? '',
    'class': classOnly,
    'species': _speciesDisplay(c),
    'subclass': subclassOnly,
    'level': '${c.level}',
    'ac': '${rules.armorClassFor(c)}',
    // Current HP is left blank deliberately - it changes turn to turn in
    // play, so a printed/exported value goes stale immediately; the
    // player pencils it in themselves, same as everything else on this
    // sheet that isn't a fixed derived stat.
    'hpMax': '${c.maxHp}',
    'hitDiceRef':
        '${c.hitDiceDie} '
        '${rules.formatModifier(rules.abilityModifier(c.abilityScores.con))}',
    // Hit Dice spent is left blank too, same reasoning as Current HP - it
    // changes as dice are spent/recovered in play.
    'hdMax': '${c.hitDiceTotal}',
    'proficiencyBonus': rules.formatModifier(
      rules.proficiencyBonusForLevel(c.level),
    ),
    'initiative': rules.formatModifier(rules.initiativeModifier(c)),
    'speed': '${rules.speedFor(c)} ft',
    'passivePerception': _passivePerception(c),
    'size': rules.sizeFor(c),
    // XP is character state, not a play-time tally - printed when there
    // is any (a milestone game leaves it at 0, and the box blank).
    'xp': c.experiencePoints > 0 ? '${c.experiencePoints}' : '',
  };
  for (final entry in values.entries) {
    _draw(graphics, _fields[entry.key]!, entry.value);
  }

  // True centers of the MODIFIER circle and SCORE tab, as offsets from
  // (cx, nameTop) - measured with a fine (5pt) grid overlaid on the
  // rendered page and cross-checked against the sheet's own extracted
  // label boxes, not eyeballed. Uses _drawCentered (real horizontal +
  // vertical centering on that point) rather than _draw's top-anchored
  // box, which needed guessing at font ascent to land a number in a
  // shape's middle.
  for (final entry in _abilityBlocks.entries) {
    final (x0, x1, nameTop) = entry.value;
    final score = c.abilityScores.of(entry.key);
    final modifier = rules.abilityModifier(score);
    final cx = (x0 + x1) / 2;
    _drawCentered(
      graphics,
      cx - 14,
      nameTop + 29,
      18,
      rules.formatModifier(modifier),
      width: 44,
      height: 26,
    );
    _drawCentered(
      graphics,
      cx + 17,
      nameTop + 34,
      14,
      '$score',
      width: 30,
      height: 20,
    );
  }

  // Saving Throws and Skills - one modifier per row, plus a filled dot
  // over the printed circle outline wherever the row's actual number
  // differs from the bare ability modifier alone (driven by the real
  // computed values, not just the stored proficient flag, so a homebrew
  // effect that changes the number without setting `proficient` still
  // shows correctly - and a proficient row whose bonus happened to net
  // to zero, if that's ever possible, wouldn't show a misleading dot).
  // Expertise doubles the modifier itself, same as everywhere else in
  // this app, but isn't marked any differently here - the sheet has no
  // second indicator for it.
  for (final (abilityKey, skillName, top, leftColumn) in _skillRows) {
    final int modifier;
    if (skillName == null) {
      modifier = rules.savingThrowModifier(c, abilityKey);
    } else {
      final entry = _skillEntryFor(c, skillName, abilityKey);
      modifier = rules.skillModifier(c, entry);
    }
    final bareModifier = rules.abilityModifier(c.abilityScores.of(abilityKey));
    // Not proficient (the row's number is identical to the ability's own
    // bare modifier, already shown in the bubble above) - the whole row
    // stays blank, not just the circle: an unfilled number here would
    // just be repeating what's already on the page.
    if (modifier == bareModifier) continue;
    final circleX = leftColumn ? _leftCircleX : _rightCircleX;
    final valueX = leftColumn ? _leftValueX : _rightValueX;
    _drawCentered(
      graphics,
      valueX,
      top + 2,
      8,
      rules.formatModifier(modifier),
      width: 20,
      height: 12,
    );
    // Saving Throw circles sit 1.5pt lower than their Skill counterparts'
    // measured position; Skill circles themselves also needed a 1pt
    // nudge down from the original measurement.
    final circleTop = top - 1 + (skillName == null ? 1.5 : 1);
    graphics.drawEllipse(
      Rect.fromLTWH(circleX - 3, circleTop, 6, 6),
      brush: PdfSolidBrush(PdfColor(30, 30, 30)),
    );
  }

  // WEAPONS & DAMAGE CANTRIPS - weapons first, then innate attacks
  // (Breath Weapon and the like), then damage cantrips. One row per
  // entry, up to the 6 ruled lines the table
  // actually has - anything past that is silently dropped rather than
  // overflowing the box.
  final weaponRows = [
    for (final weapon in c.weapons)
      (
        name: weapon.name,
        atkOrDc: rules.formatModifier(rules.attackFor(c, weapon).bonus),
        damage: rules.damageFor(c, weapon).text,
        notes: rules.masteryApplies(c, weapon) ? weapon.mastery! : '',
      ),
  ];
  final innateRows = [
    for (final attack in c.innateAttacks)
      if (rules.innateAttackInfo(c, attack).diceCount > 0)
        (
          name: attack.name,
          atkOrDc:
              'DC ${rules.innateAttackInfo(c, attack).saveDc} '
              '${attack.saveAbility[0].toUpperCase()}'
              '${attack.saveAbility.substring(1)}',
          damage:
              '${rules.innateAttackInfo(c, attack).diceCount}'
              '${rules.innateAttackInfo(c, attack).dieType} '
              '${rules.innateAttackDamageType(c, attack)}',
          notes: _extractAreaPhrase(_liveInnateAttackDesc(c, attack)),
        ),
  ];
  // Damage cantrips last - the table's own title names them, and their
  // to-hit/DC and scaled dice come from the same text-reading helper the
  // Spells tab uses (rules.spellDamageInfo). A cantrip with no damage
  // phrase (Light, Mage Hand, ...) has no business in this table.
  final cantripRows = [
    for (final key in c.spellcasting?.cantripsKnown ?? const <String>[])
      if (rules.spellRefFor(key, homebrewLevel: 0) case final spell?)
        if (rules.spellDamageInfo(spell, c.level) case final info
            when info.dice != null)
          (
            name: spell.name,
            atkOrDc: rules.spellAttackOrDcText(c, info),
            damage: rules.spellDamageText(info),
            notes: _shortRange(spell.range),
          ),
  ];
  final tableRows = [
    ...weaponRows,
    ...innateRows,
    ...cantripRows,
  ].take(_weaponsRowLines.length);
  for (final (i, row) in tableRows.indexed) {
    final lineTop = _weaponsRowLines[i];
    _drawFitted(
      graphics,
      _weaponsColumnEdges[0] + 3,
      lineTop - 3,
      _weaponsColumnEdges[1] - _weaponsColumnEdges[0] - 6,
      9,
      row.name,
    );
    _draw(
      graphics,
      _Field(
        (_weaponsColumnEdges[1] + _weaponsColumnEdges[2]) / 2,
        lineTop - 3,
        9,
        align: PdfTextAlignment.center,
        width: 44,
      ),
      row.atkOrDc,
    );
    _drawFitted(
      graphics,
      _weaponsColumnEdges[2] + 3,
      lineTop - 3,
      _weaponsColumnEdges[3] - _weaponsColumnEdges[2] - 6,
      9,
      row.damage,
    );
    _draw(
      graphics,
      _Field(_weaponsColumnEdges[3] + 3, lineTop - 3, 9, width: 120),
      row.notes,
    );
  }

  // CLASS FEATURES / SPECIES TRAITS / FEATS - each entry's short sheet
  // text (rules.sheetText: the player's own edit, else a homebrew feat's
  // sheet text or this app's bundled summary, else the full rules text),
  // since the full SRD text overflows these boxes. Species Traits come
  // from the species itself (rules.speciesTraitFeatures), not just
  // c.features - New Character never stores species traits there, so
  // reading only c.features left this box empty. Everything else in
  // c.features (class and subclass features alike - not distinguishing
  // 'subclass' from a subclass's own name as source, since
  // sample_data.dart's Jarson uses the subclass name, e.g. 'Champion', not
  // the literal string 'subclass') goes in Class Features. c.feats is
  // always feats, regardless of source (background, ASI-substitute, ...),
  // minus Ability Score Improvement: its effect is already in the ability
  // scores, so it would only take up room.
  (String, String) entryFor(GrantedFeature f) =>
      (f.name, _plainText(rules.sheetText(c, f)));
  final classFeatureEntries = [
    for (final f in c.features)
      if (f.source != 'species') entryFor(f),
  ];
  final speciesTraitEntries = [
    for (final f in rules.speciesTraitFeatures(c)) entryFor(f),
  ];
  final featEntries = [
    for (final f in c.feats)
      if (f.name != 'Ability Score Improvement') entryFor(f),
  ];

  // Class Features flows through column 1, then column 2 from its own top
  // (side by side, not stacked).
  _drawFlowingBoxes(page, classFeatureEntries, [
    _classFeaturesCol1,
    _classFeaturesCol2,
  ]);
  _drawFlowingBoxes(page, speciesTraitEntries, [_speciesTraitsBox]);
  _drawFlowingBoxes(page, featEntries, [_featsBox]);

  // EQUIPMENT TRAINING & PROFICIENCIES - the class's own armor/weapon/
  // tool text plus anything added on top (a Protector's Heavy armor and
  // Martial weapons, a hand-added proficiency) - see rules.armorTraining /
  // weaponProficiencyText / toolProficiencies.
  final training = rules.armorTraining(c);
  for (final (i, category) in const [
    'Light',
    'Medium',
    'Heavy',
    'Shields',
  ].indexed) {
    if (!training.contains(category)) continue;
    final (dx, dy) = _armorTrainingDiamonds[i];
    _drawDiamond(graphics, dx, dy);
  }

  final weaponText = rules.weaponProficiencyText(c);
  if (weaponText.isNotEmpty) {
    _drawWrapped(page, _plainText(weaponText), _weaponProficiencyArea);
  }

  final toolText = rules.toolProficiencies(c).join('; ');
  if (toolText.isNotEmpty) {
    _drawWrapped(page, _plainText(toolText), _toolProficiencyArea);
  }

  _fillPageTwo(document.pages[1], c);

  final bytes = await document.save();
  document.dispose();
  return Uint8List.fromList(bytes);
}

/// Formats one Carried Items row for the EQUIPMENT box - mirrors the
/// Overview tab's own FactRow formatting (character_sheet_screen.dart's
/// _inventoryCaption) so the exported sheet reads the same as the app.
String _inventoryLine(InventoryEntry item) {
  final qty = item.quantity > 1 ? ' ×${item.quantity}' : '';
  final captionParts = [
    if (item.attuned) 'Attuned',
    if (item.caption != null && item.caption!.isNotEmpty) item.caption!,
  ];
  final caption = captionParts.isEmpty ? '' : ' (${captionParts.join(' · ')})';
  return '${item.name}$qty$caption';
}

/// "120 feet" -> "120 ft", for the narrow Range/Notes columns.
String _shortRange(String range) => range
    .replaceAll(' feet', ' ft')
    .replaceAll(' miles', ' mi')
    .replaceAll(' mile', ' mi');

/// The casting time trimmed to fit its narrow column - "Bonus Action,
/// which you take immediately after..." -> "Bonus A.", "1 minute or
/// Ritual" -> "1 min" (the R diamond already says Ritual).
String _shortCastingTime(String time) {
  final first = time.split(RegExp(r',| or | \(')).first.trim();
  return first
      .replaceAll('Bonus Action', 'Bonus A.')
      .replaceAll(' minutes', ' min')
      .replaceAll(' minute', ' min')
      .replaceAll(' hours', ' hr')
      .replaceAll(' hour', ' hr');
}

/// Whether a spell's Material component is one a focus can't stand in for
/// - the sheet's "Required Material" marker: one with a listed cost, or
/// one the spell consumes.
bool _requiresMaterial(String components) => RegExp(
  r'\d[\d,]*\+? ?GP|consume',
  caseSensitive: false,
).hasMatch(components);

/// SPELLCASTING ABILITY/MODIFIER/SAVE DC/ATTACK BONUS, SPELL SLOTS totals,
/// and the CANTRIPS & PREPARED SPELLS table - cantrips first, then every
/// prepared or always-prepared spell by level, up to the table's 30 rows
/// (anything past that is dropped, same as the weapons table). Unprepared
/// spells (a Wizard's spellbook extras) stay off it, matching the
/// section's own title.
void _fillSpellcasting(PdfPage page, Character c) {
  final sc = c.spellcasting;
  if (sc == null) return;
  final g = page.graphics;

  _draw(g, _spellcastingAbilityField, _abilityNames[sc.ability] ?? '');
  for (final (centerY, text) in [
    (
      _spellModifierCenterY,
      rules.formatModifier(rules.spellcastingModifier(c)),
    ),
    (_spellSaveDcCenterY, '${rules.spellSaveDc(c)}'),
    (_spellAttackCenterY, rules.formatModifier(rules.spellAttackBonus(c))),
  ]) {
    _drawCentered(g, _spellStatCenterX, centerY, 14, text, width: 32);
  }

  for (final entry in sc.slots.entries) {
    final line = _slotTotalLines[entry.key];
    if (line == null || entry.value.max == 0) continue;
    final (x, lineTop) = line;
    _draw(
      g,
      _Field(x, lineTop - 2, 9, align: PdfTextAlignment.center, width: 14),
      '${entry.value.max}',
    );
  }

  final cantrips = [
    for (final key in sc.cantripsKnown)
      ?rules.spellRefFor(key, homebrewLevel: 0),
  ]..sort((a, b) => a.name.compareTo(b.name));
  final prepared =
      [
        for (final known in sc.spells)
          if (known.prepared || known.alwaysPrepared)
            ?rules.knownSpellRef(known),
      ]..sort(
        (a, b) => a.level != b.level
            ? a.level.compareTo(b.level)
            : a.name.compareTo(b.name),
      );

  for (final (i, spell) in [
    ...cantrips,
    ...prepared,
  ].take(_spellRowCount).indexed) {
    final lineTop = _spellRowFirstLine + i * _spellRowPitch;
    final textTop = lineTop - 3;
    void cell((double, double) column, String text, {bool center = false}) {
      final (left, right) = column;
      if (center) {
        _draw(
          g,
          _Field(
            (left + right) / 2,
            textTop,
            8,
            align: PdfTextAlignment.center,
            width: right - left,
          ),
          text,
        );
      } else {
        _drawFitted(
          g,
          left + 1,
          textTop,
          right - left - 2,
          8,
          text,
          minFontSize: 5.5,
        );
      }
    }

    cell(_spellLevelColumn, '${spell.level}', center: true);
    cell(_spellNameColumn, spell.name);
    cell(_spellCastingTimeColumn, _shortCastingTime(spell.castingTime));
    cell(_spellRangeColumn, _shortRange(spell.range));
    final info = rules.spellDamageInfo(spell, c.level);
    final notes = [
      rules.spellAttackOrDcText(c, info),
      rules.spellDamageText(info),
    ].where((s) => s.isNotEmpty).join(', ');
    // Falls back to the duration, minus the "Concentration, up to" the C
    // diamond already says.
    cell(
      _spellNotesColumn,
      notes.isNotEmpty
          ? notes
          : spell.duration.replaceFirst('Concentration, up to ', ''),
    );

    final diamondY = lineTop - _spellDiamondAboveLine;
    if (spell.concentration) {
      _drawDiamond(g, _spellConcentrationDiamondX, diamondY, r: 3.2);
    }
    if (spell.ritual) _drawDiamond(g, _spellRitualDiamondX, diamondY, r: 3.2);
    if (_requiresMaterial(spell.components)) {
      _drawDiamond(g, _spellMaterialDiamondX, diamondY, r: 3.2);
    }
  }
}

const _abilityNames = {
  'str': 'Strength',
  'dex': 'Dexterity',
  'con': 'Constitution',
  'int': 'Intelligence',
  'wis': 'Wisdom',
  'cha': 'Charisma',
};

/// Page 2: SPELLCASTING (see [_fillSpellcasting]), APPEARANCE, BACKSTORY &
/// PERSONALITY (+ Alignment), LANGUAGES, and EQUIPMENT (+ its Magic Item
/// Attunement sub-list), and COINS.
void _fillPageTwo(PdfPage page, Character c) {
  _fillSpellcasting(page, c);
  // Coins are character state like the equipment list above them - the
  // current amounts, blank when a denomination is 0.
  final coins = c.currency.toJson();
  for (final (key, x) in _coinCenters) {
    final amount = coins[key] as int? ?? 0;
    if (amount == 0) continue;
    _drawCentered(page.graphics, x, _coinCenterY, 11, '$amount', width: 32);
  }
  _drawWrapped(page, c.appearance, _appearanceArea);
  _drawWrapped(page, c.notes, _backstoryArea);
  if (c.alignment != null) {
    _draw(page.graphics, _alignmentField, c.alignment!);
  }
  if (c.languages.isNotEmpty) {
    _drawWrapped(page, c.languages.join(', '), _languagesArea);
  }
  if (c.inventory.isNotEmpty) {
    _drawWrapped(
      page,
      c.inventory.map(_inventoryLine).join('\n'),
      _equipmentArea,
    );
  }
  final attuned = c.inventory.where((i) => i.attuned).take(3).toList();
  final (attunementLeft, attunementRight) = _attunementLineX;
  for (final (i, item) in attuned.indexed) {
    final (dx, dy) = _attunementDiamonds[i];
    _drawDiamond(page.graphics, dx, dy);
    _draw(
      page.graphics,
      _Field(
        attunementLeft,
        _attunementLineTops[i],
        8,
        width: attunementRight - attunementLeft,
      ),
      item.name,
    );
  }
}

/// Downloads (or reuses the cached copy of) the official sheet and fills
/// it in with [c]'s data - the actual entry point the sheet's "Export
/// PDF" action calls.
Future<Uint8List> buildCharacterSheetPdf(Character c) async {
  final base = await loadOfficialSheetBytes();
  return fillCharacterSheetTopSection(base, c);
}
