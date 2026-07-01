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

  // A colour well that launches the picker popup (Phase 2). Shows the current
  // colour, or a "none" tile when [current] is null; the chosen ColorRef comes
  // back through [onPicked]. Clearing is a separate button (when [onClear] is
  // given) — the popup itself never returns "none". Any use-site opacity slider
  // stays in the pane beside this. [allowAlpha] false forbids baked translucency.
  Widget _colorWell({
    required ColorRef? current,
    required SwatchUse use,
    required ValueChanged<ColorRef> onPicked,
    VoidCallback? onClear,
    bool allowAlpha = true,
  }) {
    Future<void> open() async {
      final picked = await showColorPicker(context,
          use: use, initial: current, allowAlpha: allowAlpha);
      if (picked != null) onPicked(picked);
    }

    final resolved = current == null
        ? null
        : CardRefs(palette: widget.palette).resolveColor(current);
    final well = resolved == null
        ? _noneTile(false, open)
        : _swatch(resolved, false, open);

    if (onClear == null) {
      return Align(alignment: Alignment.centerLeft, child: well);
    }
    return Row(
      children: [
        well,
        const SizedBox(width: 12),
        if (current != null)
          TextButton(onPressed: onClear, child: const Text('None')),
      ],
    );
  }
}

String _typeLabel(FieldType t) => t.name[0].toUpperCase() + t.name.substring(1);
