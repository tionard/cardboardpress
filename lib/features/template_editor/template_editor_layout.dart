part of 'template_editor_screen.dart';

/// The Layout pane: base colour, background image, set symbol, border, corner
/// radius, and card size.
extension _TemplateLayoutPane on _TemplateBodyState {
  // ---- Layout pane ----

  Widget _layoutForm() {
    final border = _d.border;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _name,
          decoration: const InputDecoration(
              labelText: 'Template name',
              isDense: true,
              border: OutlineInputBorder()),
        ),
        const SizedBox(height: 20),
        Text('Base colour', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _colorWell(
          current: _d.baseColor,
          use: SwatchUse.card,
          onPicked: _setBaseColor,
        ),
        const SizedBox(height: 20),
        Row(children: [
          Text('Border', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          Switch(
            value: border != null,
            onChanged: (on) => _setBorder(
                on ? const BorderSpec(black: true, thickness: 0.022) : null),
          ),
        ]),
        if (border != null) ...[
          _labeledSlider(
              'Thickness',
              border.thickness,
              0.005,
              0.05,
              (v) => _update(_d.copyWith(
                  border: BorderSpec(black: border.black, thickness: v))),
              step: 0.002),
          Row(children: [
            const SizedBox(width: 80, child: Text('Colour')),
            const SizedBox(width: 8),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: true, label: Text('Black')),
                ButtonSegment(value: false, label: Text('White')),
              ],
              selected: {border.black},
              onSelectionChanged: (s) => _update(_d.copyWith(
                  border:
                      BorderSpec(black: s.first, thickness: border.thickness))),
            ),
          ]),
        ],
        const SizedBox(height: 16),
        Text('Corner radius', style: Theme.of(context).textTheme.titleSmall),
        LabeledSlider(
          label: '',
          labelWidth: 0,
          value: _d.cornerRadiusFrac.clamp(0.0, 0.12),
          min: 0.0,
          max: 0.12,
          step: 0.005,
          percent: true,
          onChanged: _setCornerRadius,
        ),
        const SizedBox(height: 8),
        Text('Card size', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        _sizeDropdown(),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(child: _dimField('Width', _widthCtl)),
          const SizedBox(width: 12),
          Expanded(child: _dimField('Height', _heightCtl)),
        ]),
      ],
    );
  }

  // ---- Layout <-> promoted-layers sync ----
  //
  // Once a template is promoted (_d.layers != null) the persisted list is the
  // render truth, so the Layout knobs that used to feed the derived chrome must
  // also update their baked layer counterparts — otherwise base colour becomes
  // a dead control and a changed corner radius leaves stale layer radii
  // (visible slivers at the corners when the radius shrinks).

  /// Base colour: template field + (when promoted) the `_base` layer's fill.
  void _setBaseColor(ColorRef ref) {
    var d = _d.copyWith(baseColor: ref);
    final ls = d.layers;
    if (ls != null) {
      d = d.copyWith(layers: [
        for (final l in ls)
          l.id == kBaseLayerId && l.fill != null
              ? l.copyWith(fill: l.fill!.copyWith(color: ref))
              : l,
      ]);
    }
    _update(d);
  }

  /// Corner radius: template field + (when promoted) the baked radius on the
  /// full-card chrome layers, which mirror the card's radius for AA parity.
  void _setCornerRadius(double v) {
    var d = _d.copyWith(cornerRadiusFrac: v);
    final ls = d.layers;
    if (ls != null) {
      const fullCardChrome = {
        kBaseLayerId,
        kBgLayerId,
        kTintLayerId,
        kFoilLayerId,
      };
      d = d.copyWith(layers: [
        for (final l in ls)
          fullCardChrome.contains(l.id) ? l.copyWith(cornerRadius: v) : l,
      ]);
    }
    _update(d);
  }

  /// Border on/off: template field + (when promoted) add/remove the `_border`
  /// slot so the Layers list stays in step with what actually draws.
  void _setBorder(BorderSpec? border) {
    var d = _d.copyWith(border: border);
    final ls = d.layers;
    if (ls != null) {
      final has = ls.any((l) => l.id == kBorderLayerId);
      if (border != null && !has) {
        d = d.copyWith(layers: [
          ...ls,
          const Layer(
              id: kBorderLayerId,
              name: 'Border',
              frac: Rect.fromLTRB(0, 0, 1, 1)),
        ]);
      } else if (border == null && has) {
        d = d.copyWith(layers: [
          for (final l in ls)
            if (l.id != kBorderLayerId) l,
        ]);
      }
    }
    _update(d);
  }

  Widget _sizeDropdown() {
    String currentKey = 'Custom';
    for (final e in _sizePresets.entries) {
      if ((e.value.$1 - _d.widthInches).abs() < 0.001 &&
          (e.value.$2 - _d.heightInches).abs() < 0.001) {
        currentKey = e.key;
        break;
      }
    }
    return DropdownButton<String>(
      isExpanded: true,
      value: currentKey,
      items: [
        if (currentKey == 'Custom')
          DropdownMenuItem(
              value: 'Custom',
              child: Text('Custom (${_d.widthInches} × ${_d.heightInches})')),
        for (final k in _sizePresets.keys)
          DropdownMenuItem(value: k, child: Text(k)),
      ],
      onChanged: (k) {
        if (k == null || k == 'Custom') return;
        final (w, h) = _sizePresets[k]!;
        _setDims(w, h);
      },
    );
  }

  Widget _dimField(String label, TextEditingController ctl) => TextField(
        controller: ctl,
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          suffixText: 'in',
        ),
      );
}
