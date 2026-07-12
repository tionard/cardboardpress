// Frames-library resolution (reference + snapshot): while a border aspect's
// frameId resolves, the library's live values (image, cuts, modes) overlay the
// stored snapshot; use-site properties (thickness, drawCenter, tint) always
// stay with the layer; an unresolved id leaves the snapshot rendering
// unchanged. Pure model — no rendering, no database.

import 'dart:ui';

import 'package:cardboardpress/model/card_model.dart';
import 'package:cardboardpress/model/layer_migration.dart';
import 'package:cardboardpress/model/layers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const frame = FrameEntry(
    id: 'fr_1',
    name: 'Parchment',
    imageId: 'img_live',
    insetL: 0.10,
    insetT: 0.15,
    insetR: 0.20,
    insetB: 0.25,
    edgeMode: SliceFillMode.tile,
    centerMode: SliceFillMode.stretch,
  );

  final snapshotSpec = NineSliceSpec(
    imageId: 'img_snapshot',
    frameId: 'fr_1',
    insetL: 0.33,
    insetT: 0.33,
    insetR: 0.33,
    insetB: 0.33,
    edgeMode: SliceFillMode.stretch,
    centerMode: SliceFillMode.tile,
    thickness: 0.11,
    drawCenter: false,
    tint: ColorRef.literal(const ColorValue.single(Color(0xFF8A6D3B))),
  );

  Layer borderLayer(NineSliceSpec spec) => Layer(
      id: 'b',
      name: 'Frame',
      frac: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.9),
      border: spec);

  test('a resolving frameId overlays the live library values', () {
    final out =
        resolveFrameLayers([borderLayer(snapshotSpec)], {'fr_1': frame});
    final b = out.single.border!;
    expect(b.imageId, equals('img_live'));
    expect(b.insetL, equals(0.10));
    expect(b.insetT, equals(0.15));
    expect(b.insetR, equals(0.20));
    expect(b.insetB, equals(0.25));
    expect(b.edgeMode, equals(SliceFillMode.tile));
    expect(b.centerMode, equals(SliceFillMode.stretch));
  });

  test('use-site properties survive resolution untouched', () {
    final out =
        resolveFrameLayers([borderLayer(snapshotSpec)], {'fr_1': frame});
    final b = out.single.border!;
    expect(b.thickness, equals(0.11));
    expect(b.drawCenter, isFalse);
    expect(b.tint, isNotNull);
    expect(b.frameId, equals('fr_1'));
  });

  test('an unresolved frameId (deleted frame) keeps the snapshot', () {
    final out = resolveFrameLayers(
        [borderLayer(snapshotSpec)], {'fr_other': frame});
    final b = out.single.border!;
    expect(b.imageId, equals('img_snapshot'));
    expect(b.insetL, equals(0.33));
    expect(b.edgeMode, equals(SliceFillMode.stretch));
  });

  test('layers without a frame reference pass through by identity', () {
    final bare = borderLayer(const NineSliceSpec(imageId: 'img_bare'));
    final plain = Layer(
        id: 'p',
        name: 'Plain',
        frac: const Rect.fromLTRB(0, 0, 1, 1),
        fill: FillAspect(
            color:
                ColorRef.literal(const ColorValue.single(Color(0xFF123456)))));
    final input = [bare, plain];
    final out = resolveFrameLayers(input, {'fr_1': frame});
    expect(identical(out, input), isTrue,
        reason: 'nothing resolved, so the input list is returned as-is');
  });

  test('an empty frames map is a no-op', () {
    final input = [borderLayer(snapshotSpec)];
    final out = resolveFrameLayers(input, const {});
    expect(identical(out, input), isTrue);
  });

  test('FrameEntry.applyTo bakes reference + snapshot at pick time', () {
    // What _pickLayerBorder stores: the frame overlaid on a default spec.
    final picked = frame.applyTo(const NineSliceSpec(thickness: 0.09));
    expect(picked.frameId, equals('fr_1'));
    expect(picked.imageId, equals('img_live'));
    expect(picked.insetB, equals(0.25));
    expect(picked.thickness, equals(0.09), reason: 'use-site value preserved');
  });
}
