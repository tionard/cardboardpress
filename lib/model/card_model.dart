// lib/model/card_model.dart
//
// PURE value objects describing a card. No Flutter widgets, no Riverpod, no
// platform calls — only `dart:ui` for the plain value types Color/Rect/etc.
// Keeping this layer pure is what lets the SAME data feed the on-screen
// preview, the collection thumbnails, and the print-DPI PNG export.
//
// (For a C# dev: think of these as immutable records / POCOs. `final` fields +
// `const` constructors ≈ readonly value types.)

import 'dart:ui';

/// How the two colours of a *double* colour are split across an area.
enum MixOrientation { vertical, horizontal }

/// The nine fixed field types a template can hold (spec §3.6).
/// Note the label is always "art", never "artwork".
enum FieldType { name, alias, cost, type, rules, flavor, stat, art, footer }

/// Foil treatments (spec §3.11). "none" is a first-class option.
enum FoilType { none, holo, gold }

/// A palette colour. Either a single RGB, or two RGB blended along an axis.
///
/// IMPORTANT (spec §3.1): transparency is NOT stored here. Opacity is applied
/// at the *use site* (a tint at 88%, a fill at 70%, …), because the same
/// swatch can be used at different opacities in different places.
class ColorValue {
  final Color c1;
  final Color? c2; // null => single colour
  final MixOrientation orientation;
  final double mix; // 0 = hard edge, 1 = fully soft blend across the span

  const ColorValue.single(this.c1)
      : c2 = null,
        orientation = MixOrientation.vertical,
        mix = 0;

  const ColorValue.duo(
    this.c1,
    Color this.c2, {
    this.orientation = MixOrientation.vertical,
    this.mix = 0.3,
  });

  bool get isDouble => c2 != null;
}

/// A reference to a palette colour (spec §1, §8). Models "live id + retained
/// snapshot": while the referenced palette colour exists, the live value wins;
/// once it's deleted, the [snapshot] keeps dependents rendering. So deleting a
/// palette colour never breaks a card.
class ColorRef {
  final String? id; // palette colour id, or null for a one-off literal value
  final ColorValue snapshot; // last-known value; the fallback after deletion

  const ColorRef({required this.id, required this.snapshot});

  /// A non-referencing literal colour (no palette link).
  const ColorRef.literal(this.snapshot) : id = null;
}

/// A field's optional outline. Stored as a *relationship to the fill*, not an
/// absolute colour, so it tracks the fill automatically when the fill changes
/// (spec §3.6).
class OutlineSpec {
  final bool lighter; // true => lighter than fill, false => darker
  final double intensity; // 0..1, how far toward white/black
  final double thickness; // as a fraction of card width

  const OutlineSpec({
    this.lighter = false,
    this.intensity = 0.4,
    this.thickness = 0.004,
  });
}

/// Per-field text styling. The text colour REFERENCES the palette (like fills
/// and the base colour), so it can be single or double and updates live when
/// the referenced swatch changes. [colorAlpha] applies use-site transparency.
class TextStyleSpec {
  final double sizeFrac; // font size as a fraction of card HEIGHT
  final bool bold;
  final bool italic;
  final TextAlign align;
  final ColorRef colorRef;
  final double colorAlpha;

  const TextStyleSpec({
    required this.sizeFrac,
    this.bold = false,
    this.italic = false,
    this.align = TextAlign.left,
    required this.colorRef,
    this.colorAlpha = 1.0,
  });
}

/// One placed region on the card.
///
/// The position/size [frac] is expressed in FRACTIONS of the card (0..1), never
/// in pixels. This is the trick that makes drawing resolution-independent: the
/// exact same field maths is correct at a 240px-wide preview and at a
/// 750px-wide print render.
class FieldSpec {
  final FieldType type;
  final Rect frac; // L,T,R,B each in 0..1 of the card
  final double cornerRadius; // fraction of card width
  final bool sharp; // sharp corners override cornerRadius
  final ColorRef? fill; // background fill reference (null for Art)
  final double fillAlpha; // use-site opacity for the fill, 0..1
  final OutlineSpec? outline; // optional
  final TextStyleSpec? text; // present on text-bearing fields

  const FieldSpec({
    required this.type,
    required this.frac,
    this.cornerRadius = 0.02,
    this.sharp = false,
    this.fill,
    this.fillAlpha = 1.0,
    this.outline,
    this.text,
  });
}

/// The card's optional outer border (spec §3.5). White or black ONLY, and it
/// always renders pure — never affected by the card's tint or foil.
class BorderSpec {
  final bool black; // true = black, false = white
  final double thickness; // fraction of card width

  const BorderSpec({this.black = true, this.thickness = 0.02});
}

/// Everything needed to draw one card. For this first spike, per-field content
/// is just a simple type→string map; later this becomes a richer CardContent.
class CardData {
  final double widthInches;
  final double heightInches;
  final double cornerRadiusFrac; // card corner radius as fraction of width
  final ColorRef baseColor;
  final BorderSpec? border;
  final List<FieldSpec> fields;
  final FoilType foil;
  final Map<FieldType, String> textContent;

  const CardData({
    this.widthInches = 2.5,
    this.heightInches = 3.5,
    this.cornerRadiusFrac = 0.05,
    required this.baseColor,
    this.border,
    required this.fields,
    this.foil = FoilType.none,
    this.textContent = const {},
  });
}

/// Resolves references (palette colours today; template, rarity, symbols later)
/// to their live value *or a retained snapshot* if the target was deleted
/// (spec §1, §8).
///
/// This is a plain value object the UI builds from the current palette and
/// hands to `paintCard`. It keeps the renderer PURE — `paintCard` asks the
/// resolver for a value and never sees a dangling reference or touches storage.
class CardRefs {
  /// Current palette: colour id -> live value. Built by the UI from the
  /// palette provider; empty while still loading (snapshots cover that).
  final Map<String, ColorValue> palette;

  const CardRefs({this.palette = const {}});

  /// Live value if the referenced colour still exists, else the snapshot.
  ColorValue resolveColor(ColorRef ref) {
    final id = ref.id;
    if (id != null) {
      final live = palette[id];
      if (live != null) return live;
    }
    return ref.snapshot;
  }
}

/// A palette entry as the UI/state layer sees it: identity + name + the colour
/// value. This is the domain shape; the drift row is mapped into this so
/// features never import database types directly.
class PaletteSwatch {
  final String id;
  final String name;
  final ColorValue value;

  const PaletteSwatch({
    required this.id,
    required this.name,
    required this.value,
  });
}

/// A template's layout (spec §3): card geometry, base colour, optional border,
/// and the ordered fields. It holds NO text content — that's per-card. A card
/// composes a TemplateData with its content into a [CardData] for rendering.
class TemplateData {
  final double widthInches;
  final double heightInches;
  final double cornerRadiusFrac;
  final ColorRef baseColor;
  final BorderSpec? border;
  final List<FieldSpec> fields;

  const TemplateData({
    this.widthInches = 2.5,
    this.heightInches = 3.5,
    this.cornerRadiusFrac = 0.05,
    required this.baseColor,
    this.border,
    required this.fields,
  });
}

/// A persisted template as the UI/state layer sees it: identity + name + the
/// layout. (The drift row is mapped into this so features never import db types.)
class TemplateEntry {
  final String id;
  final String name;
  final TemplateData data;

  const TemplateEntry({
    required this.id,
    required this.name,
    required this.data,
  });
}
