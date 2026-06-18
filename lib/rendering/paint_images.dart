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

/// Draws the set symbol as a silhouette filled with [cv] (the rarity colour:
/// single → solid, double → split gradient), the image acting as an alpha mask.
/// This is the "double colour clipped to a symbol's shape" recipe (rendering.md):
/// fill the symbol's box, then keep the fill only where the glyph has alpha via
/// BlendMode.dstIn. [alpha] is baked into the fill so the whole thing fades.
void _paintSetSymbolTinted(
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
    fill.color = cv.c1.withValues(alpha: a);
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

void _paintArtPlaceholder(ui.Canvas canvas, ui.RRect rrect, ui.Size size) {
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
    'ART',
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
