// lib/model/layers.dart
//
// LAYER REDESIGN — Phase 1a: the model only.
//
// A template's layout is moving from a fixed enum of nine field types plus a
// hardcoded z-order to a single ordered `List<Layer>` (list order == z-order;
// see references/layer-redesign-decisions.md). This file defines those value
// objects. It is deliberately INERT: nothing imports it yet, no migration writes
// it, the renderer does not read it, and there is no serialization or schema for
// it. That lands in 1b (migration + a render-diff harness that proves existing
// cards render pixel-identical) and Phase 2 (flip the renderer, serialize,
// schema v11 → v12).
//
// Aspects reuse the existing spec types (OutlineSpec, NineSliceSpec,
// WatermarkSpec, TextStyleSpec, FoilType, ColorRef, ArtTransform) so the
// migration from FieldSpec/TemplateData is lossless.

import 'dart:ui';

import 'card_model.dart';

/// The kind of a layer. `generic` covers everything the old fixed field types
/// did except the three that keep a bespoke per-card editor.
enum LayerKind { generic, art, rules, footer }

/// Which Card-Editor tab an exposed aspect's per-card control appears in.
enum EditorTab { card, art, color, set, export }

/// A per-card-editable facet of a layer. A layer exposes zero or more of these,
/// each routed to one [EditorTab]; empty exposure = template-only (no card slot).
enum ExposedAspect { text, fill, image, outlineColor, foil, visible }

/// Where an image aspect gets its picture. `fixed` = a template-level ImageStore
/// id ([ImageAspect.imageId]); `setSymbol` = resolved from the card's set at
/// compose time (auto-tinted by the card's rarity colour).
enum ImageSource { fixed, setSymbol }

const Object _unset = Object();

/// A flat colour fill of the layer's rect (single or double colour). Replaces
/// `FieldSpec.fill` + `fillAlpha` + `cornerRadius`, and the card base + tint.
/// Per-colour alpha lives inside the [ColorValue]; [alpha] is the use-site dimmer.
class FillAspect {
  final ColorRef color;
  final double alpha; // use-site opacity, 0..1

  const FillAspect({
    required this.color,
    this.alpha = 1.0,
  });

  FillAspect copyWith({ColorRef? color, double? alpha}) => FillAspect(
        color: color ?? this.color,
        alpha: alpha ?? this.alpha,
      );
}

/// An image drawn in the layer's rect.
///
/// * `source == fixed` with a non-null [tint] → the image is a silhouette filled
///   with the tint colour (alpha-mask), like the watermark / set-symbol tint.
/// * `source == fixed` with a null [tint] → the image is drawn as-is, cover-fit
///   with [transform] (like card art or a template background).
/// * `source == setSymbol` → the picture is resolved from the card's set at
///   compose time and tinted by the card's rarity colour; [imageId] is unused.
///
/// The `art` layer kind resolves its picture per-card (keyed by the layer id),
/// not from [imageId]; [imageId] carries a template-level fixed image for
/// generic image layers (background, decorative art, a silhouette symbol).
class ImageAspect {
  final ImageSource source;
  final String imageId; // template ImageStore id for fixed images; '' otherwise
  final ColorRef? tint; // null = draw as-is; non-null = silhouette tint
  final double alpha; // use-site opacity, 0..1
  final ArtTransform transform; // cover-fit zoom/pan for as-is images

  const ImageAspect({
    this.source = ImageSource.fixed,
    this.imageId = '',
    this.tint,
    this.alpha = 1.0,
    this.transform = const ArtTransform(),
  });

  ImageAspect copyWith({
    ImageSource? source,
    String? imageId,
    Object? tint = _unset,
    double? alpha,
    ArtTransform? transform,
  }) =>
      ImageAspect(
        source: source ?? this.source,
        imageId: imageId ?? this.imageId,
        tint: identical(tint, _unset) ? this.tint : tint as ColorRef?,
        alpha: alpha ?? this.alpha,
        transform: transform ?? this.transform,
      );
}

/// Text on a layer. [literal] null = bound to per-card content (keyed by the
/// layer id, like today's `textContent`); non-null = fixed text authored on the
/// template. [inline] true renders through the inline engine (`{tag}` symbols +
/// `**bold**`/`*italic*` markup) rather than as plain text. A text aspect may
/// render a text symbol as well as characters.
/// A bound, derived text value, resolved per-card at compose time. A text aspect
/// composes an ordered list of these (joined by its separator); an empty list
/// means the text is free (typed per-card when the aspect is exposed to a tab).
enum TextSource {
  cardName,
  setName,
  setAbbrev,
  collectorNumber,
  rarityName,
  rarityAbbrev,
  artist,
  copyright,
}

