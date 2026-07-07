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
          _labeledSlider('Thickness', border.thickness, 0.005, 0.05,
              (v) => _update(_d.copyWith(
                  border: BorderSpec(black: border.black, thickness: v)))),
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
          decimals: 3,
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

  Widget _bgImageSection() {
    final hasImage = _d.bgImageId != null;
    final loading = hasImage && !_images.containsKey(_d.bgImageId);
    final tr = _d.bgTransform;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('Background image', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          if (hasImage && !tr.isIdentity)
            TextButton(
              onPressed: () => _setBgTransform(const ArtTransform()),
              child: const Text('Reset'),
            ),
        ]),
        const SizedBox(height: 6),
        if (!hasImage)
          OutlinedButton.icon(
            onPressed: _pickBgImage,
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add image'),
          )
        else ...[
          Row(children: [
            OutlinedButton.icon(
              onPressed: _pickBgImage,
              icon: const Icon(Icons.image_outlined),
              label: const Text('Replace'),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: _removeBgImage,
              icon: const Icon(Icons.delete_outline),
              label: const Text('Remove'),
            ),
          ]),
          if (loading)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Loading image…',
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 4),
          _labeledSlider('Zoom', tr.zoom, 1.0, 3.0,
              (v) => _setBgTransform(tr.copyWith(zoom: v))),
          _labeledSlider('Horizontal', tr.panX, -1.0, 1.0,
              (v) => _setBgTransform(tr.copyWith(panX: v))),
          _labeledSlider('Vertical', tr.panY, -1.0, 1.0,
              (v) => _setBgTransform(tr.copyWith(panY: v))),
          Text(
            'The image draws above the base colour and below a card\u2019s '
            'tint, so a tinted card still shows over it.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }

  // ---- set symbol placement ----

  void _setSymFrac({double? l, double? t, double? r, double? b}) {
    const min = 0.03;
    final p = _d.setSymbol;
    var left = l ?? p.frac.left;
    var top = t ?? p.frac.top;
    var right = r ?? p.frac.right;
    var bottom = b ?? p.frac.bottom;
    if (l != null) left = left.clamp(0.0, right - min);
    if (r != null) right = right.clamp(left + min, 1.0);
    if (t != null) top = top.clamp(0.0, bottom - min);
    if (b != null) bottom = bottom.clamp(top + min, 1.0);
    _update(_d.copyWith(
        setSymbol: p.copyWith(frac: Rect.fromLTRB(left, top, right, bottom))));
  }

  Widget _setSymbolSection() {
    final p = _d.setSymbol;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text('Set symbol', style: Theme.of(context).textTheme.titleSmall),
          const Spacer(),
          Switch(
            value: p.enabled,
            onChanged: (on) =>
                _update(_d.copyWith(setSymbol: p.copyWith(enabled: on))),
          ),
        ]),
        Text(
          'Where a set\u2019s chosen symbol draws on cards using this template. '
          'The symbol itself is picked per set in Collection.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        if (p.enabled) ...[
          const SizedBox(height: 4),
          _labeledSlider('Left', p.frac.left, 0, 1, (v) => _setSymFrac(l: v),
              step: 0.01),
          _labeledSlider('Top', p.frac.top, 0, 1, (v) => _setSymFrac(t: v),
              step: 0.01),
          _labeledSlider('Right', p.frac.right, 0, 1, (v) => _setSymFrac(r: v),
              step: 0.01),
          _labeledSlider('Bottom', p.frac.bottom, 0, 1, (v) => _setSymFrac(b: v),
              step: 0.01),
          _labeledSlider('Opacity', p.alpha, 0, 1,
              (v) => _update(_d.copyWith(setSymbol: p.copyWith(alpha: v)))),
        ],
      ],
    );
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
