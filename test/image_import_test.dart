// Upload gate tests (data/image_import.dart). The properties that matter:
// within-limits images pass through BYTE-IDENTICAL (the content-hash dedup
// depends on it), oversized ones downscale to the cap with aspect preserved,
// and rejections (file too big, unreadable, too small) throw a showable
// ImageImportException — with the byte-size check firing before any decode.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cardboardpress/data/image_import.dart';
import 'package:flutter_test/flutter_test.dart';

/// Encode a solid-colour PNG of the given size.
Future<Uint8List> _png(int w, int h) async {
  final rec = ui.PictureRecorder();
  ui.Canvas(rec)
    .drawRect(ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
        ui.Paint()..color = const ui.Color(0xFF336699));
  final img = await rec.endRecording().toImage(w, h);
  final data = await img.toByteData(format: ui.ImageByteFormat.png);
  img.dispose();
  return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
}

/// Decode dimensions of encoded bytes (verifies re-encodes are real).
Future<(int, int)> _dims(Uint8List bytes) async {
  final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
  final desc = await ui.ImageDescriptor.encoded(buffer);
  final d = (desc.width, desc.height);
  desc.dispose();
  buffer.dispose();
  return d;
}

void main() {
  test('within-limits upload passes through byte-identical', () async {
    final input = await _png(100, 100);
    final r = await processImportedImage(input,
        kind: ImageImportKind.artwork, ext: 'JPG');
    expect(r.bytes, same(input),
        reason: 'untouched bytes keep the content-hash dedup stable');
    expect(r.ext, equals('jpg'));
    expect(r.width, equals(100));
    expect(r.height, equals(100));
    expect(r.downscaledFrom, isNull);
    expect(r.notice, isNull);
  });

  test('boundary size is still a passthrough', () async {
    final input = await _png(1024, 1024);
    final r =
        await processImportedImage(input, kind: ImageImportKind.frame);
    expect(r.bytes, same(input));
    expect(r.downscaledFrom, isNull);
  });

  test('oversized dimensions downscale to the cap, aspect preserved',
      () async {
    final input = await _png(2500, 1250);
    final r =
        await processImportedImage(input, kind: ImageImportKind.artwork);
    expect(r.width, equals(2048));
    expect(r.height, equals(1024));
    expect(r.ext, equals('png'));
    expect(r.downscaledFrom, equals((width: 2500, height: 1250)));
    expect(r.notice, contains('2048'));
    expect(r.bytes, isNot(same(input)));
    // The re-encode is real: the stored bytes decode at the new size.
    expect(await _dims(r.bytes), equals((2048, 1024)));
  });

  test('frames and symbols reject images below 32px', () async {
    final tiny = await _png(16, 16);
    await expectLater(
        processImportedImage(tiny, kind: ImageImportKind.frame),
        throwsA(isA<ImageImportException>()
            .having((e) => e.message, 'message', contains('small'))));
    await expectLater(
        processImportedImage(tiny, kind: ImageImportKind.symbol),
        throwsA(isA<ImageImportException>()));
  });

  test('artwork has no 32px floor', () async {
    final tiny = await _png(16, 16);
    final r =
        await processImportedImage(tiny, kind: ImageImportKind.artwork);
    expect(r.bytes, same(tiny));
  });

  test('oversized files reject before any decode', () async {
    // 2 MB + 1 of zeros isn't a valid image, but the size guard must fire
    // FIRST — the message says "large", not "couldn't be read".
    final huge = Uint8List(2 * 1024 * 1024 + 1);
    await expectLater(
        processImportedImage(huge, kind: ImageImportKind.textSymbol),
        throwsA(isA<ImageImportException>()
            .having((e) => e.message, 'message', contains('large'))));
  });

  test('unreadable files reject with a decode message', () async {
    final garbage = Uint8List.fromList([1, 2, 3, 4, 5]);
    await expectLater(
        processImportedImage(garbage, kind: ImageImportKind.artwork),
        throwsA(isA<ImageImportException>()
            .having((e) => e.message, 'message', contains("couldn't"))));
  });
}
