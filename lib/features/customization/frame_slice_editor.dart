// lib/features/customization/frame_slice_editor.dart
//
// The visual slicing editor for library frames (plan phase 3), plus the shared
// preview plumbing it owns: [FramePreviewPainter] and [decodedFrameImage] (used
// by the manager's grid thumbs and the template-side picker too).
//
// [editFrameSlicing] is THE slicing dialog — opened from Customization →
// Frames and from a template border's "Edit frame…" alike, always editing the
// LIBRARY frame, so every referencing template follows. The sprite is rendered
// large with four draggable guide lines (one per cut); cuts snap to whole
// SOURCE pixels — the natural grid for slicing, since a sprite's border art
// sits on pixel boundaries — with a live %·px readout. Beside the guides, live
// mini-previews at three aspect ratios (card / square / banner) show how the
// slicing behaves at different shapes, painted through the real nine-slice
// renderer (one render path, extended to the editor).
//
// Desktop notes baked in: drags use paired horizontal+vertical drag
// recognisers (not onPan), so they beat an enclosing scrollable's own drag in
// the gesture arena — whichever axis wins, both handlers feed the same update,
// so a sloppy diagonal drag still follows the pointer. Hit zones are ±24 px
// around each line, no fiddly handle-hunting.

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/card_model.dart';
import '../../rendering/paint_card.dart';
import '../../state/providers.dart';

// ---------------------------------------------------------------------------
// The dialog
// ---------------------------------------------------------------------------

