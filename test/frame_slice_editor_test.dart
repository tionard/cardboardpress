// The one pure piece of the visual slicing editor: cuts snap to whole SOURCE
// pixels (a sprite's border art sits on pixel boundaries), clamped to the
// model's 0..0.49 range. The dragging itself is eyeball-tested.

import 'package:cardboardpress/features/customization/frame_slice_editor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('snaps to the nearest whole source pixel', () {
    // 0.104 of a 30px sprite is 3.12px -> 3px -> 0.1.
    expect(snapInsetToSourcePixels(0.104, 30), closeTo(0.1, 1e-9));
    // 0.116 -> 3.48px -> 3px as well.
    expect(snapInsetToSourcePixels(0.116, 30), closeTo(0.1, 1e-9));
    // 0.12 -> 3.6px -> 4px -> 0.1333…
    expect(snapInsetToSourcePixels(0.12, 30), closeTo(4 / 30, 1e-9));
  });

  test('clamps to the model range even when snapping would exceed it', () {
    // 0.49 of 30px is 14.7px; the nearest pixel (15) would be 0.5 — the final
    // clamp keeps the result at the model's ceiling.
    expect(snapInsetToSourcePixels(0.49, 30), equals(0.49));
    expect(snapInsetToSourcePixels(0.75, 30), equals(0.49));
    expect(snapInsetToSourcePixels(-0.2, 30), equals(0.0));
  });

  test('zero stays exactly zero (the 3-slice trigger)', () {
    expect(snapInsetToSourcePixels(0.0, 30), equals(0.0));
    expect(snapInsetToSourcePixels(0.01, 30), equals(0.0),
        reason: '0.3px rounds to the 0px boundary');
  });

  test('a degenerate source size skips the snap but still clamps', () {
    expect(snapInsetToSourcePixels(0.3, 0), equals(0.3));
    expect(snapInsetToSourcePixels(0.6, 0), equals(0.49));
  });
}
