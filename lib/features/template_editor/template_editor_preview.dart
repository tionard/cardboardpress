// lib/features/template_editor/template_editor_preview.dart
//
// The editor's live PREVIEW: composes the template with EMPTY content (so
// placeholders show), paints it through the one true render path, and stacks
// the editor overlays on top — the set-symbol zone guide and the
// selected-layer outline. `_fittingPreviewWithOverlay` is the size-to-box
// variant used by both the desktop column and the phone dock.

part of 'template_editor_screen.dart';

extension _TemplatePreview on _TemplateBodyState {
  // Fit the preview (and its overlays) into whatever box it's handed, so it can
  // scale as the dock grows/shrinks on the phone.
  Widget _fittingPreviewWithOverlay() {
    final aspect = _d.widthInches / _d.heightInches;
    return LayoutBuilder(
      builder: (context, c) {
        const pad = 16.0;
        final double availW = c.maxWidth - pad * 2;
        final double availH = c.maxHeight - pad * 2;
        if (availW <= 0 || availH <= 0) return const SizedBox.shrink();
        double w = availW;
        if (w / aspect > availH) w = availH * aspect;
        return Padding(
          padding: const EdgeInsets.all(pad),
          child: Center(child: _previewWithOverlay(w)),
        );
      },
    );
  }

  Widget _previewWithOverlay(double w) {
    final h = w * _d.heightInches / _d.widthInches;
    // Empty content: free text layers render their PLACEHOLDER (showPlaceholders
    // below) and bound layers their preview samples. Sample card content would
    // mask edited placeholders, since every template shares the default field ids.
    final card = composeCard(_d,
        content: const CardContent(),
        symbolImageIds: ref.watch(textSymbolMapProvider),
        symbolsById: ref.watch(symbolsMapProvider),
        footerPlaceholder: _footerPlaceholder);
    final layers = effectiveTemplateLayers(_d);
    Layer? symbolGuide;
    Layer? selectedLayer;
    for (final l in layers) {
      if (l.id == kSetSymbolLayerId && l.visible) symbolGuide = l;
      if (_mode == _Mode.layers && l.id == _selectedLayerId) selectedLayer = l;
    }
    // The border draws outside the card rect; an in-card outline would lie.
    if (selectedLayer?.id == kBorderLayerId) selectedLayer = null;
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          CardPreview(
              card: card,
              refs: CardRefs(
                  palette: widget.palette,
                  images: _images,
                  showPlaceholders: true),
              width: w),
          // Selected-layer outline (Layers mode): live feedback for the
          // Position & size sliders even on layers with nothing visible to draw
          // (no fill/image/outline yet). Rounded to match the layer's corner.
          if (selectedLayer != null)
            Positioned(
              left: selectedLayer.frac.left * w,
              top: selectedLayer.frac.top * h,
              width: selectedLayer.frac.width * w,
              height: selectedLayer.frac.height * h,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius:
                        BorderRadius.circular(selectedLayer.cornerRadius * w),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.primary, width: 2),
                  ),
                ),
              ),
            ),
          // Set-symbol placement guide (the symbol itself only renders on real
          // cards, where the set has chosen one — here we just show the zone).
          // Read from the EFFECTIVE layers so a promoted template's moved or
          // hidden set-symbol layer is reflected, not the stale field placement.
          if (symbolGuide != null)
            Positioned(
              left: symbolGuide.frac.left * w,
              top: symbolGuide.frac.top * h,
              width: symbolGuide.frac.width * w,
              height: symbolGuide.frac.height * h,
              child: IgnorePointer(
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Theme.of(context).colorScheme.tertiary,
                        width: 1.5),
                    color: Theme.of(context)
                        .colorScheme
                        .tertiary
                        .withValues(alpha: 0.12),
                  ),
                  child: Icon(Icons.star_border,
                      size: 16,
                      color: Theme.of(context).colorScheme.tertiary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
