// test/layer_serialization_test.dart
//
// LAYER REDESIGN — Phase 2a: Layer <-> JSON round-trips losslessly.
// (Re-serialization equality proves every field survived, without needing == on
// the value objects.)

import 'dart:ui';

import 'package:cardboardpress/model/card_model.dart';
import 'package:cardboardpress/model/layer_migration.dart';
import 'package:cardboardpress/model/layers.dart';
import 'package:cardboardpress/model/sample_card.dart';
import 'package:cardboardpress/model/serialization.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migrated sample layers round-trip through JSON', () {
    final layers = templateToLayers(sampleTemplate());
    final json = layersToJson(layers);
    final back = layersFromJson(json);

    expect(back.length, equals(layers.length));
    expect(layersToJson(back), equals(json),
        reason: 'a layer field failed to round-trip');
  });

  test('layer with the new aspect wrappers round-trips', () {
    final ref = ColorRef.literal(const ColorValue.single(Color(0xFF3F6FB0)));
    final layer = Layer(
      id: 'l1',
      name: 'Everything',
      visible: false, // stored as 'hidden'
      frac: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.5),
      cornerRadius: 0.03,
      fill: FillAspect(color: ref, alpha: 0.8),
      image: ImageAspect(
        source: ImageSource.setSymbol,
        imageId: 'img_1',
        tint: ref,
        alpha: 0.7,
        transform: const ArtTransform(zoom: 1.5, panX: 0.1, panY: -0.2),
      ),
      foil: FoilType.holo,
      exposed: const {
        ExposedAspect.text: EditorTab.card,
        ExposedAspect.fill: EditorTab.color,
      },
    );

    final json = layersToJson([layer]);
    final back = layersFromJson(json);

    expect(back.length, equals(1));
    expect(back.single.visible, isFalse);
    expect(back.single.foil, equals(FoilType.holo));
    expect(back.single.image?.source, equals(ImageSource.setSymbol));
    expect(back.single.exposed[ExposedAspect.fill], equals(EditorTab.color));
    expect(layersToJson(back), equals(json));
  });

  test('border aspect with per-edge insets and tile modes round-trips', () {
    final ref = ColorRef.literal(const ColorValue.single(Color(0xFF8A6D3B)));
    final layer = Layer(
      id: 'lb',
      name: 'Frame',
      frac: const Rect.fromLTRB(0.05, 0.05, 0.95, 0.95),
      border: NineSliceSpec(
        imageId: 'img_9',
        insetL: 0.10,
        insetT: 0.20,
        insetR: 0.30,
        insetB: 0.40,
        thickness: 0.08,
        edgeMode: SliceFillMode.tile,
        centerMode: SliceFillMode.tile,
        drawCenter: false,
        tint: ref,
      ),
    );

    final json = layersToJson([layer]);
    final back = layersFromJson(json);

    final b = back.single.border!;
    expect(b.insetL, equals(0.10));
    expect(b.insetT, equals(0.20));
    expect(b.insetR, equals(0.30));
    expect(b.insetB, equals(0.40));
    expect(b.thickness, equals(0.08));
    expect(b.edgeMode, equals(SliceFillMode.tile));
    expect(b.centerMode, equals(SliceFillMode.tile));
    expect(b.drawCenter, isFalse);
    expect(b.tint, isNotNull);
    expect(layersToJson(back), equals(json));
  });

  test('a bare border map decodes with safe defaults (stretch, equal cuts)',
      () {
    final back = layersFromJson(
        '{"v":1,"layers":[{"id":"x","name":"X","kind":"generic",'
        '"frac":[0,0,1,1],"cr":0.02,"border":{"img":"i1","center":true}}]}');
    final b = back.single.border!;
    expect(b.imageId, equals('i1'));
    expect(b.insetL, equals(0.33));
    expect(b.insetB, equals(0.33));
    expect(b.thickness, equals(0.06));
    expect(b.edgeMode, equals(SliceFillMode.stretch));
    expect(b.centerMode, equals(SliceFillMode.stretch));
  });
}
