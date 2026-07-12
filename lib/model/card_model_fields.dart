part of 'card_model.dart';

// Field & positioning specs: a field's outline, text style, the field itself,
// the card border, and the art/set-symbol placement transforms.

/// A field's optional outline. Stored as a *relationship to the fill*, not an
/// absolute colour, so it tracks the fill automatically when the fill changes
/// (spec §3.6).
class OutlineSpec {
  final bool lighter; // legacy: true => lighter than fill, false => darker
  final double intensity; // legacy: 0..1, how far toward white/black
  final double thickness; // as a fraction of card width
  // Explicit outline colour. When set, the outline draws in this colour and
  // renders even with no fill. When null, fall back to the legacy relative
  // shade of the fill (lighter/intensity) — so pre-existing outlines are
  // unchanged. New/edited outlines set a colour; the shade path is legacy-only.
  // A double (two-colour) value renders as a gradient stroke, like fills.
  final ColorRef? color;
  final double alpha; // use-site opacity of the stroke, 0..1

  const OutlineSpec({
    this.lighter = false,
    this.intensity = 0.4,
    this.thickness = 0.004,
    this.color,
    this.alpha = 1.0,
  });

  OutlineSpec copyWith({
    bool? lighter,
    double? intensity,
    double? thickness,
    Object? color = _sentinel,
    double? alpha,
  }) =>
      OutlineSpec(
        lighter: lighter ?? this.lighter,
        intensity: intensity ?? this.intensity,
        thickness: thickness ?? this.thickness,
        color: identical(color, _sentinel) ? this.color : color as ColorRef?,
        alpha: alpha ?? this.alpha,
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

  /// Bundled font family for this text (must match a pubspec `fonts:` family
  /// from the catalog in model/font_catalog.dart). Null = the app default.
  /// Template-level only — deliberately NOT exposed per-card.
  final String? fontFamily;

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
    this.fontFamily,
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
    Object? fontFamily = _sentinel, // sentinel: null must CLEAR back to default
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
        fontFamily: identical(fontFamily, _sentinel)
            ? this.fontFamily
            : fontFamily as String?,
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

/// How a 9-slice patch fills the space it's given.
///
/// [stretch] scales the source patch to fit (the classic look); [tile] repeats
/// it at the size implied by the drawn corner scale, centred so any partial
/// tiles split evenly between both ends — better for textured parchment/metal
/// frames that smear when stretched. Designed to grow: a planned third mode
/// fits as many whole tiles as possible then stretches them equally to absorb
/// the remainder (CSS border-image "round").
enum SliceFillMode { stretch, tile }

/// A 9-slice (nine-patch) frame sprite for a layer's background: the sprite's
/// corners stay fixed while its edges and center stretch or tile, so an ornate
/// border/bevel never distorts at any layer size. [imageId] points into the
/// ImageStore (user-supplied art, like card art / the template background).
///
/// The four insets say where to CUT the source sprite — each as a fraction of
/// the SOURCE IMAGE ([insetL]/[insetR] of its width, [insetT]/[insetB] of its
/// height, 0..0.49). A zero inset removes that band entirely, which is how a
/// 3-slice falls out for free: `insetT = insetB = 0` is a horizontal
/// (left/center/right) 3-slice, `insetL = insetR = 0` a vertical one.
///
/// [thickness] is the DRAWN size of the thickest edge as a fraction of the
/// CARD WIDTH, so the frame scales with the card (preview ↔ print) but NOT
/// with the layer's size — that's the whole point of 9-slice. Edges with
/// smaller source insets draw proportionally thinner
/// (drawn = thickness × cardWidth × inset / maxInset), so the sides keep the
/// same ratios to each other that they have in the sprite.
///
/// [edgeMode]/[centerMode] pick stretch or tile per region. [drawCenter] off
/// skips the middle patch entirely, leaving the interior transparent (fill /
/// art shows through a border-only frame). [tint] recolours the sprite's
/// opaque pixels.
///
/// Reference + snapshot (like ColorRef / templateSnapshot): [frameId] points at
/// a Frames-library entry that OWNS the slicing (image + cuts + tile modes).
/// While the id resolves, the library's live values win — editing a frame
/// updates every referencing template. The fields stored here are the snapshot
/// taken when the frame was picked, so deleting a library frame never breaks a
/// template. [thickness], [drawCenter], and [tint] are use-site (per-layer)
/// and never come from the library.
class NineSliceSpec {
  final String imageId;
  final String? frameId; // Frames-library reference; null = snapshot only
  final double insetL; // source cut, fraction of source WIDTH, 0..0.49
  final double insetT; // source cut, fraction of source HEIGHT, 0..0.49
  final double insetR; // source cut, fraction of source WIDTH, 0..0.49
  final double insetB; // source cut, fraction of source HEIGHT, 0..0.49
  final double thickness; // drawn thickest-edge size, fraction of card width
  final SliceFillMode edgeMode;
  final SliceFillMode centerMode;
  final bool drawCenter;
  final ColorRef? tint; // optional recolour of the sprite's opaque pixels

  const NineSliceSpec({
    this.imageId = '',
    this.frameId,
    this.insetL = 0.33,
    this.insetT = 0.33,
    this.insetR = 0.33,
    this.insetB = 0.33,
    this.thickness = 0.06,
    this.edgeMode = SliceFillMode.stretch,
    this.centerMode = SliceFillMode.stretch,
    this.drawCenter = true,
    this.tint,
  });

  bool get hasImage => imageId.isNotEmpty;

  NineSliceSpec copyWith({
    String? imageId,
    Object? frameId = _sentinel,
    double? insetL,
    double? insetT,
    double? insetR,
    double? insetB,
    double? thickness,
    SliceFillMode? edgeMode,
    SliceFillMode? centerMode,
    bool? drawCenter,
    Object? tint = _sentinel,
  }) =>
      NineSliceSpec(
        imageId: imageId ?? this.imageId,
        frameId:
            identical(frameId, _sentinel) ? this.frameId : frameId as String?,
        insetL: insetL ?? this.insetL,
        insetT: insetT ?? this.insetT,
        insetR: insetR ?? this.insetR,
        insetB: insetB ?? this.insetB,
        thickness: thickness ?? this.thickness,
        edgeMode: edgeMode ?? this.edgeMode,
        centerMode: centerMode ?? this.centerMode,
        drawCenter: drawCenter ?? this.drawCenter,
        tint: identical(tint, _sentinel) ? this.tint : tint as ColorRef?,
      );
}

// ---------------------------------------------------------------------------
// Footer arrangement (template-level). The footer's VALUES resolve per-card
// (number/set/rarity/artist/copyright), but their LAYOUT — which components
// show, where, and in what order — is configured once on the template's footer
// field and shared by every card. Rendering anchors each zone's text to a
// corner/edge of the footer box, so the box's size/position (edited like any
// field) decides how the zones sit.
// ---------------------------------------------------------------------------

/// How the footer box is divided into zones.
enum FooterMode {
  singleLine, // one line: [line]
  leftRight, // two ends: [left, right]
  fourCorners, // box corners: [topLeft, topRight, bottomLeft, bottomRight]
}

/// The placeable pieces of collector info. Their text is derived per-card.
enum FooterComponent { number, set, rarity, artist, copyright }

/// A placement slot. Which ones are live depends on [FooterMode].
enum FooterZone { line, left, right, topLeft, topRight, bottomLeft, bottomRight }

/// One placed component: which piece, and which zone it sits in. Order within a
/// zone follows the order items appear in [FooterSpec.items].
class FooterItem {
  final FooterComponent component;
  final FooterZone zone;
  const FooterItem(this.component, this.zone);

  FooterItem copyWith({FooterComponent? component, FooterZone? zone}) =>
      FooterItem(component ?? this.component, zone ?? this.zone);

  @override
  bool operator ==(Object other) =>
      other is FooterItem && other.component == component && other.zone == zone;
  @override
  int get hashCode => Object.hash(component, zone);
}

class FooterSpec {
  final FooterMode mode;

  /// Visible components, in render order. A component absent here is hidden.
  final List<FooterItem> items;

  const FooterSpec({
    this.mode = FooterMode.singleLine,
    this.items = const [],
  });

  /// The default: every component on one line, in collector-info order. This
  /// reproduces the original single-string footer.
  const FooterSpec.defaults()
      : mode = FooterMode.singleLine,
        items = const [
          FooterItem(FooterComponent.number, FooterZone.line),
          FooterItem(FooterComponent.set, FooterZone.line),
          FooterItem(FooterComponent.rarity, FooterZone.line),
          FooterItem(FooterComponent.artist, FooterZone.line),
          FooterItem(FooterComponent.copyright, FooterZone.line),
        ];

  /// The zones live for the current mode, in a stable order.
  List<FooterZone> get zones {
    switch (mode) {
      case FooterMode.singleLine:
        return const [FooterZone.line];
      case FooterMode.leftRight:
        return const [FooterZone.left, FooterZone.right];
      case FooterMode.fourCorners:
        return const [
          FooterZone.topLeft,
          FooterZone.topRight,
          FooterZone.bottomLeft,
          FooterZone.bottomRight,
        ];
    }
  }

  FooterSpec copyWith({FooterMode? mode, List<FooterItem>? items}) =>
      FooterSpec(mode: mode ?? this.mode, items: items ?? this.items);
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
  final FooterSpec? footer; // Footer field only; per-zone layout of components
  final NineSliceSpec? frame; // optional 9-slice sprite drawn over the fill

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
    this.footer,
    this.frame,
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
    Object? footer = _sentinel,
    Object? frame = _sentinel,
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
        footer: identical(footer, _sentinel)
            ? this.footer
            : footer as FooterSpec?,
        frame: identical(frame, _sentinel)
            ? this.frame
            : frame as NineSliceSpec?,
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
