part of 'template_editor_screen.dart';

/// The Fields pane: add / remove / select fields and edit the selected one
/// (type, layer order, position, corner, fill, outline, text style).
extension _TemplateFieldsPane on _TemplateBodyState {
  /// Open the symbol picker for a Rules field's watermark, then decode the
  /// chosen symbol so the preview reflects it.
  Future<void> _pickWatermarkSymbol(FieldSpec f) async {
    final current = f.watermark;
    final choice = await pickSymbol(context, ref, currentId: current?.symbolId);
    if (choice == null) return; // cancelled
    final base = current ?? const WatermarkSpec(color: _inkRef);
    _updateField(
        f.copyWith(watermark: base.copyWith(symbolId: choice.id ?? '')));
    _syncImages();
  }

  // ---- Fields pane ----

  Widget _fieldsPane() {
    final sel = _selectedField;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text('Fields', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            PopupMenuButton<FieldType>(
              onSelected: _addField,
              itemBuilder: (_) => [
                for (final t in FieldType.values)
                  PopupMenuItem(
                      value: t,
                      enabled: _canAdd(t),
                      child: Text(_typeLabel(t))),
              ],
              child: const Chip(
                avatar: Icon(Icons.add, size: 18),
                label: Text('Add field'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final f in _d.fields)
              ChoiceChip(
                label: Text(_typeLabel(f.type)),
                selected: f.id == _selectedFieldId,
                onSelected: (_) => _selectField(f.id),
              ),
          ],
        ),
        const Divider(height: 28),
        if (sel == null)
          Text('Select a field to edit it, or add one.',
              style: Theme.of(context).textTheme.bodySmall)
        else
          _fieldEditor(sel),
      ],
    );
  }

  Widget _fieldEditor(FieldSpec f) {
    final text = f.text;
    final outline = f.outline;
    final index = _d.fields.indexWhere((x) => x.id == f.id);
    final last = _d.fields.length - 1;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pinned: type, layer order, delete — always visible.
        Row(
          children: [
            const SizedBox(width: 80, child: Text('Type')),
            Expanded(
              child: DropdownButton<FieldType>(
                isExpanded: true,
                value: f.type,
                items: [
                  for (final t in FieldType.values)
                    DropdownMenuItem(
                        value: t,
                        enabled: _canChangeTo(t, f),
                        child: Text(_typeLabel(t))),
                ],
                onChanged: (t) {
                  if (t != null) _changeFieldType(f, t);
                },
              ),
            ),
            IconButton(
              tooltip: 'Move back (behind)',
              icon: const Icon(Icons.keyboard_arrow_up),
              onPressed: index > 0 ? () => _moveField(f.id, -1) : null,
            ),
            IconButton(
              tooltip: 'Move forward (on top)',
              icon: const Icon(Icons.keyboard_arrow_down),
              onPressed: index < last ? () => _moveField(f.id, 1) : null,
            ),
            IconButton(
              tooltip: 'Remove field',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _removeField(f.id),
            ),
          ],
        ),
        Text(
          'Layer ${index + 1} of ${last + 1} — later layers draw on top.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        _section('pos', 'Position & size', [
          _labeledSlider('Left', f.frac.left, 0, 1, (v) => _setFrac(f, l: v),
              step: 0.01),
          _labeledSlider('Top', f.frac.top, 0, 1, (v) => _setFrac(f, t: v),
              step: 0.01),
          _labeledSlider('Right', f.frac.right, 0, 1, (v) => _setFrac(f, r: v),
              step: 0.01),
          _labeledSlider('Bottom', f.frac.bottom, 0, 1,
              (v) => _setFrac(f, b: v), step: 0.01),
          const SizedBox(height: 8),
          _labeledSlider('Corner', f.cornerRadius, 0, 0.1,
              (v) => _updateField(f.copyWith(cornerRadius: v))),
        ]),
        if (f.type != FieldType.art)
          _section('fill', 'Fill', [
            const SizedBox(height: 4),
            Wrap(spacing: 10, runSpacing: 10, children: [
              _noneTile(
                  f.fill == null, () => _updateField(f.copyWith(fill: null))),
              for (final s in widget.swatches)
                _swatch(
                    s.value,
                    s.id == f.fill?.id,
                    () => _updateField(f.copyWith(
                        fill: ColorRef(id: s.id, snapshot: s.value)))),
            ]),
            if (f.fill != null)
              _labeledSlider('Opacity', f.fillAlpha, 0, 1,
                  (v) => _updateField(f.copyWith(fillAlpha: v))),
          ]),
        _section('outline', 'Outline', [
          Row(children: [
            const SizedBox(width: 80, child: Text('Enabled')),
            Switch(
              value: outline != null,
              onChanged: (on) => _updateField(
                  f.copyWith(outline: on ? const OutlineSpec() : null)),
            ),
          ]),
          if (outline != null) ...[
            _labeledSlider(
                'Intensity',
                outline.intensity,
                0,
                1,
                (v) => _updateField(
                    f.copyWith(outline: outline.copyWith(intensity: v)))),
            Row(children: [
              const SizedBox(width: 80, child: Text('Lighter')),
              Switch(
                value: outline.lighter,
                onChanged: (v) => _updateField(
                    f.copyWith(outline: outline.copyWith(lighter: v))),
              ),
            ]),
          ],
        ]),
        if (text != null)
          _section('text', 'Text', [
            _labeledSlider('Size', text.sizeFrac, 0.01, 0.12,
                (v) => _updateField(f.copyWith(text: text.copyWith(sizeFrac: v)))),
            Row(children: [
              const SizedBox(width: 80, child: Text('Bold')),
              Switch(
                value: text.bold,
                onChanged: (v) =>
                    _updateField(f.copyWith(text: text.copyWith(bold: v))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SegmentedButton<TextAlign>(
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(
                        value: TextAlign.left,
                        icon: Icon(Icons.format_align_left)),
                    ButtonSegment(
                        value: TextAlign.center,
                        icon: Icon(Icons.format_align_center)),
                    ButtonSegment(
                        value: TextAlign.right,
                        icon: Icon(Icons.format_align_right)),
                  ],
                  selected: {text.align},
                  onSelectionChanged: (s) => _updateField(
                      f.copyWith(text: text.copyWith(align: s.first))),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const SizedBox(width: 80, child: Text('Anchor')),
              SegmentedButton<VAlign>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: VAlign.top, icon: Icon(Icons.vertical_align_top)),
                  ButtonSegment(
                      value: VAlign.middle,
                      icon: Icon(Icons.vertical_align_center)),
                  ButtonSegment(
                      value: VAlign.bottom,
                      icon: Icon(Icons.vertical_align_bottom)),
                ],
                selected: {text.vAlign},
                onSelectionChanged: (s) => _updateField(
                    f.copyWith(text: text.copyWith(vAlign: s.first))),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              const SizedBox(width: 80, child: Text('Fit')),
              SegmentedButton<TextFit>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: TextFit.fixed, label: Text('Fixed')),
                  ButtonSegment(value: TextFit.shrink, label: Text('Shrink')),
                ],
                selected: {text.fit},
                onSelectionChanged: (s) => _updateField(
                    f.copyWith(text: text.copyWith(fit: s.first))),
              ),
            ]),
            _labeledSlider('Side padding', text.padX, 0, 0.12,
                (v) => _updateField(f.copyWith(text: text.copyWith(padX: v)))),
            _labeledSlider('Vert padding', text.padY, 0, 0.12,
                (v) => _updateField(f.copyWith(text: text.copyWith(padY: v)))),
            const SizedBox(height: 8),
            Text('Colour', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Wrap(spacing: 10, runSpacing: 10, children: [
              for (final s in widget.swatches)
                _swatch(
                    s.value,
                    s.id == text.colorRef.id,
                    () => _updateField(f.copyWith(
                        text: text.copyWith(
                            colorRef: ColorRef(id: s.id, snapshot: s.value))))),
            ]),
            _labeledSlider('Opacity', text.colorAlpha, 0, 1,
                (v) => _updateField(
                    f.copyWith(text: text.copyWith(colorAlpha: v)))),
          ]),
        if (f.type == FieldType.rules)
          _section('wm', 'Watermark', [
            Row(children: [
              const SizedBox(width: 80, child: Text('Enabled')),
              Switch(
                value: f.watermark != null,
                onChanged: (on) => _updateField(f.copyWith(
                    watermark:
                        on ? const WatermarkSpec(color: _inkRef) : null)),
              ),
            ]),
            if (f.watermark != null) ...[
              Text('A symbol drawn faintly behind the rules text.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Row(children: [
                const SizedBox(width: 80, child: Text('Symbol')),
                OutlinedButton.icon(
                  onPressed: () => _pickWatermarkSymbol(f),
                  icon: const Icon(Icons.image_outlined),
                  label: Text(
                      f.watermark!.symbolId.isEmpty ? 'Choose…' : 'Change…'),
                ),
              ]),
              const SizedBox(height: 8),
              Text('Colour', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 6),
              Wrap(spacing: 10, runSpacing: 10, children: [
                for (final s in widget.swatches)
                  _swatch(
                      s.value,
                      s.id == f.watermark!.color.id,
                      () => _updateField(f.copyWith(
                          watermark: f.watermark!.copyWith(
                              color: ColorRef(id: s.id, snapshot: s.value))))),
              ]),
              _labeledSlider('Opacity', f.watermark!.alpha, 0, 1,
                  (v) => _updateField(
                      f.copyWith(watermark: f.watermark!.copyWith(alpha: v)))),
            ],
          ]),
        if (f.type == FieldType.footer)
          _section('footer', 'Footer', [
            Row(children: [
              const SizedBox(width: 80, child: Text('Enabled')),
              Switch(
                value: f.footer != null,
                onChanged: (on) => _updateField(f.copyWith(
                    footer: on ? const FooterSpec.defaults() : null)),
              ),
            ]),
            if (f.footer == null)
              Text(
                'Off: one auto line. Turn on to pick a layout and place each '
                'piece (number, set, rarity, artist, copyright).',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (f.footer != null) ..._footerControls(f, f.footer!),
          ]),
      ],
    );
  }

  /// A collapsible group in the field editor. The header (title + chevron) is
  /// always shown; [children] appear only when expanded. Expansion state lives
  /// on the body, so it persists as you move between fields.
  Widget _section(String key, String title, List<Widget> children) {
    final open = _expandedSections.contains(key);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => _toggleSection(key),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(children: [
              Icon(open ? Icons.expand_more : Icons.chevron_right, size: 20),
              const SizedBox(width: 4),
              Text(title, style: Theme.of(context).textTheme.labelLarge),
            ]),
          ),
        ),
        if (open) ...children,
        const Divider(height: 1),
      ],
    );
  }

  // ---- footer arrangement ----

  List<Widget> _footerControls(FieldSpec f, FooterSpec spec) {
    final hidden = [
      for (final c in FooterComponent.values)
        if (!spec.items.any((it) => it.component == c)) c,
    ];
    return [
      const SizedBox(height: 6),
      Row(children: [
        const SizedBox(width: 76, child: Text('Layout')),
        Expanded(
          child: SegmentedButton<FooterMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: FooterMode.singleLine, label: Text('Single')),
              ButtonSegment(value: FooterMode.leftRight, label: Text('L · R')),
              ButtonSegment(
                  value: FooterMode.fourCorners, label: Text('Corners')),
            ],
            selected: {spec.mode},
            onSelectionChanged: (s) => _setFooterMode(f, s.first),
          ),
        ),
      ]),
      const SizedBox(height: 8),
      Text('Place each piece in a zone (or hide it); arrows reorder.',
          style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 2),
      if (spec.mode == FooterMode.fourCorners)
        Text('Tip: make the footer box ~2 lines tall so corners separate.',
            style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 4),
      for (var i = 0; i < spec.items.length; i++)
        _footerRow(f, spec, spec.items[i].component, spec.items[i].zone,
            idx: i, count: spec.items.length),
      for (final c in hidden) _footerRow(f, spec, c, null),
    ];
  }

  Widget _footerRow(
      FieldSpec f, FooterSpec spec, FooterComponent c, FooterZone? zone,
      {int? idx, int? count}) {
    final visible = zone != null;
    return Row(children: [
      SizedBox(width: 76, child: Text(_footerComponentLabel(c))),
      Expanded(
        child: DropdownButton<FooterZone?>(
          isExpanded: true,
          isDense: true,
          value: zone,
          items: [
            const DropdownMenuItem<FooterZone?>(
                value: null, child: Text('Hidden')),
            for (final z in spec.zones)
              DropdownMenuItem<FooterZone?>(
                  value: z, child: Text(_footerZoneLabel(z))),
          ],
          onChanged: (z) => _setFooterZone(f, c, z),
        ),
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: '',
        icon: const Icon(Icons.keyboard_arrow_up),
        onPressed: (visible && idx != null && idx > 0)
            ? () => _moveFooterItem(f, c, -1)
            : null,
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        tooltip: '',
        icon: const Icon(Icons.keyboard_arrow_down),
        onPressed: (visible && idx != null && count != null && idx < count - 1)
            ? () => _moveFooterItem(f, c, 1)
            : null,
      ),
    ]);
  }

  void _setFooterMode(FieldSpec f, FooterMode mode) {
    final spec = f.footer ?? const FooterSpec.defaults();
    final valid = FooterSpec(mode: mode).zones.toSet();
    final fallback = FooterSpec(mode: mode).zones.first;
    // Components in zones the new mode doesn't have move to its first zone, so
    // nothing silently disappears when switching layouts.
    final items = [
      for (final it in spec.items)
        valid.contains(it.zone) ? it : it.copyWith(zone: fallback),
    ];
    _updateField(f.copyWith(footer: spec.copyWith(mode: mode, items: items)));
  }

  void _setFooterZone(FieldSpec f, FooterComponent c, FooterZone? zone) {
    final spec = f.footer!;
    final items = [...spec.items];
    final idx = items.indexWhere((it) => it.component == c);
    if (zone == null) {
      if (idx >= 0) items.removeAt(idx); // hide
    } else if (idx >= 0) {
      items[idx] = items[idx].copyWith(zone: zone); // move zones
    } else {
      items.add(FooterItem(c, zone)); // show
    }
    _updateField(f.copyWith(footer: spec.copyWith(items: items)));
  }

  void _moveFooterItem(FieldSpec f, FooterComponent c, int delta) {
    final spec = f.footer!;
    final items = [...spec.items];
    final idx = items.indexWhere((it) => it.component == c);
    final ni = idx + delta;
    if (idx < 0 || ni < 0 || ni >= items.length) return;
    final tmp = items[idx];
    items[idx] = items[ni];
    items[ni] = tmp;
    _updateField(f.copyWith(footer: spec.copyWith(items: items)));
  }

  String _footerComponentLabel(FooterComponent c) {
    switch (c) {
      case FooterComponent.number:
        return 'Number';
      case FooterComponent.set:
        return 'Set';
      case FooterComponent.rarity:
        return 'Rarity';
      case FooterComponent.artist:
        return 'Artist';
      case FooterComponent.copyright:
        return 'Copyright';
    }
  }

  String _footerZoneLabel(FooterZone z) {
    switch (z) {
      case FooterZone.line:
        return 'Line';
      case FooterZone.left:
        return 'Left';
      case FooterZone.right:
        return 'Right';
      case FooterZone.topLeft:
        return 'Top-left';
      case FooterZone.topRight:
        return 'Top-right';
      case FooterZone.bottomLeft:
        return 'Bottom-left';
      case FooterZone.bottomRight:
        return 'Bottom-right';
    }
  }
}
