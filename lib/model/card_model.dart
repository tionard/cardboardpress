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

import 'markup.dart';

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

  OutlineSpec copyWith({bool? lighter, double? intensity, double? thickness}) =>
      OutlineSpec(
        lighter: lighter ?? this.lighter,
        intensity: intensity ?? this.intensity,
        thickness: thickness ?? this.thickness,
      );
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

  TextStyleSpec copyWith({
    double? sizeFrac,
    bool? bold,
    bool? italic,
    TextAlign? align,
    ColorRef? colorRef,
    double? colorAlpha,
  }) =>
      TextStyleSpec(
        sizeFrac: sizeFrac ?? this.sizeFrac,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        align: align ?? this.align,
        colorRef: colorRef ?? this.colorRef,
        colorAlpha: colorAlpha ?? this.colorAlpha,
      );
}

/// One placed region on the card.
///
/// The position/size [frac] is expressed in FRACTIONS of the card (0..1), never
/// in pixels. This is the trick that makes drawing resolution-independent: the
/// exact same field maths is correct at a 240px-wide preview and at a
/// 750px-wide print render.
class FieldSpec {
  final String id; // stable per-field id (content is keyed by this, not type)
  final FieldType type;
  final Rect frac; // L,T,R,B each in 0..1 of the card
  final double cornerRadius; // fraction of card width (0 = square corners)
  final ColorRef? fill; // background fill reference (null for Art)
  final double fillAlpha; // use-site opacity for the fill, 0..1
  final OutlineSpec? outline; // optional
  final TextStyleSpec? text; // present on text-bearing fields

  const FieldSpec({
    required this.id,
    required this.type,
    required this.frac,
    this.cornerRadius = 0.02,
    this.fill,
    this.fillAlpha = 1.0,
    this.outline,
    this.text,
  });

  FieldSpec copyWith({
    FieldType? type,
    Rect? frac,
    double? cornerRadius,
    Object? fill = _sentinel,
    double? fillAlpha,
    Object? outline = _sentinel,
    Object? text = _sentinel,
  }) =>
      FieldSpec(
        id: id,
        type: type ?? this.type,
        frac: frac ?? this.frac,
        cornerRadius: cornerRadius ?? this.cornerRadius,
        fill: identical(fill, _sentinel) ? this.fill : fill as ColorRef?,
        fillAlpha: fillAlpha ?? this.fillAlpha,
        outline:
            identical(outline, _sentinel) ? this.outline : outline as OutlineSpec?,
        text: identical(text, _sentinel) ? this.text : text as TextStyleSpec?,
      );
}

/// The card's optional outer border (spec §3.5). White or black ONLY, and it
/// always renders pure — never affected by the card's tint or foil.
class BorderSpec {
  final bool black; // true = black, false = white
  final double thickness; // fraction of card width

  const BorderSpec({this.black = true, this.thickness = 0.02});
}

/// Everything needed to draw one card: a template's layout merged with this
/// card's content. [textContent] is keyed by FIELD ID (not type), so multiple
/// fields of the same type (e.g. several Stats, or custom fields) are distinct.
/// Per-field art positioning. zoom 1.0 == cover-fit (current behaviour);
/// panX/panY in -1..1 slide the visible crop within the available slack.
class ArtTransform {
  final double zoom;
  final double panX;
  final double panY;

  const ArtTransform({this.zoom = 1.0, this.panX = 0.0, this.panY = 0.0});

  ArtTransform copyWith({double? zoom, double? panX, double? panY}) =>
      ArtTransform(
        zoom: zoom ?? this.zoom,
        panX: panX ?? this.panX,
        panY: panY ?? this.panY,
      );

  bool get isIdentity => zoom == 1.0 && panX == 0.0 && panY == 0.0;
}

/// Where a set symbol draws on a card. Placement is **template layout** (per
/// Tio's call): a fraction-of-card rect, an opacity, and an on/off. Transparency
/// lives here — it's a property of the placement, not of the rarity. The symbol
/// itself comes from the card's set (set.symbolId); this just says where/how big/
/// how faint it sits, identically at preview and export resolution.
class SetSymbolPlacement {
  final bool enabled;
  final Rect frac; // LTRB in 0..1 of the card
  final double alpha; // 0..1 opacity

