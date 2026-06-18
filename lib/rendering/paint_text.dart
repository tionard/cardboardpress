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
