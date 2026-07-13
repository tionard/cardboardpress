// lib/model/image_refs.dart
//
// Collects every image id a persisted entity references — the source of truth
// for the startup image garbage collector (data/image_gc.dart), which deletes
// any stored file NOT returned from here.
//
// ⚠ MAINTENANCE CONTRACT: if a new model field ever stores an image id, it
// MUST be added here in the same change — an unlisted reference means the GC
// deletes an image that's still in use. The full list of reference surfaces
// today:
//
//   TemplateData : bgImageId
//                  fields[].frame.imageId          (legacy field frames)
//                  layers[].image.imageId          (fixed-image aspect)
//                  layers[].border.imageId         (9-slice — this is the
//                                                   frame SNAPSHOT, which must
//                                                   survive library deletes)
//   CardContent  : art values                      (per-field card art)
//   DB tables    : symbols / textSymbols / frames  (handled by the GC itself)
//
// Watermarks reference SYMBOL ids, not image ids — they resolve through the
// symbols table, so the table walk covers them. Related-but-different:
// CardData.imageIdsToDecode() lists what a COMPOSED card needs decoded for
// painting; this file lists what PERSISTED entities keep alive on disk.

import 'card_model.dart';
import 'layers.dart';

/// Every image id [t] references (background, legacy field frames, layer
/// images, and layer border sprites — including snapshots of deleted frames).
Set<String> imageIdsOfTemplate(TemplateData t) {
  final ids = <String>{};
  final bg = t.bgImageId;
  if (bg != null && bg.isNotEmpty) ids.add(bg);
  for (final f in t.fields) {
    final frame = f.frame;
    if (frame != null && frame.imageId.isNotEmpty) ids.add(frame.imageId);
  }
  for (final l in t.layers ?? const <Layer>[]) {
    final img = l.image;
    if (img != null && img.imageId.isNotEmpty) ids.add(img.imageId);
    final b = l.border;
    if (b != null && b.imageId.isNotEmpty) ids.add(b.imageId);
  }
  return ids;
}

/// Every image id [c] references (per-field card art). Per-card overrides
/// hold colours, alphas, and SYMBOL ids — no image ids.
Set<String> imageIdsOfCardContent(CardContent c) =>
    c.art.values.where((id) => id.isNotEmpty).toSet();
