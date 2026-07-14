// lib/rendering/sheet_pdf.dart
//
// Wraps rendered sheet pages (PNGs from sheet_export.dart) into a single PDF
// with true physical page dimensions, so "print at actual size" is guaranteed
// by the file itself rather than by the user's print-dialog settings. Kept in
// its own file so the pdf package dependency stays out of the PNG-only path.

import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'sheet_export.dart' show SheetPaper;

/// One page per PNG, each filling its physical page exactly (the PNGs were
/// rendered at the same paper dimensions, so `fill` introduces no distortion).
Future<Uint8List> sheetPagesToPdf(
  List<Uint8List> pagePngs,
  SheetPaper paper, {
  bool landscape = false,
}) async {
  final w = paper.widthIn * PdfPageFormat.inch;
  final h = paper.heightIn * PdfPageFormat.inch;
  final format =
      landscape ? PdfPageFormat(h, w) : PdfPageFormat(w, h);
  final doc = pw.Document();
  for (final png in pagePngs) {
    final image = pw.MemoryImage(png);
    doc.addPage(pw.Page(
      pageFormat: format,
      margin: pw.EdgeInsets.zero,
      build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
    ));
  }
  return doc.save();
}
