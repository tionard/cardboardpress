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
//
// Mobile perf notes baked in: during a drag the guide editor tracks the live
// value INTERNALLY and only commits through [onChanged] on release, so the
// dialog — and its three mini nine-slice previews — rebuild once per drag,
// not per tick. The transparency checkerboard is rasterised ONCE into a
// cached image (one draw op per frame instead of ~2k rects), and the guide
// canvas and each preview sit behind RepaintBoundary so a tick repaints
// nothing but the guide layer itself.

import 'dart:collection' show LinkedHashMap;
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
                RepaintBoundary(
                  child: CustomPaint(
                    size: Size(w, h),
                    painter: FramePreviewPainter(
                        image: img, spec: spec(), backdrop: backdrop),
                  ),
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
                  const SizedBox(height: 12),
                  Text(
                    'Stretch scales the pattern; Tile repeats it at its '
                    'natural size (partial tiles split evenly at the ends); '
                    'Fit repeats whole tiles only, stretched evenly to fill '
                    'exactly.',
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  _modeRow(ctx, 'Edges', edgeMode,
                      (m) => setLocal(() => edgeMode = m)),
                  const SizedBox(height: 8),
                  _modeRow(ctx, 'Center', centerMode,
                      (m) => setLocal(() => centerMode = m)),
                  const SizedBox(height: 4),
                  Text(
                    'Center mode applies when a template fills the center '
                    'with this frame.',
                    style: Theme.of(ctx).textTheme.bodySmall,
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

/// A labelled Stretch | Tile | Fit picker for one 9-slice region.
Widget _modeRow(BuildContext context, String label, SliceFillMode value,
    ValueChanged<SliceFillMode> onChanged) {
  return Row(
    children: [
      SizedBox(width: 60, child: Text(label)),
      Expanded(
        child: SegmentedButton<SliceFillMode>(
          showSelectedIcon: false,
          style: const ButtonStyle(
              visualDensity: VisualDensity(horizontal: -2, vertical: -2)),
          segments: const [
            ButtonSegment(
                value: SliceFillMode.stretch, label: Text('Stretch')),
            ButtonSegment(value: SliceFillMode.tile, label: Text('Tile')),
            ButtonSegment(value: SliceFillMode.fit, label: Text('Fit')),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
        ),
      ),
    ],
  );
}

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

  // Live values while a drag is in flight; committed through onChanged on
  // release. Null when idle — the widget is controlled between drags.
  double? _dragL, _dragT, _dragR, _dragB;

  // The transparency checkerboard, rasterised once per size/theme and reused
  // every frame (one drawImageRect instead of a rect-per-cell loop).
  ui.Image? _checker;
  Size? _checkerSize;
  Color? _checkerA, _checkerB;

  double get _effL => _dragL ?? widget.insetL;
  double get _effT => _dragT ?? widget.insetT;
  double get _effR => _dragR ?? widget.insetR;
  double get _effB => _dragB ?? widget.insetB;

  @override
  void dispose() {
    _checker?.dispose();
    super.dispose();
  }

  ui.Image _checkerFor(Size s, Color a, Color b) {
    final cached = _checker;
    if (cached != null &&
        _checkerSize == s &&
        _checkerA == a &&
        _checkerB == b) {
      return cached;
    }
    cached?.dispose();
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    const cell = 8.0;
    canvas.drawRect(Offset.zero & s, Paint()..color = a);
    final pb = Paint()..color = b;
    for (var y = 0; y * cell < s.height; y++) {
      for (var x = 0; x * cell < s.width; x++) {
        if ((x + y).isOdd) {
          canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), pb);
        }
      }
    }
    final pic = rec.endRecording();
    final img = pic.toImageSync(s.width.ceil(), s.height.ceil());
    pic.dispose();
    _checker = img;
    _checkerSize = s;
    _checkerA = a;
    _checkerB = b;
    return img;
  }

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
      (_Guide.left, (p.dx - _effL * s.width).abs()),
      (_Guide.right, (p.dx - (s.width - _effR * s.width)).abs()),
      (_Guide.top, (p.dy - _effT * s.height).abs()),
      (_Guide.bottom, (p.dy - (s.height - _effB * s.height)).abs()),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    setState(() => _active = candidates.first.$2 <= 24 ? candidates.first.$1 : null);
  }

  // Per-tick updates stay INSIDE this State: only the guide canvas and the
  // readout row repaint while dragging. The parent hears about it on release.
  void _update(Offset p) {
    final g = _active;
    if (g == null) return;
    final s = _canvasSize;
    final iw = widget.image.width;
    final ih = widget.image.height;
    setState(() {
      switch (g) {
        case _Guide.left:
          _dragL = snapInsetToSourcePixels(p.dx / s.width, iw);
        case _Guide.right:
          _dragR = snapInsetToSourcePixels((s.width - p.dx) / s.width, iw);
        case _Guide.top:
          _dragT = snapInsetToSourcePixels(p.dy / s.height, ih);
        case _Guide.bottom:
          _dragB = snapInsetToSourcePixels((s.height - p.dy) / s.height, ih);
      }
    });
  }

  void _end() {
    final changed =
        _dragL != null || _dragT != null || _dragR != null || _dragB != null;
    final l = _effL, t = _effT, r = _effR, b = _effB;
    setState(() {
      _active = null;
      _dragL = _dragT = _dragR = _dragB = null;
    });
    // Commit AFTER clearing the overrides: the parent rebuilds us with the
    // same values we just showed, so nothing jumps.
    if (changed) widget.onChanged(l, t, r, b);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final s = _canvasSize;
    final iw = widget.image.width;
    final ih = widget.image.height;
    final checker = _checkerFor(
        s, scheme.surfaceContainerHighest, scheme.surfaceContainerLow);

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
            child: RepaintBoundary(
              child: CustomPaint(
                size: s,
                painter: _GuidePainter(
                  image: widget.image,
                  checker: checker,
                  insetL: _effL,
                  insetT: _effT,
                  insetR: _effR,
                  insetB: _effB,
                  active: _active,
                  accent: scheme.primary,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 14,
          children: [
            readout('L', _effL, iw, _Guide.left),
            readout('T', _effT, ih, _Guide.top),
            readout('R', _effR, iw, _Guide.right),
            readout('B', _effB, ih, _Guide.bottom),
          ],
        ),
      ],
    );
  }
}

