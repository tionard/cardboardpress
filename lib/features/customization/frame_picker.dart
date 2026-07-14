// lib/features/customization/frame_picker.dart
//
// A reusable picker over the Frames library, used by the template editor's
// border aspect. The library is the ONLY way a border sprite exists — the
// "Upload new" action here saves straight into the library and returns the
// new frame, so there is no bare per-template sprite path. Returns:
//
//   * null              -> cancelled (caller does nothing)
//   * FrameChoice('fr_…') -> that frame chosen
//
// Usage:
//   final choice = await pickFrame(context, ref, currentId: border.frameId);
//   if (choice != null) { /* overlay the frame onto the layer's border */ }

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/image_import.dart';
import '../../model/card_model.dart';
import '../../state/providers.dart';
import 'frame_manager.dart';

/// The result of [pickFrame]: the chosen frame's id.
class FrameChoice {
  final String id;
  const FrameChoice(this.id);
}

Future<FrameChoice?> pickFrame(
  BuildContext context,
  WidgetRef ref, {
  String? currentId,
}) {
  return showDialog<FrameChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Choose frame'),
      content: SizedBox(
        width: 420,
        child: Consumer(
          builder: (ctx, ref, _) {
            final async = ref.watch(framesProvider);
            return async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Could not load frames: $e'),
              data: (frames) => _grid(ctx, ref, frames, currentId),
            );
          },
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => _uploadNew(ctx, ref),
          icon: const Icon(Icons.upload_outlined),
          label: const Text('Upload new'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

Widget _grid(BuildContext context, WidgetRef ref, List<FrameEntry> frames,
    String? currentId) {
  if (frames.isEmpty) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'No frames yet — "Upload new" adds one to the library (also managed '
        'in Customize → Frames).',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
  return SingleChildScrollView(
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final f in frames)
          _frameTile(context, f, selected: f.id == currentId),
      ],
    ),
  );
}

Widget _frameTile(BuildContext context, FrameEntry f,
    {required bool selected}) {
  final scheme = Theme.of(context).colorScheme;
  return InkWell(
    onTap: () => Navigator.pop(context, FrameChoice(f.id)),
    borderRadius: BorderRadius.circular(10),
    child: Container(
      width: 104,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          width: selected ? 2 : 1,
          color: selected ? scheme.primary : scheme.outlineVariant,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FramePreviewThumb(frame: f, width: 84),
          const SizedBox(height: 6),
          Text(
            f.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}

/// Pick an image, ask for a name, save it to the library, and pop the picker
/// with the new frame chosen — upload-and-use in one motion. (Its slicing can
/// be tuned afterwards via "Edit frame…" or Customize → Frames.)
Future<void> _uploadNew(BuildContext dialogCtx, WidgetRef ref) async {
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
    if (dialogCtx.mounted) {
      ScaffoldMessenger.of(dialogCtx)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
    return;
  }
  final notice = imported.notice;
  if (notice != null && dialogCtx.mounted) {
    ScaffoldMessenger.of(dialogCtx)
        .showSnackBar(SnackBar(content: Text(notice)));
  }
  if (!dialogCtx.mounted) return;

  final nameCtl = TextEditingController();
  final name = await showDialog<String>(
    context: dialogCtx,
    builder: (ctx) => AlertDialog(
      title: const Text('Name the new frame'),
      content: TextField(
        controller: nameCtl,
        autofocus: true,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          labelText: 'Name',
          hintText: 'e.g. Parchment',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
        FilledButton(
          onPressed: () {
            if (nameCtl.text.trim().isEmpty) return;
            Navigator.pop(ctx, nameCtl.text.trim());
          },
          child: const Text('Add'),
        ),
      ],
    ),
  );
  nameCtl.dispose();
  if (name == null) return;

  final imageId = await ref
      .read(imageStoreProvider)
      .save(imported.bytes, ext: imported.ext);
  final frameId = await ref
      .read(frameRepositoryProvider)
      .add(name: name, imageId: imageId);
  if (dialogCtx.mounted) {
    Navigator.pop(dialogCtx, FrameChoice(frameId));
  }
}
