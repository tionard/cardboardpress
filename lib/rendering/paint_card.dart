// lib/rendering/paint_card.dart
//
// THE single render path. This is the ONLY place a card is ever drawn.
// The on-screen preview, the collection thumbnails, and the exported PNG all
// call this exact function — that's the architectural promise of the app
// (spec §6, §8): what you see is what you export.
//
// Rules for this file:
//   * It is PURE: it reads a CardData (+ a CardRefs resolver) and draws. It
//     never touches storage, app state, or platform APIs.
//   * Every dimension is derived from `size` (via the 0..1 fractions on the
//     model), never a hard-coded pixel. That's why the same code is correct at
//     thumbnail size and at print resolution.
//
// If you ever find card-drawing logic living somewhere OTHER than here, that's
// the bug this architecture exists to prevent.
//
// Split across parts (one library): paintCard + the per-field dispatcher live
// here; colour fills, the text/inline-symbol engine, and the image/foil helpers
// live in paint_colors.dart / paint_text.dart / paint_images.dart. They're all
// plain top-level functions in the same library, so paintCard reaches them
// directly — no behaviour change, just navigation.

import 'dart:math' as math;
import 'dart:ui' as ui;

import '../model/card_model.dart';
import '../model/markup.dart';

part 'paint_colors.dart';
part 'paint_text.dart';
part 'paint_images.dart';

/// Draws one card into [canvas], filling a card of [size].
void paintCard(ui.Canvas canvas, ui.Size size, CardData card, CardRefs refs) {
  final w = size.width;
  final radius = card.cornerRadiusFrac * w;
  final cardRect = ui.Offset.zero & size;
  final cardRRect =
      ui.RRect.fromRectAndRadius(cardRect, ui.Radius.circular(radius));

  // --- Everything except the border is clipped to the card's rounded shape ---
  canvas.save();
  canvas.clipRRect(cardRRect);

  // 1. Card base colour (resolved from its palette reference).
  _fillRRect(canvas, cardRRect, refs.resolveColor(card.baseColor), 1.0);

  // 1a. Optional template background image, drawn OVER the base but UNDER the
  //     tint. Same cover-fit + zoom/pan as card art, clipped to the card's
  //     rounded shape. Because the tint (next step) layers on top, an opaque
  //     per-card tint still fully covers the image — tint keeps working over a
  //     template that uses a background. resolveImage returns null when the id
  //     is absent or not yet decoded, so the renderer simply skips it.
  final bgImg = refs.resolveImage(card.bgImageId);
  if (bgImg != null) {
    _paintArtImage(canvas, cardRRect, bgImg, card.bgTransform);
  }

  // 1b. Optional per-card tint, layered OVER the base at its own opacity, so a
  //     partial alpha blends toward the base (a real tint, not a full replace).
  final tint = card.tint;
  if (tint != null) {
    _fillRRect(canvas, cardRRect, refs.resolveColor(tint), card.tintAlpha);
  }

  // 2. Each field, in order. (Draw order WITHIN a field: bg → outline →
  //    content — handled inside _paintField.)
  for (final field in card.fields) {
    _paintField(canvas, size, field, card, refs);
  }

  // 2c. Set symbol — a template-placed graphic (its rect / size / opacity are
  //     template layout; its image comes from the card's set). Drawn over the
  //     fields, under the foil. If the card's rarity carries a colour, the
  //     symbol is tinted by it (silhouette fill); otherwise it draws as-is.
  //     Contain-fit + centred so the aspect ratio holds at any placement size.
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
      // Tinted: the symbol becomes a silhouette filled with the rarity colour
      // (single or double), the image acting as an alpha mask.
      _paintTintedSymbol(canvas, ssImg, dst, refs.resolveColor(tint), ssp.alpha);
    } else {
      _paintSetSymbol(canvas, ssImg, dst, ssp.alpha);
    }
  }

  // 3. Foil overlay, over the card content (but below the border).
  _paintFoil(canvas, cardRect, cardRRect, card.foil);

  canvas.restore(); // end the card clip

  // 4. Border — outermost chrome, drawn OVER everything, always pure
  //    black/white, never tinted or foiled (spec §3.5).
  final border = card.border;
  if (border != null) {
    final stroke = border.thickness * w;
    final paint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = stroke
      ..color = border.black
          ? const ui.Color(0xFF000000)
          : const ui.Color(0xFFFFFFFF);
    // Inset by half the stroke width so the line sits inside the card edge.
    canvas.drawRRect(cardRRect.deflate(stroke / 2), paint);
  }
}

// ---------------------------------------------------------------------------
// Fields
// ---------------------------------------------------------------------------

