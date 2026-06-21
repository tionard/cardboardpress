part of 'template_editor_screen.dart';

/// Shared presentation helpers for the Template Editor body — the stepped/
/// labelled slider and the palette swatch / none tiles, used by both panes.
extension _TemplateEditorShared on _TemplateBodyState {
  // ---- shared bits ----

  Widget _labeledSlider(String label, double value, double min, double max,
      ValueChanged<double> onChanged,
      {double? step}) {
    // Fine ranges (sizes/thicknesses) read better with an extra decimal.
    return LabeledSlider(
      label: label,
      value: value,
      min: min,
      max: max,
      step: step,
      decimals: max <= 0.2 ? 3 : 2,
      onChanged: onChanged,
    );
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
