// lib/rendering/sheet_export.dart
//
// Print-sheet and TTS-sheet composition. Like export.dart, this contains NO
// card-drawing logic — every cell is painted by the same paintCard the
// preview and single-card export use, just positioned on a page canvas. Pages
// render one at a time (render → encode → dispose), so only one page raster
// is ever in memory.
//
// Two products:
//   * composeSheetPages — physical print pages (A4/Letter, margins, optional
//     gaps and cut guides) at a chosen DPI. Cards are laid out on a centred
//     grid; the caller expands per-card copy counts into the list before
//     calling. The free-tier watermark, when requested, is drawn per CARD
//     cell (after its faithful render), matching single-card export policy.
//   * composeTtsSheets — Tabletop Simulator deck sheets: a gapless, markless
//     grid, max 10 columns × 7 rows per sheet (TTS's importer limit), sheet
//     width capped at 4096 px (texture-friendly). Cards beyond 70 continue on
//     further sheets. Each sheet reports its grid so the user can type it
//     into TTS's importer.
//
// Layout math lives in [computeSheetLayout], pure and unit-tested; rendering
// consumes it.

import 'dart:typed_data';
import 'dart:ui' as ui;

import '../model/card_model.dart';
import 'export_watermark.dart';
import 'paint_card.dart';

const double _mmPerInch = 25.4;

/// Physical paper sizes, in inches.
enum SheetPaper {
  a4(8.27, 11.69, 'A4'),
  letter(8.5, 11.0, 'Letter');

  const SheetPaper(this.widthIn, this.heightIn, this.label);
  final double widthIn;
  final double heightIn;
  final String label;
}

/// Print-sheet options. [dpi] is the RESOLVED dpi (the caller runs
/// resolveExportQuality first — policy stays in one place).
class SheetSettings {
  final SheetPaper paper;
  final bool landscape;
  final double dpi;
  final double gapMm; // spacing between cards (0 = shared cut edges)
  final double marginMm; // printer-safe page margin
  final bool cutMarks;

  const SheetSettings({
    this.paper = SheetPaper.a4,
    this.landscape = false,
    this.dpi = 300,
    this.gapMm = 0,
    this.marginMm = 5,
    this.cutMarks = true,
  });

  double get pageWidthIn => landscape ? paper.heightIn : paper.widthIn;
  double get pageHeightIn => landscape ? paper.widthIn : paper.heightIn;
}

/// The computed grid for one page: everything in PIXELS at the chosen dpi.
class SheetLayout {
  final int cols;
  final int rows;
  final double pageW;
  final double pageH;
  final double cardW;
  final double cardH;
  final double gap;
  final double originX; // grid block is centred on the page
  final double originY;

  const SheetLayout({
    required this.cols,
    required this.rows,
    required this.pageW,
    required this.pageH,
    required this.cardW,
    required this.cardH,
    required this.gap,
    required this.originX,
    required this.originY,
  });

  int get perPage => cols * rows;

  /// The trim rect of cell [index] (row-major).
  ui.Rect cellRect(int index) {
    final c = index % cols;
    final r = index ~/ cols;
    return ui.Rect.fromLTWH(originX + c * (cardW + gap),
        originY + r * (cardH + gap), cardW, cardH);
  }
}

