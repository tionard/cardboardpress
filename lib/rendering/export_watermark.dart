// lib/rendering/export_watermark.dart
//
// The free-tier export watermark. This is EXPORT-ONLY chrome, deliberately kept
// OUT of paintCard: paintCard renders the card faithfully (so preview == export
// for the card itself), and this stamp is overlaid AFTERWARDS by the export path
// only when the user isn't Pro. It is never card content and never appears in
// the live preview.
//
// PLACEHOLDER: this draws a procedural diagonal wordmark, so there's no asset to
// bundle. To swap in real art later, decode your PNG to a ui.Image once and
// tile/stamp it in here — nothing else in the pipeline changes, because the
// export path just calls drawExportWatermark().

import 'dart:math' as math;
import 'dart:ui' as ui;

/// Overlays the free-tier watermark across [size] (the export canvas). Sizing is
/// all relative to [size], so it looks the same at 300 and 600 DPI.
void drawExportWatermark(ui.Canvas canvas, ui.Size size) {
  const text = 'CardboardPress';
  final fontSize = size.width * 0.05;
  final mark = _wordmark(text, fontSize);

  final tileW = mark.maxIntrinsicWidth + size.width * 0.10; // wordmark + gap
  final tileH = fontSize * 3.0;
  final diag = math.sqrt(size.width * size.width + size.height * size.height);

  canvas.save();
  // Rotate around the centre so the repeated wordmark runs diagonally — the
  // classic "sample image" look, and awkward to crop out of a card face.
  canvas.translate(size.width / 2, size.height / 2);
  canvas.rotate(-math.pi / 6); // -30 degrees
  canvas.translate(-size.width / 2, -size.height / 2);

  var row = 0;
  for (double y = -diag; y < diag; y += tileH) {
    final offset = row.isEven ? 0.0 : tileW / 2; // brick-stagger the rows
    for (double x = -diag; x < diag; x += tileW) {
      canvas.drawParagraph(mark, ui.Offset(x + offset, y));
    }
    row++;
  }
  canvas.restore();
}

ui.Paragraph _wordmark(String text, double fontSize) {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
    fontSize: fontSize,
    fontWeight: ui.FontWeight.w700,
  ))
    ..pushStyle(ui.TextStyle(
      // Translucent white with a soft dark shadow, so it reads on most card
      // colours. (A real asset will do this better; this is the placeholder.)
      color: const ui.Color(0x40FFFFFF),
      fontWeight: ui.FontWeight.w700,
      letterSpacing: fontSize * 0.04,
      shadows: const [
        ui.Shadow(
            color: ui.Color(0x33000000),
            offset: ui.Offset(0, 1),
            blurRadius: 2),
      ],
    ))
    ..addText(text);
  final p = builder.build();
  p.layout(const ui.ParagraphConstraints(width: 100000));
  return p;
}
