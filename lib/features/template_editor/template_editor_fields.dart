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
        Text('Position', style: Theme.of(context).textTheme.labelLarge),
        _labeledSlider('Left', f.frac.left, 0, 1, (v) => _setFrac(f, l: v),
            step: 0.01),
        _labeledSlider('Top', f.frac.top, 0, 1, (v) => _setFrac(f, t: v),
            step: 0.01),
        _labeledSlider('Right', f.frac.right, 0, 1, (v) => _setFrac(f, r: v),
            step: 0.01),
        _labeledSlider('Bottom', f.frac.bottom, 0, 1, (v) => _setFrac(f, b: v),
            step: 0.01),
        const SizedBox(height: 8),
        _labeledSlider('Corner', f.cornerRadius, 0, 0.1,
            (v) => _updateField(f.copyWith(cornerRadius: v))),
        const SizedBox(height: 12),
        Text('Fill', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 6),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _noneTile(f.fill == null, () => _updateField(f.copyWith(fill: null))),
          for (final s in widget.swatches)
            _swatch(s.value, s.id == f.fill?.id,
                () => _updateField(
                    f.copyWith(fill: ColorRef(id: s.id, snapshot: s.value)))),
        ]),
        if (f.fill != null)
          _labeledSlider('Opacity', f.fillAlpha, 0, 1,
              (v) => _updateField(f.copyWith(fillAlpha: v))),
        const SizedBox(height: 12),
        Row(children: [
          Text('Outline', style: Theme.of(context).textTheme.labelLarge),
          const Spacer(),
          Switch(
            value: outline != null,
            onChanged: (on) => _updateField(
                f.copyWith(outline: on ? const OutlineSpec() : null)),
          ),
        ]),
        if (outline != null) ...[
          _labeledSlider('Intensity', outline.intensity, 0, 1,
              (v) => _updateField(f.copyWith(outline: outline.copyWith(intensity: v)))),
          Row(children: [
            const SizedBox(width: 80, child: Text('Lighter')),
            Switch(
              value: outline.lighter,
              onChanged: (v) => _updateField(
                  f.copyWith(outline: outline.copyWith(lighter: v))),
            ),
          ]),
        ],
        if (text != null) ...[
          const SizedBox(height: 12),
          Text('Text', style: Theme.of(context).textTheme.labelLarge),
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
            SegmentedButton<TextAlign>(
              segments: const [
                ButtonSegment(value: TextAlign.left, icon: Icon(Icons.format_align_left)),
                ButtonSegment(value: TextAlign.center, icon: Icon(Icons.format_align_center)),
                ButtonSegment(value: TextAlign.right, icon: Icon(Icons.format_align_right)),
              ],
              selected: {text.align},
              onSelectionChanged: (s) => _updateField(
                f.copyWith(text: text.copyWith(align: s.first))),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            const SizedBox(width: 80, child: Text('Anchor')),
            SegmentedButton<VAlign>(
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
          Text('Text colour', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final s in widget.swatches)
              _swatch(s.value, s.id == text.colorRef.id,
                  () => _updateField(f.copyWith(
                      text: text.copyWith(
                          colorRef: ColorRef(id: s.id, snapshot: s.value))))),
          ]),
          _labeledSlider('Opacity', text.colorAlpha, 0, 1,
              (v) => _updateField(
                  f.copyWith(text: text.copyWith(colorAlpha: v)))),
        ],
        if (f.type == FieldType.rules) ...[
          const SizedBox(height: 12),
          Row(children: [
            Text('Watermark', style: Theme.of(context).textTheme.labelLarge),
            const Spacer(),
            Switch(
              value: f.watermark != null,
              onChanged: (on) => _updateField(f.copyWith(
                  watermark: on ? const WatermarkSpec(color: _inkRef) : null)),
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
                _swatch(s.value, s.id == f.watermark!.color.id,
                    () => _updateField(f.copyWith(
                        watermark: f.watermark!.copyWith(
                            color: ColorRef(id: s.id, snapshot: s.value))))),
            ]),
            _labeledSlider('Opacity', f.watermark!.alpha, 0, 1,
                (v) => _updateField(
                    f.copyWith(watermark: f.watermark!.copyWith(alpha: v)))),
          ],
        ],
      ],
    );
  }
}
