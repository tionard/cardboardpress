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
        // Field-derived layers (art/rules/footer + generic text/fill/outline/
        // border) rebuild their FieldSpec and use the real dispatcher, so their
        // rendering stays pixel-identical to the legacy path. Only a GENERIC
        // layer carrying an aspect the field model has no slot for — a fixed
        // image (decorative / silhouette / set symbol) or a per-layer foil —
        // takes the new generic sub-order drawer. No field-derived layer has
        // either aspect, so existing cards are byte-for-byte unchanged.
        if (layer.kind == LayerKind.generic &&
            (layer.image != null || layer.foil != FoilType.none)) {
          _paintGenericLayer(canvas, size, layer, card, refs);
        } else {
          _paintField(canvas, size, _layerToFieldSpec(layer), card, refs);
        }
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

// A generic layer's own draw path: it honours the fixed aspect sub-order
//   fill -> image -> border -> outline -> foil -> text
// (references/layer-redesign-decisions.md), placed/clipped by the layer's rect.
// It reuses the SAME primitive helpers as _paintField, so the shared aspects
// (fill / 9-slice / outline / text) look identical; it adds the two aspects the
// field model has no slot for: a fixed IMAGE (as-is, silhouette-tinted, or
// resolved from the card's set symbol) and a per-layer FOIL. Field-derived
// layers never reach here (none carry an image or foil aspect).
void _paintGenericLayer(
    ui.Canvas canvas, ui.Size size, Layer layer, CardData card, CardRefs refs) {
  final rect = ui.Rect.fromLTRB(
    layer.frac.left * size.width,
    layer.frac.top * size.height,
    layer.frac.right * size.width,
    layer.frac.bottom * size.height,
  );
  final r = layer.cornerRadius * size.width; // 0 => square corners
  final rrect = ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(r));

  // A 9-slice border is an ALTERNATIVE background to the flat fill (as in the
  // field model): when present it suppresses the fill and the fill-derived
  // outline — matching _paintField's spriteMode so migrated frames stay faithful.
  final spriteMode = layer.border != null;
  final fill = layer.fill == null ? null : refs.resolveColor(layer.fill!.color);
  final fillAlpha = layer.fill?.alpha ?? 1.0;

  // 1. fill
  if (fill != null && !spriteMode) {
    _fillRRect(canvas, rrect, fill, fillAlpha);
  }

  // 2. image (fixed as-is / fixed silhouette-tint / set symbol)
  final image = layer.image;
  if (image != null) {
    _paintLayerImage(canvas, rect, rrect, image, card, refs);
  }

  // 3. border (9-slice frame), drawn like _paintFieldFrame
  final frame = layer.border;
  if (frame != null && frame.hasImage) {
    final img = refs.resolveImage(frame.imageId);
    if (img != null) {
      final tint = frame.tint == null ? null : refs.resolveColor(frame.tint!);
      _paintNineSlice(canvas, rect, img, frame, size,
          tint: tint, alpha: fillAlpha);
    }
  }

  // 4. outline — explicit colour if set (draws even with no fill), else a
  //    relative shade of the fill. Suppressed in sprite mode (border present).
  final outline = layer.outline;
  if (outline != null && !spriteMode) {
    final col = _outlineColor(outline, refs, fill?.c1);
    if (col != null) {
      final strokeW = outline.thickness * size.width;
      final paint = ui.Paint()
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = strokeW
        ..color = col;
      canvas.drawRRect(rrect.deflate(strokeW / 2), paint);
    }
  }

  // 5. foil
  _paintFoil(canvas, rect, rrect, layer.foil);

  // 6. text — per-card content keyed by layer id, else the layer's literal.
  //    Inline renders single-line (as the old Cost did); a per-aspect max-lines
  //    control arrives with the authoring UI (Drop C).
  final ta = layer.text;
  if (ta != null) {
    final s = card.textContent[layer.id] ?? ta.literal ?? '';
    if (s.isNotEmpty) {
      canvas.save();
      canvas.clipRRect(rrect);
      final color = refs.resolveColor(ta.style.colorRef);
      if (ta.inline) {
        _paintInline(canvas, rect, tokenizeInline(s), ta.style, size, color,
            card, refs, maxLines: 1);
      } else {
        _paintText(canvas, rect, s, ta.style, size, color);
      }
      canvas.restore();
    }
  }
}

// The image aspect of a generic layer. `setSymbol` resolves from the card's set
// symbol and auto-tints with the rarity colour; a `fixed` image is a silhouette
// filled with its tint when one is set, otherwise drawn as-is (cover-fit +
// zoom/pan, clipped to the rounded rect, honouring the use-site alpha).
void _paintLayerImage(ui.Canvas canvas, ui.Rect rect, ui.RRect rrect,
    ImageAspect image, CardData card, CardRefs refs) {
  if (image.source == ImageSource.setSymbol) {
    final img = refs.resolveImage(card.setSymbolImageId);
    if (img == null) return;
    final tint = card.setSymbolTint;
    if (tint != null) {
      _paintTintedSymbol(
          canvas, img, rect, refs.resolveColor(tint), image.alpha);
    } else {
      _paintSetSymbol(canvas, img, rect, image.alpha);
    }
    return;
  }

  final img = refs.resolveImage(image.imageId);
  if (img == null) return;
  if (image.tint != null) {
    _paintTintedSymbol(
        canvas, img, rect, refs.resolveColor(image.tint!), image.alpha);
  } else if (image.alpha >= 1.0) {
    _paintArtImage(canvas, rrect, img, image.transform);
  } else {
    // Group the as-is draw so the use-site alpha dims it as a whole.
    canvas.saveLayer(
        rect,
        ui.Paint()
          ..color = const ui.Color(0xFFFFFFFF).withValues(alpha: image.alpha));
    _paintArtImage(canvas, rrect, img, image.transform);
    canvas.restore();
  }
}