class TextAspect {
  final TextStyleSpec style;
  final String placeholder; // template-preview-only dummy text; never on a card
  // Ordered bound sources joined by [separator] (e.g. a footer line
  // "001/XXX · CORE · R"). Empty = free text: typed per-card when exposed, else
  // nothing. Every part shares this aspect's styling.
  final List<TextSource> parts;
  final String separator; // joins resolved parts; padded with spaces if non-empty
  final bool inline; // parse {symbols} / **bold**
  final bool multiline; // wrap to multiple lines (also drives card-editor field)

  const TextAspect({
    required this.style,
    this.placeholder = '',
    this.parts = const [],
    this.separator = '·',
    this.inline = false,
    this.multiline = false,
  });

  bool get isBound => parts.isNotEmpty;

  TextAspect copyWith({
    TextStyleSpec? style,
    String? placeholder,
    List<TextSource>? parts,
    String? separator,
    bool? inline,
    bool? multiline,
  }) =>
      TextAspect(
        style: style ?? this.style,
        placeholder: placeholder ?? this.placeholder,
        parts: parts ?? this.parts,
        separator: separator ?? this.separator,
        inline: inline ?? this.inline,
        multiline: multiline ?? this.multiline,
      );
}

/// One entry in a template's ordered layer list. List order is z-order (index 0
/// = bottom). Every layer has a [frac] rect (LTRB in 0..1 of the card); a
/// whole-card / background layer simply spans the full 0..1 rect. Aspects are
/// opt-in (null = absent); a generic layer may carry any combination, drawn in a
/// fixed sub-order: fill → image → border → outline → foil → text.
///
/// Existing spec types are reused verbatim as aspects (outline / border / foil /
/// watermark / footer) so migration from FieldSpec is lossless.
class Layer {
  final String id;
  final String name;
  final bool visible;
  final LayerKind kind;
  final Rect frac; // LTRB, 0..1 of the card
  final double cornerRadius; // fraction of card width (0 = square); field geometry

  final FillAspect? fill;
  final ImageAspect? image;
  final NineSliceSpec? border; // 9-slice frame (reused type)
  final OutlineSpec? outline; // relative-shade outline (reused type)
  final FoilType foil; // none = no foil aspect
  final TextAspect? text;
  final WatermarkSpec? watermark; // Rules watermark (reused type; see 1b notes)
  final FooterSpec? footer; // footer kind (reused type)

  /// Per-aspect exposure → which Card-Editor tab the control appears in. Empty
  /// = template-only. Several aspects may be exposed at once.
  final Map<ExposedAspect, EditorTab> exposed;

  const Layer({
    required this.id,
    required this.name,
    this.visible = true,
    this.kind = LayerKind.generic,
    required this.frac,
    this.cornerRadius = 0.02,
    this.fill,
    this.image,
    this.border,
    this.outline,
    this.foil = FoilType.none,
    this.text,
    this.watermark,
    this.footer,
    this.exposed = const {},
  });

  Layer copyWith({
    String? name,
    bool? visible,
    LayerKind? kind,
    Rect? frac,
    double? cornerRadius,
    Object? fill = _unset,
    Object? image = _unset,
    Object? border = _unset,
    Object? outline = _unset,
    FoilType? foil,
    Object? text = _unset,
    Object? watermark = _unset,
    Object? footer = _unset,
    Map<ExposedAspect, EditorTab>? exposed,
  }) =>
      Layer(
        id: id,
        name: name ?? this.name,
        visible: visible ?? this.visible,
        kind: kind ?? this.kind,
        frac: frac ?? this.frac,
        cornerRadius: cornerRadius ?? this.cornerRadius,
        fill: identical(fill, _unset) ? this.fill : fill as FillAspect?,
        image: identical(image, _unset) ? this.image : image as ImageAspect?,
        border:
            identical(border, _unset) ? this.border : border as NineSliceSpec?,
        outline:
            identical(outline, _unset) ? this.outline : outline as OutlineSpec?,
        foil: foil ?? this.foil,
        text: identical(text, _unset) ? this.text : text as TextAspect?,
        watermark: identical(watermark, _unset)
            ? this.watermark
            : watermark as WatermarkSpec?,
        footer:
            identical(footer, _unset) ? this.footer : footer as FooterSpec?,
        exposed: exposed ?? this.exposed,
      );
}
