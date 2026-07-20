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

/// Tint dispatcher: silhouette (alpha-mask fill, the original recipe) or
/// multiply (keeps the picture's own values — black stays black, light areas
/// take the colour). All symbol-tint call sites route through here.
void _paintSymbolTint(ui.Canvas canvas, ui.Image img, ui.Rect dst,
    ColorValue cv, double alpha, TintMode mode) {
  if (mode == TintMode.multiply) {
    _paintMultipliedSymbol(canvas, img, dst, cv, alpha);
  } else {
    _paintTintedSymbol(canvas, img, dst, cv, alpha);
  }
}

/// Draws [img] contain-fit + centred in [dst], then MULTIPLIES [cv] over it
/// (BlendMode.modulate): black detail survives, white areas take the full
/// tint, greys shade between — the "keep the line art" tint for overlay /
/// rarity colours on shaded symbols. The tint colour's own alpha acts as
/// STRENGTH (lerped toward white, i.e. toward "no tint") rather than
/// translucency — a translucent modulate would darken instead of fade.
/// [alpha] is the use-site opacity of the whole result. Transparent glyph
/// pixels stay transparent: everything happens inside a saveLayer, where
/// modulate against nothing is nothing.
void _paintMultipliedSymbol(
    ui.Canvas canvas, ui.Image img, ui.Rect dst, ColorValue cv, double alpha) {
  final box = _containRect(img, dst);
  if (box == null) return;
  final a = alpha.clamp(0.0, 1.0);
  if (a <= 0.0) return;

  final adj = _tintStrength(cv);

  canvas.saveLayer(box, ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, a));
  canvas.drawImageRect(
    img,
    ui.Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
    box,
    ui.Paint()..filterQuality = ui.FilterQuality.medium,
  );
  final fill = ui.Paint()..blendMode = ui.BlendMode.modulate;
  final shader = _doubleShader(adj, box, 1.0);
  if (shader != null) {
    fill.shader = shader; // double colour → split gradient, full strength
  } else {
    fill.color = adj.c1;
  }
  canvas.drawRect(box, fill);
  canvas.restore();
}

/// Multiply-mode strength: the tint colour's own alpha lerps it toward white
/// (= toward "no tint") rather than acting as translucency — a translucent
/// modulate would darken instead of fade. Shared by both multiplied painters.
ColorValue _tintStrength(ColorValue cv) {
  ui.Color strength(ui.Color c) => ui.Color.lerp(
      const ui.Color(0xFFFFFFFF), c.withValues(alpha: 1.0), c.a)!;
  return cv.isDouble
      ? ColorValue.duo(strength(cv.c1), strength(cv.c2!),
          orientation: cv.orientation, mix: cv.mix)
      : ColorValue.single(strength(cv.c1));
}

/// Multiply tint for a FIXED IMAGE used as artwork/background: draws exactly
/// like the untinted path — cover-fit with the layer's zoom/pan [tr], clipped
/// to the rounded rect — then multiplies [cv] over the result. This is the
/// "tinted background" recipe; the contain-fit [_paintMultipliedSymbol] is the
/// symbol-stamp recipe (set symbol, watermark), which has no transform.
void _paintMultipliedImage(ui.Canvas canvas, ui.Rect rect, ui.RRect rrect,
    ui.Image img, ArtTransform tr, ColorValue cv, double alpha) {
  final a = alpha.clamp(0.0, 1.0);
  if (a <= 0.0) return;
  canvas.saveLayer(rect, ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, a));
  _paintArtImage(canvas, rrect, img, tr);
  final fill = ui.Paint()..blendMode = ui.BlendMode.modulate;
  final adj = _tintStrength(cv);
  final shader = _doubleShader(adj, rect, 1.0);
  if (shader != null) {
    fill.shader = shader;
  } else {
    fill.color = adj.c1;
  }
  // Pixels outside the rounded clip are transparent in this layer, and
  // transparent × tint = transparent — safe to modulate the whole rect.
  canvas.drawRect(rect, fill);
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

