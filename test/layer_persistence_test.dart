// test/layer_persistence_test.dart
//
// LAYER REDESIGN — Phase 4 (foundation) gate.
//
// Two guarantees for the source-of-truth flip, where a template can now carry a
// persisted `List<Layer>` (stored inside the existing `spec` JSON — no schema
// bump) instead of deriving its layers from the fixed fields:
//
//   1. Round-trip. A materialised layer list survives templateToJson ->
//      templateFromJson intact (order, ids, kinds, aspects, exposure). And a
//      template with no persisted layers still decodes to `layers == null`, so
//      every existing save reloads exactly as before.
//   2. Render parity. Rendering a card whose template has been materialised
//      (`layers = templateToLayers(t)`) is PIXEL-IDENTICAL to the same card
//      rendered from the derived path (`layers == null`). This proves flipping
//      the renderer's source of truth to the persisted list changes nothing for
//      an already-authored layout.
//
// Run: `flutter test`.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:cardboardpress/model/card_model.dart';
import 'package:cardboardpress/model/layers.dart';
import 'package:cardboardpress/model/layer_migration.dart';
import 'package:cardboardpress/model/sample_card.dart';
import 'package:cardboardpress/model/serialization.dart';
import 'package:cardboardpress/rendering/paint_card.dart';
import 'package:flutter_test/flutter_test.dart';

Future<Uint8List> _renderRgba(
    void Function(ui.Canvas, ui.Size) paint, ui.Size size) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  paint(canvas, size);
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.width.round(), size.height.round());
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

int _firstDiff(Uint8List a, Uint8List b) {
  final n = a.length < b.length ? a.length : b.length;
  for (var i = 0; i < n; i++) {
    if (a[i] != b[i]) return i;
  }
  return a.length == b.length ? -1 : n;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const size = ui.Size(375, 525); // 2.5" x 3.5" @ 150 dpi
  const refs = CardRefs();

  group('layer persistence round-trip', () {
    test('null layers stay null (existing saves unchanged)', () {
      final t = sampleTemplate();
      expect(t.layers, isNull, reason: 'sample template is field-derived');
      final round = templateFromJson(templateToJson(t));
      expect(round.layers, isNull,
          reason: 'no "layers" key => decodes back to null');
    });

    test('materialised layers survive JSON round-trip', () {
      final t = sampleTemplate();
      final materialised = t.copyWith(layers: templateToLayers(t));
      final round = templateFromJson(templateToJson(materialised));

      final src = materialised.layers!;
      final got = round.layers;
      expect(got, isNotNull);
      expect(got!.length, equals(src.length));

      for (var i = 0; i < src.length; i++) {
        expect(got[i].id, equals(src[i].id), reason: 'order/id at $i');
        expect(got[i].kind, equals(src[i].kind), reason: 'kind at $i');
        expect(got[i].name, equals(src[i].name), reason: 'name at $i');
      }

      // Aspect + exposure spot-checks against the known derived layout.
      final base = got.firstWhere((l) => l.id == kBaseLayerId);
      expect(base.fill, isNotNull, reason: 'base keeps its fill aspect');

      final tint = got.firstWhere((l) => l.id == kTintLayerId);
      expect(tint.fill, isNotNull, reason: 'tint keeps its fill aspect');
      expect(tint.exposed[ExposedAspect.fill], isNull,
          reason: 'tint is no longer exposed — per-card tint is the Color tab');

      // Everything is a generic layer now — target by the stable field id and
      // assert on the ASPECTS, not the retired LayerKind values.
      final rules = got.firstWhere((l) => l.id == fRulesId);
      expect(rules.text?.inline, isTrue, reason: 'rules text stays inline');
      expect(rules.exposed[ExposedAspect.text], equals(EditorTab.card),
          reason: 'rules exposes text to the card tab');

      final art = got.firstWhere((l) => l.id == fArtId);
      expect(art.image?.source, equals(ImageSource.cardArt),
          reason: 'art resolves its picture per-card');
      expect(art.exposed[ExposedAspect.image], isNull,
          reason: 'art is not exposed — the dedicated Art panel owns it');
    });
  });

  group('derived vs materialised render parity', () {
    for (final border in [true, false]) {
      for (final foil in [FoilType.none, FoilType.holo]) {
        test('border=$border foil=$foil', () async {
          final t = sampleTemplate(border: border);
          final tMat = t.copyWith(layers: templateToLayers(t));

          final derived = composeCard(t,
              content: sampleContent(), foil: foil, footerPlaceholder: 'x');
          final persisted = composeCard(tMat,
              content: sampleContent(), foil: foil, footerPlaceholder: 'x');

          expect(derived.layers, isNull);
          expect(persisted.layers, isNotNull);

          final a =
              await _renderRgba((c, s) => paintCard(c, s, derived, refs), size);
          final b = await _renderRgba(
              (c, s) => paintCard(c, s, persisted, refs), size);

          expect(b.length, equals(a.length), reason: 'dimensions differ');
          final diff = _firstDiff(a, b);
          expect(diff, equals(-1),
              reason: 'persisted-layer render diverges from derived at byte '
                  '$diff (of ${a.length})');
        });
      }
    }
  });
}
