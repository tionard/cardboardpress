part of 'template_editor_screen.dart';

// Reserved chrome layer ids: system layers the user can reorder and hide, but
// not delete or rename. Their *appearance* is driven by the template's dedicated
// fields (base colour, border, set-symbol placement, …) and edited in the Layout
// tab — even after promotion, the renderer pulls those from the card, not from
// the materialised chrome layer — so this pane only arranges them.
const Set<String> _kChromeLayerIds = {
  kBaseLayerId,
  kBgLayerId,
  kTintLayerId,
  kSetSymbolLayerId,
  kFoilLayerId,
  kBorderLayerId,
};

// Defaults used when an aspect is first switched on, or a new layer is created.
const ColorRef _kLayerFillDefault =
    ColorRef.literal(ColorValue.single(Color(0xFF9E9E9E)));
const ColorRef _kLayerTextDefault =
    ColorRef.literal(ColorValue.single(Color(0xFF1A1A1A)));
const ColorRef _kOutlineDefault =
    ColorRef.literal(ColorValue.single(Color(0xFF1A1A1A)));

/// The Layers pane: author the template's z-stack. It shows the effective layer
/// list, lets you add / remove / reorder / hide / rename / reposition layers,
/// and selects one for the (upcoming) per-aspect appearance editor.
///
/// PROMOTION. A template starts field-derived (`_d.layers == null`) and is drawn
/// from its fields + the arrangement overlay. The first *structural* edit here
/// materialises an explicit `_d.layers` (baking in whatever the overlay was) and
/// clears the overlay — from then on the list IS the source of truth. Promotion
/// is deliberate and one-way per session (a "Revert to fields" escape lives in
/// the Fields tab). Ids are preserved, so per-card content keeps resolving.
extension _TemplateLayersPane on _TemplateBodyState {
  bool _isChromeLayer(String id) => _kChromeLayerIds.contains(id);

  Layer? _selectedLayer(List<Layer> shown) {
    for (final l in shown) {
      if (l.id == _selectedLayerId) return l;
    }
    return null;
  }

  // ---- pane ----

  Widget _layersPane() {
    final scheme = Theme.of(context).colorScheme;
    final shown = effectiveTemplateLayers(_d);
    return _layersReordering
        ? _layersReorderView(shown, scheme)
        : _layersEditView(shown, scheme);
  }

