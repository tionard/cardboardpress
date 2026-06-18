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
import '../model/markup.dart';

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
  //     template layout). Drawn over the fields, under the foil. Untinted for
  //     now; the rarity-colour tint is the next step. Contain-fit + centred so
  //     the symbol's aspect ratio is preserved at any placement size.
  final ssp = card.setSymbolPlacement;
  final ssImg = refs.resolveImage(card.setSymbolImageId);
  if (ssp != null && ssp.enabled && ssImg != null) {
    final dst = ui.Rect.fromLTRB(
      ssp.frac.left * size.width,
      ssp.frac.top * size.height,
      ssp.frac.right * size.width,
      ssp.frac.bottom * size.height,
    );
    _paintSetSymbol(canvas, ssImg, dst, ssp.alpha);
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

  // 2.3 Content — text, drawn in its resolved colour (single or double).
  //     Cost renders inline text + {tag} symbols; other text fields are plain.
  //     (Rules rich-text joins the inline path with bold/italic/size later.)
  //     Keyed by field id.
  if (field.type == FieldType.cost) {
    final s = card.textContent[field.id] ?? '';
    final ts = field.text;
    if (s.isNotEmpty && ts != null) {
      final color = refs.resolveColor(ts.colorRef);
      _paintInline(canvas, rect, tokenizeInline(s), ts, size, color, card, refs,
          maxLines: 1);
    }
  } else if (field.text != null) {
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
// Inline content: text + {tag} symbols (Cost now; rich text extends this)
// ---------------------------------------------------------------------------

/// Lays out a sequence of text + symbol [tokens] in [rect] and paints it,
/// vertically centred. Symbols become inline placeholders sized to the line
/// height, then their decoded glyph images are drawn into the placeholder
/// boxes. Uses ParagraphBuilder.addPlaceholder so text and symbols share one
/// layout pass — identical at preview and export resolution.
void _paintInline(
  ui.Canvas canvas,
  ui.Rect rect,
  List<InlineToken> tokens,
  TextStyleSpec ts,
  ui.Size size,
  ColorValue color,
  CardData card,
  CardRefs refs, {
  int maxLines = 1,
}) {
  final fontSize = ts.sizeFrac * size.height;
  final weight = ts.bold ? ui.FontWeight.bold : ui.FontWeight.normal;
  final slant = ts.italic ? ui.FontStyle.italic : ui.FontStyle.normal;

  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
    textAlign: ts.align,
    fontWeight: weight,
    fontStyle: slant,
    fontSize: fontSize,
    maxLines: maxLines,
    ellipsis: '…',
  ))
    ..pushStyle(ui.TextStyle(
      color: color.c1.withValues(alpha: ts.colorAlpha),
      fontWeight: weight,
      fontStyle: slant,
      fontSize: fontSize,
    ));

  // Collect a symbol spec per placeholder, in the order placeholders are added,
  // so we can match each placeholder box to its symbol after layout.
  final specs = <SymbolSpec>[];
  final side = fontSize; // square glyph, roughly one line tall
  for (final tk in tokens) {
    if (tk is TextRun) {
      builder.addText(tk.text);
    } else if (tk is SymbolRun) {
      specs.add(tk.spec);
      builder.addPlaceholder(
        side,
        side,
        ui.PlaceholderAlignment.middle,
        baseline: ui.TextBaseline.alphabetic,
      );
    }
  }

  final paragraph = builder.build()
    ..layout(ui.ParagraphConstraints(width: rect.width));

  final top = rect.top + (rect.height - paragraph.height) / 2;
  final clampedTop = top < rect.top ? rect.top : top;
  final origin = ui.Offset(rect.left, clampedTop);
  canvas.drawParagraph(paragraph, origin);

  final boxes = paragraph.getBoxesForPlaceholders();
  for (var i = 0; i < boxes.length && i < specs.length; i++) {
    final b = boxes[i];
    _drawSymbol(
      canvas,
      ui.Rect.fromLTRB(origin.dx + b.left, origin.dy + b.top,
          origin.dx + b.right, origin.dy + b.bottom),
      specs[i],
      card,
      refs,
    );
  }
}

// ---------------------------------------------------------------------------
// Symbol drawing (atoms, numeric pips, splits, overlays)
// ---------------------------------------------------------------------------

const _numPipBg = ui.Color(0xFFBEB9AD); // generic numeric pip background
const _numPipFg = ui.Color(0xFF2C2B27); // numeric pip text

