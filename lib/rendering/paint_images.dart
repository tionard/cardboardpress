part of 'paint_card.dart';

// ---------------------------------------------------------------------------
// Images: set symbol, art, foil
// ---------------------------------------------------------------------------

/// Draws [img] centred inside [dst], preserving aspect ratio (letterboxed).
/// Draws the set symbol contain-fit into [dst] at [alpha] opacity. At full
/// opacity it draws directly; otherwise it goes through a layer so the whole
/// symbol fades uniformly (rather than per-pixel double-blending).
void _paintSetSymbol(
    ui.Canvas canvas, ui.Image img, ui.Rect dst, double alpha) {
  final a = alpha.clamp(0.0, 1.0);
  if (a >= 1.0) {
    _drawImageContain(canvas, img, dst);
    return;
  }
  if (a <= 0.0) return;
  canvas.saveLayer(dst, ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, a));
  _drawImageContain(canvas, img, dst);
  canvas.restore();
}

/// Draws [img] as a silhouette filled with [cv] (single → solid, double → split
/// gradient), the image acting as an alpha mask, contain-fit + centred inside
/// [dst] at [alpha] opacity. The "double colour clipped to a symbol's shape"
/// recipe (rendering.md): fill the symbol's box, then keep the fill only where
/// the glyph has alpha via BlendMode.dstIn. Shared by the rarity-tinted set
/// symbol and the Rules-field watermark.
void _paintTintedSymbol(
    ui.Canvas canvas, ui.Image img, ui.Rect dst, ColorValue cv, double alpha) {
  final box = _containRect(img, dst);
  if (box == null) return;
  final a = alpha.clamp(0.0, 1.0);
  if (a <= 0.0) return;

  canvas.saveLayer(box, ui.Paint());
  final fill = ui.Paint();
  final shader = _doubleShader(cv, box, a);
  if (shader != null) {
    fill.shader = shader;
  } else {
    // baked alpha × use-site alpha (see _doubleShader).
    fill.color = cv.c1.withValues(alpha: cv.c1.a * a);
  }
  canvas.drawRect(box, fill);
  canvas.drawImageRect(
    img,
    ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    box,
    ui.Paint()
      ..blendMode = ui.BlendMode.dstIn
      ..filterQuality = ui.FilterQuality.medium,
  );
  canvas.restore();
}

/// The centred, aspect-preserving rect for [img] fitted inside [dst]
/// (contain-fit). Null when the image has no pixels.
ui.Rect? _containRect(ui.Image img, ui.Rect dst) {
  final iw = img.width.toDouble();
  final ih = img.height.toDouble();
  if (iw <= 0 || ih <= 0) return null;
  final scale = math.min(dst.width / iw, dst.height / ih);
  final w = iw * scale;
  final h = ih * scale;
  return ui.Rect.fromLTWH(
      dst.left + (dst.width - w) / 2, dst.top + (dst.height - h) / 2, w, h);
}

void _drawImageContain(ui.Canvas canvas, ui.Image img, ui.Rect dst) {
  final box = _containRect(img, dst);
  if (box == null) return;
  canvas.drawImageRect(
    img,
    ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    box,
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
}

// ---------------------------------------------------------------------------
// 9-slice frame sprite
// ---------------------------------------------------------------------------

/// Draws [img] as a 9-slice frame filling [dst]: the four corners stay fixed,
/// the edges stretch along one axis, and the center stretches both ways. Source
/// insets come from [spec.slice] (a fraction of the sprite); the DRAWN corner
/// size is [spec.inset] × card width, clamped to the field so it can't overrun a
/// small box. With [spec.drawCenter] false the middle patch is skipped, leaving
/// the field's interior (fill / art) showing through a border-only frame.
void _paintNineSlice(ui.Canvas canvas, ui.Rect dst, ui.Image img,
    NineSliceSpec spec, ui.Size size,
    {ColorValue? tint, double alpha = 1.0}) {
  final iw = img.width.toDouble();
  final ih = img.height.toDouble();
  if (iw <= 0 || ih <= 0 || dst.width <= 0 || dst.height <= 0) return;

  final a = alpha.clamp(0.0, 1.0);
  if (a <= 0) return;

  final sliceF = spec.slice.clamp(0.0, 0.49);
  final sl = sliceF * iw; // source insets (uniform fraction of the sprite)
  final st = sliceF * ih;
  final midSW = iw - sl * 2;
  final midSH = ih - st * 2;

  final base = spec.inset * size.width;
  final diX = math.min(base, dst.width / 2); // drawn corner size, clamped
  final diY = math.min(base, dst.height / 2);
  final midDW = dst.width - diX * 2;
  final midDH = dst.height - diY * 2;

  final paint = ui.Paint()..filterQuality = ui.FilterQuality.medium;
  final l = dst.left, t = dst.top, r = dst.right, b = dst.bottom;

  void patch(double sx, double sy, double sw, double sh, double dx, double dy,
      double dw, double dh) {
    if (sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0) return;
    canvas.drawImageRect(img, ui.Rect.fromLTWH(sx, sy, sw, sh),
        ui.Rect.fromLTWH(dx, dy, dw, dh), paint);
  }

  // A tint multiplies a palette colour (single or double) onto the sprite,
  // preserving its shading and respecting alpha — transparent stays transparent.
  // (Authoring a white/grey sprite and tinting it is the clean recolour path.)
  // Overall [alpha] fades the whole frame as a unit. Either needs an isolated
  // layer: the tint so it only multiplies the sprite, the alpha so the patches
  // fade together rather than overlapping seams double-blending.
  final tinted = tint != null;
  final needLayer = tinted || a < 1.0;
  if (needLayer) {
    canvas.saveLayer(dst, ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, a));
  }

  // Corners (never scaled out of proportion — fixed source → fixed dest).
  patch(0, 0, sl, st, l, t, diX, diY);
  patch(iw - sl, 0, sl, st, r - diX, t, diX, diY);
  patch(0, ih - st, sl, st, l, b - diY, diX, diY);
  patch(iw - sl, ih - st, sl, st, r - diX, b - diY, diX, diY);
  // Edges (stretch along one axis).
  patch(sl, 0, midSW, st, l + diX, t, midDW, diY); // top
  patch(sl, ih - st, midSW, st, l + diX, b - diY, midDW, diY); // bottom
  patch(0, st, sl, midSH, l, t + diY, diX, midDH); // left
  patch(iw - sl, st, sl, midSH, r - diX, t + diY, diX, midDH); // right
  // Center (stretches both ways).
  if (spec.drawCenter) {
    patch(sl, st, midSW, midSH, l + diX, t + diY, midDW, midDH);
  }

  if (tinted) {
    final tp = ui.Paint()..blendMode = ui.BlendMode.modulate;
    final shader = _doubleShader(tint, dst, 1.0);
    if (shader != null) {
      tp.shader = shader; // double colour → split gradient
    } else {
      tp.color = tint.c1; // single colour
    }
    canvas.drawRect(dst, tp);
  }

  if (needLayer) canvas.restore();
}

