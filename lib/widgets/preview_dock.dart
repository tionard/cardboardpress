// lib/widgets/preview_dock.dart
//
// A phone-layout primitive: a large preview area with a slide-up "dock" pinned
// to the bottom. Dragging the dock's grab handle resizes it, and the preview
// above shrinks/grows to fill whatever space the dock leaves. Tapping the handle
// toggles between collapsed and the default open height.
//
// It is deliberately GENERIC — it knows nothing about cards. The caller supplies
// three widgets:
//   * header   — optional, fixed, sits on top (e.g. the template picker row).
//   * preview  — fills the area above the dock. Put a LayoutBuilder inside it so
//                your content fits the (shrinking) box it's handed.
//   * dock     — the content laid out below the grab handle (e.g. rail + panel).
//
// Keeping it card-agnostic means the Template Editor (and any future editor) can
// reuse the exact same gesture without duplicating the drag/snap logic.

import 'package:flutter/material.dart';

class PreviewDockScaffold extends StatefulWidget {
  final Widget? header;
  final Widget preview;
  final Widget dock;

  /// Dock height as a fraction of the available (below-header) area.
  final double minFraction; // collapsed — just the handle + a peek of the dock
  final double initialFraction; // default open height
  final double maxFraction; // expanded

  const PreviewDockScaffold({
    super.key,
    this.header,
    required this.preview,
    required this.dock,
    this.minFraction = 0.14,
    this.initialFraction = 0.52,
    this.maxFraction = 0.88,
  });

  @override
  State<PreviewDockScaffold> createState() => _PreviewDockScaffoldState();
}

class _PreviewDockScaffoldState extends State<PreviewDockScaffold> {
  late double _frac = widget.initialFraction;
  bool _dragging = false;

  void _onDragStart() => setState(() => _dragging = true);

  void _onDrag(double dy, double areaH) {
    if (areaH <= 0) return;
    // Dragging the handle UP (negative dy) grows the dock and shrinks preview.
    setState(() {
      _frac = (_frac - dy / areaH)
          .clamp(widget.minFraction, widget.maxFraction)
          .toDouble();
    });
  }

  void _onDragEnd() {
    // Snap to the nearest of the three rest positions.
    final stops = <double>[
      widget.minFraction,
      widget.initialFraction,
      widget.maxFraction,
    ];
    var best = stops.first;
    var bestDist = (best - _frac).abs();
    for (final s in stops) {
      final d = (s - _frac).abs();
      if (d < bestDist) {
        best = s;
        bestDist = d;
      }
    }
    setState(() {
      _frac = best;
      _dragging = false;
    });
  }

  void _toggle() {
    setState(() {
      final collapsed = _frac <= widget.minFraction + 0.02;
      _frac = collapsed ? widget.initialFraction : widget.minFraction;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (widget.header != null) widget.header!,
        Expanded(
          child: LayoutBuilder(
            builder: (context, c) {
              final areaH = c.maxHeight;
              final dockH = areaH * _frac;
              final previewH = areaH - dockH;
              // Track the finger instantly while dragging; animate the snap.
              final dur =
                  _dragging ? Duration.zero : const Duration(milliseconds: 180);
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: dur,
                    curve: Curves.easeOut,
                    left: 0,
                    right: 0,
                    top: 0,
                    height: previewH < 0 ? 0 : previewH,
                    child: widget.preview,
                  ),
                  AnimatedPositioned(
                    duration: dur,
                    curve: Curves.easeOut,
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: dockH,
                    child: _DockShell(
                      onDragStart: _onDragStart,
                      onDrag: (dy) => _onDrag(dy, areaH),
                      onDragEnd: _onDragEnd,
                      onTapHandle: _toggle,
                      child: widget.dock,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The rounded panel that holds the grab handle (the drag target) and the dock
/// content below it.
class _DockShell extends StatelessWidget {
  final VoidCallback onDragStart;
  final ValueChanged<double> onDrag; // primaryDelta dy
  final VoidCallback onDragEnd;
  final VoidCallback onTapHandle;
  final Widget child;

  const _DockShell({
    required this.onDragStart,
    required this.onDrag,
    required this.onDragEnd,
    required this.onTapHandle,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 10,
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragStart: (_) => onDragStart(),
            onVerticalDragUpdate: (d) => onDrag(d.primaryDelta ?? 0),
            onVerticalDragEnd: (_) => onDragEnd(),
            onTap: onTapHandle,
            child: SizedBox(
              height: 28,
              width: double.infinity,
              child: Center(
                child: Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}