  static const Rect defaultFrac = Rect.fromLTRB(0.80, 0.55, 0.93, 0.625);

  const SetSymbolPlacement({
    this.enabled = false,
    this.frac = defaultFrac,
    this.alpha = 1.0,
  });

  SetSymbolPlacement copyWith({bool? enabled, Rect? frac, double? alpha}) =>
      SetSymbolPlacement(
        enabled: enabled ?? this.enabled,
        frac: frac ?? this.frac,
        alpha: alpha ?? this.alpha,
      );

  /// True for a fresh, untouched placement — lets serialization skip writing it.
  bool get isDefault => !enabled && frac == defaultFrac && alpha == 1.0;
}

class CardData {
  final double widthInches;
  final double heightInches;
  final double cornerRadiusFrac; // card corner radius as fraction of width
  final ColorRef baseColor;
  final ColorRef? tint; // optional per-card tint over the base
  final double tintAlpha; // 0..1 opacity of the tint
  final BorderSpec? border;
  final List<FieldSpec> fields;
  final FoilType foil;
  final Map<String, String> textContent; // fieldId -> text
  final Map<String, String> artImageIds; // fieldId -> image id
  final Map<String, ArtTransform> artTransforms; // fieldId -> zoom/pan
  final String? bgImageId; // template background image, drawn under the tint
  final ArtTransform bgTransform; // cover-fit zoom/pan for the bg image
  final Map<String, String> symbolImageIds; // text-symbol tag (lower) -> imageId
  final String? setSymbolImageId; // resolved set-symbol image (from the set)
  final SetSymbolPlacement? setSymbolPlacement; // where/how it draws (template)

  const CardData({
    this.widthInches = 2.5,
    this.heightInches = 3.5,
    this.cornerRadiusFrac = 0.05,
    required this.baseColor,
    this.tint,
    this.tintAlpha = 1.0,
    this.border,
    required this.fields,
    this.foil = FoilType.none,
    this.textContent = const {},
    this.artImageIds = const {},
    this.artTransforms = const {},
    this.bgImageId,
    this.bgTransform = const ArtTransform(),
    this.symbolImageIds = const {},
    this.setSymbolImageId,
    this.setSymbolPlacement,
  });

  /// Every image id the renderer needs decoded: card art, the template
  /// background, and the glyphs for any {tag} used in symbol-bearing fields.
  /// Render sites decode these into [CardRefs.images] before painting.
  Set<String> imageIdsToDecode() {
    final ids = <String>{
      ...artImageIds.values,
      if (bgImageId != null) bgImageId!,
      if (setSymbolImageId != null) setSymbolImageId!,
    };
    for (final f in fields) {
      if (f.type != FieldType.cost) continue; // Rules joins with rich text
      final content = textContent[f.id];
      if (content == null) continue;
      for (final tag in referencedTags(content)) {
        final id = symbolImageIds[tag];
        if (id != null) ids.add(id);
      }
    }
    return ids;
  }
}

/// Resolves references (palette colours today; template, rarity, symbols later)
/// to their live value *or a retained snapshot* if the target was deleted
/// (spec §1, §8).
///
/// This is a plain value object the UI builds from the current palette and
/// hands to `paintCard`. It keeps the renderer PURE — `paintCard` asks the
/// resolver for a value and never sees a dangling reference or touches storage.
class CardRefs {
  /// Current palette: colour id -> live value.
  final Map<String, ColorValue> palette;

  /// Decoded art images: image id -> ui.Image. Pre-decoded by the widget layer
  /// (paintCard is synchronous, so it never loads/decodes images itself).
  final Map<String, Image> images;

  const CardRefs({this.palette = const {}, this.images = const {}});

  /// Live value if the referenced colour still exists, else the snapshot.
  ColorValue resolveColor(ColorRef ref) {
    final id = ref.id;
    if (id != null) {
      final live = palette[id];
      if (live != null) return live;
    }
    return ref.snapshot;
  }