// ---------------------------------------------------------------------------
// Foil
// ---------------------------------------------------------------------------

void _paintFoil(
    ui.Canvas canvas, ui.Rect rect, ui.RRect rrect, FoilType foil) {
  if (foil == FoilType.none) return;

  const transparent = ui.Color(0x00FFFFFF);
  final colors = switch (foil) {
    FoilType.holo => <ui.Color>[
        transparent,
        const ui.Color(0x8078B4FF), // blue
        const ui.Color(0x80FFAADC), // pink
        const ui.Color(0x80AAFFC8), // green
        transparent,
      ],
    FoilType.gold => <ui.Color>[
        transparent,
        const ui.Color(0x80ECD9A8),
        const ui.Color(0x99FFF3CF),
        const ui.Color(0x80ECD9A8),
        transparent,
      ],
    FoilType.none => const <ui.Color>[],
  };
  const stops = <double>[0.0, 0.36, 0.5, 0.64, 1.0];

  final shader =
      ui.Gradient.linear(rect.topLeft, rect.bottomRight, colors, stops);

  // A "screen" blended layer lightens what's underneath where the sweep is
  // coloured, and does nothing where it's transparent — a believable foil.
  canvas.saveLayer(rect, ui.Paint()..blendMode = ui.BlendMode.screen);
  canvas.drawRRect(rrect, ui.Paint()..shader = shader);
  canvas.restore();
}

// ---------------------------------------------------------------------------
// Art placeholder (temporary — real image picking comes later)
// ---------------------------------------------------------------------------

void _paintArtImage(
    ui.Canvas canvas, ui.RRect rrect, ui.Image img, ArtTransform t) {
  final dst = rrect.outerRect;
  final iw = img.width.toDouble();
  final ih = img.height.toDouble();

  // Cover-fit baseline: the centred crop that fills dst at zoom 1.
  final scale = math.max(dst.width / iw, dst.height / ih);
  final zoom = t.zoom <= 0 ? 1.0 : t.zoom;
  final cropW = (dst.width / scale) / zoom; // zoom in => smaller source crop
  final cropH = (dst.height / scale) / zoom;

  // Pan slides the crop within the leftover image (slack); -1..1 maps edge to
  // edge, 0 stays centred. Clamped so the crop never leaves the image.
  final slackX = iw - cropW;
  final slackY = ih - cropH;
  final px = t.panX.clamp(-1.0, 1.0);
  final py = t.panY.clamp(-1.0, 1.0);
  final left = (slackX / 2) * (1 + px);
  final top = (slackY / 2) * (1 + py);

  final src = ui.Rect.fromLTWH(left, top, cropW, cropH);

  canvas.save();
  canvas.clipRRect(rrect);
  canvas.drawImageRect(
      img, src, dst, ui.Paint()..filterQuality = ui.FilterQuality.medium);
  canvas.restore();
}

void _paintArtPlaceholder(ui.Canvas canvas, ui.RRect rrect, ui.Size size,
    {String label = 'ART'}) {
  final rect = rrect.outerRect;
  canvas.save();
  canvas.clipRRect(rrect);
  canvas.drawRect(rect, ui.Paint()..color = const ui.Color(0xFFE4E1D8));

  final line = ui.Paint()
    ..color = const ui.Color(0x22000000)
    ..strokeWidth = size.width * 0.004;
  for (double x = rect.left - rect.height;
      x < rect.right;
      x += size.width * 0.06) {
    canvas.drawLine(
        ui.Offset(x, rect.bottom), ui.Offset(x + rect.height, rect.top), line);
  }
  canvas.restore();

  _paintText(
    canvas,
    rect,
    label,
    const TextStyleSpec(
      sizeFrac: 0.04,
      align: ui.TextAlign.center,
      colorRef: ColorRef.literal(ColorValue.single(ui.Color(0xFF000000))),
      colorAlpha: 0.4,
    ),
    size,
    const ColorValue.single(ui.Color(0xFF000000)),
  );
}
