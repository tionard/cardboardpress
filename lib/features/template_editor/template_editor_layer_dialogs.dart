// lib/features/template_editor/template_editor_layer_dialogs.dart
//
// Dialogs and pickers launched from the Layers pane: bound-text parts editor,
// free-text placeholder editor, watermark symbol picker, layer image / border
// sprite pickers, and layer rename. Pure "ask the user, then _updateLayer"
// flows — no pane layout and no mutation logic of their own.

part of 'template_editor_screen.dart';

extension _TemplateLayerDialogs on _TemplateBodyState {
  Future<void> _editTextParts(Layer layer) async {
    final result = await showDialog<(List<TextSource>, String)>(
      context: context,
      builder: (_) => _TextPartsDialog(
        initialParts: layer.text?.parts ?? const [],
        initialSeparator: layer.text?.separator ?? '\u00b7',
      ),
    );
    if (result == null) return;
    final (chosen, sep) = result;
    _updateLayer(
        layer.id,
        (l) => l.copyWith(
            text: l.text?.copyWith(parts: chosen, separator: sep)));
  }

  Future<void> _editLayerPlaceholder(Layer layer) async {
    final value = await showDialog<String>(
      context: context,
      builder: (_) =>
          _PlaceholderDialog(initial: layer.text?.placeholder ?? ''),
    );
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
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _RenameLayerDialog(initial: layer.name),
    );
    if (name == null || name.isEmpty) return;
    _updateLayer(layer.id, (l) => l.copyWith(name: name));
  }
}

// ---------------------------------------------------------------------------
// Dialog widgets
//
// Each dialog OWNS its TextEditingController and disposes it in its own
// State.dispose — i.e. only after the route has fully left the tree. The old
// pattern (create controller in the launcher, `ctl.dispose()` right after
// `await showDialog` returns) disposed the controller while the dialog was
// still on screen playing its exit transition, with a live TextField (and on
// mobile a dismissing keyboard) attached to it. That corrupted teardown
// ordering — the Windows a11y bridge's "Nodes left pending by the update"
// console error, and on Android the `'_dependents.isEmpty'` framework
// assertion (full red screen). Focus is also released before popping so the
// IME dismissal never races the route teardown.
// ---------------------------------------------------------------------------

/// Bound-text parts editor. Pops `(chosen sources, separator)` on Save.
class _TextPartsDialog extends StatefulWidget {
  final List<TextSource> initialParts;
  final String initialSeparator;
  const _TextPartsDialog(
      {required this.initialParts, required this.initialSeparator});

  @override
  State<_TextPartsDialog> createState() => _TextPartsDialogState();
}

class _TextPartsDialogState extends State<_TextPartsDialog> {
  late final List<TextSource> chosen = List.of(widget.initialParts);
  late final TextEditingController sepCtl =
      TextEditingController(text: widget.initialSeparator);

  @override
  void dispose() {
    sepCtl.dispose();
    super.dispose();
  }

  void _pop(BuildContext ctx, (List<TextSource>, String)? result) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(ctx, result);
  }

  @override
  Widget build(BuildContext ctx) {
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
                    onPressed: () => setState(() => chosen.add(src)),
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
                      onReorderItem: (o, n) => setState(() {
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
                          onPressed: () => setState(() => chosen.removeAt(i)),
                        ),
                      ),
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => _pop(ctx, null), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => _pop(ctx, (chosen, sepCtl.text)),
            child: const Text('Save')),
      ],
    );
  }
}

/// Free-text placeholder editor. Pops the new placeholder string on Save.
class _PlaceholderDialog extends StatefulWidget {
  final String initial;
  const _PlaceholderDialog({required this.initial});

  @override
  State<_PlaceholderDialog> createState() => _PlaceholderDialogState();
}

class _PlaceholderDialogState extends State<_PlaceholderDialog> {
  late final TextEditingController ctl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  void _pop(BuildContext ctx, String? value) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(ctx, value);
  }

  @override
  Widget build(BuildContext ctx) {
    return AlertDialog(
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
            onPressed: () => _pop(ctx, null), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => _pop(ctx, ctl.text), child: const Text('Save')),
      ],
    );
  }
}

/// Layer rename. Pops the trimmed new name on Rename / submit.
class _RenameLayerDialog extends StatefulWidget {
  final String initial;
  const _RenameLayerDialog({required this.initial});

  @override
  State<_RenameLayerDialog> createState() => _RenameLayerDialogState();
}

class _RenameLayerDialogState extends State<_RenameLayerDialog> {
  late final TextEditingController ctl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  void _pop(BuildContext ctx, String? value) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(ctx, value);
  }

  @override
  Widget build(BuildContext ctx) {
    return AlertDialog(
      title: const Text('Rename layer'),
      content: TextField(
        controller: ctl,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => _pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => _pop(ctx, null), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => _pop(ctx, ctl.text.trim()),
            child: const Text('Rename')),
      ],
    );
  }
}
