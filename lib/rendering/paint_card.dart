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

  // 1. Card base colour.
  _fillRRect(canvas, cardRRect, card.baseColor, 1.0);

  // 2. Each field, in order. (Draw order WITHIN a field: bg → outline →
  //    content — handled inside _paintField.)
  for (final field in card.fields) {
    _paintField(canvas, size, field, card);
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

void _paintField(ui.Canvas canvas, ui.Size size, FieldSpec field, CardData card) {
  final rect = ui.Rect.fromLTRB(
    field.frac.left * size.width,
    field.frac.top * size.height,
    field.frac.right * size.width,
    field.frac.bottom * size.height,
  );
  final r = field.sharp ? 0.0 : field.cornerRadius * size.width;
  final rrect = ui.RRect.fromRectAndRadius(rect, ui.Radius.circular(r));

  // Art has no background/outline — just its image (a placeholder here).
  if (field.type == FieldType.art) {
    _paintArtPlaceholder(canvas, rrect, size);
    return;
  }

  // 2.1 Background fill (flat for now; 9-slice sprites come later).
  if (field.fill != null) {
    _fillRRect(canvas, rrect, field.fill!, field.fillAlpha);
  }

  // 2.2 Outline — a relative shade of the fill, so it tracks the fill.
  final outline = field.outline;
  if (outline != null && field.fill != null) {
    final shaded = _shade(field.fill!.c1,
        lighter: outline.lighter, t: outline.intensity);
    final strokeW = outline.thickness * size.width;
    final paint = ui.Paint()
      ..style = ui.PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..color = shaded;
    canvas.drawRRect(rrect.deflate(strokeW / 2), paint);
  }

  // 2.3 Content — text. (Rules rich-text + inline symbols come later; for the
  //     spike every text field is laid out as one simple paragraph.)
  if (field.text != null) {
    final s = card.textContent[field.type] ?? '';
    if (s.isNotEmpty) _paintText(canvas, rect, s, field.text!, size);
  }
}

// ---------------------------------------------------------------------------
// Colour fills (single + double)
// ---------------------------------------------------------------------------

/// Fills [rrect] with a [ColorValue] at use-site [alpha].
/// A single colour paints flat; a double colour paints a two-stop gradient
/// split along its orientation, with a mix band whose width is [ColorValue.mix].
void _fillRRect(ui.Canvas canvas, ui.RRect rrect, ColorValue cv, double alpha) {
  final paint = ui.Paint();

  if (cv.isDouble) {
    // Bake the use-site opacity straight into the gradient colours (a shader
    // ignores paint.color's RGB, so this is the clean way to apply alpha).
    final c1 = cv.c1.withOpacity(alpha);
    final c2 = cv.c2!.withOpacity(alpha);

    final m = cv.mix.clamp(0.0, 1.0);
    final half = m / 2;
    // m==0 => duplicate stops at 0.5 => hard edge. m==1 => blend across all.
    final stops = <double>[0.0, 0.5 - half, 0.5 + half, 1.0];
    final colors = <ui.Color>[c1, c1, c2, c2];

    final rect = rrect.outerRect;
    final (from, to) = cv.orientation == MixOrientation.vertical
        ? (rect.topCenter, rect.bottomCenter)
        : (rect.centerLeft, rect.centerRight);

    paint.shader = ui.Gradient.linear(from, to, colors, stops);
  } else {
    paint.color = cv.c1.withOpacity(alpha);
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

/// Lays out [text] as a single paragraph and centres it vertically in [rect].
/// Uses dart:ui's ParagraphBuilder directly (no Flutter widgets) so the exact
/// same layout is produced for preview and for export.
void _paintText(
    ui.Canvas canvas, ui.Rect rect, String text, TextStyleSpec ts, ui.Size size) {
  final fontSize = ts.sizeFrac * size.height;
  final weight = ts.bold ? ui.FontWeight.bold : ui.FontWeight.normal;
  final slant = ts.italic ? ui.FontStyle.italic : ui.FontStyle.normal;

  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
    textAlign: ts.align,
    fontWeight: weight,
    fontStyle: slant,
    fontSize: fontSize,
    maxLines: 4,
    ellipsis: '…',
  ))
    ..pushStyle(ui.TextStyle(
      color: ts.color,
      fontWeight: weight,
      fontStyle: slant,
      fontSize: fontSize,
    ))
    ..addText(text);

  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: rect.width));

  final dy = rect.top + (rect.height - paragraph.height) / 2;
  canvas.drawParagraph(
      paragraph, ui.Offset(rect.left, dy < rect.top ? rect.top : dy));
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
        sizeFrac: 0.04, align: ui.TextAlign.center, color: ui.Color(0x66000000)),
    size,
  );
}