  /// The decoded image for [imageId], or null if absent / not yet loaded.
  Image? resolveImage(String? imageId) =>
      imageId == null ? null : images[imageId];
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
  final String? bgImageId; // optional background image, drawn UNDER the tint
  final ArtTransform bgTransform; // cover-fit zoom/pan for the bg image
  final SetSymbolPlacement setSymbol; // where the set symbol draws (layout)

  const TemplateData({
    this.widthInches = 2.5,
    this.heightInches = 3.5,
    this.cornerRadiusFrac = 0.05,
    required this.baseColor,
    this.border,
    required this.fields,
    this.bgImageId,
    this.bgTransform = const ArtTransform(),
    this.setSymbol = const SetSymbolPlacement(),
  });

  TemplateData copyWith({
    double? widthInches,
    double? heightInches,
    double? cornerRadiusFrac,
    ColorRef? baseColor,
    Object? border = _sentinel, // pass null to clear the border
    List<FieldSpec>? fields,
    Object? bgImageId = _sentinel, // pass null to clear the bg image
    ArtTransform? bgTransform,
    SetSymbolPlacement? setSymbol,
  }) =>
      TemplateData(
        widthInches: widthInches ?? this.widthInches,
        heightInches: heightInches ?? this.heightInches,
        cornerRadiusFrac: cornerRadiusFrac ?? this.cornerRadiusFrac,
        baseColor: baseColor ?? this.baseColor,
        border: identical(border, _sentinel) ? this.border : border as BorderSpec?,
        fields: fields ?? this.fields,
        bgImageId:
            identical(bgImageId, _sentinel) ? this.bgImageId : bgImageId as String?,
        bgTransform: bgTransform ?? this.bgTransform,
        setSymbol: setSymbol ?? this.setSymbol,
      );
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

  TemplateEntry copyWith({String? name, TemplateData? data}) => TemplateEntry(
        id: id,
        name: name ?? this.name,
        data: data ?? this.data,
      );
}

/// A card's authored content, keyed by field id. Today it's just per-field
/// text; art images, artist credit, stat values, etc. join later.
class CardContent {
  final Map<String, String> text; // fieldId -> text value
  final Map<String, String> art; // fieldId -> image id
  final Map<String, ArtTransform> artTransforms; // fieldId -> zoom/pan
  final ColorRef? tint; // optional per-card base-colour override
  final double tintAlpha; // 0..1 opacity of the tint over the base
  final String artist; // per-card; rendered by the Footer
  final String? rarityId; // live rarity reference (footer abbreviation)

  const CardContent({
    this.text = const {},
    this.art = const {},
    this.artTransforms = const {},
    this.tint,
    this.tintAlpha = 1.0,
    this.artist = '',
    this.rarityId,
  });

  CardContent _copy({
    Map<String, String>? text,
    Map<String, String>? art,
    Map<String, ArtTransform>? artTransforms,
    Object? tint = _sentinel,
    double? tintAlpha,
    String? artist,
    Object? rarityId = _sentinel,
  }) =>
      CardContent(
        text: text ?? this.text,
        art: art ?? this.art,
        artTransforms: artTransforms ?? this.artTransforms,
        tint: identical(tint, _sentinel) ? this.tint : tint as ColorRef?,
        tintAlpha: tintAlpha ?? this.tintAlpha,
        artist: artist ?? this.artist,
        rarityId:
            identical(rarityId, _sentinel) ? this.rarityId : rarityId as String?,
      );

  CardContent withText(String fieldId, String value) {
    final next = Map<String, String>.from(text);
    next[fieldId] = value;
    return _copy(text: next);
  }

  /// Set (or clear, when [imageId] is null) the art image for a field. Clearing
  /// also drops any zoom/pan for that field.
  CardContent withArt(String fieldId, String? imageId) {
    final next = Map<String, String>.from(art);
    final nextT = Map<String, ArtTransform>.from(artTransforms);
    if (imageId == null) {
      next.remove(fieldId);
      nextT.remove(fieldId);
    } else {
      next[fieldId] = imageId;
    }
    return _copy(art: next, artTransforms: nextT);
  }

