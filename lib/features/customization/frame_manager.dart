// lib/features/customization/frame_manager.dart
//
// Management UI for the Frames library: shared 9-slice border sprites. Drop it
// into the Customization "Frames" sub-tab:
//
//     const FrameManager()
//
// It binds to framesProvider / frameRepositoryProvider / imageStore. Add
// (pick image + name), edit slicing (cuts + tile modes — the library-owned
// half of a 9-slice), rename, replace image, and delete. Templates reference
// these frames on their border aspect; edits here update every referencing
// template live, and deletes leave them rendering from their snapshot.
//
// Previews paint through paintFramePreview — the SAME nine-slice painter the
// card renderer uses — on a neutral card-aspect rounded rect, so what the
// grid shows is exactly how the frame slices on a card. [FramePreviewThumb]
// is public (the template-side frame picker reuses it); the slicing dialog
// itself — the visual guide-line editor — lives in frame_slice_editor.dart
// and is shared with the template editor's "Edit frame…".

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/image_import.dart';
import '../../model/card_model.dart';
import '../../state/providers.dart';
import 'frame_slice_editor.dart';

class FrameManager extends ConsumerWidget {
  const FrameManager({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(framesProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load frames: $e')),
      data: (frames) => _body(context, ref, frames),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, List<FrameEntry> frames) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Frames', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _addFrame(context, ref),
                icon: const Icon(Icons.add),
                label: const Text('Add frame'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Sliced border sprites shared across templates: upload once, use '
            'everywhere. Editing a frame\'s slicing updates every template '
            'that uses it; each template still sets its own thickness.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (frames.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('No frames yet — add one to get started.',
                  style: Theme.of(context).textTheme.bodyMedium),
            )
          else
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final f in frames) _tile(context, ref, f),
              ],
            ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext context, WidgetRef ref, FrameEntry f) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 128,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: () => editFrameSlicing(context, ref, f),
                borderRadius: BorderRadius.circular(6),
                child: FramePreviewThumb(frame: f, width: 100),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      f.name,
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
                          case 'slicing':
                            editFrameSlicing(context, ref, f);
                          case 'rename':
                            _rename(context, ref, f);
                          case 'replace':
                            _replaceImage(context, ref, f);
                          case 'delete':
                            _delete(context, ref, f);
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'slicing', child: Text('Edit slicing')),
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

  Future<void> _addFrame(BuildContext context, WidgetRef ref) async {
    final nameCtl = TextEditingController();
    Uint8List? bytes;
    var ext = 'png';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Add frame'),
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
                      final res =
                          await FilePicker.pickFiles(type: FileType.image);
                      if (res == null) return;
                      final f = res.files.first;
                      final picked = await f.readAsBytes();
                      final ImportedImage imported;
                      try {
                        imported = await processImportedImage(picked,
                            kind: ImageImportKind.frame,
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
                controller: nameCtl,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'e.g. Parchment',
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
      final frameId = await ref
          .read(frameRepositoryProvider)
          .add(name: nameCtl.text, imageId: id);
      // Straight into the cuts: a fresh upload almost always needs its slicing
      // set before it's usable, so don't make that a second trip to the menu.
      if (context.mounted) {
        final f = ref.read(framesMapProvider)[frameId];
        if (f != null) await editFrameSlicing(context, ref, f);
      }
    }
    nameCtl.dispose();
  }

  Future<void> _rename(
      BuildContext context, WidgetRef ref, FrameEntry f) async {
    final ctl = TextEditingController(text: f.name);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Rename frame'),
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
    if (name != null && name != f.name) {
      await ref.read(frameRepositoryProvider).rename(f.id, name);
    }
  }

  Future<void> _replaceImage(
      BuildContext context, WidgetRef ref, FrameEntry f) async {
    final res = await FilePicker.pickFiles(type: FileType.image);
    if (res == null) return;
    final file = res.files.first;
    final bytes = await file.readAsBytes();
    final ImportedImage imported;
    try {
      imported = await processImportedImage(bytes,
          kind: ImageImportKind.frame,
          ext: (file.extension ?? 'png').toLowerCase());
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
    await ref.read(frameRepositoryProvider).replaceImage(f.id, id);
    // (The old file becomes unreferenced; the startup image GC collects it.)
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, FrameEntry f) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${f.name}"?'),
        content: const Text(
            'Templates using this frame keep the copy they saved when it was '
            'picked, so nothing breaks — but they stop following future edits '
            'and the frame leaves the library for good.'),
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
      await ref.read(frameRepositoryProvider).delete(f.id);
    }
  }
}

// ---------------------------------------------------------------------------
// Preview thumb (public — reused by the template-side frame picker; painter
// and decode cache come from frame_slice_editor.dart)
// ---------------------------------------------------------------------------

/// A card-aspect (2.5 : 3.5) preview of a library frame, painted through the
/// real nine-slice renderer on a neutral rounded rect. Decodes the frame's
/// image once into a small process-wide cache (a replaced image gets a new id,
/// so the cache never goes stale).
class FramePreviewThumb extends ConsumerStatefulWidget {
  final FrameEntry frame;
  final double width;
  const FramePreviewThumb({super.key, required this.frame, this.width = 100});

  @override
  ConsumerState<FramePreviewThumb> createState() => _FramePreviewThumbState();
}

class _FramePreviewThumbState extends ConsumerState<FramePreviewThumb> {
  ui.Image? _img;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant FramePreviewThumb old) {
    super.didUpdateWidget(old);
    if (old.frame.imageId != widget.frame.imageId) _load();
  }

  Future<void> _load() async {
    final img = await decodedFrameImage(ref, widget.frame.imageId);
    if (!mounted) return;
    setState(() => _img = img);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget.width;
    final h = w * 3.5 / 2.5;
    final img = _img;
    return SizedBox(
      width: w,
      height: h,
      child: img == null
          ? const Center(
              child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2)))
          : CustomPaint(
              painter: FramePreviewPainter(
                image: img,
                spec: widget.frame.previewSpec(),
                backdrop:
                    Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
    );
  }
}
