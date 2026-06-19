part of 'card_model.dart';

// Field & positioning specs: a field's outline, text style, the field itself,
// the card border, and the art/set-symbol placement transforms.

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
/// How a text field handles content that doesn't fit its box.
enum TextFit { fixed, shrink }

/// Vertical anchoring of text within its field box.
enum VAlign { top, middle, bottom }

class TextStyleSpec {
  final double sizeFrac; // font size as a fraction of card HEIGHT
  final bool bold;
  final bool italic;
  final TextAlign align; // horizontal alignment
  final VAlign vAlign; // vertical anchor within the field box
  final ColorRef colorRef;
  final double colorAlpha;
  final TextFit fit; // fixed size, or shrink the font until it fits the box
  final double padX; // horizontal inset, as a fraction of card width (sides only)
  final double padY; // vertical inset, as a fraction of card height (top+bottom)

  const TextStyleSpec({
    required this.sizeFrac,
    this.bold = false,
    this.italic = false,
    this.align = TextAlign.left,
    this.vAlign = VAlign.top,
    required this.colorRef,
    this.colorAlpha = 1.0,
    this.fit = TextFit.fixed,
    this.padX = 0.04,
    this.padY = 0.0,
  });

  TextStyleSpec copyWith({
    double? sizeFrac,
    bool? bold,
    bool? italic,
    TextAlign? align,
    VAlign? vAlign,
    ColorRef? colorRef,
    double? colorAlpha,
    TextFit? fit,
    double? padX,
    double? padY,
  }) =>
      TextStyleSpec(
        sizeFrac: sizeFrac ?? this.sizeFrac,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        align: align ?? this.align,
        vAlign: vAlign ?? this.vAlign,
        colorRef: colorRef ?? this.colorRef,
        colorAlpha: colorAlpha ?? this.colorAlpha,
        fit: fit ?? this.fit,
        padX: padX ?? this.padX,
        padY: padY ?? this.padY,
      );
}

/// One placed region on the card.
///
/// The position/size [frac] is expressed in FRACTIONS of the card (0..1), never
/// in pixels. This is the trick that makes drawing resolution-independent: the
/// exact same field maths is correct at a 240px-wide preview and at a
/// 750px-wide print render.
/// The Rules field's optional watermark (spec §3.7): a standalone symbol drawn
/// faintly BEHIND the rules text, centred in the field. [symbolId] is a
/// standalone-symbol id (resolved to an image at compose time; '' = none chosen
/// yet); [color] is a palette colour (single or double, clipped to the symbol's
/// shape); [alpha] is its transparency. Independent of the set symbol — it lives
/// on the field, not the set.
class WatermarkSpec {
  final String symbolId;
  final ColorRef color;
  final double alpha;

  const WatermarkSpec({
    this.symbolId = '',
    required this.color,
    this.alpha = 0.15,
  });

  WatermarkSpec copyWith({String? symbolId, ColorRef? color, double? alpha}) =>
      WatermarkSpec(
        symbolId: symbolId ?? this.symbolId,
        color: color ?? this.color,
        alpha: alpha ?? this.alpha,
      );
}

class FieldSpec {
  final String id; // stable per-field id (content is keyed by this, not type)
  final FieldType type;
  final Rect frac; // L,T,R,B each in 0..1 of the card
  final double cornerRadius; // fraction of card width (0 = square corners)
  final ColorRef? fill; // background fill reference (null for Art)
  final double fillAlpha; // use-site opacity for the fill, 0..1
  final OutlineSpec? outline; // optional
  final TextStyleSpec? text; // present on text-bearing fields
  final WatermarkSpec? watermark; // Rules field only; drawn behind the text

  const FieldSpec({
    required this.id,
    required this.type,
    required this.frac,
    this.cornerRadius = 0.02,
    this.fill,
    this.fillAlpha = 1.0,
    this.outline,
    this.text,
    this.watermark,
  });

  FieldSpec copyWith({
    FieldType? type,
    Rect? frac,
    double? cornerRadius,
    Object? fill = _sentinel,
    double? fillAlpha,
    Object? outline = _sentinel,
    Object? text = _sentinel,
    Object? watermark = _sentinel,
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
        watermark: identical(watermark, _sentinel)
            ? this.watermark
            : watermark as WatermarkSpec?,
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