  // Edit mode: pick a layer (chips) and edit it in a full-height panel. The
  // reorder list is tucked behind the ↕ button so aspects get the whole space.
  Widget _layersEditView(List<Layer> shown, ColorScheme scheme) {
    // Chrome (base/tint/…) is arranged in reorder mode and styled in the Layout
    // tab, so the edit chips list only the authored/field layers.
    final editable = [
      for (final l in shown)
        if (!_isChromeLayer(l.id)) l,
    ];
    final selected = _selectedLayer(shown);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Text('Layers', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              if (shown.length >= 2)
                IconButton(
                  tooltip: 'Reorder',
                  icon: const Icon(Icons.swap_vert),
                  onPressed: () => _setLayersReordering(true),
                ),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Add layer'),
                onPressed: _addGenericLayer,
              ),
            ],
          ),
        ),
        if (editable.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Add a layer to start building this template.',
                style: Theme.of(context).textTheme.bodySmall),
          )
        else
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final l in editable)
                  ChoiceChip(
                    label: Text(l.name),
                    selected: l.id == _selectedLayerId,
                    onSelected: (_) => _selectLayer(l.id),
                  ),
              ],
            ),
          ),
        const Divider(height: 1),
        Expanded(
          child: (selected == null || _isChromeLayer(selected.id))
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      editable.isEmpty
                          ? 'No editable layers yet.'
                          : 'Select a layer to edit it.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  child: _selectedLayerEditor(selected, scheme),
                ),
        ),
      ],
    );
  }

  // Reorder mode: drag the whole stack (chrome included); aspect controls are
  // hidden, mirroring the Collection's card-reorder view. 'Done' returns to edit.
  Widget _layersReorderView(List<Layer> shown, ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
          child: Row(
            children: [
              Text('Reorder layers',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              TextButton(
                onPressed: () => _setLayersReordering(false),
                child: const Text('Done'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Drag the handles to reorder — the top of the list is the back of '
            'the card, the bottom draws in front. The eye hides a layer.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            buildDefaultDragHandles: false,
            itemCount: shown.length,
            onReorderItem: (oldIndex, newIndex) =>
                _reorderLayers(oldIndex, newIndex),
            itemBuilder: (context, i) => _layerRow(shown, i, scheme),
          ),
        ),
      ],
    );
  }

  /// One reorder-mode row: drag handle · name (+ any note) · eye.
  /// Keyed by the layer id, as ReorderableListView requires.
  Widget _layerRow(List<Layer> shown, int i, ColorScheme scheme) {
    final layer = shown[i];
    final isBorder = layer.id == kBorderLayerId;
    final isChrome = _isChromeLayer(layer.id);
    final visible = layer.visible;

    final note = isBorder
        ? 'Draws outside the card edge — reordering has no visual effect yet; '
            'hiding works.'
        : isChrome
            ? 'System layer — its look is set in the Layout tab.'
            : null;

    return Container(
      key: ValueKey(layer.id),
      margin: const EdgeInsets.symmetric(vertical: 4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          ReorderableDragStartListener(
            index: i,
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.drag_handle),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    layer.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: visible
                              ? scheme.onSurface
                              : scheme.onSurfaceVariant,
                        ),
                  ),
                  if (note != null)
                    Text(
                      note,
                      style: Theme.of(context)
                          .textTheme
                          .labelSmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: visible ? 'Hide layer' : 'Show layer',
            icon: Icon(visible ? Icons.visibility : Icons.visibility_off),
            color: visible ? scheme.onSurfaceVariant : scheme.outline,
            onPressed: () => _toggleLayerVisible(layer),
          ),
        ],
      ),
    );
  }

  /// The selected layer's editor: a header row (visibility · rename · delete)
  /// plus a collapsible Position & size section and the per-aspect sections.
  /// Chrome layers only get a note (their look is the Layout tab's job).
  Widget _selectedLayerEditor(Layer layer, ColorScheme scheme) {
    final isChrome = _isChromeLayer(layer.id);
    final visible = layer.visible;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(layer.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall),
            ),
            IconButton(
              tooltip: visible ? 'Hide layer' : 'Show layer',
              icon: Icon(visible ? Icons.visibility : Icons.visibility_off),
              onPressed: () => _toggleLayerVisible(layer),
            ),
            if (!isChrome)
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _renameLayer(layer),
              ),
            if (!isChrome)
              IconButton(
                tooltip: 'Remove layer',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => _removeLayer(layer.id),
              ),
          ],
        ),
        const SizedBox(height: 4),
        if (isChrome)
          Text(
            'This is a system layer. Reorder or hide it here; its appearance is '
            'controlled in the Layout tab.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          )
        else ...[
          _exposeControl(layer.id, ExposedAspect.visible, layer.exposed),
          const SizedBox(height: 8),
          _section('l_geo', 'Position & size', [
            _labeledSlider('Left', layer.frac.left, 0, 1,
                (v) => _setLayerFrac(layer, l: v),
                step: 0.01),
            _labeledSlider(
                'Top', layer.frac.top, 0, 1, (v) => _setLayerFrac(layer, t: v),
                step: 0.01),
            _labeledSlider('Right', layer.frac.right, 0, 1,
                (v) => _setLayerFrac(layer, r: v),
                step: 0.01),
            _labeledSlider('Bottom', layer.frac.bottom, 0, 1,
                (v) => _setLayerFrac(layer, b: v),
                step: 0.01),
            const SizedBox(height: 8),
            _labeledSlider('Corner', layer.cornerRadius, 0, 0.1,
                (v) => _setLayerCorner(layer, v)),
          ]),
          ..._layerAspectSections(layer),
        ],
      ],
    );
  }

  // ---- per-aspect appearance ----
  //
  // A layer starts with just geometry; aspects are added on demand from the
  // "+ Add aspect" menu, and each present aspect has a Remove. Fill/Image/
  // Outline/Text also carry the per-aspect "Editing" control (template vs a
  // card-editor tab). Foil/Border have no per-card exposure (yet).

  List<Widget> _layerAspectSections(Layer layer) {
    final id = layer.id;
    final fill = layer.fill;
    final image = layer.image;
    final border = layer.border;
    final outline = layer.outline;
    final foil = layer.foil;
    final text = layer.text;
    return [
      if (fill != null)
        _section('l_fill', 'Fill', [
          Text('Colour', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          _colorWell(
            current: fill.color,
            use: SwatchUse.card,
            onPicked: (r) => _updateLayer(
                id,
                (l) => l.copyWith(
                    fill: (l.fill ?? const FillAspect(color: _kLayerFillDefault))
                        .copyWith(color: r))),
          ),
          _labeledSlider('Opacity', fill.alpha, 0, 1,
              (v) => _updateLayer(id,
                  (l) => l.copyWith(fill: l.fill?.copyWith(alpha: v)))),
          _exposeControl(id, ExposedAspect.fill, layer.exposed),
          _removeAspectRow(
              () => _updateLayer(id, (l) => l.copyWith(fill: null))),
        ]),
      if (image != null)
        _section('l_image', 'Image', [
          Row(children: [
            const SizedBox(width: 80, child: Text('Source')),
            Expanded(
              child: SegmentedButton<ImageSource>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: ImageSource.fixed, label: Text('Picture')),
                  ButtonSegment(
                      value: ImageSource.setSymbol, label: Text('Set symbol')),
                ],
                selected: {image.source},
                onSelectionChanged: (s) => _updateLayer(id,
                    (l) => l.copyWith(image: l.image?.copyWith(source: s.first))),
              ),
            ),
          ]),
          if (image.source == ImageSource.fixed)
            Row(children: [
              const SizedBox(width: 80, child: Text('Picture')),
              OutlinedButton.icon(
                onPressed: () => _pickLayerImage(layer),
                icon: const Icon(Icons.image_outlined),
                label: Text(image.imageId.isEmpty ? 'Choose…' : 'Change…'),
              ),
            ])
          else
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  "Uses the card's set symbol, tinted by the rarity colour.",
                  style: Theme.of(context).textTheme.bodySmall),
            ),
          const SizedBox(height: 8),
          if (image.source == ImageSource.fixed) ...[
            Text('Tint (silhouette)',
                style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            _colorWell(
              current: image.tint,
              use: SwatchUse.card,
              onPicked: (r) => _updateLayer(
                  id, (l) => l.copyWith(image: l.image?.copyWith(tint: r))),
              onClear: () => _updateLayer(
                  id, (l) => l.copyWith(image: l.image?.copyWith(tint: null))),
            ),
          ],
          _labeledSlider('Opacity', image.alpha, 0, 1,
              (v) => _updateLayer(id,
                  (l) => l.copyWith(image: l.image?.copyWith(alpha: v)))),
          _exposeControl(id, ExposedAspect.image, layer.exposed),
          _removeAspectRow(
              () => _updateLayer(id, (l) => l.copyWith(image: null))),
        ]),
      if (border != null)
        _section('l_border', 'Border (9-slice)', [
          Text('A sprite frame. While on, it replaces the flat fill.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          Row(children: [
            const SizedBox(width: 80, child: Text('Sprite')),
            OutlinedButton.icon(
              onPressed: () => _pickLayerBorder(layer),
              icon: const Icon(Icons.image_outlined),
              label: Text(border.hasImage ? 'Change…' : 'Choose…'),
            ),
          ]),
          if (border.hasImage) ...[
            _labeledSlider('Slice', border.slice, 0, 0.49,
                (v) => _updateLayer(id,
                    (l) => l.copyWith(border: l.border?.copyWith(slice: v)))),
            _labeledSlider('Corner', border.inset, 0, 0.2,
                (v) => _updateLayer(id,
                    (l) => l.copyWith(border: l.border?.copyWith(inset: v)))),
            _aspectToggle(
                'Fill center',
                border.drawCenter,
                (v) => _updateLayer(id,
                    (l) => l.copyWith(border: l.border?.copyWith(drawCenter: v)))),
            const SizedBox(height: 8),
            Text('Tint', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            _colorWell(
              current: border.tint,
              use: SwatchUse.card,
              onPicked: (r) => _updateLayer(
                  id, (l) => l.copyWith(border: l.border?.copyWith(tint: r))),
              onClear: () => _updateLayer(
                  id, (l) => l.copyWith(border: l.border?.copyWith(tint: null))),
            ),
          ],
          _removeAspectRow(
              () => _updateLayer(id, (l) => l.copyWith(border: null))),
        ]),
      if (outline != null)
        _section('l_outline', 'Outline', [
          Text('Colour', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 6),
          _colorWell(
            current: outline.color,
            use: SwatchUse.card,
            onPicked: (r) => _updateLayer(
                id, (l) => l.copyWith(outline: l.outline?.copyWith(color: r))),
          ),
          _labeledSlider(
              'Thickness',
              outline.thickness,
              0,
              0.02,
              (v) => _updateLayer(id,
                  (l) => l.copyWith(outline: l.outline?.copyWith(thickness: v)))),
          if (outline.color == null && fill == null)
            Text('This outline shades the fill — pick a colour, or add a Fill.',
                style: Theme.of(context).textTheme.bodySmall),
          _exposeControl(id, ExposedAspect.outlineColor, layer.exposed),
          _removeAspectRow(
              () => _updateLayer(id, (l) => l.copyWith(outline: null))),
        ]),
      if (foil != null)
        _section('l_foil', 'Foil', [
          Row(children: [
            const SizedBox(width: 80, child: Text('Style')),
            Expanded(
              child: SegmentedButton<FoilType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: FoilType.none, label: Text('None')),
                  ButtonSegment(value: FoilType.holo, label: Text('Holo')),
                  ButtonSegment(value: FoilType.gold, label: Text('Gold')),
                ],
                selected: {foil},
                onSelectionChanged: (s) =>
                    _updateLayer(id, (l) => l.copyWith(foil: s.first)),
              ),
            ),
          ]),
          _exposeControl(id, ExposedAspect.foil, layer.exposed),
          _removeAspectRow(
              () => _updateLayer(id, (l) => l.copyWith(foil: null))),
        ]),
      if (text != null)
        _section('l_text', 'Text', [
          ..._textAspectControls(layer, text),
          _removeAspectRow(
              () => _updateLayer(id, (l) => l.copyWith(text: null))),
        ]),
      const SizedBox(height: 8),
      _addAspectMenu(layer),
    ];
  }

  /// A right-aligned "Remove" button ending an aspect section.
  Widget _removeAspectRow(VoidCallback onRemove) => Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: onRemove,
          icon: const Icon(Icons.close, size: 16),
          label: const Text('Remove'),
        ),
      );

  /// "+ Add aspect" — lists only the aspects this layer doesn't have yet.
  Widget _addAspectMenu(Layer layer) {
    final absent = <String, String>{
      if (layer.fill == null) 'fill': 'Fill',
      if (layer.image == null) 'image': 'Image',
      if (layer.border == null) 'border': 'Border (9-slice)',
      if (layer.outline == null) 'outline': 'Outline',
      if (layer.foil == null) 'foil': 'Foil',
      if (layer.text == null) 'text': 'Text',
    };
    if (absent.isEmpty) {
      return Text('All aspects added.',
          style: Theme.of(context).textTheme.bodySmall);
    }
    return Align(
      alignment: Alignment.centerLeft,
      child: PopupMenuButton<String>(
        onSelected: (a) => _addAspect(layer, a),
        itemBuilder: (ctx) => [
          for (final e in absent.entries)
            PopupMenuItem(value: e.key, child: Text(e.value)),
        ],
        child: const Chip(
          avatar: Icon(Icons.add, size: 18),
          label: Text('Add aspect'),
        ),
      ),
    );
  }

  void _addAspect(Layer layer, String a) {
    _updateLayer(
        layer.id,
        (l) => switch (a) {
              'fill' =>
                l.copyWith(fill: const FillAspect(color: _kLayerFillDefault)),
              'image' => l.copyWith(image: const ImageAspect()),
              'border' => l.copyWith(border: const NineSliceSpec()),
              'outline' =>
                l.copyWith(outline: const OutlineSpec(color: _kOutlineDefault)),
              'foil' => l.copyWith(foil: FoilType.holo),
              'text' => l.copyWith(text: _defaultTextAspect()),
              _ => l,
            });
  }

  List<Widget> _textAspectControls(Layer layer, TextAspect text) {
    final id = layer.id;
    final s = text.style;
    final placeholder = text.placeholder;
    final partsSummary = text.parts.isEmpty
        ? 'Free text (typed on the card)'
        : text.parts.map(_textSourceLabel).join(' ${text.separator} ');
    return [
      Row(children: [
        const SizedBox(width: 80, child: Text('Sources')),
        Expanded(
          child: Text(partsSummary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        ),
        TextButton(
            onPressed: () => _editTextParts(layer), child: const Text('Edit…')),
      ]),
      Row(children: [
        const SizedBox(width: 80, child: Text('Placeholder')),
        Expanded(
          child: Text(placeholder.isEmpty ? '(none)' : placeholder,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        ),
        TextButton(
            onPressed: () => _editLayerPlaceholder(layer),
            child: const Text('Edit…')),
      ]),
      Row(children: [
        const SizedBox(width: 80, child: Text('Multiline')),
        Switch(
          value: text.multiline,
          onChanged: (v) => _updateLayer(
              id, (l) => l.copyWith(text: l.text?.copyWith(multiline: v))),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Wrap to multiple lines (and a multi-line card field).',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]),
      Row(children: [
        const SizedBox(width: 80, child: Text('Markup')),
        Switch(
          value: text.inline,
          onChanged: (v) => _updateLayer(
              id, (l) => l.copyWith(text: l.text?.copyWith(inline: v))),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Parse {symbols} and **bold** / *italic*.',
              style: Theme.of(context).textTheme.bodySmall),
        ),
      ]),
      _labeledSlider(
          'Size',
          s.sizeFrac,
          0.01,
          0.12,
          (v) => _updateLayer(id,
              (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(sizeFrac: v))))),
      Row(children: [
        const SizedBox(width: 80, child: Text('Bold')),
        Switch(
          value: s.bold,
          onChanged: (v) => _updateLayer(id,
              (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(bold: v)))),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SegmentedButton<TextAlign>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                  value: TextAlign.left, icon: Icon(Icons.format_align_left)),
              ButtonSegment(
                  value: TextAlign.center, icon: Icon(Icons.format_align_center)),
              ButtonSegment(
                  value: TextAlign.right, icon: Icon(Icons.format_align_right)),
            ],
            selected: {s.align},
            onSelectionChanged: (a) => _updateLayer(id,
                (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(align: a.first)))),
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
                value: VAlign.middle, icon: Icon(Icons.vertical_align_center)),
            ButtonSegment(
                value: VAlign.bottom, icon: Icon(Icons.vertical_align_bottom)),
          ],
          selected: {s.vAlign},
          onSelectionChanged: (a) => _updateLayer(id,
              (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(vAlign: a.first)))),
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
          selected: {s.fit},
          onSelectionChanged: (a) => _updateLayer(id,
              (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(fit: a.first)))),
        ),
      ]),
      _labeledSlider(
          'Side padding',
          s.padX,
          0,
          0.12,
          (v) => _updateLayer(id,
              (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(padX: v))))),
      _labeledSlider(
          'Vert padding',
          s.padY,
          0,
          0.12,
          (v) => _updateLayer(id,
              (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(padY: v))))),
      const SizedBox(height: 8),
      Text('Colour', style: Theme.of(context).textTheme.bodySmall),
      const SizedBox(height: 6),
      _colorWell(
        current: s.colorRef,
        use: SwatchUse.text,
        onPicked: (r) => _updateLayer(id,
            (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(colorRef: r)))),
      ),
      _labeledSlider(
          'Opacity',
          s.colorAlpha,
          0,
          1,
          (v) => _updateLayer(id,
              (l) => l.copyWith(text: l.text?.copyWith(style: s.copyWith(colorAlpha: v))))),
      _exposeControl(id, ExposedAspect.text, layer.exposed),
    ];
  }

  Widget _aspectToggle(String label, bool value, ValueChanged<bool> onChanged) =>
      Row(children: [
        SizedBox(width: 80, child: Text(label)),
        Switch(value: value, onChanged: onChanged),
      ]);

  // ---- exposure routing (Phase 4 tail) ----
  //
  // Each aspect can be "exposed" to one Card-Editor tab, meaning the card gets a
  // per-card control for it (wired up in Phase 5). Empty = template-only.

  static String _tabLabel(EditorTab t) => switch (t) {
        EditorTab.card => 'Card',
        EditorTab.art => 'Art',
        EditorTab.color => 'Colour',
        EditorTab.set => 'Set',
        EditorTab.export => 'Export',
      };

  Widget _exposeControl(
      String layerId, ExposedAspect aspect, Map<ExposedAspect, EditorTab> exposed) {
    final current = exposed[aspect]; // null = template-only
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          const SizedBox(width: 80, child: Text('Editing')),
          Expanded(
            child: DropdownButton<EditorTab?>(
              isExpanded: true,
              value: current,
              items: [
                const DropdownMenuItem<EditorTab?>(
                    value: null, child: Text('In template')),
                for (final t in EditorTab.values)
                  DropdownMenuItem<EditorTab?>(
                      value: t, child: Text('Card · ${_tabLabel(t)} tab')),
              ],
              onChanged: (t) => _setExposed(layerId, aspect, t),
            ),
          ),
        ],
      ),
    );
  }

  void _setExposed(String layerId, ExposedAspect aspect, EditorTab? tab) {
    _updateLayer(layerId, (l) {
      final m = Map<ExposedAspect, EditorTab>.from(l.exposed);
      if (tab == null) {
        m.remove(aspect);
      } else {
        m[aspect] = tab;
      }
      return l.copyWith(exposed: m);
    });
  }

  TextAspect _defaultTextAspect() => const TextAspect(
        style: TextStyleSpec(
            sizeFrac: 0.04, vAlign: VAlign.middle, colorRef: _kLayerTextDefault),
      );

  /// Two-list picker: available sources (chips, tap to add) + the chosen,
  /// reorderable list, plus a Separator field. Duplicates aren't allowed, so
  /// chosen entries key cleanly by value for the reorderable list.
  Future<void> _editTextParts(Layer layer) async {
    final chosen = List<TextSource>.from(layer.text?.parts ?? const []);
    final sepCtl = TextEditingController(text: layer.text?.separator ?? '·');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final available = [
            for (final src in TextSource.values)
              if (!chosen.contains(src)) src,
          ];
          return AlertDialog(
            title: const Text('Text sources'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    const SizedBox(width: 90, child: Text('Separator')),
                    Expanded(
                      child: TextField(
                        controller: sepCtl,
                        decoration: const InputDecoration(
                            isDense: true, hintText: '· (leave blank for none)'),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Text('Available', style: Theme.of(ctx).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      if (available.isEmpty)
                        Text('All sources added',
                            style: Theme.of(ctx).textTheme.bodySmall),
                      for (final src in available)
                        ActionChip(
                          avatar: const Icon(Icons.add, size: 16),
                          label: Text(_textSourceLabel(src)),
                          onPressed: () => setLocal(() => chosen.add(src)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text('In this text (drag to reorder)',
                      style: Theme.of(ctx).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 200,
                    child: chosen.isEmpty
                        ? Center(
                            child: Text('Empty = free text (typed on the card)',
                                style: Theme.of(ctx).textTheme.bodySmall))
                        : ReorderableListView.builder(
                            itemCount: chosen.length,
                            onReorderItem: (o, n) => setLocal(() {
                              if (n > o) n -= 1;
                              final m = chosen.removeAt(o);
                              chosen.insert(n.clamp(0, chosen.length), m);
                            }),
                            itemBuilder: (c, i) => ListTile(
                              key: ValueKey(chosen[i]),
                              dense: true,
                              leading: const Icon(Icons.drag_handle),
                              title: Text(_textSourceLabel(chosen[i])),
                              trailing: IconButton(
                                icon: const Icon(Icons.close, size: 18),
                                onPressed: () =>
                                    setLocal(() => chosen.removeAt(i)),
                              ),
                            ),
                          ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save')),
            ],
          );
        },
      ),
    );
    final sep = sepCtl.text;
    sepCtl.dispose();
    if (saved != true) return;
    _updateLayer(
        layer.id,
        (l) => l.copyWith(
            text: l.text?.copyWith(parts: chosen, separator: sep)));
  }

  Future<void> _editLayerPlaceholder(Layer layer) async {
    final ctl = TextEditingController(text: layer.text?.placeholder ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Placeholder text'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Placeholder',
            hintText: 'Dummy text shown only in the template preview',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text),
              child: const Text('Save')),
        ],
      ),
    );
    ctl.dispose();
    if (value == null) return;
    _updateLayer(layer.id,
        (l) => l.copyWith(text: l.text?.copyWith(placeholder: value)));
  }

  static String _textSourceLabel(TextSource s) => switch (s) {
        TextSource.cardName => 'Card name',
        TextSource.setName => 'Set name',
        TextSource.setAbbrev => 'Set abbreviation',
        TextSource.collectorNumber => 'Collector number',
        TextSource.rarityName => 'Rarity name',
        TextSource.rarityAbbrev => 'Rarity abbreviation',
        TextSource.artist => 'Artist',
        TextSource.copyright => 'Copyright',
      };

  /// Pick a fixed picture for the layer's image aspect (resets its zoom/pan).
  Future<void> _pickLayerImage(Layer layer) async {
    final imageId = await _pickAndStoreImage();
    if (imageId == null) return;
    _updateLayer(
        layer.id,
        (l) => l.copyWith(
            image: (l.image ?? const ImageAspect()).copyWith(
                source: ImageSource.fixed,
                imageId: imageId,
                transform: const ArtTransform())));
  }

  /// Pick the 9-slice sprite for the layer's border aspect.
  Future<void> _pickLayerBorder(Layer layer) async {
    final imageId = await _pickAndStoreImage();
    if (imageId == null) return;
    _updateLayer(
        layer.id,
        (l) => l.copyWith(
            border: (l.border ?? const NineSliceSpec()).copyWith(imageId: imageId)));
  }

  // ---- mutations (all promote-on-edit) ----

  /// Edit the layer list, promoting the template on first touch: read the
  /// effective list (baking any arrangement overlay into it), apply [edit], and
  /// store it as the explicit `_d.layers`, clearing the now-superseded overlay.
  void _editLayers(List<Layer> Function(List<Layer>) edit) {
    final current = effectiveTemplateLayers(_d);
    final next = edit([...current]);
    _update(_d.copyWith(
      layers: next,
      layerOrder: const [],
      hiddenLayers: const [],
    ));
  }

  /// Replace one layer (by id) with [f] applied to it — the workhorse behind the
  /// per-layer controls. Promotes on first edit like everything here.
  void _updateLayer(String id, Layer Function(Layer) f) => _editLayers((ls) => [
        for (final l in ls) l.id == id ? f(l) : l,
      ]);

  /// Reorder within the explicit list. `newIndex` is an insertion point that's
  /// off by one when moving an item downward (same as the Collection list).
  void _reorderLayers(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    _editLayers((ls) {
      if (oldIndex < 0 || oldIndex >= ls.length) return ls;
      final moved = ls.removeAt(oldIndex);
      ls.insert(newIndex.clamp(0, ls.length), moved);
      return ls;
    });
  }

  void _toggleLayerVisible(Layer layer) =>
      _updateLayer(layer.id, (l) => l.copyWith(visible: !l.visible));

  /// Add a new generic layer on top of the stack, with a neutral fill so it's
  /// visible immediately, and select it. Appended = top of the z-order = the
  /// last (bottom) row of the list.
  void _addGenericLayer() {
    final count = effectiveTemplateLayers(_d)
        .where((l) => !_isChromeLayer(l.id) && l.kind == LayerKind.generic)
        .length;
    final id = 'l_${DateTime.now().microsecondsSinceEpoch}';
    // Starts with geometry only — appearance is added from "+ Add aspect".
    final layer = Layer(
      id: id,
      name: 'Layer ${count + 1}',
      frac: const Rect.fromLTRB(0.3, 0.4, 0.7, 0.6),
    );
    _editLayers((ls) => [...ls, layer]);
    _selectLayer(id);
  }

  void _removeLayer(String id) {
    if (_isChromeLayer(id)) return; // system layers stay
    _editLayers((ls) => [
          for (final l in ls)
            if (l.id != id) l,
        ]);
    if (_selectedLayerId == id) _selectLayer(null);
  }

  Future<void> _renameLayer(Layer layer) async {
    final ctl = TextEditingController(text: layer.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename layer'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Name'),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, ctl.text.trim()),
              child: const Text('Rename')),
        ],
      ),
    );
    ctl.dispose();
    if (name == null || name.isEmpty) return;
    _updateLayer(layer.id, (l) => l.copyWith(name: name));
  }

  void _setLayerFrac(Layer layer, {double? l, double? t, double? r, double? b}) {
    const min = 0.03;
    var left = l ?? layer.frac.left;
    var top = t ?? layer.frac.top;
    var right = r ?? layer.frac.right;
    var bottom = b ?? layer.frac.bottom;
    if (l != null) left = left.clamp(0.0, right - min);
    if (r != null) right = right.clamp(left + min, 1.0);
    if (t != null) top = top.clamp(0.0, bottom - min);
    if (b != null) bottom = bottom.clamp(top + min, 1.0);
    final nf = Rect.fromLTRB(left, top, right, bottom);
    _updateLayer(layer.id, (l) => l.copyWith(frac: nf));
  }

  void _setLayerCorner(Layer layer, double v) =>
      _updateLayer(layer.id, (l) => l.copyWith(cornerRadius: v));
}
