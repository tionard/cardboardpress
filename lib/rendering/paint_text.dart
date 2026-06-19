part of 'paint_card.dart';

// ---------------------------------------------------------------------------
// Text
// ---------------------------------------------------------------------------

/// Lays out [text] and centres it vertically in [rect], filled with [color]
/// (single → flat fill; double → a gradient spanning the actual text box).
/// Uses dart:ui's ParagraphBuilder directly (no Flutter widgets) so the exact
/// same layout is produced for preview and for export.
void _paintText(ui.Canvas canvas, ui.Rect rect, String text, TextStyleSpec ts,
    ui.Size size, ColorValue color) {
  final weight = ts.bold ? ui.FontWeight.bold : ui.FontWeight.normal;
  final slant = ts.italic ? ui.FontStyle.italic : ui.FontStyle.normal;

  // Horizontal padding only (sides), per design — text may reach the box top.
  final pad = ts.padX * size.width;
  final box = ui.Rect.fromLTRB(
      rect.left + pad, rect.top, rect.right - pad, rect.bottom);
  if (box.width <= 1) return;

  ui.Paragraph layoutAt(double fs, {ui.Paint? fg, ui.Color? col}) {
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: ts.align,
      fontWeight: weight,
      fontStyle: slant,
      fontSize: fs,
    ))
      ..pushStyle(ui.TextStyle(
        foreground: fg,
        color: fg == null ? col : null,
        fontSize: fs,
        fontWeight: weight,
        fontStyle: slant,
      ))
      ..addText(text);
    return b.build()..layout(ui.ParagraphConstraints(width: box.width));
  }

  // Font size: fixed, or shrink until the laid-out text fits the box (height
  // and longest line). Same maths at preview and print, so it's stable.
  var fs = ts.sizeFrac * size.height;
  if (ts.fit == TextFit.shrink) {
    const measureColor = ui.Color(0xFF000000);
    var p = layoutAt(fs, col: measureColor);
    var guard = 0;
    while ((p.height > box.height || p.longestLine > box.width + 0.5) &&
        fs > 3.0 &&
        guard++ < 80) {
      fs *= 0.96;
      p = layoutAt(fs, col: measureColor);
    }
  }

  // Measure at the final size for gradient placement + vertical anchoring.
  final measure = layoutAt(fs, col: const ui.Color(0xFF000000));
  final textW = measure.longestLine;
  final textH = measure.height;

  double top;
  switch (ts.vAlign) {
    case VAlign.top:
      top = box.top;
      break;
    case VAlign.middle:
      top = box.top + (box.height - textH) / 2;
      break;
    case VAlign.bottom:
      top = box.bottom - textH;
      break;
  }
  if (top < box.top) top = box.top; // overflow clips at the bottom, never the top

  // Horizontal start of the glyph box (for the gradient), by alignment.
  double left = box.left;
  if (ts.align == ui.TextAlign.center) {
    left = box.left + (box.width - textW) / 2;
  } else if (ts.align == ui.TextAlign.right || ts.align == ui.TextAlign.end) {
    left = box.left + (box.width - textW);
  }
  final textRect = ui.Rect.fromLTWH(left, top, textW, textH);

  final shader = _doubleShader(color, textRect, ts.colorAlpha);
  final paragraph = shader != null
      ? layoutAt(fs, fg: ui.Paint()..shader = shader)
      : layoutAt(fs, col: color.c1.withValues(alpha: ts.colorAlpha));

  canvas.drawParagraph(paragraph, ui.Offset(box.left, top));
}

// ---------------------------------------------------------------------------
// Inline content: text + {tag} symbols (Cost now; rich text extends this)
// ---------------------------------------------------------------------------

