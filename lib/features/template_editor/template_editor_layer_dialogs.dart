// lib/features/template_editor/template_editor_layer_dialogs.dart
//
// Dialogs and pickers launched from the Layers pane: bound-text parts editor,
// free-text placeholder editor, watermark symbol picker, layer image / border
// sprite pickers, and layer rename. Pure "ask the user, then _updateLayer"
// flows — no pane layout and no mutation logic of their own.

part of 'template_editor_screen.dart';

extension _TemplateLayerDialogs on _TemplateBodyState {
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

  /// Open the symbol picker for the layer's watermark, then decode the chosen
  /// symbol so the preview reflects it immediately.
  Future<void> _pickLayerWatermarkSymbol(Layer layer) async {
    final choice =
        await pickSymbol(context, ref, currentId: layer.watermark?.symbolId);
    if (choice == null) return; // cancelled
    _updateLayer(
        layer.id,
        (l) => l.copyWith(
            watermark:
                (l.watermark ?? const WatermarkSpec(color: _kWatermarkDefault))
                    .copyWith(symbolId: choice.id ?? '')));
    _syncImages();
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

  /// Pick this layer's frame from the Frames library. The library is the only
  /// way a border sprite exists ("Upload new" in the picker saves to it); the
  /// chosen frame's values are overlaid onto the layer's border aspect —
  /// reference id + a snapshot baked at pick time — keeping the layer's own
  /// thickness / drawCenter / tint.
  Future<void> _pickLayerBorder(Layer layer) async {
    final choice =
        await pickFrame(context, ref, currentId: layer.border?.frameId);
    if (choice == null) return;
    final f = ref.read(framesMapProvider)[choice.id];
    if (f == null) return;
    _updateLayer(
        layer.id,
        (l) =>
            l.copyWith(border: f.applyTo(l.border ?? const NineSliceSpec())));
    _syncImages();
  }

  // ---- mutations (all promote-on-edit) ----

  /// Edit the layer list, promoting the template on first touch: read the
  /// effective list (baking any arrangement overlay into it), apply [edit], and
  /// store it as the explicit `_d.layers`, clearing the now-superseded overlay.
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
}
