// lib/features/customization/text_symbol_manager.dart
//
// Self-contained management UI for inline text symbols (spec §3.2). Drop this
// into the Customization "Text" sub-tab:
//
//     const TextSymbolManager()
//
// It binds to textSymbolsProvider / textSymbolRepositoryProvider / imageStore,
// so no extra wiring is needed. Add (pick image + tag), rename, replace image,
// and delete. The renderer matches tags case-insensitively, so {R} and {r} are
// the same symbol.

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/image_import.dart';
import '../../model/card_model.dart';
import '../../state/providers.dart';

class TextSymbolManager extends ConsumerWidget {
  const TextSymbolManager({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(textSymbolsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load symbols: $e')),
      data: (symbols) => _body(context, ref, symbols),
    );
  }

  Widget _body(
      BuildContext context, WidgetRef ref, List<TextSymbolEntry> symbols) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Text symbols',
                  style: Theme.of(context).textTheme.titleMedium),
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
            'Use a symbol in Cost or Rules text by its tag, e.g. {R}. Combine '
            'them as {A/B} (split) or {2^B} (number over symbol). Any number '
            'like {2} renders as a grey pip automatically.',
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

  Widget _tile(BuildContext context, WidgetRef ref, TextSymbolEntry s) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 108,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SymbolThumb(imageId: s.imageId, size: 48),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '{${s.tag}}',
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
                        PopupMenuItem(value: 'rename', child: Text('Rename tag')),
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
    final tagCtl = TextEditingController();
    Uint8List? bytes;
    var ext = 'png';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add text symbol'),
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
                          type: FileType.image);
                      if (res == null) return;
                      final f = res.files.first;
                      final picked = await f.readAsBytes();
                      final ImportedImage imported;
                      try {
                        imported = await processImportedImage(picked,
                            kind: ImageImportKind.textSymbol,
                            ext: (f.extension ?? 'png').toLowerCase());
                      } on ImageImportException catch (e) {
                        if (ctx.mounted) {
                          ScaffoldMessenger.of(ctx).showSnackBar(
                              SnackBar(content: Text(e.message)));
                        }
                        return;
                      }
                      final notice = imported.notice;
                      if (notice != null && ctx.mounted) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                            SnackBar(content: Text(notice)));
                      }
                      setLocal(() {
                        bytes = imported.bytes;
                        ext = imported.ext;
                      });
                    },
                    icon: const Icon(Icons.upload_outlined),
                    label: Text(bytes == null ? 'Choose image' : 'Change'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              TextField(
                controller: tagCtl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Tag',
                  hintText: 'e.g. R',
                  prefixText: '{',
                  suffixText: '}',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Avoid spaces and the characters { } / ^ in a tag.',
                style: Theme.of(ctx).textTheme.bodySmall,
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                if (tagCtl.text.trim().isEmpty || bytes == null) return;
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
          .read(textSymbolRepositoryProvider)
          .add(tag: tagCtl.text, imageId: id);
    }
    tagCtl.dispose();
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, TextSymbolEntry s) async {
    final ctl = TextEditingController(text: s.tag);
    final tag = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename tag'),
        content: TextField(
          controller: ctl,
          autofocus: true,
          decoration: const InputDecoration(
            prefixText: '{',
            suffixText: '}',
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
    if (tag != null && tag != s.tag) {
      await ref.read(textSymbolRepositoryProvider).rename(s.id, tag);
    }
  }

  Future<void> _replaceImage(
      BuildContext context, WidgetRef ref, TextSymbolEntry s) async {
    final res =
        await FilePicker.pickFiles(type: FileType.image);
    if (res == null) return;
    final f = res.files.first;
    final bytes = await f.readAsBytes();
    final ImportedImage imported;
    try {
      imported = await processImportedImage(bytes,
          kind: ImageImportKind.textSymbol,
          ext: (f.extension ?? 'png').toLowerCase());
    } on ImageImportException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    final notice = imported.notice;
    if (notice != null && context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(notice)));
    }
    final id = await ref
        .read(imageStoreProvider)
        .save(imported.bytes, ext: imported.ext);
    await ref.read(textSymbolRepositoryProvider).replaceImage(s.id, id);
    // (The old file becomes unreferenced; the startup image GC collects it.)
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, TextSymbolEntry s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete {${s.tag}}?'),
        content: const Text(
            'Cards that reference this tag will show a blank gap until you '
            'add a symbol with the same tag again.'),
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
      await ref.read(textSymbolRepositoryProvider).delete(s.id);
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
                  width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)))
          : Image.memory(_bytes!, fit: BoxFit.contain),
    );
  }
}
