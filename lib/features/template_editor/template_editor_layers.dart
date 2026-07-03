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
    // Effective list: the explicit `_d.layers` once promoted, else the derived
    // layers with the overlay applied. Index 0 is the BOTTOM of the stack (drawn
    // first); the last row draws on top — so the top of the list is the back of
    // the card.
    final shown = effectiveTemplateLayers(_d);
    final selected = _selectedLayer(shown);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(
            children: [
              Text('Layers', style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              ActionChip(
                avatar: const Icon(Icons.add, size: 18),
                label: const Text('Add layer'),
                onPressed: _addGenericLayer,
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text(
            'Drag to reorder the draw stack — the top of the list is the back '
            'of the card, the bottom draws in front. Tap a layer to edit it; '
            'the eye hides it without deleting it.',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          flex: selected == null ? 1 : 3,
          child: ReorderableListView.builder(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
            buildDefaultDragHandles: false,
            itemCount: shown.length,
            onReorderItem: (oldIndex, newIndex) =>
                _reorderLayers(oldIndex, newIndex),
            itemBuilder: (context, i) => _layerRow(shown, i, scheme),
          ),
        ),
        if (selected != null) ...[
          const Divider(height: 1),
          Expanded(
            flex: 4,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              child: _selectedLayerEditor(selected, scheme),
            ),
          ),
        ],
      ],
    );
  }

  /// One row: drag handle · name (+ any note, tap to select) · eye · delete.
  /// Keyed by the layer id, as ReorderableListView requires.
  Widget _layerRow(List<Layer> shown, int i, ColorScheme scheme) {
    final layer = shown[i];
    final isBorder = layer.id == kBorderLayerId;
    final isChrome = _isChromeLayer(layer.id);
    final selected = layer.id == _selectedLayerId;
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
        color: selected
            ? scheme.secondaryContainer
            : scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: selected ? Border.all(color: scheme.primary) : null,
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
            child: InkWell(
              onTap: () => _selectLayer(selected ? null : layer.id),
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
          ),
          IconButton(
            tooltip: visible ? 'Hide layer' : 'Show layer',
            icon: Icon(visible ? Icons.visibility : Icons.visibility_off),
            color: visible ? scheme.onSurfaceVariant : scheme.outline,
            onPressed: () => _toggleLayerVisible(layer),
          ),
          if (!isChrome)
            IconButton(
              tooltip: 'Remove layer',
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _removeLayer(layer.id),
            ),
        ],
      ),
    );
  }

  /// The selected layer's editor. Chrome layers only get a note (their look is
  /// the Layout tab's job); other layers get rename + geometry. The per-aspect
  /// appearance controls (fill / image / border / outline / foil / text) land in
  /// the next drop.
  Widget _selectedLayerEditor(Layer layer, ColorScheme scheme) {
    final isChrome = _isChromeLayer(layer.id);
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
            if (!isChrome)
              IconButton(
                tooltip: 'Rename',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => _renameLayer(layer),
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
          Text('Position & size',
              style: Theme.of(context).textTheme.labelLarge),
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
          const SizedBox(height: 12),
          ..._layerAspectSections(layer),
        ],
      ],
    );
  }

  // ---- per-aspect appearance (C2a: fill / outline / foil / text) ----

  List<Widget> _layerAspectSections(Layer layer) {
    final id = layer.id;
    final fill = layer.fill;
    final image = layer.image;
    final border = layer.border;
    final outline = layer.outline;
    final text = layer.text;
    return [
      _section('l_fill', 'Fill', [
        _aspectToggle(
            'Enabled',
            fill != null,
            (on) => _updateLayer(
                id,
                (l) => l.copyWith(
                    fill: on
                        ? const FillAspect(color: _kLayerFillDefault)
                        : null))),
        if (fill != null) ...[
          const SizedBox(height: 8),
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
        ],
      ]),
      _section('l_image', 'Image', [
        _aspectToggle(
            'Enabled',
            image != null,
            (on) => _updateLayer(id,
                (l) => l.copyWith(image: on ? const ImageAspect() : null))),
        if (image != null) ...[
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
        ],
      ]),
      _section('l_border', 'Border (9-slice)', [
        _aspectToggle(
            'Enabled',
            border != null,
            (on) => _updateLayer(id,
                (l) => l.copyWith(border: on ? const NineSliceSpec() : null))),
        if (border != null) ...[
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
        ],
      ]),
      _section('l_outline', 'Outline', [
        _aspectToggle(
            'Enabled',
            outline != null,
            (on) => _updateLayer(id,
                (l) => l.copyWith(outline: on ? const OutlineSpec() : null))),
        if (outline != null) ...[
          _labeledSlider(
              'Intensity',
              outline.intensity,
              0,
              1,
              (v) => _updateLayer(id,
                  (l) => l.copyWith(outline: l.outline?.copyWith(intensity: v)))),
          _aspectToggle(
              'Lighter',
              outline.lighter,
              (v) => _updateLayer(id,
                  (l) => l.copyWith(outline: l.outline?.copyWith(lighter: v)))),
          if (fill == null)
            Text('Outline shades the fill — add a Fill for it to show.',
                style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
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
              selected: {layer.foil},
              onSelectionChanged: (s) =>
                  _updateLayer(id, (l) => l.copyWith(foil: s.first)),
            ),
          ),
        ]),
      ]),
      _section('l_text', 'Text', [
        _aspectToggle(
            'Enabled',
            text != null,
            (on) => _updateLayer(id,
                (l) => l.copyWith(text: on ? _defaultTextAspect() : null))),
        if (text != null) ..._textAspectControls(layer, text),
      ]),
    ];
  }

  List<Widget> _textAspectControls(Layer layer, TextAspect text) {
    final id = layer.id;
    final s = text.style;
    final literal = text.literal ?? '';
    return [
      Row(children: [
        const SizedBox(width: 80, child: Text('Content')),
        Expanded(
          child: Text(literal.isEmpty ? '(empty)' : literal,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall),
        ),
        TextButton(
            onPressed: () => _editLayerText(layer), child: const Text('Edit…')),
      ]),
      Row(children: [
        const SizedBox(width: 80, child: Text('Inline')),
        Switch(
          value: text.inline,
          onChanged: (v) => _updateLayer(
              id, (l) => l.copyWith(text: l.text?.copyWith(inline: v))),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Parse {symbols} and **bold**; single line.',
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
    ];
  }

  Widget _aspectToggle(String label, bool value, ValueChanged<bool> onChanged) =>
      Row(children: [
        SizedBox(width: 80, child: Text(label)),
        Switch(value: value, onChanged: onChanged),
      ]);

  TextAspect _defaultTextAspect() => const TextAspect(
        style: TextStyleSpec(
            sizeFrac: 0.04, vAlign: VAlign.middle, colorRef: _kLayerTextDefault),
        literal: '',
      );

  Future<void> _editLayerText(Layer layer) async {
    final ctl = TextEditingController(text: layer.text?.literal ?? '');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Layer text'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          minLines: 1,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Text',
            hintText: 'Fixed text drawn on this layer',
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
    if (value == null) return; // cancelled
    _updateLayer(
        layer.id, (l) => l.copyWith(text: l.text?.copyWith(literal: value)));
  }

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
    final layer = Layer(
      id: id,
      name: 'Layer ${count + 1}',
      frac: const Rect.fromLTRB(0.3, 0.4, 0.7, 0.6),
      fill: const FillAspect(color: _kLayerFillDefault),
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
