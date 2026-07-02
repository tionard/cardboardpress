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
}