/// Edits [f]'s slicing — the four source cuts and the two tile modes — with
/// draggable guide lines and live multi-aspect previews. Saving writes to the
/// LIBRARY, so every referencing template updates.
Future<void> editFrameSlicing(
    BuildContext context, WidgetRef ref, FrameEntry f) async {
  final img = await decodedFrameImage(ref, f.imageId);
  if (!context.mounted) return;
  if (img == null) {
    ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load the frame\'s image.')));
    return;
  }

  var insetL = f.insetL, insetT = f.insetT, insetR = f.insetR, insetB = f.insetB;
  var edgeMode = f.edgeMode, centerMode = f.centerMode;

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) {
        final backdrop = Theme.of(ctx).colorScheme.surfaceContainerHighest;
        NineSliceSpec spec() => NineSliceSpec(
              imageId: f.imageId,
              insetL: insetL,
              insetT: insetT,
              insetR: insetR,
              insetB: insetB,
              edgeMode: edgeMode,
              centerMode: centerMode,
              thickness: 0.08,
            );
        Widget preview(String caption, double w, double h) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CustomPaint(
                  size: Size(w, h),
                  painter: FramePreviewPainter(
                      image: img, spec: spec(), backdrop: backdrop),
                ),
                const SizedBox(height: 4),
                Text(caption, style: Theme.of(ctx).textTheme.bodySmall),
              ],
            );
        return AlertDialog(
          title: Text('Slicing — ${f.name}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Drag a line to set where the sprite is cut. A cut at 0 '
                    'removes that band — e.g. Top and Bottom at 0 makes a '
                    'left/center/right 3-slice. Cuts snap to sprite pixels.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 10),
                  Center(
                    child: InsetGuideEditor(
                      image: img,
                      insetL: insetL,
                      insetT: insetT,
                      insetR: insetR,
                      insetB: insetB,
                      maxWidth: 432,
                      maxHeight: 280,
                      onChanged: (l, t, r, b) => setLocal(() {
                        insetL = l;
                        insetT = t;
                        insetR = r;
                        insetB = b;
                      }),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text('How it slices',
                      style: Theme.of(ctx).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      preview('Card', 80, 112),
                      preview('Square', 96, 96),
                      preview('Banner', 150, 84),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tile edges'),
                    subtitle: const Text(
                        'Repeat the edge pattern instead of stretching it'),
                    value: edgeMode == SliceFillMode.tile,
                    onChanged: (v) => setLocal(() => edgeMode =
                        v ? SliceFillMode.tile : SliceFillMode.stretch),
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Tile center'),
                    subtitle: const Text(
                        'Applies when a template fills the center with this '
                        'frame'),
                    value: centerMode == SliceFillMode.tile,
                    onChanged: (v) => setLocal(() => centerMode =
                        v ? SliceFillMode.tile : SliceFillMode.stretch),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    ),
  );

  if (saved == true) {
    await ref.read(frameRepositoryProvider).updateSlicing(
          f.id,
          insetL: insetL,
          insetT: insetT,
          insetR: insetR,
          insetB: insetB,
          edgeMode: edgeMode,
          centerMode: centerMode,
        );
  }
}

// ---------------------------------------------------------------------------
// Guide editor
// ---------------------------------------------------------------------------

enum _Guide { left, top, right, bottom }

/// Snap a source-cut fraction to whole source pixels — the natural grid for
/// slicing, since a sprite's border art sits on pixel boundaries — clamped to
/// the model's 0..0.49 range. A non-positive [sourcePx] skips the snap.
double snapInsetToSourcePixels(double frac, int sourcePx) {
  final v = frac.clamp(0.0, 0.49);
  if (sourcePx <= 0) return v;
  return ((v * sourcePx).round() / sourcePx).clamp(0.0, 0.49);
}

/// The sprite rendered large (contain-fit inside [maxWidth]×[maxHeight], over
/// a checkerboard so transparency reads) with four draggable cut lines and a
/// %·px readout per cut. Self-contained: canvas on top, readout row below.
class InsetGuideEditor extends StatefulWidget {
  final ui.Image image;
  final double insetL, insetT, insetR, insetB;
  final double maxWidth, maxHeight;
  final void Function(double l, double t, double r, double b) onChanged;

  const InsetGuideEditor({
    super.key,
    required this.image,
    required this.insetL,
    required this.insetT,
    required this.insetR,
    required this.insetB,
    required this.onChanged,
    this.maxWidth = 400,
    this.maxHeight = 280,
  });

  @override
  State<InsetGuideEditor> createState() => _InsetGuideEditorState();
}

class _InsetGuideEditorState extends State<InsetGuideEditor> {
  _Guide? _active;

  Size get _canvasSize {
    final iw = widget.image.width.toDouble();
    final ih = widget.image.height.toDouble();
    if (iw <= 0 || ih <= 0) return Size(widget.maxWidth, widget.maxHeight);
    final scale = (widget.maxWidth / iw < widget.maxHeight / ih)
        ? widget.maxWidth / iw
        : widget.maxHeight / ih;
    return Size(iw * scale, ih * scale);
  }

  void _start(Offset p) {
    final s = _canvasSize;
    // Nearest guide line within 24 px claims the drag.
    final candidates = <(_Guide, double)>[
      (_Guide.left, (p.dx - widget.insetL * s.width).abs()),
      (_Guide.right, (p.dx - (s.width - widget.insetR * s.width)).abs()),
      (_Guide.top, (p.dy - widget.insetT * s.height).abs()),
      (_Guide.bottom, (p.dy - (s.height - widget.insetB * s.height)).abs()),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    setState(() => _active = candidates.first.$2 <= 24 ? candidates.first.$1 : null);
  }

  void _update(Offset p) {
    final g = _active;
    if (g == null) return;
    final s = _canvasSize;
    final iw = widget.image.width;
    final ih = widget.image.height;
    var l = widget.insetL, t = widget.insetT, r = widget.insetR, b = widget.insetB;
    switch (g) {
      case _Guide.left:
        l = snapInsetToSourcePixels(p.dx / s.width, iw);
      case _Guide.right:
        r = snapInsetToSourcePixels((s.width - p.dx) / s.width, iw);
      case _Guide.top:
        t = snapInsetToSourcePixels(p.dy / s.height, ih);
      case _Guide.bottom:
        b = snapInsetToSourcePixels((s.height - p.dy) / s.height, ih);
    }
    widget.onChanged(l, t, r, b);
  }

  void _end() => setState(() => _active = null);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _canvasSize;
    final iw = widget.image.width;
    final ih = widget.image.height;

    Widget readout(String label, double frac, int sourcePx, _Guide g) {
      final active = _active == g;
      return Text(
        '$label ${(frac * 100).toStringAsFixed(0)}% · '
        '${(frac * sourcePx).round()}px',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: active ? scheme.primary : null,
              fontWeight: active ? FontWeight.bold : null,
            ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Paired H+V drag recognisers (NOT onPan): same-type recognisers beat
        // an enclosing scrollable's drag in the gesture arena, and both feed
        // the same handlers so the guide follows the pointer whichever axis
        // claimed the gesture.
        GestureDetector(
          onHorizontalDragStart: (d) => _start(d.localPosition),
          onHorizontalDragUpdate: (d) => _update(d.localPosition),
          onHorizontalDragEnd: (_) => _end(),
          onVerticalDragStart: (d) => _start(d.localPosition),
          onVerticalDragUpdate: (d) => _update(d.localPosition),
          onVerticalDragEnd: (_) => _end(),
          child: MouseRegion(
            cursor: SystemMouseCursors.move,
            child: CustomPaint(
              size: s,
              painter: _GuidePainter(
                image: widget.image,
                insetL: widget.insetL,
                insetT: widget.insetT,
                insetR: widget.insetR,
                insetB: widget.insetB,
                active: _active,
                accent: scheme.primary,
                checkerA: scheme.surfaceContainerHighest,
                checkerB: scheme.surfaceContainerLow,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          children: [
            readout('L', widget.insetL, iw, _Guide.left),
            readout('T', widget.insetT, ih, _Guide.top),
            readout('R', widget.insetR, iw, _Guide.right),
            readout('B', widget.insetB, ih, _Guide.bottom),
          ],
        ),
      ],
    );
  }
}

class _GuidePainter extends CustomPainter {
  final ui.Image image;
  final double insetL, insetT, insetR, insetB;
  final _Guide? active;
  final Color accent;
  final Color checkerA;
  final Color checkerB;

  const _GuidePainter({
    required this.image,
    required this.insetL,
    required this.insetT,
    required this.insetR,
    required this.insetB,
    required this.active,
    required this.accent,
    required this.checkerA,
    required this.checkerB,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);

    // Checkerboard, so a transparent sprite reads.
    const cell = 8.0;
    final pa = Paint()..color = checkerA;
    final pb = Paint()..color = checkerB;
    for (var y = 0; y * cell < size.height; y++) {
      for (var x = 0; x * cell < size.width; x++) {
        canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell),
            (x + y).isEven ? pa : pb);
      }
    }

    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.medium,
    );

    final xL = insetL * size.width;
    final xR = size.width - insetR * size.width;
    final yT = insetT * size.height;
    final yB = size.height - insetB * size.height;

    void line(Offset a, Offset b, bool isActive) {
      // A soft white underlay keeps the line visible on any sprite colour.
      canvas.drawLine(
          a,
          b,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.7)
            ..strokeWidth = (isActive ? 3.0 : 2.0) + 2);
      canvas.drawLine(
          a,
          b,
          Paint()
            ..color = accent
            ..strokeWidth = isActive ? 3.0 : 2.0);
    }

    void grip(Offset c) {
      canvas.drawCircle(c, 7, Paint()..color = accent);
      canvas.drawCircle(
          c,
          7,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = Colors.white);
    }

    line(Offset(xL, 0), Offset(xL, size.height), active == _Guide.left);
    line(Offset(xR, 0), Offset(xR, size.height), active == _Guide.right);
    line(Offset(0, yT), Offset(size.width, yT), active == _Guide.top);
    line(Offset(0, yB), Offset(size.width, yB), active == _Guide.bottom);

    grip(Offset(xL, size.height / 2));
    grip(Offset(xR, size.height / 2));
    grip(Offset(size.width / 2, yT));
    grip(Offset(size.width / 2, yB));

    canvas.restore();
  }

  @override
  bool shouldRepaint(_GuidePainter old) =>
      !identical(old.image, image) ||
      old.insetL != insetL ||
      old.insetT != insetT ||
      old.insetR != insetR ||
      old.insetB != insetB ||
      old.active != active ||
      old.accent != accent ||
      old.checkerA != checkerA ||
      old.checkerB != checkerB;
}

// ---------------------------------------------------------------------------
// Shared preview plumbing (used by the manager grid and the picker too)
// ---------------------------------------------------------------------------

/// Paints a frame preview through [paintFramePreview] — the same nine-slice
/// painter the card renderer uses.
class FramePreviewPainter extends CustomPainter {
  final ui.Image image;
  final NineSliceSpec spec;
  final Color backdrop;
  const FramePreviewPainter(
      {required this.image, required this.spec, required this.backdrop});

  @override
  void paint(Canvas canvas, Size size) =>
      paintFramePreview(canvas, size, image, spec, backdrop: backdrop);

  @override
  bool shouldRepaint(FramePreviewPainter old) =>
      !identical(old.image, image) ||
      old.backdrop != backdrop ||
      old.spec.imageId != spec.imageId ||
      old.spec.insetL != spec.insetL ||
      old.spec.insetT != spec.insetT ||
      old.spec.insetR != spec.insetR ||
      old.spec.insetB != spec.insetB ||
      old.spec.edgeMode != spec.edgeMode ||
      old.spec.centerMode != spec.centerMode ||
      old.spec.thickness != spec.thickness;
}

/// Decode a stored image into a ui.Image, via a small process-wide cache.
/// Image ids are immutable (a replaced image gets a new id), so entries never
/// go stale.
final Map<String, ui.Image> _imageCache = {};

Future<ui.Image?> decodedFrameImage(WidgetRef ref, String imageId) async {
  if (imageId.isEmpty) return null;
  final cached = _imageCache[imageId];
  if (cached != null) return cached;
  final bytes = await ref.read(imageStoreProvider).load(imageId);
  if (bytes == null) return null;
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  _imageCache[imageId] = frame.image;
  return frame.image;
}