/// Draws a (possibly composite) symbol into [box].
void _drawSymbol(ui.Canvas canvas, ui.Rect box, SymbolSpec spec, CardData card,
    CardRefs refs) {
  switch (spec) {
    case AtomSymbol(:final token):
      final img = refs.resolveImage(card.symbolImageIds[token]);
      if (img != null) {
        _drawImageContain(canvas, img, box);
      } else if (_isAllDigits(token)) {
        _drawNumberPip(canvas, box, token); // any number -> grey pip
      }
    // unknown non-numeric atom with no image -> leave the gap blank

    case SplitSymbol(:final a, :final b):
      // Anti-diagonal split: top-left = a, bottom-right = b. Each half draws
      // its sub-symbol at full size, clipped to its triangle.
      final tl = ui.Path()
        ..moveTo(box.left, box.top)
        ..lineTo(box.right, box.top)
        ..lineTo(box.left, box.bottom)
        ..close();
      final br = ui.Path()
        ..moveTo(box.right, box.top)
        ..lineTo(box.right, box.bottom)
        ..lineTo(box.left, box.bottom)
        ..close();
      canvas.save();
      canvas.clipPath(tl);
      _drawSymbol(canvas, box, a, card, refs);
      canvas.restore();
      canvas.save();
      canvas.clipPath(br);
      _drawSymbol(canvas, box, b, card, refs);
      canvas.restore();
      canvas.drawLine(
        box.topRight,
        box.bottomLeft,
        ui.Paint()
          ..color = const ui.Color(0x33000000)
          ..strokeWidth = box.width * 0.04
          ..style = ui.PaintingStyle.stroke,
      );

    case OverlaySymbol(:final number, :final base):
      _drawSymbol(canvas, box, base, card, refs);
      _drawNumberText(canvas, box, number, const ui.Color(0xFFFFFFFF),
          withShadow: true);
  }
}

bool _isAllDigits(String s) =>
    s.isNotEmpty && s.codeUnits.every((c) => c >= 0x30 && c <= 0x39);

/// A grey pip with [number] centred inside it (the generic numeric symbol).
void _drawNumberPip(ui.Canvas canvas, ui.Rect box, String number) {
  final r = math.min(box.width, box.height) / 2;
  canvas.drawCircle(
    box.center,
    r,
    ui.Paint()
      ..color = _numPipBg
      ..isAntiAlias = true,
  );
  _drawNumberText(canvas, box, number, _numPipFg);
}

/// Draws [number] centred in [box], shrinking to fit multi-digit values.
void _drawNumberText(ui.Canvas canvas, ui.Rect box, String number,
    ui.Color color,
    {bool withShadow = false}) {
  final inner = box.width * 0.74; // keep digits inside the circle
  var fontSize = box.height * 0.62;

  ui.Paragraph build(double fs) => (ui.ParagraphBuilder(ui.ParagraphStyle(
        textAlign: ui.TextAlign.center,
        fontSize: fs,
        fontWeight: ui.FontWeight.bold,
      ))
        ..pushStyle(ui.TextStyle(
          color: color,
          fontSize: fs,
          fontWeight: ui.FontWeight.bold,
          shadows: withShadow
              ? const [ui.Shadow(color: ui.Color(0xCC000000), blurRadius: 2)]
              : null,
        ))
        ..addText(number))
      .build()
    ..layout(ui.ParagraphConstraints(width: box.width));

  var paragraph = build(fontSize);
  if (paragraph.longestLine > inner && paragraph.longestLine > 0) {
    fontSize *= inner / paragraph.longestLine;
    paragraph = build(fontSize);
  }
  final topY = box.top + (box.height - paragraph.height) / 2;
  canvas.drawParagraph(paragraph, ui.Offset(box.left, topY));
}

/// Draws [img] centred inside [dst], preserving aspect ratio (letterboxed).
/// Draws the set symbol contain-fit into [dst] at [alpha] opacity. At full
/// opacity it draws directly; otherwise it goes through a layer so the whole
/// symbol fades uniformly (rather than per-pixel double-blending).
void _paintSetSymbol(
    ui.Canvas canvas, ui.Image img, ui.Rect dst, double alpha) {
  final a = alpha.clamp(0.0, 1.0);
  if (a >= 1.0) {
    _drawImageContain(canvas, img, dst);
    return;
  }
  if (a <= 0.0) return;
  canvas.saveLayer(dst, ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, a));
  _drawImageContain(canvas, img, dst);
  canvas.restore();
}

void _drawImageContain(ui.Canvas canvas, ui.Image img, ui.Rect dst) {
  final iw = img.width.toDouble();
  final ih = img.height.toDouble();
  if (iw <= 0 || ih <= 0) return;
  final scale = math.min(dst.width / iw, dst.height / ih);
  final w = iw * scale;
  final h = ih * scale;
  final left = dst.left + (dst.width - w) / 2;
  final top = dst.top + (dst.height - h) / 2;
  canvas.drawImageRect(
    img,
    ui.Rect.fromLTWH(0, 0, iw, ih),
    ui.Rect.fromLTWH(left, top, w, h),
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
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
