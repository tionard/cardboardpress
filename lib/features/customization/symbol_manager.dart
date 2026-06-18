// lib/features/customization/symbol_manager.dart
//
// Self-contained management UI for standalone symbols (spec §3.3). Drop it into
// the Customization "Symbols" sub-tab:
//
//     const SymbolManager()
//
// It binds to symbolsProvider / symbolRepositoryProvider / imageStore, so no
// extra wiring is needed. Add (pick image + name), rename, replace image, and
// delete. These are the graphics used for set symbols and watermarks — not
// inline text symbols and not composable.
//
// (They don't appear on a card yet: set-symbol placement lives in the Template
// Editor and the watermark belongs to the Rules field — both later steps. This
// is the library those features will draw from.)

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/card_model.dart';
import '../../state/providers.dart';

class SymbolManager extends ConsumerWidget {
  const SymbolManager({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(symbolsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load symbols: $e')),
      data: (symbols) => _body(context, ref, symbols),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, List<SymbolEntry> symbols) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Symbols', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _addSymbol(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add symbol'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Standalone graphics used as a set symbol or a watermark. Unlike '
            'text symbols they aren\'t typed inline and can\'t be combined — you '
            'pick one by name where it\'s needed.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (symbols.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('No symbols yet — add one to get started.',
                  style: Theme.of(context).textTheme.bodyMedium),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final s in symbols) _tile(context, ref, s),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, SymbolEntry s) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 120,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SymbolThumb(imageId: s.imageId, size: 56),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      s.name,
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 28,
                    height: 28,
                    child: PopupMenuButton<String>(
                      tooltip: '', // avoid the Tooltip-in-scrollview AXTree spam
                      padding: EdgeInsets.zero,
                      iconSize: 18,
                      icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
                      onSelected: (v) {
                        switch (v) {
                          case 'rename':
                            _rename(context, ref, s);
                          case 'replace':
                            _replaceImage(context, ref, s);
                          case 'delete':
                            _delete(context, ref, s);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'rename', child: Text('Rename')),
                        PopupMenuItem(
                            value: 'replace', child: Text('Replace image')),
                        PopupMenuItem(value: 'delete', child: Text('Delete')),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- actions ----

  Future<void> _addSymbol(BuildContext context, WidgetRef ref) async {
    final nameCtl = TextEditingController();
    Uint8List? bytes;
    var ext = 'png';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add symbol'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: Theme.of(ctx).colorScheme.outlineVariant),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: bytes == null
                        ? const Icon(Icons.image_outlined)
                        : Image.memory(bytes!, fit: BoxFit.contain),
                  ),
                  const SizedBox(width: 12),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final res = await FilePicker.pickFiles(
                          type: FileType.image, withData: true);
                      if (res == null) return;
                      final f = res.files.first;
                      if (f.bytes == null) return;
                      setLocal(() {
                        bytes = f.bytes;
                        ext = (f.extension ?? 'png').toLowerCase();
                      });
                    },
                    icon: const Icon(Icons.upload_outlined),
                    label: Text(bytes == null ? 'Choose image' : 'Change'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: nameCtl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Star',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (nameCtl.text.trim().isEmpty || bytes == null) return;
                Navigator.pop(ctx, true);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );

    if (confirmed == true && bytes != null) {
      final id = await ref.read(imageStoreProvider).save(bytes!, ext: ext);
      await ref
          .read(symbolRepositoryProvider)
          .add(name: nameCtl.text, imageId: id);
    }
    nameCtl.dispose();
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, SymbolEntry s) async {
    final ctl = TextEditingController(text: s.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename symbol'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              if (ctl.text.trim().isEmpty) return;
              Navigator.pop(ctx, ctl.text.trim());
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctl.dispose();
    if (name != null && name != s.name) {
      await ref.read(symbolRepositoryProvider).rename(s.id, name);
    }
  }

  Future<void> _replaceImage(
      BuildContext context, WidgetRef ref, SymbolEntry s) async {
    final res =
        await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (res == null) return;
    final f = res.files.first;
    if (f.bytes == null) return;
    final id = await ref
        .read(imageStoreProvider)
        .save(f.bytes!, ext: (f.extension ?? 'png').toLowerCase());
    await ref.read(symbolRepositoryProvider).replaceImage(s.id, id);
    // (The old image file is left on disk; orphan cleanup is handled elsewhere.)
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, SymbolEntry s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${s.name}"?'),
        content: const Text(
            'Anywhere this symbol is used as a set symbol or watermark will '
            'fall back to nothing until you pick another one.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(symbolRepositoryProvider).delete(s.id);
    }
  }
}

/// Loads a symbol's bytes from the ImageStore once and shows them. A tiny
/// process-wide cache avoids re-reading the file on every rebuild.
class _SymbolThumb extends ConsumerStatefulWidget {
  final String imageId;
  final double size;
  const _SymbolThumb({required this.imageId, required this.size});

  @override
  ConsumerState<_SymbolThumb> createState() => _SymbolThumbState();
}

class _SymbolThumbState extends ConsumerState<_SymbolThumb> {
  static final Map<String, Uint8List> _cache = {};
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SymbolThumb old) {
    super.didUpdateWidget(old);
    if (old.imageId != widget.imageId) _load();
  }

  Future<void> _load() async {
    final cached = _cache[widget.imageId];
    if (cached != null) {
      setState(() => _bytes = cached);
      return;
    }
    final bytes = await ref.read(imageStoreProvider).load(widget.imageId);
    if (!mounted || bytes == null) return;
    _cache[widget.imageId] = bytes;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: _bytes == null
          ? const Center(
              child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)))
          : Image.memory(_bytes!, fit: BoxFit.contain),
    );
  }
}
