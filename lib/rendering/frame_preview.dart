// lib/rendering/frame_preview.dart
//
// Library-frame preview painting (Customization → Frames grid, the slicing
// editor, and the template-side frame picker). Lives INSIDE the paint_card
// library on purpose: it draws through the exact same _paintNineSlice the card
// renderer uses, so a preview can never disagree with how the frame renders on
// a card — the one-render-path promise extended to the library UI.

part of 'paint_card.dart';

/// Paints [spec] (a frame's slicing at a representative thickness — see
/// FrameEntry.previewSpec) over a neutral card-aspect rounded rect filling
/// [size]. The backdrop makes border-only sprites and transparent centers
/// readable; the corner radius mirrors a card's so the frame sits the way it
/// would on one. Callers pick a card-aspect [size] (2.5 : 3.5) — the painter
/// doesn't enforce it, which the slicing editor uses to show other aspects.
void paintFramePreview(
  ui.Canvas canvas,
  ui.Size size,
  ui.Image img,
  NineSliceSpec spec, {
  ui.Color backdrop = const ui.Color(0xFFECEAE2),
}) {
  final rect = ui.Offset.zero & size;
  final rr = ui.RRect.fromRectAndRadius(
      rect, ui.Radius.circular(size.width * 0.05));
  canvas.drawRRect(rr, ui.Paint()..color = backdrop);
  canvas.save();
  canvas.clipRRect(rr);
  _paintNineSlice(canvas, rect, img, spec, size);
  canvas.restore();
}