void _paintField(
    ui.Canvas canvas, ui.Size size, FieldSpec field, CardData card, CardRefs refs) {
  final rect = ui.Rect.fromLTRB(
    field.frac.left * size.width,
    field.frac.top * size.height,
    field.frac.right * size.width,
    field.frac.bottom * size.height,
  );
  final r = field.cornerRadius * size.width; // 0 => square corners
  final rrect = ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(r));

  // Art has no background/outline — just its image (a placeholder here).
  // Art: draw the resolved image (cover-fit, clipped) if present, else a
  // placeholder. The image is resolved via refs — never loaded here.
  if (field.type == FieldType.art) {
    final img = refs.resolveImage(card.artImageIds[field.id]);
    if (img != null) {
      _paintArtImage(canvas, rrect, img,
          card.artTransforms[field.id] ?? const ArtTransform());
    } else {
      _paintArtPlaceholder(canvas, rrect, size);
    }
    return;
  }

  // Resolve the fill reference once; outline is derived from the SAME resolved
  // value so it tracks live palette edits too.
  final fill = field.fill == null ? null : refs.resolveColor(field.fill!);

  // 2.1 Background fill (flat for now; 9-slice sprites come later).
  if (fill != null) {
    _fillRRect(canvas, rrect, fill, field.fillAlpha);
  }

  // 2.2 Outline — a relative shade of the fill, so it tracks the fill.
  final outline = field.outline;
  if (outline != null && fill != null) {
    final shaded = _shade(fill.c1, lighter: outline.lighter, t: outline.intensity);
    final strokeW = outline.thickness * size.width;
    final paint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..color = shaded;
    canvas.drawRRect(rrect.deflate(strokeW / 2), paint);
  }

  // 2.x Watermark (a property of the Rules field): a symbol silhouette filled
  //     with a palette colour, centred in the field and drawn BEHIND the text.
  //     Clipped to the field's rounded rect so it never bleeds past the corners.
  final wm = field.watermark;
  if (wm != null) {
    final wmImg = refs.resolveImage(card.watermarkImageIds[field.id]);
    if (wmImg != null) {
      canvas.save();
      canvas.clipRRect(rrect);
      _paintTintedSymbol(canvas, wmImg, rect, refs.resolveColor(wm.color), wm.alpha);
      canvas.restore();
    }
  }

  // 2.3 Content — text, drawn in its resolved colour (single or double).
  //     Cost renders inline text + {tag} symbols; other text fields are plain.
  //     (Rules rich-text joins the inline path with bold/italic/size later.)
  //     Keyed by field id.
  //
  //     Text is clipped to the field box so overflow is hidden rather than
  //     spilling past the border; horizontal padding and vertical anchoring are
  //     handled inside the painters (per the field's text style).
  canvas.save();
  canvas.clipRRect(rrect);
  final s = card.textContent[field.id] ?? '';
  // Cost and Rules both run through the inline engine (text + {symbols} +
  // **bold**/*italic*). Cost is single-line; Rules wraps to many lines.
  final inline =
      field.type == FieldType.cost || field.type == FieldType.rules;
  if (field.type == FieldType.footer &&
      field.footer != null &&
      field.text != null) {
    // Configured footer: paint each zone's pieces anchored to its corner/edge.
    _paintFooterZones(canvas, rect, field.footer!, field.text!, card, refs, size);
  } else if (inline) {
    final ts = field.text;
    if (s.isNotEmpty && ts != null) {
      final color = refs.resolveColor(ts.colorRef);
      _paintInline(canvas, rect, tokenizeInline(s), ts, size, color, card, refs,
          maxLines: field.type == FieldType.cost ? 1 : null);
    }
  } else if (field.text != null) {
    if (s.isNotEmpty) {
      final textColor = refs.resolveColor(field.text!.colorRef);
      _paintText(canvas, rect, s, field.text!, size, textColor);
    }
  }
  canvas.restore();
}

// Footer zones: for each live zone, join its assigned components (in order,
// skipping empties) and paint them anchored to the matching corner/edge of the
// footer box. All zones share the footer field's text style; only the
// alignment changes. The box's size/position decides how the zones sit — make
// it ~2 lines tall for the 4-corners mode so top and bottom rows don't collide.
void _paintFooterZones(ui.Canvas canvas, ui.Rect rect, FooterSpec spec,
    TextStyleSpec ts, CardData card, CardRefs refs, ui.Size size) {
  final color = refs.resolveColor(ts.colorRef);
  for (final zone in spec.zones) {
    final parts = <String>[
      for (final item in spec.items)
        if (item.zone == zone &&
            (card.footerValues[item.component] ?? '').isNotEmpty)
          card.footerValues[item.component]!,
    ];
    if (parts.isEmpty) continue;
    final (align, vAlign) = _footerZoneAnchor(zone, ts.align);
    _paintText(canvas, rect, parts.join('  ·  '),
        ts.copyWith(align: align, vAlign: vAlign), size, color);
  }
}

(ui.TextAlign, VAlign) _footerZoneAnchor(FooterZone zone, ui.TextAlign dflt) {
  switch (zone) {
    case FooterZone.line:
      return (dflt, VAlign.middle);
    case FooterZone.left:
      return (ui.TextAlign.left, VAlign.middle);
    case FooterZone.right:
      return (ui.TextAlign.right, VAlign.middle);
    case FooterZone.topLeft:
      return (ui.TextAlign.left, VAlign.top);
    case FooterZone.topRight:
      return (ui.TextAlign.right, VAlign.top);
    case FooterZone.bottomLeft:
      return (ui.TextAlign.left, VAlign.bottom);
    case FooterZone.bottomRight:
      return (ui.TextAlign.right, VAlign.bottom);
  }
}