/// Draws [img] as a 9-slice frame filling [dst]: the corners stay fixed, the
/// edges scale along one axis, and the center fills both ways.
///
/// Source cuts are PER-EDGE ([spec.insetL/T/R/B], fractions of the source
/// image); a zero cut removes that band entirely, so `insetT = insetB = 0` is
/// a horizontal 3-slice with no special casing. The DRAWN thickness is
/// resolution-independent: the thickest edge draws at [spec.thickness] × card
/// width and the others proportionally to their source-cut FRACTIONS
/// (fraction-proportional, not pixel-proportional, so a uniformly-cut
/// non-square sprite still draws square corners). If the bands would overrun a
/// small box, all four shrink together so the proportions hold.
///
/// Edges and center each honour a [SliceFillMode]: stretch, or tile at the
/// scale implied by the adjacent drawn corner — tile size therefore also
/// derives from card width, keeping preview and export pixel-equivalent. Tiles
/// are centred so partial tiles split evenly between both ends. With
/// [spec.drawCenter] false the middle patch is skipped, leaving the layer's
/// interior (fill / art) showing through a border-only frame.
void _paintNineSlice(ui.Canvas canvas, ui.Rect dst, ui.Image img,
    NineSliceSpec spec, ui.Size size,
    {ColorValue? tint, double alpha = 1.0}) {
  final iw = img.width.toDouble();
  final ih = img.height.toDouble();
  if (iw <= 0 || ih <= 0 || dst.width <= 0 || dst.height <= 0) return;

  final a = alpha.clamp(0.0, 1.0);
  if (a <= 0) return;

  // No edge anti-aliasing: every patch (and every tile) is an axis-aligned
  // rect, and adjacent rects share their boundary coordinate exactly. With AA
  // on, the shared fractional edge gets partial coverage from BOTH sides that
  // never sums back to full opacity — the hairline "slice lines" between
  // patches and between tiles, in every fill mode. With AA off each device
  // pixel belongs to exactly one rect: no gaps, no double-cover. Nothing here
  // rotates, so there are no diagonal edges that would want AA.
  //
  // FilterQuality.low, not medium: medium's mipmaps average across the slice
  // cut lines when the frame draws smaller than the sprite, tinting each
  // patch's boundary pixels with the NEIGHBOURING patch's content — another
  // seam that varies with preview scale. Bilinear-only sampling stays inside
  // a texel of the cut. (Export draws at or above sprite scale, where the two
  // are identical anyway.)
  final paint = ui.Paint()
    ..filterQuality = ui.FilterQuality.low
    ..isAntiAlias = false;

  // A tint multiplies a palette colour (single or double) onto the sprite,
  // preserving its shading and respecting alpha — transparent stays transparent.
  // (Authoring a white/grey sprite and tinting it is the clean recolour path.)
  // Overall [alpha] fades the whole frame as a unit. Either needs an isolated
  // layer: the tint so it only multiplies the sprite, the alpha so the patches
  // fade together rather than overlapping seams double-blending.
  final tinted = tint != null;
  final needLayer = tinted || a < 1.0;
  // Inflated by a pixel: boundary snapping in the patch pass can land the
  // outer edges up to half a device pixel outside [dst], and a tight layer
  // would shave that sliver off — a seam at the frame's outer edge, but only
  // when tinted or faded. The modulate rect below inflates to match.
  final layerBounds = dst.inflate(1);
  if (needLayer) {
    canvas.saveLayer(
        layerBounds, ui.Paint()..color = ui.Color.fromRGBO(0, 0, 0, a));
  }

  _paintNineSlicePatches(canvas, dst, img, spec, size, paint);

  if (tinted) {
    final tp = ui.Paint()..blendMode = ui.BlendMode.modulate;
    final shader = _doubleShader(tint, dst, 1.0);
    if (shader != null) {
      tp.shader = shader; // double colour → split gradient
    } else {
      tp.color = tint.c1; // single colour
    }
    canvas.drawRect(layerBounds, tp);
  }

  if (needLayer) canvas.restore();
}