class _GuidePainter extends CustomPainter {
  final ui.Image image;
  final ui.Image checker; // pre-rasterised checkerboard, one draw op
  final double insetL, insetT, insetR, insetB;
  final _Guide? active;
  final Color accent;

  const _GuidePainter({
    required this.image,
    required this.checker,
    required this.insetL,
    required this.insetT,
    required this.insetR,
    required this.insetB,
    required this.active,
    required this.accent,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.save();
    canvas.clipRect(rect);

    // Checkerboard (so a transparent sprite reads), rasterised once upstream.
    canvas.drawImageRect(
      checker,
      Rect.fromLTWH(
          0, 0, checker.width.toDouble(), checker.height.toDouble()),
      rect,
      Paint(),
    );

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
      !identical(old.checker, checker) ||
      old.insetL != insetL ||
      old.insetT != insetT ||
      old.insetR != insetR ||
      old.insetB != insetB ||
      old.active != active ||
      old.accent != accent;
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

/// Decode a stored image into a ui.Image, via a small process-wide LRU cache.
/// Image ids are immutable (content-addressed; edited content = new id), so
/// entries never go stale — the cache is bounded purely to cap native memory
/// on mobile. The capacity comfortably exceeds anything visible at once
/// (frames grid + picker + slicing dialog), so an evicted-and-disposed image
/// is never one a live painter still holds; an evicted frame simply re-decodes
/// next time its thumb builds.
const _imageCacheCap = 48;
final LinkedHashMap<String, ui.Image> _imageCache = LinkedHashMap();

Future<ui.Image?> decodedFrameImage(WidgetRef ref, String imageId) async {
  if (imageId.isEmpty) return null;
  final cached = _imageCache.remove(imageId);
  if (cached != null) {
    _imageCache[imageId] = cached; // re-insert: most recently used
    return cached;
  }
  final bytes = await ref.read(imageStoreProvider).load(imageId);
  if (bytes == null) return null;
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  _imageCache[imageId] = frame.image;
  while (_imageCache.length > _imageCacheCap) {
    _imageCache.remove(_imageCache.keys.first)?.dispose();
  }
  return frame.image;
}
