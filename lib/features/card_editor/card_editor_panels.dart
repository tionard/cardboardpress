part of 'card_editor_screen.dart';

/// The per-category settings panels (Card / Art / Color / Set / Export) and
/// the dispatcher that picks one based on the selected rail category.
extension _CardEditorPanels on _CardEditorBodyState {
  Widget _settings() {
    switch (_cat) {
      case _Cat.card:
        return _cardSettings();
      case _Cat.art:
        return _artSettings();
      case _Cat.color:
        return _colorSettings();
      case _Cat.set:
        return _setSettings();
      case _Cat.export:
        return _exportSettings();
    }
  }

  Widget _cardSettings() {
    final tabGroups = _exposedByLayer(EditorTab.card);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final f in _editableFields) ...[
          TextField(
            controller: _controllerFor(f),
            maxLines: f.type == FieldType.rules ? 4 : 1,
            decoration: InputDecoration(
              labelText: _fieldLabel(f.type),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        for (final g in tabGroups)
          ..._exposedLayerBlock(g, EditorTab.card),
        Text(
          'Each field autosaves as you type and the preview updates live. The '
          'Footer is omitted — it shows values derived from the set and rarity. '
          'Switch templates from the picker at the top.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _artSettings() {
    final tabGroups = _exposedByLayer(EditorTab.art);
    final artId = _artFieldId;
    if (artId == null) {
      if (tabGroups.isEmpty) {
        return const Center(child: Text('This template has no Art field.'));
      }
      // No bespoke Art field but layers expose image aspects to this tab.
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          for (final g in tabGroups)
            ..._exposedLayerBlock(g, EditorTab.art),
        ],
      );
    }
    final imageId = _working.content.art[artId];
    final img = imageId == null ? null : _images[imageId];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          height: 170,
          width: double.infinity,
          child: img != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: RawImage(image: img, fit: BoxFit.cover),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: const Center(child: Text('No art yet')),
                ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _pickArt(artId),
              icon: const Icon(Icons.upload_outlined),
              label: Text(imageId == null ? 'Pick image' : 'Replace image'),
            ),
            if (imageId != null)
              OutlinedButton.icon(
                onPressed: () => _removeArt(artId),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
              ),
          ],
        ),
        if (img != null) ...[
          const SizedBox(height: 8),
          _artTransformControls(artId),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _artist,
          decoration: const InputDecoration(
            labelText: 'Artist',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'The image is copied into the app and rendered through the same '
          'paintCard, so the preview and export match exactly. The artist '
          'credit is per-card content shown by the Footer.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        for (final g in tabGroups)
          ..._exposedLayerBlock(g, EditorTab.art),
      ],
    );
  }

  Widget _artTransformControls(String artId) {
    final tr = _working.content.artTransforms[artId] ?? const ArtTransform();

    Widget slider(String label, double value, double min, double max,
        ValueChanged<double> onChanged) {
      return LabeledSlider(
        label: label,
        value: value,
        min: min,
        max: max,
        decimals: 2,
        labelWidth: 78,
        onChanged: onChanged,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Position', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            if (!tr.isIdentity)
              TextButton(
                onPressed: () =>
                    _setArtTransform(artId, const ArtTransform()),
                child: const Text('Reset'),
              ),
          ],
        ),
        slider('Zoom', tr.zoom, 1.0, 3.0,
            (v) => _setArtTransform(artId, tr.copyWith(zoom: v))),
        slider('Horizontal', tr.panX, -1.0, 1.0,
            (v) => _setArtTransform(artId, tr.copyWith(panX: v))),
        slider('Vertical', tr.panY, -1.0, 1.0,
            (v) => _setArtTransform(artId, tr.copyWith(panY: v))),
      ],
    );
  }

  Widget _setSettings() {
    final setId = _working.setId;
    final rarityId = _working.content.rarityId;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Set', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Unassigned'),
              selected: setId == null,
              onSelected: (_) => _changeSet(null),
            ),
            for (final s in widget.sets)
              ChoiceChip(
                label: Text(s.name),
                selected: setId == s.id,
                onSelected: (_) => _changeSet(s.id),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Rarity', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('None'),
              selected: rarityId == null,
              onSelected: (_) => _setRarity(null),
            ),
            for (final r in widget.rarities)
              ChoiceChip(
                label: Text(r.abbreviation.isEmpty
                    ? r.name
                    : '${r.name} (${r.abbreviation})'),
                selected: rarityId == r.id,
                onSelected: (_) => _setRarity(r.id),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Membership and rarity feed the Footer (set abbreviation, collector '
          'number, copyright, and rarity). The Footer shows derived values, so '
          'changing these updates it live.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        for (final g in _exposedByLayer(EditorTab.set))
          ..._exposedLayerBlock(g, EditorTab.set),
      ],
    );
  }

  Widget _colorSettings() {
    final refs = CardRefs(palette: widget.palette);
    final defaultBase = refs.resolveColor(_effective.baseColor);
    final tint = _working.content.tint;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Tint', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Row(
          children: [
            // A colour well: shows the current tint (or the base as "Default")
            // and opens the picker popup. The returned ColorRef flows straight
            // to _setTintRef — a palette pick keeps its id, a hand-built colour
            // comes back as a literal, and both render through resolveColor. The
            // use-site Opacity slider below is unchanged (per-colour alpha lives
            // in the picker; this stays the master dimmer).
            _SwatchTile(
              value: tint == null ? defaultBase : refs.resolveColor(tint),
              label: tint == null ? 'Default' : 'Tint',
              selected: false,
              onTap: () async {
                final picked = await showColorPicker(
                  context,
                  use: SwatchUse.card,
                  initial: tint,
                );
                if (picked != null) _setTintRef(picked);
              },
            ),
            const SizedBox(width: 12),
            if (tint != null)
              TextButton(
                onPressed: _clearTint,
                child: const Text('Use default'),
              ),
          ],
        ),
        if (_working.content.tint != null) ...[
          const SizedBox(height: 12),
          LabeledSlider(
            label: 'Opacity',
            value: _working.content.tintAlpha.clamp(0.0, 1.0),
            min: 0,
            max: 1,
            step: 0.05,
            decimals: 2,
            labelWidth: 70,
            onChanged: _setTintAlpha,
          ),
        ],
        const SizedBox(height: 20),
        Text('Foil', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final f in FoilType.values)
              ChoiceChip(
                label: Text(_foilLabel(f)),
                selected: _working.foil == f,
                onSelected: (_) => _setFoil(f),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Tint layers over the template\'s base colour at the opacity you set, '
          'so a partial value blends the two. "Default" removes it. Foil draws a '
          'sheen over the whole card.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        for (final g in _exposedByLayer(EditorTab.color))
          ..._exposedLayerBlock(g, EditorTab.color),
      ],
    );
  }

  Widget _exportSettings() {
    final theme = Theme.of(context);
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final pro = widget.proUnlocked;
    // Free is pinned to 300 even if _dpi holds 600 (e.g. Pro toggled off
    // mid-session); the exporter enforces this too — this is just display.
    final shownDpi = (!pro && _dpi == 600) ? 300 : _dpi;
    final spinner = _exporting
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2))
        : null;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Export', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        Text('RESOLUTION',
            style: theme.textTheme.labelMedium?.copyWith(
              color: theme.colorScheme.primary,
              letterSpacing: 0.8,
              fontWeight: FontWeight.w600,
            )),
        const SizedBox(height: 6),
        SegmentedButton<int>(
          showSelectedIcon: false,
          segments: [
            const ButtonSegment(value: 300, label: Text('300 DPI')),
            ButtonSegment(
              value: 600,
              label: const Text('600 DPI'),
              icon: pro ? null : const Icon(Icons.lock_outline, size: 16),
            ),
          ],
          selected: {shownDpi},
          onSelectionChanged: (sel) {
            final v = sel.first;
            if (v == 600 && !pro) {
              _showProNeeded();
              return; // keep the free 300 selection
            }
            _selectDpi(v);
          },
        ),
        const SizedBox(height: 12),
        Text(
          pro
              ? 'Renders at $shownDpi DPI (${_exportDims(shownDpi)}) through the '
                  'same paintCard the preview uses — watermark-free.'
              : 'Free exports render at 300 DPI (${_exportDims(300)}) with a '
                  'watermark. Unlock Pro in Settings for 600 DPI and no watermark.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        if (isAndroid) ...[
          FilledButton.icon(
            onPressed: _exporting ? null : _saveToGallery,
            icon: spinner ?? const Icon(Icons.photo_library_outlined),
            label: Text(_exporting ? 'Working…' : 'Save to Photos'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _exporting ? null : _shareImage,
            icon: const Icon(Icons.ios_share_outlined),
            label: const Text('Share…'),
          ),
        ] else
          FilledButton.icon(
            onPressed: _exporting ? null : _exportPng,
            icon: spinner ?? const Icon(Icons.download_outlined),
            label: Text(_exporting ? 'Exporting…' : 'Export PNG…'),
          ),
        for (final g in _exposedByLayer(EditorTab.export))
          ..._exposedLayerBlock(g, EditorTab.export),
      ],
    );
  }

  void _showProNeeded() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text('600 DPI and watermark-free exports are a Pro '
          'feature.'),
      action: SnackBarAction(
        label: 'Settings',
        onPressed: widget.onOpenSettings,
      ),
    ));
  }

  // "W×H px" for the card at [dpi], from the working card's dimensions.
  String _exportDims(int dpi) {
    final t = _working.templateSnapshot;
    final w = (t.widthInches * dpi).round();
    final h = (t.heightInches * dpi).round();
    return '$w×$h px';
  }

  // ---- Phase 5: exposed-aspect wiring ----
  //
  // For each AUTHORED generic layer with any aspect exposed to [tab], the panel
  // gets a compact block: one control per exposed aspect. System chrome layers
  // (base/tint/bg/set-symbol/foil/border) and the bespoke kinds (art/rules/
  // footer) are already fully driven by the dedicated panels above (text fields,
  // the art panel, the tint well, the set/rarity chips), so they're skipped here
  // to avoid rendering their controls twice. (This is the step-1 boundary until
  // the field path is retired and these become the ONLY controls.)

  // While the field path is still alive, the dedicated panels render a control
  // for every layer that came from a template FIELD (text fields on the Card
  // tab, the art image, the footer) plus the chrome slots (tint / set symbol).
  // So the generic exposed-block path must skip anything with a field id or a
  // reserved id, or those controls appear twice. (Step-1 boundary: once fields
  // are retired, this path becomes the ONLY source and the filter goes away.)
  bool _ownedByLegacyPanel(Layer l) =>
      _kReservedLayerIds.contains(l.id) ||
      _effective.fields.any((f) => f.id == l.id);

  List<_LayerExposureGroup> _exposedByLayer(EditorTab tab) {
    final layers = effectiveTemplateLayers(_effective);
    final out = <_LayerExposureGroup>[];
    for (final l in layers) {
      if (_ownedByLegacyPanel(l)) continue;
      final aspects = <ExposedAspect>[
        for (final e in l.exposed.entries)
          if (e.value == tab) e.key,
      ];
      if (aspects.isEmpty) continue;
      out.add(_LayerExposureGroup(l, aspects));
    }
    return out;
  }

  List<Widget> _exposedLayerBlock(_LayerExposureGroup g, EditorTab tab) {
    final scheme = Theme.of(context).colorScheme;
    return [
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(g.layer.name, style: Theme.of(context).textTheme.titleSmall),
            const SizedBox(height: 8),
            for (final a in g.aspects) ...[
              _exposedAspectControl(g.layer, a),
              const SizedBox(height: 8),
            ],
          ],
        ),
      ),
    ];
  }

  Widget _exposedAspectControl(Layer layer, ExposedAspect aspect) {
    switch (aspect) {
      case ExposedAspect.text:
        // Bound text is composed from sources (derived), so it isn't typed here.
        if (layer.text?.isBound ?? false) {
          return const SizedBox.shrink();
        }
        return TextField(
          controller: _exposedTextController(layer.id, ''),
          maxLines: layer.text?.multiline == true ? 4 : 1,
          decoration: const InputDecoration(
            labelText: 'Text',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        );
      case ExposedAspect.image:
        // Bespoke `art` kind is already fully handled by the Art panel above;
        // don't offer a duplicate row for it.
        if (layer.kind == LayerKind.art) {
          return const SizedBox.shrink();
        }
        final imageId = _working.content.art[layer.id];
        return Row(children: [
          Expanded(
            child: Text(
              imageId == null ? 'No image set' : 'Image set',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          TextButton(
            onPressed: () => _pickLayerImageOverride(layer.id),
            child: Text(imageId == null ? 'Pick…' : 'Change…'),
          ),
          if (imageId != null)
            TextButton(
              onPressed: () => _removeLayerImageOverride(layer.id),
              child: const Text('Remove'),
            ),
        ]);
      case ExposedAspect.fill:
        return _exposedColorRow(
          label: 'Fill',
          current: _working.content.fillColors[layer.id],
          templateDefault: layer.fill?.color,
          onPicked: (r) => _setLayerFill(layer.id, r),
          onClear: () => _setLayerFill(layer.id, null),
        );
      case ExposedAspect.outlineColor:
        return _exposedColorRow(
          label: 'Outline',
          current: _working.content.outlineColors[layer.id],
          templateDefault: layer.outline?.color,
          onPicked: (r) => _setLayerOutline(layer.id, r),
          onClear: () => _setLayerOutline(layer.id, null),
        );
      case ExposedAspect.visible:
        final hidden = _working.content.cardHiddenLayers.contains(layer.id);
        return Row(children: [
          const Expanded(child: Text('Visible')),
          Switch(
            value: !hidden,
            onChanged: (v) => _setLayerHidden(layer.id, !v),
          ),
        ]);
      case ExposedAspect.foil:
        final override = _working.content.foilOverrides[layer.id];
        final current = override ?? layer.foil ?? FoilType.none;
        return Row(children: [
          const SizedBox(width: 80, child: Text('Foil')),
          Expanded(
            child: SegmentedButton<FoilType>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: FoilType.none, label: Text('None')),
                ButtonSegment(value: FoilType.holo, label: Text('Holo')),
                ButtonSegment(value: FoilType.gold, label: Text('Gold')),
              ],
              selected: {current},
              onSelectionChanged: (s) => _setLayerFoil(layer.id, s.first),
            ),
          ),
          if (override != null)
            TextButton(
                onPressed: () => _setLayerFoil(layer.id, null),
                child: const Text('Use default')),
        ]);
    }
  }

  Widget _exposedColorRow({
    required String label,
    required ColorRef? current,
    required ColorRef? templateDefault,
    required ValueChanged<ColorRef> onPicked,
    required VoidCallback onClear,
  }) {
    final refs = CardRefs(palette: widget.palette);
    final effective = current ?? templateDefault;
    return Row(children: [
      SizedBox(width: 80, child: Text(label)),
      _SwatchTile(
        value: effective == null
            ? const ColorValue.single(Color(0xFF9E9E9E))
            : refs.resolveColor(effective),
        label: current == null ? 'Default' : label,
        selected: false,
        onTap: () async {
          final picked = await showColorPicker(
            context,
            use: SwatchUse.card,
            initial: current,
          );
          if (picked != null) onPicked(picked);
        },
      ),
      if (current != null)
        TextButton(onPressed: onClear, child: const Text('Use default')),
    ]);
  }

  TextEditingController _exposedTextController(String layerId, String initial) {
    final existing = _exposedTextControllers[layerId];
    if (existing != null) return existing;
    final c = TextEditingController(text: _working.content.text[layerId] ?? initial);
    c.addListener(() {
      final v = c.text;
      if ((_working.content.text[layerId] ?? '') == v) return;
      _markDirty(() => _working = _working.copyWith(
          content: _working.content.withText(layerId, v)));
    });
    _exposedTextControllers[layerId] = c;
    return c;
  }
}

/// One layer's exposed aspects for a given tab. Rendered as a titled block.
class _LayerExposureGroup {
  final Layer layer;
  final List<ExposedAspect> aspects;
  _LayerExposureGroup(this.layer, this.aspects);
}

// System chrome layer ids still driven by dedicated panels (tint/foil in the
// Color tab) or drawn specially (border). Base/background/set-symbol are now
// ordinary generic layers.
const Set<String> _kReservedLayerIds = {
  kTintLayerId,
  kFoilLayerId,
  kBorderLayerId,
};

String _fieldLabel(FieldType t) =>
    t.name[0].toUpperCase() + t.name.substring(1);

String _foilLabel(FoilType f) =>
    f.name[0].toUpperCase() + f.name.substring(1);
