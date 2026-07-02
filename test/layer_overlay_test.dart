// test/layer_overlay_test.dart
//
// LAYER REDESIGN — Phase 3 (foundation): the arrangement overlay
// (order + visibility) behaves correctly.

import 'package:cardboardpress/model/layer_migration.dart';
import 'package:cardboardpress/model/sample_card.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = templateToLayers(sampleTemplate());
  final ids = [for (final l in base) l.id];

  test('empty overlay is the identity (same list returned)', () {
    final out = applyLayerOverlay(base, const [], const []);
    expect(identical(out, base), isTrue);
  });

  test('hidden ids get visible = false; others untouched', () {
    final target = ids[1];
    final out = applyLayerOverlay(base, const [], [target]);
    expect(out.firstWhere((l) => l.id == target).visible, isFalse);
    for (final l in out.where((l) => l.id != target)) {
      final orig = base.firstWhere((b) => b.id == l.id);
      expect(l.visible, equals(orig.visible));
    }
  });

  test('order reorders; stale ids ignored; unmentioned appended; none lost', () {
    final order = [ids[1], ids[0], 'does_not_exist'];
    final out = applyLayerOverlay(base, order, const []);
    final outIds = [for (final l in out) l.id];

    expect(outIds.first, equals(ids[1]));
    expect(outIds[1], equals(ids[0]));
    expect(outIds.length, equals(base.length)); // stale dropped, none lost
    expect(outIds.toSet(), equals(ids.toSet())); // exact same set of ids
  });
}
