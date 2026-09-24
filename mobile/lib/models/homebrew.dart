import 'effect.dart';

/// User-authored content that isn't in the SRD - a reflavored spell, a
/// DM's custom item, a homebrew background. Stored locally only (Hive),
/// never bundled with the app, so there's no licensing question: it's the
/// player's own data, same as if they'd written it on a paper sheet.
///
/// `id` is always prefixed "homebrew_" and `kind` is one of "spell",
/// "species", "background", "feat", "class", "weapon", "armor", "gear",
/// "tool", "magicItem", or "language" - matching the SRD catalog it
/// belongs to. `name` is fixed once created (see homebrew_repository.dart's
/// `update` - it never changes `name`): effects/text are matched by name
/// string, not id, so a rename would silently disconnect every
/// already-granted feat/attuned item still carrying the old name.
/// The four real 2024 SRD feat categories (see assets/srd/feats.json) - the
/// closed set a homebrew feat's [HomebrewEntry.category] should match, so
/// it plugs into the same category-restricted feat pickers (a Fighting
/// Style choice, an Epic Boon choice, ...) real SRD feats already do. Kept
/// here rather than derived from srdCatalog so homebrew_screen.dart's
/// dropdown never depends on the catalog having loaded.
const homebrewFeatCategories = [
  'Origin Feat',
  'General Feat',
  'Fighting Style Feat',
  'Epic Boon Feat',
];

class HomebrewEntry {
  const HomebrewEntry({
    required this.id,
    required this.kind,
    required this.name,
    this.desc = '',
    this.source = 'homebrew',
    this.effects = const [],
    this.category,
    this.prerequisite,
    this.shortDesc = '',
    this.data = const {},
  });
  final String id;
  final String kind;
  final String name;

  /// Free-text rules/flavor text - shown wherever a matching SRD entry's
  /// text would be (see domain/rules.dart's liveFeatureText).
  final String desc;

  /// 'homebrew' (player/DM-invented) or 'official' (real 2024 content
  /// that just isn't in the free SRD, e.g. Great Weapon Master).
  final String source;

  /// Numeric roll/DC bonuses this entry grants - only meaningful for
  /// `kind == 'feat'` (matched against a granted feat) and
  /// `kind == 'magicItem'` (matched against an attuned inventory item);
  /// ignored for every other kind. See domain/rules.dart's
  /// liveFeatureEffects/liveItemEffects.
  final List<Effect> effects;

  /// One of [homebrewFeatCategories], or null if uncategorized - only
  /// meaningful for `kind == 'feat'`. Mirrors SrdFeat.category, and drives
  /// the same thing it drives for a real SRD feat: whether this feat is
  /// offered by a category-restricted picker (resolving a "Choose a
  /// Fighting Style" or "Choose an Epic Boon" Pending Choice, say) - see
  /// character_sheet_screen.dart's _pickAndGrantFeat. An uncategorized
  /// homebrew feat only ever shows up in the unrestricted "+ Add Feat"
  /// list, same as it always has.
  final String? category;

  /// Free-text prerequisite (e.g. "Level 4+", "Strength or Dexterity
  /// 13+") - only meaningful for `kind == 'feat'`. Mirrors
  /// SrdFeat.prerequisite. Display-only: nothing in this app currently
  /// enforces a feat's prerequisite, for an SRD feat or a homebrew one -
  /// it's shown so the player can see and honor it themselves, the same
  /// as they would from a paper sheet.
  final String? prerequisite;

  /// A one- or two-line summary for the exported PDF sheet's cramped
  /// Features/Feats boxes - the counterpart to the bundled SRD short text
  /// (assets/srd/sheet-text.json). Empty means "none written": the sheet
  /// falls back to [desc]. Only meaningful for `kind == 'feat'`, the one
  /// homebrew kind that becomes a sheet entry; see rules.sheetText.
  final String shortDesc;

  /// Kind-specific rules data entered in the My Homebrew editor - a
  /// spell's level/school/casting time, a weapon's damage/properties, a
  /// species' speed/size/traits, a class's hit die and features by level,
  /// a subclass's parent class... Plain JSON (keys documented where each
  /// kind is read - see data/homebrew_catalog.dart), so a new field never
  /// needs a schema change here.
  final Map<String, dynamic> data;

  /// A copy with some fields replaced - every screen that edits one part of
  /// an entry keeps the rest.
  HomebrewEntry copyWith({
    String? desc,
    String? source,
    List<Effect>? effects,
    String? category,
    String? prerequisite,
    String? shortDesc,
    Map<String, dynamic>? data,
  }) => HomebrewEntry(
    id: id,
    kind: kind,
    name: name,
    desc: desc ?? this.desc,
    source: source ?? this.source,
    effects: effects ?? this.effects,
    category: category ?? this.category,
    prerequisite: prerequisite ?? this.prerequisite,
    shortDesc: shortDesc ?? this.shortDesc,
    data: data ?? this.data,
  );

  /// Empty/default fields are left out - [fromJson] restores their
  /// defaults - so an export file only shows what an entry actually has.
  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'name': name,
    'source': source,
    if (desc.isNotEmpty) 'desc': desc,
    if (shortDesc.isNotEmpty) 'shortDesc': shortDesc,
    'category': ?category,
    'prerequisite': ?prerequisite,
    if (effects.isNotEmpty) 'effects': effects.map((e) => e.toJson()).toList(),
    if (data.isNotEmpty) 'data': data,
  };

  factory HomebrewEntry.fromJson(Map<String, dynamic> j) => HomebrewEntry(
    id: j['id'] as String,
    kind: j['kind'] as String,
    name: j['name'] as String,
    desc: j['desc'] as String? ?? '',
    source: j['source'] as String? ?? 'homebrew',
    effects: (j['effects'] as List? ?? const [])
        .map((e) => Effect.fromJson(e as Map<String, dynamic>))
        .toList(),
    category: j['category'] as String?,
    prerequisite: j['prerequisite'] as String?,
    shortDesc: j['shortDesc'] as String? ?? '',
    data: (j['data'] as Map<String, dynamic>?) ?? const {},
  );
}