/// The geometry half of [_paintNineSlice]: cuts the sprite by the per-edge
/// insets and draws corners / edges / center into [dst].
void _paintNineSlicePatches(ui.Canvas canvas, ui.Rect dst, ui.Image img,
    NineSliceSpec spec, ui.Size size, ui.Paint paint) {
  final iw = img.width.toDouble();
  final ih = img.height.toDouble();

  // Source cut fractions (L/R of source width, T/B of source height).
  final fL = spec.insetL.clamp(0.0, 0.49);
  final fT = spec.insetT.clamp(0.0, 0.49);
  final fR = spec.insetR.clamp(0.0, 0.49);
  final fB = spec.insetB.clamp(0.0, 0.49);
  final fMax = math.max(math.max(fL, fR), math.max(fT, fB));

  if (fMax <= 0) {
    // No cuts at all — the whole sprite is one center patch. Tiling has no
    // corner scale to derive a tile size from here, so the degenerate case
    // always stretches.
    if (spec.drawCenter) {
      canvas.drawImageRect(img, ui.Rect.fromLTWH(0, 0, iw, ih), dst, paint);
    }
    return;
  }

  // Source geometry (px).
  final sl = fL * iw, sr = fR * iw, st = fT * ih, sb = fB * ih;
  final midSW = iw - sl - sr;
  final midSH = ih - st - sb;

  // Drawn geometry: the thickest cut draws at [thickness] × card width, the
  // others proportionally to their fractions — so a zero cut draws nothing and
  // the sides keep their sprite ratios. If the bands would overrun the box,
  // all four shrink together (uniform clamp preserves the proportions).
  final base = spec.thickness * size.width;
  var dL = base * fL / fMax;
  var dT = base * fT / fMax;
  var dR = base * fR / fMax;
  var dB = base * fB / fMax;
  var k = 1.0;
  if (dL + dR > 0) k = math.min(k, dst.width / (dL + dR));
  if (dT + dB > 0) k = math.min(k, dst.height / (dT + dB));
  if (k < 1.0) {
    dL *= k;
    dT *= k;
    dR *= k;
    dB *= k;
  }
  // --- Device-pixel snapping ---------------------------------------------
  // Even with AA off, patches meeting at a FRACTIONAL device pixel sample the
  // shared boundary pixel from slightly different source coordinates (each
  // drawImageRect maps src→dst independently), showing as an intermittent
  // seam that comes and goes with preview scale and thickness. Snapping every
  // boundary onto the device pixel grid makes patches abut pixel-for-pixel.
  // The canvas transform here is pure translate+scale (nothing in the model
  // rotates), so the device scale lives at m[0]/m[5].
  final mtx = canvas.getTransform();
  final psx = mtx[0].abs() > 1e-9 ? mtx[0].abs() : 1.0;
  final psy = mtx[5].abs() > 1e-9 ? mtx[5].abs() : 1.0;
  double snapX(double v) => (v * psx).roundToDouble() / psx;
  double snapY(double v) => (v * psy).roundToDouble() / psy;

  final l = snapX(dst.left), r = snapX(dst.right);
  final t = snapY(dst.top), b = snapY(dst.bottom);
  var xB = dL > 0 ? snapX(dst.left + dL) : l;
  var xC = dR > 0 ? snapX(dst.right - dR) : r;
  var yB = dT > 0 ? snapY(dst.top + dT) : t;
  var yC = dB > 0 ? snapY(dst.bottom - dB) : b;
  // A nonzero band must survive snapping with at least one device pixel.
  if (dL > 0 && xB <= l) xB = l + 1 / psx;
  if (dR > 0 && xC >= r) xC = r - 1 / psx;
  if (dT > 0 && yB <= t) yB = t + 1 / psy;
  if (dB > 0 && yC >= b) yC = b - 1 / psy;
  dL = xB - l;
  dR = r - xC;
  dT = yB - t;
  dB = b - yC;
  final midDW = r - l - dL - dR;
  final midDH = b - t - dT - dB;

  void patch(double sx, double sy, double sw, double sh, double dx, double dy,
      double dw, double dh) {
    if (sw <= 0 || sh <= 0 || dw <= 0 || dh <= 0) return;
    canvas.drawImageRect(img, ui.Rect.fromLTWH(sx, sy, sw, sh),
        ui.Rect.fromLTWH(dx, dy, dw, dh), paint);
  }

  // Corners — fixed source → fixed dest, never distorted. patch() skips any
  // corner with a zero band on either axis (that's the 3-slice case).
  patch(0, 0, sl, st, l, t, dL, dT);
  patch(iw - sr, 0, sr, st, r - dR, t, dR, dT);
  patch(0, ih - sb, sl, sb, l, b - dB, dL, dB);
  patch(iw - sr, ih - sb, sr, sb, r - dR, b - dB, dR, dB);

  // Edges — stretch along the edge, or tile at the drawn/source scale of the
  // band's cross-axis (which derives from card width → resolution-exact).
  // fit is tiling with whole tiles only (see _tilePatch's `round`).
  final tileEdges = spec.edgeMode != SliceFillMode.stretch;
  final roundEdges = spec.edgeMode == SliceFillMode.fit;
  // top / bottom
  if (midSW > 0 && midDW > 0) {
    final topSrc = ui.Rect.fromLTWH(sl, 0, midSW, st);
    final topDst = ui.Rect.fromLTWH(l + dL, t, midDW, dT);
    final botSrc = ui.Rect.fromLTWH(sl, ih - sb, midSW, sb);
    final botDst = ui.Rect.fromLTWH(l + dL, b - dB, midDW, dB);
    if (tileEdges) {
      if (st > 0 && dT > 0) {
        _tilePatch(canvas, img, topSrc, topDst, dT / st, dT / st, paint,
            round: roundEdges);
      }
      if (sb > 0 && dB > 0) {
        _tilePatch(canvas, img, botSrc, botDst, dB / sb, dB / sb, paint,
            round: roundEdges);
      }
    } else {
      patch(topSrc.left, topSrc.top, topSrc.width, topSrc.height, topDst.left,
          topDst.top, topDst.width, topDst.height);
      patch(botSrc.left, botSrc.top, botSrc.width, botSrc.height, botDst.left,
          botDst.top, botDst.width, botDst.height);
    }
  }
  // left / right
  if (midSH > 0 && midDH > 0) {
    final leftSrc = ui.Rect.fromLTWH(0, st, sl, midSH);
    final leftDst = ui.Rect.fromLTWH(l, t + dT, dL, midDH);
    final rightSrc = ui.Rect.fromLTWH(iw - sr, st, sr, midSH);
    final rightDst = ui.Rect.fromLTWH(r - dR, t + dT, dR, midDH);
    if (tileEdges) {
      if (sl > 0 && dL > 0) {
        _tilePatch(canvas, img, leftSrc, leftDst, dL / sl, dL / sl, paint,
            round: roundEdges);
      }
      if (sr > 0 && dR > 0) {
        _tilePatch(canvas, img, rightSrc, rightDst, dR / sr, dR / sr, paint,
            round: roundEdges);
      }
    } else {
      patch(leftSrc.left, leftSrc.top, leftSrc.width, leftSrc.height,
          leftDst.left, leftDst.top, leftDst.width, leftDst.height);
      patch(rightSrc.left, rightSrc.top, rightSrc.width, rightSrc.height,
          rightDst.left, rightDst.top, rightDst.width, rightDst.height);
    }
  }

  // Center — fills both ways. Tile scale per axis comes from whichever band
  // exists on that axis (falling back to the other axis for 3-slices, so a
  // horizontal 3-slice's center still tiles at a sensible uniform scale).
  if (spec.drawCenter && midSW > 0 && midSH > 0 && midDW > 0 && midDH > 0) {
    final cSrc = ui.Rect.fromLTWH(sl, st, midSW, midSH);
    final cDst = ui.Rect.fromLTWH(l + dL, t + dT, midDW, midDH);
    var tiled = false;
    if (spec.centerMode != SliceFillMode.stretch) {
      double? kx, ky;
      if (sl > 0 && dL > 0) {
        kx = dL / sl;
      } else if (sr > 0 && dR > 0) {
        kx = dR / sr;
      }
      if (st > 0 && dT > 0) {
        ky = dT / st;
      } else if (sb > 0 && dB > 0) {
        ky = dB / sb;
      }
      kx ??= ky;
      ky ??= kx;
      if (kx != null && ky != null) {
        _tilePatch(canvas, img, cSrc, cDst, kx, ky, paint,
            round: spec.centerMode == SliceFillMode.fit);
        tiled = true;
      }
    }
    if (!tiled) {
      patch(cSrc.left, cSrc.top, cSrc.width, cSrc.height, cDst.left, cDst.top,
          cDst.width, cDst.height);
    }
  }
}

