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
    // Every control here is built from the template's LAYERS and their exposure
    // routing — the same list the renderer walks. A layer whose only Card-tab
    // exposure is free text renders as a plain text field (the familiar form);
    // anything richer gets a titled block of per-aspect controls.
    final tabGroups = _exposedByLayer(EditorTab.card);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (tabGroups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'This template exposes nothing to the Card tab. Expose a '
              'layer\u2019s text (or another aspect) to \u201cCard \u00b7 '
              'Card tab\u201d in the Template Editor to edit it per card.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (final g in tabGroups)
          if (g.aspects.length == 1 && g.aspects.single == ExposedAspect.text) ...[
            TextField(
              controller: _controllerFor(g.layer.id),
              maxLines: g.layer.text?.multiline == true ? 4 : 1,
              decoration: InputDecoration(
                labelText: g.layer.name,
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
          ] else
            ..._exposedLayerBlock(g, EditorTab.card),
        Text(
          'Edits update the preview live and persist when you Save. Bound text '
          '(footer lines) derives from the set and rarity, so it has no field '
          'here. Switch templates from the picker at the top.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _artSettings() {
    // One art block per layer whose image source is CARD ART (there can be
    // several now), each keyed by its layer id — plus the per-card artist
    // credit and any aspects other layers expose to this tab.
    final tabGroups = _exposedByLayer(EditorTab.art);
    final artLayers = _artLayers;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (artLayers.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'This template has no per-card art layer. Add one in the '
              'Template Editor: a layer with an Image aspect whose source is '
              '\u201cCard art\u201d.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (final l in artLayers)
          ..._artBlock(l, showTitle: artLayers.length > 1),
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
          'credit is per-card content shown by bound footer text.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        for (final g in tabGroups)
          ..._exposedLayerBlock(g, EditorTab.art),
      ],
    );
  }

  /// One per-card art layer's controls: preview, pick/replace/remove, zoom/pan.
  List<Widget> _artBlock(Layer layer, {required bool showTitle}) {
    final artId = layer.id;
    final imageId = _working.content.art[artId];
    final img = imageId == null ? null : _images[imageId];
    return [
      if (showTitle) ...[
        Text(layer.name, style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
      ],
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
      const SizedBox(height: 8),
    ];
  }

  /// Zoom / pan sliders for a per-card transform keyed by [artId]. [fallback]
  /// is what shows before any per-card value exists — identity for card art,
  /// the TEMPLATE's transform for an exposed fixed image (so the sliders start
  /// where the picture actually sits instead of jumping on first touch).
  Widget _artTransformControls(String artId,
      {ArtTransform fallback = const ArtTransform()}) {
    final tr = _working.content.artTransforms[artId] ?? fallback;

    Widget slider(String label, double value, double min, double max,
        ValueChanged<double> onChanged) {
      return LabeledSlider(
        label: label,
        value: value,
        min: min,
        max: max,
        percent: true,
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
    // Fully exposure-driven: the Tint and Foil layers are ordinary generic
    // layers whose fill / foil aspects are exposed here by default, so their
    // blocks below ARE the old dedicated controls — plus whatever else the
    // template routes to this tab. Legacy per-card values still show and clear
    // correctly through the reroute-aware setters.
    final tabGroups = _exposedByLayer(EditorTab.color);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (tabGroups.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(
              'This template exposes nothing to the Color tab. Expose a '
              'layer\u2019s fill, foil, or another aspect to \u201cCard \u00b7 '
              'Color tab\u201d in the Template Editor to edit it per card.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        for (final g in tabGroups) ..._exposedLayerBlock(g, EditorTab.color),
        Text(
          'A translucent Tint fill blends over everything beneath its layer. '
          '\u201cUse default\u201d reverts any control to the template\u2019s '
          'value.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
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

  // ---- exposed-aspect wiring ----
  //
  // The exposure maps are THE source of per-card controls: every layer with an
  // aspect routed to [tab] gets one, whether it came from a template field or
  // was authored fresh in the Layers tab. The only skips:
  //   * value-locked chrome (tint / foil / border) — their per-card values live
  //     in the dedicated Color-tab controls (card.tint / card.foil) and
  //     _resolveCardLayer ignores generic overrides for them, so a control here
  //     would be a silent no-op;
  //   * aspects with nothing to control (bound text, a card-art image already
  //     owned by the Art panel, or an exposure orphaned by a removed aspect).

  bool _aspectHasCardControl(Layer l, ExposedAspect a) => switch (a) {
        ExposedAspect.text => !(l.text?.isBound ?? true),
        ExposedAspect.image =>
          l.image != null && l.image!.source != ImageSource.cardArt,
        ExposedAspect.fill => l.fill != null,
        ExposedAspect.outlineColor => l.outline != null,
        ExposedAspect.foil => true,
        ExposedAspect.visible => true,
        ExposedAspect.watermark => l.watermark != null,
      };

  List<_LayerExposureGroup> _exposedByLayer(EditorTab tab) {
    final out = <_LayerExposureGroup>[];
    for (final l in _cardLayers) {
      if (_kValueLockedLayerIds.contains(l.id)) continue;
      final aspects = <ExposedAspect>[
        for (final e in l.exposed.entries)
          if (e.value == tab && _aspectHasCardControl(l, e.key)) e.key,
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
        // Bound text never reaches here (filtered); this is free per-card text.
        return TextField(
          controller: _controllerFor(layer.id),
          maxLines: layer.text?.multiline == true ? 4 : 1,
          decoration: const InputDecoration(
            labelText: 'Text',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        );
      case ExposedAspect.image:
        // Card-art images never reach here (Art panel owns them); this is the
        // per-card face of a FIXED template picture: an optional replacement
        // image plus position / opacity / silhouette-tint overrides, exactly
        // the controls the template author has (all “absent = template
        // value”, baked by _resolveCardLayer).
        final ia = layer.image!;
        final imageId = _working.content.art[layer.id];
        final effAlpha = _working.content.imageAlphas[layer.id] ?? ia.alpha;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(
                  imageId == null
                      ? 'Template picture'
                      : 'Custom picture on this card',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton(
                onPressed: () => _pickLayerImageOverride(layer.id),
                child: Text(imageId == null ? 'Replace…' : 'Change…'),
              ),
              if (imageId != null)
                TextButton(
                  onPressed: () => _removeLayerImageOverride(layer.id),
                  child: const Text('Use default'),
                ),
            ]),
            const SizedBox(height: 4),
            _artTransformControls(layer.id, fallback: ia.transform),
            LabeledSlider(
              label: 'Opacity',
              value: effAlpha.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              step: 0.01,
              percent: true,
              labelWidth: 78,
              onChanged: (v) => _setLayerImageAlpha(layer.id, v),
            ),
            const SizedBox(height: 8),
            _exposedColorRow(
              label: 'Tint',
              current: _working.content.imageTints[layer.id],
              templateDefault: ia.tint,
              onPicked: (r) => _setLayerImageTint(layer.id, r),
              onClear: () => _setLayerImageTint(layer.id, null),
            ),
          ],
        );
      case ExposedAspect.fill:
        // Legacy tint reroute: a pre-reroute card's tint (content.tint /
        // tintAlpha) shows and clears as if it were this layer's override.
        final isTintSlot = layer.id == kTintLayerId;
        final legacyTint = isTintSlot ? _working.content.tint : null;
        final fillOverride =
            _working.content.fillColors[layer.id] ?? legacyTint;
        final effectiveAlpha = _working.content.fillAlphas[layer.id] ??
            (legacyTint != null
                ? _working.content.tintAlpha
                : (layer.fill?.alpha ?? 1.0));
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _exposedColorRow(
              label: 'Fill',
              current: fillOverride,
              templateDefault: layer.fill?.color,
              onPicked: (r) => _setLayerFill(layer.id, r),
              onClear: () => _setLayerFill(layer.id, null),
            ),
            const SizedBox(height: 8),
            LabeledSlider(
              label: 'Opacity',
              value: effectiveAlpha.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              step: 0.01,
              percent: true,
              labelWidth: 78,
              onChanged: (v) => _setLayerFillAlpha(layer.id, v),
            ),
          ],
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
        // Legacy foil reroute: a pre-reroute card's foil (entry.foil) shows
        // and clears as if it were this layer's override.
        final legacyFoil =
            layer.id == kFoilLayerId && _working.foil != FoilType.none
                ? _working.foil
                : null;
        final override =
            _working.content.foilOverrides[layer.id] ?? legacyFoil;
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
      case ExposedAspect.watermark:
        final wm = layer.watermark!;
        final symbolOverride = _working.content.watermarkSymbols[layer.id];
        final wmColor = _working.content.watermarkColors[layer.id];
        final wmAlpha =
            _working.content.watermarkAlphas[layer.id] ?? wm.alpha;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const SizedBox(width: 80, child: Text('Symbol')),
              OutlinedButton.icon(
                onPressed: () => _pickLayerWatermarkSymbol(layer),
                icon: const Icon(Icons.image_outlined),
                label: Text(symbolOverride == null ? 'Change…' : 'Custom'),
              ),
              if (symbolOverride != null)
                TextButton(
                    onPressed: () => _clearLayerWatermarkSymbol(layer.id),
                    child: const Text('Use default')),
            ]),
            const SizedBox(height: 8),
            _exposedColorRow(
              label: 'Colour',
              current: wmColor,
              templateDefault: wm.color,
              onPicked: (r) => _setLayerWatermarkColor(layer.id, r),
              onClear: () => _setLayerWatermarkColor(layer.id, null),
            ),
            const SizedBox(height: 8),
            LabeledSlider(
              label: 'Opacity',
              value: wmAlpha.clamp(0.0, 1.0),
              min: 0,
              max: 1,
              step: 0.01,
              percent: true,
              labelWidth: 78,
              onChanged: (v) => _setLayerWatermarkAlpha(layer.id, v),
            ),
          ],
        );
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

}

/// One layer's exposed aspects for a given tab. Rendered as a titled block.
class _LayerExposureGroup {
  final Layer layer;
  final List<ExposedAspect> aspects;
  _LayerExposureGroup(this.layer, this.aspects);
}

// System layers with no per-card controls: BASE is template-owned (Layout tab)
// and BORDER draws outside the clip with its style on the template — generic
// overrides for it would be no-ops. Tint and foil are ordinary generic layers.
const Set<String> _kValueLockedLayerIds = {
  kBaseLayerId,
  kBorderLayerId,
};