/// Grid math for [cardWIn]×[cardHIn] cards on [s]'s page. Throws [StateError]
/// when not even one card fits (margins too big / card too large) — the UI
/// should catch and explain rather than render an empty page.
SheetLayout computeSheetLayout(
    SheetSettings s, double cardWIn, double cardHIn) {
  final gapIn = s.gapMm / _mmPerInch;
  final marginIn = s.marginMm / _mmPerInch;
  final usableW = s.pageWidthIn - 2 * marginIn;
  final usableH = s.pageHeightIn - 2 * marginIn;
  final cols = ((usableW + gapIn) / (cardWIn + gapIn)).floor();
  final rows = ((usableH + gapIn) / (cardHIn + gapIn)).floor();
  if (cols < 1 || rows < 1) {
    throw StateError('A ${cardWIn}×$cardHIn in card does not fit '
        '${s.paper.label} with ${s.marginMm} mm margins.');
  }
  final dpi = s.dpi;
  final cardW = cardWIn * dpi;
  final cardH = cardHIn * dpi;
  final gap = gapIn * dpi;
  final pageW = s.pageWidthIn * dpi;
  final pageH = s.pageHeightIn * dpi;
  final blockW = cols * cardW + (cols - 1) * gap;
  final blockH = rows * cardH + (rows - 1) * gap;
  return SheetLayout(
    cols: cols,
    rows: rows,
    pageW: pageW,
    pageH: pageH,
    cardW: cardW,
    cardH: cardH,
    gap: gap,
    originX: (pageW - blockW) / 2,
    originY: (pageH - blockH) / 2,
  );
}

/// Renders [cards] onto print pages per [settings]; returns one PNG per page.
/// The grid is sized from the FIRST card's physical dimensions; a card with
/// different dimensions is letterboxed (centred, aspect kept) in its cell.
Future<List<Uint8List>> composeSheetPages(
  List<CardData> cards,
  CardRefs refs,
  SheetSettings settings, {
  bool watermark = false,
}) async {
  if (cards.isEmpty) throw StateError('Nothing selected to export.');
  final layout = computeSheetLayout(
      settings, cards.first.widthInches, cards.first.heightInches);

  final pages = <Uint8List>[];
  for (var start = 0; start < cards.length; start += layout.perPage) {
    final pageCards = cards.sublist(
        start,
        (start + layout.perPage) > cards.length
            ? cards.length
            : start + layout.perPage);
    pages.add(await composeSheetPage(pageCards, refs, layout,
        cutMarks: settings.cutMarks, watermark: watermark));
  }
  return pages;
}

