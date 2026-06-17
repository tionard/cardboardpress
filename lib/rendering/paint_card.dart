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

import 'dart:math' as math;
import 'dart:ui' as ui;

import '../model/card_model.dart';

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
  final r = field.sharp ? 0.0 : field.cornerRadius * size.width;
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

  // 2.3 Content — text, drawn in its resolved colour (single or double).
  //     (Rules rich-text + inline symbols come later.) Keyed by field id.
  if (field.text != null) {
    final s = card.textContent[field.id] ?? '';
    if (s.isNotEmpty) {
      final textColor = refs.resolveColor(field.text!.colorRef);
      _paintText(canvas, rect, s, field.text!, size, textColor);
    }
  }
}

// ---------------------------------------------------------------------------
// Colour fills (single + double)
// ---------------------------------------------------------------------------

/// Builds a linear gradient shader for a *double* [ColorValue] spanning [rect],
/// with the use-site [alpha] baked into the colours. Returns null for a single
/// colour. Shared by area fills and text, so a double colour looks consistent
/// wherever it's applied.
ui.Shader? _doubleShader(ColorValue cv, ui.Rect rect, double alpha) {
  if (!cv.isDouble) return null;
  final c1 = cv.c1.withValues(alpha: alpha);
  final c2 = cv.c2!.withValues(alpha: alpha);
  final m = cv.mix.clamp(0.0, 1.0);
  final half = m / 2;
  // m==0 => duplicate stops at 0.5 => hard edge. m==1 => blend across all.
  final stops = <double>[0.0, 0.5 - half, 0.5 + half, 1.0];
  final colors = <ui.Color>[c1, c1, c2, c2];
  final (from, to) = cv.orientation == MixOrientation.vertical
      ? (rect.topCenter, rect.bottomCenter)
      : (rect.centerLeft, rect.centerRight);
  return ui.Gradient.linear(from, to, colors, stops);
}

/// Fills [rrect] with a [ColorValue] at use-site [alpha] (single or double).
void _fillRRect(ui.Canvas canvas, ui.RRect rrect, ColorValue cv, double alpha) {
  final paint = ui.Paint();
  final shader = _doubleShader(cv, rrect.outerRect, alpha);
  if (shader != null) {
    paint.shader = shader;
  } else {
    paint.color = cv.c1.withValues(alpha: alpha);
  }
  canvas.drawRRect(rrect, paint);
}

/// Lerp a colour toward white (lighter) or black (darker) by [t] (0..1).
ui.Color _shade(ui.Color base, {required bool lighter, required double t}) {
  final target =
      lighter ? const ui.Color(0xFFFFFFFF) : const ui.Color(0xFF000000);
  return ui.Color.lerp(base, target, t.clamp(0.0, 1.0))!;
}

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

/// Lays out [text] and centres it vertically in [rect], filled with [color]
/// (single → flat fill; double → a gradient spanning the actual text box).
/// Uses dart:ui's ParagraphBuilder directly (no Flutter widgets) so the exact
/// same layout is produced for preview and for export.
void _paintText(ui.Canvas canvas, ui.Rect rect, String text, TextStyleSpec ts,
    ui.Size size, ColorValue color) {
  final fontSize = ts.sizeFrac * size.height;
  final weight = ts.bold ? ui.FontWeight.bold : ui.FontWeight.normal;
  final slant = ts.italic ? ui.FontStyle.italic : ui.FontStyle.normal;

  ui.ParagraphStyle paraStyle() => ui.ParagraphStyle(
        textAlign: ts.align,
        fontWeight: weight,
        fontStyle: slant,
        fontSize: fontSize,
        maxLines: 4,
        ellipsis: '…',
      );

  // First pass: measure the laid-out text so a double-colour gradient can span
  // the actual glyph box (not the whole field), matching the swatch preview.
  final measure = (ui.ParagraphBuilder(paraStyle())
        ..pushStyle(ui.TextStyle(
            fontSize: fontSize, fontWeight: weight, fontStyle: slant))
        ..addText(text))
      .build()
    ..layout(ui.ParagraphConstraints(width: rect.width));

  final textW = measure.longestLine;
  final textH = measure.height;
  final top = rect.top + (rect.height - textH) / 2;
  final clampedTop = top < rect.top ? rect.top : top;

  // Horizontal start of the text within the field, by alignment — so the
  // gradient lines up with where the glyphs are actually drawn.
  double left = rect.left;
  if (ts.align == ui.TextAlign.center) {
    left = rect.left + (rect.width - textW) / 2;
  } else if (ts.align == ui.TextAlign.right || ts.align == ui.TextAlign.end) {
    left = rect.left + (rect.width - textW);
  }
  final textRect = ui.Rect.fromLTWH(left, clampedTop, textW, textH);

  final shader = _doubleShader(color, textRect, ts.colorAlpha);
  final runStyle = shader != null
      ? ui.TextStyle(
          foreground: ui.Paint()..shader = shader,
          fontSize: fontSize,
          fontWeight: weight,
          fontStyle: slant)
      : ui.TextStyle(
          color: color.c1.withValues(alpha: ts.colorAlpha),
          fontSize: fontSize,
          fontWeight: weight,
          fontStyle: slant);

  // Second pass: real paragraph with the resolved fill.
  final paragraph = (ui.ParagraphBuilder(paraStyle())
        ..pushStyle(runStyle)
        ..addText(text))
      .build()
    ..layout(ui.ParagraphConstraints(width: rect.width));

  canvas.drawParagraph(paragraph, ui.Offset(rect.left, clampedTop));
}

