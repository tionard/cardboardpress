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

  // The `_border` layer can't be reordered below content (it draws outside the
  // clip, after everything), but its visibility IS honoured: hiding it in the
  // Layers tab (or per-card) suppresses the draw. Absent layer = visible, so
  // lists without a border slot keep the old behaviour.
  var borderLayerVisible = true;

  for (final layer in layers) {
    if (layer.id == kBorderLayerId) {
      borderLayerVisible = layer.visible;
      continue; // the outer border is drawn outside the clip, below
    }
    if (!layer.visible) continue;
    _paintGenericLayer(canvas, size, layer, card, refs);
  }

  canvas.restore(); // end the card clip

  // Border — outermost chrome, over everything, pure black/white: gated on
  // card.border AND the `_border` layer's visibility, drawn outside the clip.
  final border = card.border;
  if (border != null && borderLayerVisible) {
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

  // 2. image (fixed / silhouette / set symbol / per-card art)
  final image = layer.image;
  if (image != null) {
    _paintLayerImage(canvas, rect, rrect, size, layer.id, image, card, refs);
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
  _paintFoil(canvas, rect, rrect, layer.foil ?? FoilType.none);

  // 5.5 watermark — a symbol silhouette filled with a palette colour, centred in
  //     the layer, clipped to its rounded rect, drawn BEHIND the text.
  final wm = layer.watermark;
  if (wm != null) {
    final wmImg = refs.resolveImage(card.watermarkImageIds[layer.id]);
    if (wmImg != null) {
      canvas.save();
      canvas.clipRRect(rrect);
      _paintTintedSymbol(
          canvas, wmImg, rect, refs.resolveColor(wm.color), wm.alpha);
      canvas.restore();
    }
  }

  // 6. text — per-card content keyed by layer id, else the layer's fixed text;
  //    in template preview an empty result falls back to the placeholder. The
  //    multiline flag drives inline wrapping (plain text wraps to the box).
  final ta = layer.text;
  if (ta != null) {
    var s = card.textContent[layer.id] ?? '';
    if (s.isEmpty && refs.showPlaceholders) s = ta.placeholder;
    if (s.isNotEmpty) {
      canvas.save();
      canvas.clipRRect(rrect);
      final color = refs.resolveColor(ta.style.colorRef);
      if (ta.inline) {
        _paintInline(canvas, rect, tokenizeInline(s), ta.style, size, color,
            card, refs, maxLines: ta.multiline ? null : 1);
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
    ui.Size size, String layerId, ImageAspect image, CardData card,
    CardRefs refs) {
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

  if (image.source == ImageSource.cardArt) {
    // Per-card art, keyed by the layer id (= the old art field id), cover-fit
    // with its per-card transform. No image => the hatched ART placeholder.
    // The aspect's use-site alpha dims the draw (grouped, like fixed images).
    final img = refs.resolveImage(card.artImageIds[layerId]);
    if (img != null) {
      final tr = card.artTransforms[layerId] ?? const ArtTransform();
      if (image.alpha >= 1.0) {
        _paintArtImage(canvas, rrect, img, tr);
      } else {
        canvas.saveLayer(
            rect,
            ui.Paint()
              ..color =
                  const ui.Color(0xFFFFFFFF).withValues(alpha: image.alpha));
        _paintArtImage(canvas, rrect, img, tr);
        canvas.restore();
      }
    } else {
      _paintArtPlaceholder(canvas, rrect, size);
    }
    return;
  }

  // Fixed image. Per-card overrides (picture / transform / opacity / tint from
  // the exposed-image controls) are already baked onto the aspect by
  // _resolveCardLayer, so this path just draws what it's handed. In the
  // template preview an unresolved picture shows a hatched IMAGE placeholder —
  // the same feedback card-art zones give — and nothing on real cards.
  final img = refs.resolveImage(image.imageId);
  if (img == null) {
    if (refs.showPlaceholders) _paintArtPlaceholder(canvas, rrect, size, label: 'IMAGE');
    return;
  }
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
