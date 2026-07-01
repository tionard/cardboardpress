part of 'paint_card.dart';

// ---------------------------------------------------------------------------
// Colour fills (single + double)
// ---------------------------------------------------------------------------

/// Builds a linear gradient shader for a *double* [ColorValue] spanning [rect].
/// Each colour's OWN (baked) alpha is multiplied by the use-site [alpha], so a
/// colour can carry intrinsic translucency and still be dimmed further at the
/// use site. Returns null for a single colour. Shared by area fills and text,
/// so a double colour looks consistent wherever it's applied.
ui.Shader? _doubleShader(ColorValue cv, ui.Rect rect, double alpha) {
  if (!cv.isDouble) return null;
  // Final alpha = per-colour (baked) alpha × use-site alpha. Every existing
  // colour is opaque (a == 1.0), so for them this equals the old override
  // (1.0 × useSite == useSite) and renders pixel-identical.
  final c1 = cv.c1.withValues(alpha: cv.c1.a * alpha);
  final c2 = cv.c2!.withValues(alpha: cv.c2!.a * alpha);
  final m = cv.mix.clamp(0.0, 1.0);
  final half = m / 2;
  // m==0 => duplicate stops at 0.5 => hard edge. m==1 => blend across all.
  final stops = <double>[0.0, 0.5 - half, 0.5 + half, 1.0];
  final colors = <ui.Color>[c1, c1, c2, c2];
  final (from, to) = cv.orientation == MixOrientation.vertical
      ? (rect.topCenter, rect.bottomCenter)
      : (rect.centerLeft, rect.centerRight);
  return ui.Gradient.linear(from, to, colors, stops);
}

/// Fills [rrect] with a [ColorValue] at use-site [alpha] (single or double).
void _fillRRect(ui.Canvas canvas, ui.RRect rrect, ColorValue cv, double alpha) {
  final paint = ui.Paint();
  final shader = _doubleShader(cv, rrect.outerRect, alpha);
  if (shader != null) {
    paint.shader = shader;
  } else {
    // baked alpha × use-site alpha (see _doubleShader).
    paint.color = cv.c1.withValues(alpha: cv.c1.a * alpha);
  }
  canvas.drawRRect(rrect, paint);
}

/// Lerp a colour toward white (lighter) or black (darker) by [t] (0..1).
ui.Color _shade(ui.Color base, {required bool lighter, required double t}) {
  final target =
      lighter ? const ui.Color(0xFFFFFFFF) : const ui.Color(0xFF000000);
  return ui.Color.lerp(base, target, t.clamp(0.0, 1.0))!;
}
