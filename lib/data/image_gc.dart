// lib/data/image_gc.dart
//
// Startup image garbage collection. With content-addressed uploads
// (image_store.dart) files are SHARED between cards/templates/libraries, so
// no delete/replace flow ever removes a file directly — this sweep is the one
// place stored images die, and only when NOTHING references them.
//
// Reference surfaces walked (keep in sync with model/image_refs.dart, which
// owns the template/card halves):
//   * templates.spec            → imageIdsOfTemplate
//   * cards.templateSnapshot    → imageIdsOfTemplate  (a deleted template's
//                                 card references images ONLY through here)
//   * cards.content             → imageIdsOfCardContent
//   * symbols / textSymbols / frames tables → imageId columns
//
// Safety posture, in order of importance:
//   1. Runs at STARTUP only — no editor holds an unsaved reference to a
//      just-uploaded image at that point.
//   2. Conservative: ANY error while building the keep-set aborts the whole
//      sweep (deleting nothing is always safe; deleting wrongly never is).
//   3. The store's sweep skips files younger than an hour, closing the race
//      with an upload landing mid-sweep.

import 'package:flutter/foundation.dart' show debugPrint;

import '../model/image_refs.dart';
import 'database.dart';
import 'image_store.dart';

/// Deletes stored images nothing in the database references. Returns the
/// number of files removed (0 on abort — errors never propagate).
Future<int> collectGarbageImages(AppDatabase db, ImageStore store) async {
  final Set<String> keep;
  try {
    keep = <String>{};
    for (final t in await db.select(db.templates).get()) {
      keep.addAll(imageIdsOfTemplate(t.spec));
    }
    for (final c in await db.select(db.cards).get()) {
      keep.addAll(imageIdsOfTemplate(c.templateSnapshot));
      keep.addAll(imageIdsOfCardContent(c.content));
    }
    for (final s in await db.select(db.symbols).get()) {
      keep.add(s.imageId);
    }
    for (final s in await db.select(db.textSymbols).get()) {
      keep.add(s.imageId);
    }
    for (final f in await db.select(db.frames).get()) {
      keep.add(f.imageId);
    }
  } catch (e) {
    // If any row fails to load/decode, we cannot know the full reference set
    // — abort rather than risk deleting something alive.
    debugPrint('image GC aborted: $e');
    return 0;
  }

  try {
    final removed = await store.sweepUnreferenced(keep);
    if (removed > 0) debugPrint('image GC: removed $removed unused file(s)');
    return removed;
  } catch (e) {
    debugPrint('image GC sweep failed: $e');
    return 0;
  }
}
