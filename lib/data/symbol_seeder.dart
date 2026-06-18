// lib/data/symbol_seeder.dart
//
// Seeds a few default text symbols on first run. The glyphs are rendered
// programmatically (no bundled binary assets) into the ImageStore, then a row
// per symbol is inserted. Idempotent: skips if any symbols already exist, so a
// user who deletes the defaults won't have them reappear.
//
// These are deliberately generic placeholders (coloured letter/number pips) —
// the point is that Cost/Rules rendering works out of the box; users replace or
// extend them in the Customization "Text" tab.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;

import 'database.dart';
import 'image_store.dart';

class _Pip {
  final String tag;
  final String glyph;
  final int bg;
  final int fg;
  const _Pip(this.tag, this.glyph, this.bg, this.fg);
}

const _defaults = <_Pip>[
  _Pip('R', 'R', 0xFFD64545, 0xFFFFFFFF), // red
  _Pip('G', 'G', 0xFF6FAE6F, 0xFFFFFFFF), // green
  _Pip('B', 'B', 0xFF4F8FD6, 0xFFFFFFFF), // blue
  _Pip('Y', 'Y', 0xFFE0A33A, 0xFF2C2B27), // amber
  _Pip('1', '1', 0xFFBEB9AD, 0xFF2C2B27), // generic numeric
];

/// Renders + inserts the default text symbols if none exist yet.
Future<void> seedDefaultTextSymbols(AppDatabase db, ImageStore store) async {
  if (await db.countTextSymbols() > 0) return; // already seeded
  for (var i = 0; i < _defaults.length; i++) {
    final d = _defaults[i];
    final bytes = await _renderPip(d.glyph, ui.Color(d.bg), ui.Color(d.fg));
    final imageId =
        await store.save(bytes, id: 'sym_${d.tag.toLowerCase()}.png');
    await db.insertTextSymbol(TextSymbolsCompanion.insert(
      id: 'ts_${d.tag.toLowerCase()}',
      tag: d.tag,
      imageId: imageId,
      position: Value(i),
    ));
  }
}

/// Draws a filled circle with a centred glyph and returns PNG bytes.
Future<Uint8List> _renderPip(String glyph, ui.Color bg, ui.Color fg) async {
  const n = 128;
  final c = n / 2;
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);

  canvas.drawCircle(
    ui.Offset(c, c),
    c - 4,
    ui.Paint()
      ..color = bg
      ..isAntiAlias = true,
  );

  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(
    textAlign: ui.TextAlign.center,
    fontSize: 78,
    fontWeight: ui.FontWeight.bold,
  ))
    ..pushStyle(ui.TextStyle(
      color: fg,
      fontSize: 78,
      fontWeight: ui.FontWeight.bold,
    ))
    ..addText(glyph);
  final paragraph = builder.build()
    ..layout(const ui.ParagraphConstraints(width: 128));
  canvas.drawParagraph(paragraph, ui.Offset(0, (n - paragraph.height) / 2));

  final image = await recorder.endRecording().toImage(n, n);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}