// ---------------------------------------------------------------------------
// Foil
// ---------------------------------------------------------------------------

void _paintFoil(
    ui.Canvas canvas, ui.Rect rect, ui.RRect rrect, FoilType foil) {
  if (foil == FoilType.none) return;

  const transparent = ui.Color(0x00FFFFFF);
  final colors = switch (foil) {
    FoilType.holo => <ui.Color>[
        transparent,
        const ui.Color(0x8078B4FF), // blue
        const ui.Color(0x80FFAADC), // pink
        const ui.Color(0x80AAFFC8), // green
        transparent,
      ],
    FoilType.gold => <ui.Color>[
        transparent,
        const ui.Color(0x80ECD9A8),
        const ui.Color(0x99FFF3CF),
        const ui.Color(0x80ECD9A8),
        transparent,
      ],
    FoilType.none => const <ui.Color>[],
  };
  const stops = <double>[0.0, 0.36, 0.5, 0.64, 1.0];

  final shader =
      ui.Gradient.linear(rect.topLeft, rect.bottomRight, colors, stops);

  // A "screen" blended layer lightens what's underneath where the sweep is
  // coloured, and does nothing where it's transparent — a believable foil.
  canvas.saveLayer(rect, ui.Paint()..blendMode = ui.BlendMode.screen);
  canvas.drawRRect(rrect, ui.Paint()..shader = shader);
  canvas.restore();
}

// ---------------------------------------------------------------------------
// Art placeholder (temporary — real image picking comes later)
// ---------------------------------------------------------------------------

void _paintArtImage(
    ui.Canvas canvas, ui.RRect rrect, ui.Image img, ArtTransform t) {
  final dst = rrect.outerRect;
  final iw = img.width.toDouble();
  final ih = img.height.toDouble();

  // Cover-fit baseline: the centred crop that fills dst at zoom 1.
  final scale = math.max(dst.width / iw, dst.height / ih);
  final zoom = t.zoom <= 0 ? 1.0 : t.zoom;
  final cropW = (dst.width / scale) / zoom; // zoom in => smaller source crop
  final cropH = (dst.height / scale) / zoom;

  // Pan slides the crop within the leftover image (slack); -1..1 maps edge to
  // edge, 0 stays centred. Clamped so the crop never leaves the image.
  final slackX = iw - cropW;
  final slackY = ih - cropH;
  final px = t.panX.clamp(-1.0, 1.0);
  final py = t.panY.clamp(-1.0, 1.0);
  final left = (slackX / 2) * (1 + px);
  final top = (slackY / 2) * (1 + py);

  final src = ui.Rect.fromLTWH(left, top, cropW, cropH);

  canvas.save();
  canvas.clipRRect(rrect);
  canvas.drawImageRect(
      img, src, dst, ui.Paint()..filterQuality = ui.FilterQuality.medium);
  canvas.restore();
}

void _paintArtPlaceholder(ui.Canvas canvas, ui.RRect rrect, ui.Size size) {
  final rect = rrect.outerRect;
  canvas.save();
  canvas.clipRRect(rrect);
  canvas.drawRect(rect, ui.Paint()..color = const ui.Color(0xFFE4E1D8));

  final line = ui.Paint()
    ..color = const ui.Color(0x22000000)
    ..strokeWidth = size.width * 0.004;
  for (double x = rect.left - rect.height;
      x < rect.right;
      x += size.width * 0.06) {
    canvas.drawLine(
        ui.Offset(x, rect.bottom), ui.Offset(x + rect.height, rect.top), line);
  }
  canvas.restore();

  _paintText(
    canvas,
    rect,
    'ART',
    const TextStyleSpec(
      sizeFrac: 0.04,
      align: ui.TextAlign.center,
      colorRef: ColorRef.literal(ColorValue.single(ui.Color(0xFF000000))),
      colorAlpha: 0.4,
    ),
    size,
    const ColorValue.single(ui.Color(0xFF000000)),
  );
}