/// Lays out a sequence of text + symbol [tokens] in [rect] and paints it,
/// vertically centred. Symbols become inline placeholders sized to the line
/// height, then their decoded glyph images are drawn into the placeholder
/// boxes. Uses ParagraphBuilder.addPlaceholder so text and symbols share one
/// layout pass — identical at preview and export resolution.
/// A per-run inline text style. Emphasis is the field's base bold/italic ORed
/// with the run's own (from **bold** / *italic* markup). Inline text is single
/// colour (c1); double-colour fills are a plain-text-field feature.
ui.TextStyle _runStyle(
        double fs, bool bold, bool italic, ColorValue color, double alpha) =>
    ui.TextStyle(
      color: color.c1.withValues(alpha: alpha),
      fontWeight: bold ? ui.FontWeight.bold : ui.FontWeight.normal,
      fontStyle: italic ? ui.FontStyle.italic : ui.FontStyle.normal,
      fontSize: fs,
    );

/// Draws inline content: literal text (with per-run bold/italic) interleaved
/// with {symbol} pips. Used by Cost (single line) and Rules (multi-line, which
/// wraps and — when the field is set to shrink — auto-sizes to fit the box).
/// Honours the field's side padding and vertical anchor, like plain text.
void _paintInline(
  ui.Canvas canvas,
  ui.Rect rect,
  List<InlineToken> tokens,
  TextStyleSpec ts,
  ui.Size size,
  ColorValue color,
  CardData card,
  CardRefs refs, {
  int? maxLines = 1,
}) {
  final baseBold = ts.bold;
  final baseItalic = ts.italic;
  final weight = baseBold ? ui.FontWeight.bold : ui.FontWeight.normal;
  final slant = baseItalic ? ui.FontStyle.italic : ui.FontStyle.normal;

  // Side-only padding, matching plain text fields.
  final pad = ts.padX * size.width;
  final box = ui.Rect.fromLTRB(
      rect.left + pad, rect.top, rect.right - pad, rect.bottom);
  if (box.width <= 1) return;

  // Symbol specs in placeholder order, collected once (independent of size).
  final specs = <SymbolSpec>[
    for (final tk in tokens)
      if (tk is SymbolRun) tk.spec,
  ];

  // Build the laid-out paragraph at a given font size. Each text run pushes its
  // own style (emphasis ORed with the field base); symbols are square
  // placeholders ~one line tall, so they scale with the text when it shrinks.
  ui.Paragraph build(double fs) {
    final b = ui.ParagraphBuilder(ui.ParagraphStyle(
      textAlign: ts.align,
      fontWeight: weight,
      fontStyle: slant,
      fontSize: fs,
      maxLines: maxLines,
      ellipsis: maxLines == 1 ? '\u2026' : null,
    ))
      ..pushStyle(_runStyle(fs, baseBold, baseItalic, color, ts.colorAlpha));
    for (final tk in tokens) {
      if (tk is TextRun) {
        b.pushStyle(_runStyle(fs, baseBold || tk.bold, baseItalic || tk.italic,
            color, ts.colorAlpha));
        b.addText(tk.text);
        b.pop();
      } else if (tk is SymbolRun) {
        b.addPlaceholder(
          fs,
          fs,
          ui.PlaceholderAlignment.middle,
          baseline: ui.TextBaseline.alphabetic,
        );
      }
    }
    return b.build()..layout(ui.ParagraphConstraints(width: box.width));
  }

  // Font size: fixed, or shrink until the content fits the box (height for
  // wrapped rules; longest line for a single-line cost).
  var fontSize = ts.sizeFrac * size.height;
  var paragraph = build(fontSize);
  if (ts.fit == TextFit.shrink) {
    var guard = 0;
    while ((paragraph.height > box.height ||
            paragraph.longestLine > box.width + 0.5) &&
        fontSize > 3.0 &&
        guard++ < 80) {
      fontSize *= 0.96;
      paragraph = build(fontSize);
    }
  }

  double top;
  switch (ts.vAlign) {
    case VAlign.top:
      top = box.top;
      break;
    case VAlign.middle:
      top = box.top + (box.height - paragraph.height) / 2;
      break;
    case VAlign.bottom:
      top = box.bottom - paragraph.height;
      break;
  }
  if (top < box.top) top = box.top;
  final origin = ui.Offset(box.left, top);
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