/// Tiles [src] (a sprite patch) across [dstRect] at [scaleX]/[scaleY] (drawn
/// px per source px), clipped to the rect.
///
/// Plain tiling ([round] false) keeps the ideal tile size and CENTRES the
/// grid, so any partial tiles split evenly between both ends — the two ends
/// of a frame edge mirror each other instead of one clean end and one chopped
/// end. Round/fit tiling ([round] true) draws WHOLE tiles only: per axis it
/// fits as many ideal-size tiles as possible (at least one) and stretches them
/// all equally to fill exactly — no cut-offs, slight per-tile distortion (CSS
/// border-image "round"). An exact-multiple space makes the two identical.
void _tilePatch(ui.Canvas canvas, ui.Image img, ui.Rect src, ui.Rect dstRect,
    double scaleX, double scaleY, ui.Paint paint,
    {required bool round}) {
  var tw = src.width * scaleX;
  var th = src.height * scaleY;
  if (tw < 0.01 || th < 0.01 || dstRect.width <= 0 || dstRect.height <= 0) {
    return;
  }
  final int nx;
  final int ny;
  final double x0;
  final double y0;
  if (round) {
    nx = math.max(1, (dstRect.width / tw).round());
    ny = math.max(1, (dstRect.height / th).round());
    tw = dstRect.width / nx;
    th = dstRect.height / ny;
    x0 = dstRect.left;
    y0 = dstRect.top;
  } else {
    // Tolerance before ceil: an edge band's cross-axis tile size EQUALS the
    // band thickness by construction, so the ratio is exactly 1 — except
    // float noise can land at 1.0000000002, which ceil turns into TWO tiles
    // and the centring below then phase-shifts the pattern by half a tile.
    // Which bands trip it depends on rounding (right/bottom accumulate
    // differently than left/top), producing an asymmetric-looking frame.
    const eps = 1e-6;
    nx = math.max(1, (dstRect.width / tw - eps).ceil());
    ny = math.max(1, (dstRect.height / th - eps).ceil());
    x0 = dstRect.center.dx - nx * tw / 2;
    y0 = dstRect.center.dy - ny * th / 2;
  }
  // Snap every tile edge to the device pixel grid (see the snapping note in
  // _paintNineSlicePatches — same intermittent-seam mechanism, between tiles
  // instead of patches). Adjacent tiles share the snapped edge exactly; each
  // tile absorbs the sub-pixel difference as invisible stretch. A tile whose
  // snapped span collapses to zero is skipped.
  final mtx = canvas.getTransform();
  final psx = mtx[0].abs() > 1e-9 ? mtx[0].abs() : 1.0;
  final psy = mtx[5].abs() > 1e-9 ? mtx[5].abs() : 1.0;
  double snapX(double v) => (v * psx).roundToDouble() / psx;
  double snapY(double v) => (v * psy).roundToDouble() / psy;

  canvas.save();
  // Hard clip, no AA: plain tiling's centred grid OVERHANGS the band and this
  // clip trims the partial end tiles — an anti-aliased clip edge leaves them
  // partial-coverage at the band boundary, a seam only Tile mode can produce
  // (fit's tiles end exactly at the rect and never get trimmed). The band
  // rect arrives already snapped to the device grid by the caller, so a hard
  // clip lands exactly on a pixel boundary.
  canvas.clipRect(dstRect, doAntiAlias: false);
  for (var j = 0; j < ny; j++) {
    final ty0 = snapY(y0 + j * th);
    final ty1 = snapY(y0 + (j + 1) * th);
    if (ty1 <= ty0) continue;
    for (var i = 0; i < nx; i++) {
      final tx0 = snapX(x0 + i * tw);
      final tx1 = snapX(x0 + (i + 1) * tw);
      if (tx1 <= tx0) continue;
      canvas.drawImageRect(
          img, src, ui.Rect.fromLTRB(tx0, ty0, tx1, ty1), paint);
    }
  }
  canvas.restore();
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