/// Renders ONE page: a slice of at most [SheetLayout.perPage] cards onto the
/// layout's page canvas. This is composeSheetPages' worker, public so the
/// settings dialog's live preview renders exactly the export (at a thumbnail
/// dpi) — one render path, extended to the preview.
Future<Uint8List> composeSheetPage(
  List<CardData> cards,
  CardRefs refs,
  SheetLayout l, {
  bool cutMarks = true,
  bool watermark = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas =
      ui.Canvas(recorder, ui.Rect.fromLTWH(0, 0, l.pageW, l.pageH));
  canvas.drawRect(ui.Rect.fromLTWH(0, 0, l.pageW, l.pageH),
      ui.Paint()..color = const ui.Color(0xFFFFFFFF));

  for (var i = 0; i < cards.length; i++) {
    final card = cards[i];
    final cell = l.cellRect(i);
    // Letterbox a card whose physical size differs from the grid card's.
    final scale = (cell.width / card.widthInches)
            .clamp(0, cell.height / card.heightInches)
        .toDouble();
    final drawSize =
        ui.Size(card.widthInches * scale, card.heightInches * scale);
    final dx = cell.left + (cell.width - drawSize.width) / 2;
    final dy = cell.top + (cell.height - drawSize.height) / 2;
    canvas.save();
    canvas.translate(dx, dy);
    canvas.clipRect(ui.Rect.fromLTWH(0, 0, drawSize.width, drawSize.height));
    paintCard(canvas, drawSize, card, refs);
    if (watermark) drawExportWatermark(canvas, drawSize);
    canvas.restore();
  }

  if (cutMarks) _drawCutGuides(canvas, l);

  final picture = recorder.endRecording();
  final image = await picture.toImage(l.pageW.round(), l.pageH.round());
  final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return bytes!.buffer.asUint8List();
}

/// Cut guides. With a gap, classic crop marks sit in the gaps/margins just
/// outside each trim corner; with no gap (shared edges) marks would cross the
/// neighbouring card, so full hairlines are drawn ALONG the shared trim lines
/// instead — they disappear with the cut.
void _drawCutGuides(ui.Canvas canvas, SheetLayout l) {
  final paint = ui.Paint()
    ..color = const ui.Color(0xFF888888)
    ..strokeWidth = (l.pageW / 1200).clamp(1.0, 4.0);

  if (l.gap <= 0) {
    final left = l.originX;
    final right = l.originX + l.cols * l.cardW;
    final top = l.originY;
    final bottom = l.originY + l.rows * l.cardH;
    for (var c = 0; c <= l.cols; c++) {
      final x = l.originX + c * l.cardW;
      canvas.drawLine(ui.Offset(x, top), ui.Offset(x, bottom), paint);
    }
    for (var r = 0; r <= l.rows; r++) {
      final y = l.originY + r * l.cardH;
      canvas.drawLine(ui.Offset(left, y), ui.Offset(right, y), paint);
    }
    return;
  }

  final markLen = (l.pageW / 100).clamp(6.0, 60.0); // ~3 mm at A4/300
  for (var i = 0; i < l.cols * l.rows; i++) {
    final cell = l.cellRect(i);
    for (final corner in [
      cell.topLeft,
      cell.topRight,
      cell.bottomLeft,
      cell.bottomRight,
    ]) {
      final sx = corner.dx == cell.left ? -1.0 : 1.0;
      final sy = corner.dy == cell.top ? -1.0 : 1.0;
      canvas.drawLine(corner, corner + ui.Offset(sx * markLen, 0), paint);
      canvas.drawLine(corner, corner + ui.Offset(0, sy * markLen), paint);
    }
  }
}

// ---------------------------------------------------------------------------
// Tabletop Simulator sheets
// ---------------------------------------------------------------------------

/// One TTS deck sheet plus the grid its importer needs to be told.
class TtsSheet {
  final Uint8List png;
  final int cols;
  final int rows;
  const TtsSheet({required this.png, required this.cols, required this.rows});
}

/// Gapless, markless deck sheets for Tabletop Simulator's custom-deck
/// importer: max 10 columns × 7 rows per sheet, sheet width capped at
/// [maxSheetWidth] px. Cell size derives from the first card's aspect.
Future<List<TtsSheet>> composeTtsSheets(
  List<CardData> cards,
  CardRefs refs, {
  bool watermark = false,
  int maxSheetWidth = 4096,
}) async {
  if (cards.isEmpty) throw StateError('Nothing selected to export.');
  const maxCols = 10, maxRows = 7;
  final first = cards.first;
  final aspect = first.heightInches / first.widthInches;

  final sheets = <TtsSheet>[];
  for (var start = 0; start < cards.length; start += maxCols * maxRows) {
    final chunk = cards.sublist(
        start,
        (start + maxCols * maxRows) > cards.length
            ? cards.length
            : start + maxCols * maxRows);
    final cols = chunk.length < maxCols ? chunk.length : maxCols;
    final rows = (chunk.length + cols - 1) ~/ cols;
    final cardW = (maxSheetWidth / maxCols).floorToDouble();
    final cardH = (cardW * aspect).roundToDouble();

    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(
        recorder, ui.Rect.fromLTWH(0, 0, cols * cardW, rows * cardH));
    for (var i = 0; i < chunk.length; i++) {
      final cell = ui.Rect.fromLTWH(
          (i % cols) * cardW, (i ~/ cols) * cardH, cardW, cardH);
      canvas.save();
      canvas.translate(cell.left, cell.top);
      canvas.clipRect(ui.Rect.fromLTWH(0, 0, cardW, cardH));
      paintCard(canvas, ui.Size(cardW, cardH), chunk[i], refs);
      if (watermark) drawExportWatermark(canvas, ui.Size(cardW, cardH));
      canvas.restore();
    }
    final picture = recorder.endRecording();
    final image =
        await picture.toImage((cols * cardW).round(), (rows * cardH).round());
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    picture.dispose();
    image.dispose();
    sheets.add(
        TtsSheet(png: bytes!.buffer.asUint8List(), cols: cols, rows: rows));
  }
  return sheets;
}
