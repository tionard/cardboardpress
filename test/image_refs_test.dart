// The image GC deletes anything model/image_refs.dart doesn't return, so this
// test is the safety net for the sweep's correctness: every reference surface
// (background, legacy field frame, layer image, border snapshot, card art)
// must be collected, and empty ids must not leak in.

import 'dart:ui';

import 'package:cardboardpress/model/card_model.dart';
import 'package:cardboardpress/model/image_refs.dart';
import 'package:cardboardpress/model/layers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('collects every template reference surface', () {
    final t = TemplateData(
      baseColor: ColorRef.literal(const ColorValue.single(Color(0xFFFFFFFF))),
      bgImageId: 'img_bg',
      fields: const [
        FieldSpec(
          id: 'f1',
          type: FieldType.name,
          frac: Rect.fromLTRB(0, 0, 1, 0.1),
          frame: NineSliceSpec(imageId: 'img_field_frame'),
        ),
      ],
      layers: const [
        Layer(
          id: 'l1',
          name: 'Art',
          frac: Rect.fromLTRB(0.1, 0.1, 0.9, 0.5),
          image: ImageAspect(imageId: 'img_layer'),
        ),
        Layer(
          id: 'l2',
          name: 'Frame',
          frac: Rect.fromLTRB(0, 0, 1, 1),
          // The border imageId is the frame SNAPSHOT — it must be kept alive
          // even when the library frame it came from is long deleted.
          border: NineSliceSpec(imageId: 'img_border_snapshot', frameId: 'fr_gone'),
        ),
      ],
    );

    expect(
      imageIdsOfTemplate(t),
      equals({'img_bg', 'img_field_frame', 'img_layer', 'img_border_snapshot'}),
    );
  });

  test('empty ids never leak into the keep-set', () {
    final t = TemplateData(
      baseColor: ColorRef.literal(const ColorValue.single(Color(0xFF000000))),
      fields: const [
        FieldSpec(
          id: 'f1',
          type: FieldType.name,
          frac: Rect.fromLTRB(0, 0, 1, 0.1),
          frame: NineSliceSpec(), // no image chosen
        ),
      ],
      layers: const [
        Layer(
          id: 'l1',
          name: 'Plain',
          frac: Rect.fromLTRB(0, 0, 1, 1),
          image: ImageAspect(imageId: ''),
        ),
      ],
    );
    expect(imageIdsOfTemplate(t), isEmpty);
  });

  test('collects card art and dedups shared images', () {
    const c = CardContent(art: {
      'zoneA': 'img_art_shared',
      'zoneB': 'img_art_shared', // same artwork twice — one keep entry
      'zoneC': 'img_art_other',
      'zoneD': '', // cleared slot
    });
    expect(imageIdsOfCardContent(c),
        equals({'img_art_shared', 'img_art_other'}));
  });
}
