// lib/features/template_editor/template_editor_layers.dart
//
// The Layers pane CORE: pane views (edit + reorder), the layer row and
// selected-layer editor, exposure routing, and — most importantly — the
// mutation engine. `_editLayers` is the single choke point every layer
// mutation flows through (it promotes a derived template to a materialised
// one and pins Base to the bottom). Per-aspect section builders live in
// template_editor_layer_aspects.dart; dialogs and pickers in
// template_editor_layer_dialogs.dart — all parts of the same library, all
// extensions on _TemplateBodyState.

part of 'template_editor_screen.dart';

// The only system layers left. BASE is the card's ground: always the bottom
// of the stack (pinned, not draggable) and styled from the Layout tab (colour,
// corner), so it isn't edited here. BORDER draws outside the rounded clip and
// is styled in the Layout tab. Everything else — background, tint, set-symbol,
// foil, and every authored layer — is a plain generic layer.
const Set<String> _kChromeLayerIds = {
  kBaseLayerId,
  kBorderLayerId,
};

/// The Layers pane: author the template's z-stack. It shows the effective layer
/// list, lets you add / remove / reorder / hide / rename / reposition layers,
/// and selects one for the (upcoming) per-aspect appearance editor.
///
/// PROMOTION. A legacy template starts derived (`_d.layers == null`) and is
/// drawn from its retired fields + the arrangement overlay. The first edit here
/// materialises an explicit `_d.layers` (baking in whatever the overlay was) and
/// clears the overlay — from then on the list IS the source of truth. One-way:
/// the fields editor is gone. Ids are preserved, so per-card content resolves.
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

  /// Reorder is only meaningful with 2+ layers in the stack (chrome included) —
  /// mirrors the old header row's `shown.length >= 2` guard, but callable from
  /// the mode-switch row in the parent build without threading `shown` through.
  bool get _hasReorderableLayers => effectiveTemplateLayers(_d).length >= 2;

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
        // No header row here anymore — the "Layers" label is redundant with the
        // active segment above, and its reorder / add-layer actions moved onto
        // the mode-switch row to reclaim this band for the aspect controls.
        const SizedBox(height: 8),
        if (editable.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text('Add a layer to start building this template.',
                style: Theme.of(context).textTheme.bodySmall),
          )
        else
          // Single-row horizontal strip instead of a multi-row Wrap: the chip
          // list stays one row tall no matter how many layers a template has,
          // leaving the space below for the actual aspect controls. The
          // selected chip auto-scrolls into view (_selectLayer), and edge fades
          // signal there's more to scroll to.
          _layerChipStrip(editable),
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

  /// The one-row, horizontally scrolling layer picker. Each chip carries a
  /// GlobalKey (kept in _layerChipKeys) so _scrollChipIntoView can centre the
  /// selected one. A ShaderMask paints symmetric edge fades so partially
  /// scrolled chips read as "more over here" rather than "clipped".
  Widget _layerChipStrip(List<Layer> editable) {
    // Prune keys for layers that no longer exist so the map can't grow forever.
    final liveIds = {for (final l in editable) l.id};
    _layerChipKeys.removeWhere((id, _) => !liveIds.contains(id));

    const fade = 16.0; // px of fade at each end
    return SizedBox(
      height: 48,
      child: ShaderMask(
        shaderCallback: (rect) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: const [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [0.0, fade / rect.width, 1 - fade / rect.width, 1.0],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ScrollConfiguration(
          // Desktop fix: a horizontal scrollable only takes TOUCH drag by
          // default — mouse drag isn't a recognised scroll device and a
          // vertical mouse wheel doesn't map to horizontal scroll, so on
          // Windows the strip looked frozen. Opting mouse + trackpad into the
          // drag devices makes click-drag scroll it; scrollbars stay hidden.
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: false,
            dragDevices: {
              ui.PointerDeviceKind.touch,
              ui.PointerDeviceKind.mouse,
              ui.PointerDeviceKind.trackpad,
              ui.PointerDeviceKind.stylus,
            },
          ),
          child: SingleChildScrollView(
            // NON-LAZY on purpose. ListView builds children lazily, so a layer
            // appended off-screen (every "Add layer") had NO chip widget yet —
            // its GlobalKey never resolved and ensureVisible could never find
            // it, which is why auto-scroll-to-new-layer silently failed. A Row
            // builds every chip up front (layer counts are tiny), so any chip
            // can always be scrolled into view. Same controller, same look.
            controller: _layerStripCtl,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              spacing: 8,
              children: [
                for (final l in editable)
                  ChoiceChip(
                    key: _layerChipKeys.putIfAbsent(l.id, () => GlobalKey()),
                    label: Text(l.name),
                    selected: l.id == _selectedLayerId,
                    onSelected: (_) => _selectLayer(l.id),
                  ),
              ],
            ),
          ),
        ),
      ),
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
    final isBase = layer.id == kBaseLayerId;
    final visible = layer.visible;

    final note = isBorder
        ? 'Draws outside the card edge — reordering has no visual effect yet; '
            'hiding works.'
        : isBase
            ? 'Always the bottom layer — colour and corner are in the Layout tab.'
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
          if (isBase)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Icon(Icons.lock_outline, color: scheme.outline),
            )
          else
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
          _section('l_geo', 'Position & size', [
            _labeledSlider('Left', layer.frac.left, 0, 1,
                (v) => _setLayerFrac(layer, l: v),
                step: 0.005),
            _labeledSlider(
                'Top', layer.frac.top, 0, 1, (v) => _setLayerFrac(layer, t: v),
                step: 0.005),
            _labeledSlider('Right', layer.frac.right, 0, 1,
                (v) => _setLayerFrac(layer, r: v),
                step: 0.005),
            _labeledSlider('Bottom', layer.frac.bottom, 0, 1,
                (v) => _setLayerFrac(layer, b: v),
                step: 0.005),
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

  void _editLayers(List<Layer> Function(List<Layer>) edit) {
    final current = effectiveTemplateLayers(_d);
    var next = edit([...current]);
    // Invariant: the Base layer is always the bottom of the stack (index 0).
    // Normalised here — the single choke point every mutation flows through —
    // so drags can't slip anything beneath it and legacy orders self-heal.
    final baseIdx = next.indexWhere((l) => l.id == kBaseLayerId);
    if (baseIdx > 0) {
      final base = next.removeAt(baseIdx);
      next = [base, ...next];
    }
    _update(_d.copyWith(
      layers: next,
      layerOrder: const [],
      hiddenLayers: const [],
    ));
    // Any layer edit can newly reference an undecoded image — a {tag} typed
    // into a text placeholder being the everyday case (mirrors the card
    // editor's _markDirty → _syncArtImages fix). The sync skips ids already
    // decoded, so it's cheap; without it a new glyph only appeared after
    // save + reopen re-ran the initState sync.
    _syncImages();
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
    final count =
        effectiveTemplateLayers(_d).where((l) => l.id.startsWith('l_')).length;
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

  /// A collapsible group in the aspect editor. The header (title + chevron) is
  /// always shown; [children] appear only when expanded. Expansion state lives
  /// on the body State, so it persists as you move between layers.
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
}
