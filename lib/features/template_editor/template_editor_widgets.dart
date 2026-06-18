part of 'template_editor_screen.dart';

/// Shared presentation helpers for the Template Editor body — the stepped/
/// labelled slider and the palette swatch / none tiles, used by both panes.
extension _TemplateEditorShared on _TemplateBodyState {
  // ---- shared bits ----

  // Fine controls (small ranges like sizes/thicknesses) read better with more
  // precision than coarse 0..1/0..3 sliders.
  String _fmtSlider(double v, double max) =>
      max <= 0.2 ? v.toStringAsFixed(3) : v.toStringAsFixed(2);

  Widget _labeledSlider(String label, double value, double min, double max,
      ValueChanged<double> onChanged,
      {double? step}) {
    final shown = value.clamp(min, max);
    // Snap to discrete steps. Fine ranges step by 0.005, coarser ones by 0.05,
    // unless the caller overrides (e.g. position uses clean 1% steps).
    final s = step ?? ((max - min) <= 0.15 ? 0.005 : 0.05);
    final divisions = ((max - min) / s).round().clamp(1, 1000);
    return Row(children: [
      SizedBox(
          width: 80,
          child: Text(label, style: Theme.of(context).textTheme.bodySmall)),
      Expanded(
        child: Slider(
            value: shown,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged),
      ),
      SizedBox(
        width: 40,
        child: Text(
          _fmtSlider(shown, max),
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    ]);
  }

  Widget _swatch(ColorValue v, bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(8);
    final deco = v.c2 == null
        ? BoxDecoration(color: v.c1, borderRadius: radius)
        : BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              colors: [v.c1, v.c2!],
              begin: v.orientation == MixOrientation.vertical
                  ? Alignment.topCenter
                  : Alignment.centerLeft,
              end: v.orientation == MixOrientation.vertical
                  ? Alignment.bottomCenter
                  : Alignment.centerRight,
            ),
          );
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Container(
        width: 40,
        height: 40,
        decoration: deco.copyWith(
          border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 3 : 1),
        ),
      ),
    );
  }

  Widget _noneTile(bool selected, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 3 : 1),
        ),
        child: Icon(Icons.block, size: 18, color: scheme.outline),
      ),
    );
  }
}

String _typeLabel(FieldType t) => t.name[0].toUpperCase() + t.name.substring(1);
