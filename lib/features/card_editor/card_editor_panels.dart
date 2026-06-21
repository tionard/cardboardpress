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
      default:
        return Center(
          child: Text('${_catLabels[_cat]} — coming soon',
              style: Theme.of(context).textTheme.bodyMedium),
        );
    }
  }

  Widget _cardSettings() {
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
    final artId = _artFieldId;
    if (artId == null) {
      return const Center(child: Text('This template has no Art field.'));
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
      ],
    );
  }

  Widget _artTransformControls(String artId) {
    final tr = _working.content.artTransforms[artId] ?? const ArtTransform();

    Widget slider(String label, double value, double min, double max,
        ValueChanged<double> onChanged) {
      final shown = value.clamp(min, max);
      final step = (max - min) <= 0.15 ? 0.005 : 0.05;
      final divisions = ((max - min) / step).round().clamp(1, 1000);
      return Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Slider(
              value: shown,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              shown.toStringAsFixed(2),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
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
      ],
    );
  }

  Widget _colorSettings() {
    final refs = CardRefs(palette: widget.palette);
    final tintId = _working.content.tint?.id;
    final defaultBase = refs.resolveColor(_effective.baseColor);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Tint', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SwatchTile(
              value: defaultBase,
              label: 'Default',
              selected: _working.content.tint == null,
              onTap: _clearTint,
            ),
            for (final s in widget.swatches)
              _SwatchTile(
                value: s.value,
                label: s.name,
                selected: s.id == tintId,
                onTap: () => _setTint(s),
              ),
          ],
        ),
        if (_working.content.tint != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            const SizedBox(width: 70, child: Text('Opacity')),
            Expanded(
              child: Slider(
                value: _working.content.tintAlpha.clamp(0.0, 1.0),
                divisions: 20,
                onChanged: _setTintAlpha,
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                _working.content.tintAlpha.clamp(0.0, 1.0).toStringAsFixed(2),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ]),
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
      ],
    );
  }

  Widget _exportSettings() {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    final spinner = _exporting
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2))
        : null;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Export', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          isAndroid
              ? 'Renders this card at 300 dpi (750×1050 px) through the same '
                  'paintCard the preview uses, so the image matches exactly. '
                  'Save it to your photos or share it straight from here.'
              : 'Renders this card at 300 dpi (750×1050 px) through the same '
                  'paintCard the preview uses, so the PNG matches exactly — '
                  'including art and colours. You choose where to save it.',
          style: Theme.of(context).textTheme.bodySmall,
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
      ],
    );
  }
}

String _fieldLabel(FieldType t) =>
    t.name[0].toUpperCase() + t.name.substring(1);

String _foilLabel(FoilType f) =>
    f.name[0].toUpperCase() + f.name.substring(1);