  /// Set the zoom/pan for a field's art.
  CardContent withArtTransform(String fieldId, ArtTransform t) {
    final next = Map<String, ArtTransform>.from(artTransforms);
    if (t.isIdentity) {
      next.remove(fieldId);
    } else {
      next[fieldId] = t;
    }
    return _copy(artTransforms: next);
  }

  /// Set (or clear, when [ref] is null) the card's tint.
  CardContent withTint(ColorRef? ref) => _copy(tint: ref);

  CardContent withTintAlpha(double a) => _copy(tintAlpha: a);

  CardContent withArtist(String value) => _copy(artist: value);

  /// Set (or clear, when [id] is null) the card's rarity reference.
  CardContent withRarity(String? id) => _copy(rarityId: id);
}

const Object _sentinel = Object();

/// A persisted card as the UI/state layer sees it. The template is a reference:
/// [templateId] is the live link; [templateSnapshot] is the retained fallback
/// (spec §1, §8) so deleting a template never breaks the card.
class CardEntry {
  final String id;
  final String? templateId;
  final TemplateData templateSnapshot;
  final CardContent content;
  final FoilType foil;
  final String? setId; // null => Unassigned

  const CardEntry({
    required this.id,
    required this.templateId,
    required this.templateSnapshot,
    required this.content,
    this.foil = FoilType.none,
    this.setId,
  });

  /// The layout to draw with: the live template if it still exists, else the
  /// snapshot. (Mirrors ColorRef resolution, at the template level.)
  TemplateData effectiveTemplate(Map<String, TemplateData> liveTemplates) {
    final id = templateId;
    if (id != null) {
      final live = liveTemplates[id];
      if (live != null) return live;
    }
    return templateSnapshot;
  }

  CardEntry copyWith({
    String? templateId,
    TemplateData? templateSnapshot,
    CardContent? content,
    FoilType? foil,
    Object? setId = _sentinel,
  }) =>
      CardEntry(
        id: id,
        templateId: templateId ?? this.templateId,
        templateSnapshot: templateSnapshot ?? this.templateSnapshot,
        content: content ?? this.content,
        foil: foil ?? this.foil,
        setId: identical(setId, _sentinel) ? this.setId : setId as String?,
      );
}

/// A rarity (spec §3): name + 1–3-letter abbreviation. (Its palette colour and
/// snapshot-on-delete ref are added when a rarity editor exists.)
class RarityEntry {
  final String id;
  final String name;
  final String abbreviation;
  final int position;

  const RarityEntry({
    required this.id,
    required this.name,
    this.abbreviation = '',
    this.position = 0,
  });
}

/// An inline text symbol (spec §3.2): a `{tag}` that renders as a glyph image.
/// Tags are matched case-insensitively; [imageId] points into the ImageStore.
class TextSymbolEntry {
  final String id;
  final String tag;
  final String imageId;
  final int position;

  const TextSymbolEntry({
    required this.id,
    required this.tag,
    required this.imageId,
    this.position = 0,
  });
}

/// A standalone symbol (spec §3.3): a graphic used only as a set symbol or a
/// watermark — not inline, not composable. Just a name + image; any colour tint
/// (rarity colour for a set symbol, palette colour for a watermark) is applied
/// at the render site, never stored here.
class SymbolEntry {
  final String id;
  final String name;
  final String imageId;
  final int position;

  const SymbolEntry({
    required this.id,
    required this.name,
    required this.imageId,
    this.position = 0,
  });
}

/// A set (Collection folder): name + footer-feeding metadata + numbering.
/// "Unassigned" is not stored — it's the null-setId bucket, always shown first.
class SetEntry {
  final String id;
  final String name;
  final String abbreviation;
  final int year;
  final String owner;
  final bool numbering;
  final int position;
  final String? symbolId; // chosen standalone symbol (set symbol); null => none

  const SetEntry({
    required this.id,
    required this.name,
    this.abbreviation = '',
    this.year = 2026,
    this.owner = '',
    this.numbering = true,
    this.position = 0,
    this.symbolId,
  });
}
