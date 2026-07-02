// lib/rendering/paint_card_layers.dart
//
// LAYER REDESIGN — Phase 1b-ii: the parallel, layer-driven renderer.
//
// `part of 'paint_card.dart'` so it reuses that library's private draw helpers
// (_fillRRect, _paintArtImage, _paintTintedSymbol, _paintSetSymbol, _paintFoil,
// _paintField) with zero re-implementation. It walks a `List<Layer>`
// (bottom→top) and reproduces `paintCard` exactly: chrome layers (base / bg /
// tint / set symbol / foil / border) draw from the CardData by their reserved
// ids, and each field layer is rebuilt into its original FieldSpec and handed to
// the real `_paintField`.
//
// This exists ONLY to prove the migration is pixel-identical (see the parity
// test). The live app still calls `paintCard`; Phase 2 flips it.

part of 'paint_card.dart';

/// Draws one card from its migrated [layers], filling a card of [size].
/// Intended to be byte-for-byte identical to `paintCard` for a layer list
/// produced by `templateToLayers`.
void paintCardFromLayers(
    ui.Canvas canvas, ui.Size size, CardData card, List<Layer> layers, CardRefs refs) {
  final w = size.width;
  final radius = card.cornerRadiusFrac * w;
  final cardRect = ui.Offset.zero & size;
  final cardRRect =
      ui.RRect.fromRectAndRadius(cardRect, ui.Radius.circular(radius));

  // Everything except the border is clipped to the card's rounded shape.
  canvas.save();
  canvas.clipRRect(cardRRect);

  for (final layer in layers) {
    if (!layer.visible) continue;
    switch (layer.id) {
      case kBaseLayerId:
        _fillRRect(canvas, cardRRect, refs.resolveColor(card.baseColor), 1.0);
      case kBgLayerId:
        {
          final bgImg = refs.resolveImage(card.bgImageId);
          if (bgImg != null) {
            _paintArtImage(canvas, cardRRect, bgImg, card.bgTransform);
          }
        }
      case kTintLayerId:
        {
          final tint = card.tint;
          if (tint != null) {
            _fillRRect(
                canvas, cardRRect, refs.resolveColor(tint), card.tintAlpha);
          }
        }
      case kSetSymbolLayerId:
        _paintSetSymbolChrome(canvas, size, card, refs);
      case kFoilLayerId:
        _paintFoil(canvas, cardRect, cardRRect, card.foil);
      case kBorderLayerId:
        break; // the outer border is drawn outside the clip, below
      default:
        // A field layer: rebuild its FieldSpec and use the real dispatcher, so
        // field rendering is guaranteed identical.
        _paintField(canvas, size, _layerToFieldSpec(layer), card, refs);
    }
  }

  canvas.restore(); // end the card clip

  // Border — outermost chrome, over everything, pure black/white. Identical to
  // paintCard: gated on card.border, drawn outside the clip. (The optional
  // `_border` layer is just a Layers-list marker; this is the real draw.)
  final border = card.border;
  if (border != null) {
    final stroke = border.thickness * w;
    final paint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = border.black
          ? const ui.Color(0xFF000000)
          : const ui.Color(0xFFFFFFFF);
    canvas.drawRRect(cardRRect.deflate(stroke / 2), paint);
  }
}

// The set-symbol chrome block, lifted verbatim from paintCard.
void _paintSetSymbolChrome(
    ui.Canvas canvas, ui.Size size, CardData card, CardRefs refs) {
  final ssp = card.setSymbolPlacement;
  final ssImg = refs.resolveImage(card.setSymbolImageId);
  if (ssp != null && ssp.enabled && ssImg != null) {
    final dst = ui.Rect.fromLTRB(
      ssp.frac.left * size.width,
      ssp.frac.top * size.height,
      ssp.frac.right * size.width,
      ssp.frac.bottom * size.height,
    );
    final tint = card.setSymbolTint;
    if (tint != null) {
      _paintTintedSymbol(canvas, ssImg, dst, refs.resolveColor(tint), ssp.alpha);
    } else {
      _paintSetSymbol(canvas, ssImg, dst, ssp.alpha);
    }
  }
}

// Rebuild the original FieldSpec from a field layer. The reconstructed `type`
// only needs to drive the same `_paintField` branch the original took:
//   art → art; rules → rules (inline, multi-line); footer → footer zones;
//   generic + inline text → cost (inline, single-line); generic plain → name
//   (any non-special plain-text type renders identically).
// Every other FieldSpec field is carried through unchanged, so `_paintField`
// produces identical pixels.
FieldSpec _layerToFieldSpec(Layer layer) {
  final type = switch (layer.kind) {
    LayerKind.art => FieldType.art,
    LayerKind.rules => FieldType.rules,
    LayerKind.footer => FieldType.footer,
    LayerKind.generic =>
      (layer.text?.inline ?? false) ? FieldType.cost : FieldType.name,
  };
  return FieldSpec(
    id: layer.id,
    type: type,
    frac: layer.frac,
    cornerRadius: layer.cornerRadius,
    fill: layer.fill?.color,
    fillAlpha: layer.fill?.alpha ?? 1.0,
    outline: layer.outline,
    text: layer.text?.style,
    watermark: layer.watermark,
    footer: layer.footer,
    frame: layer.border,
  );
}
