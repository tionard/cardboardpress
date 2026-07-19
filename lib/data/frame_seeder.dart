// lib/data/frame_seeder.dart
//
// Seeds the bundled Frames-library pack (shared 9-slice border sprites) at
// app startup — the frames sibling of symbol_seeder.dart, using the exact
// same versioned pattern:
//
//  * PNGs ship as assets under assets/seed/frames/ and are copied into the
//    ImageStore under stable ids, then one Frames row is inserted per sprite.
//  * A pack version in AppSettings ('seed.frames.packVersion') gates the
//    work: stored < _packVersion (re-)runs the seed, matching/newer skips.
//    Growing the pack across releases = bump _packVersion + append entries.
//  * Re-running is harmless: images overwrite with identical bytes, rows use
//    insertOrIgnore — user edits to a seeded frame's name/slicing survive.
//  * The row ids ('fr_seed_*') and image ids ('frm_seed_*') come from shared
//    constants in lib/model/sample_card.dart, because seeded TEMPLATES bake
//    the same values into their border-aspect snapshots — one source of
//    truth keeps library and snapshots in lockstep.

import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../model/sample_card.dart';
import 'database.dart';
import 'image_store.dart';

/// Bump when the bundled pack changes (new frames, replaced art).
const _packVersion = 1;
const _packVersionKey = 'seed.frames.packVersion';

/// Where the pack's PNGs live. Must match the pubspec asset entry (folder
/// entries need the trailing slash and cover only direct children).
const _assetDir = 'assets/seed/frames';

class _SeedFrame {
  final String file; // PNG basename under [_assetDir]
  final String id; // Frames row id ('fr_seed_*', minted only here)
  final String imageId; // stable ImageStore id ('frm_seed_*')
  final String name; // display name in Customize → Frames
  final double insetL, insetT, insetR, insetB; // source cuts (fractions)

  const _SeedFrame({
    required this.file,
    required this.id,
    required this.imageId,
    required this.name,
    required this.insetL,
    required this.insetT,
    required this.insetR,
    required this.insetB,
  });
}

// Library order in Customize → Frames = list order (appended after any frames
// the user already has).
const _pack = <_SeedFrame>[
  _SeedFrame(
    file: 'frame_wings.png',
    id: kWingsFrameId,
    imageId: kWingsFrameImageId,
    name: 'WingsFrame',
    insetL: kWingsInsetLR,
    insetT: kWingsInsetTB,
    insetR: kWingsInsetLR,
    insetB: kWingsInsetTB,
  ),
  _SeedFrame(
    file: 'panel_wings.png',
    id: kWingsPanelId,
    imageId: kWingsPanelImageId,
    name: 'WingsPanel',
    insetL: kWingsInsetLR,
    insetT: kWingsInsetTB,
    insetR: kWingsInsetLR,
    insetB: kWingsInsetTB,
  ),
];

/// Seeds/tops-up the bundled frames pack. Called from main() before runApp;
/// must never throw, so a missing/corrupt asset is logged, skipped, and
/// retried next launch (the version key is only written when the whole pack
/// landed).
Future<void> seedDefaultFrames(AppDatabase db, ImageStore store) async {
  final settings = await db.readSettings();
  final have = int.tryParse(settings[_packVersionKey] ?? '') ?? 0;
  if (have >= _packVersion) return;

  // Append after the user's existing frames rather than colliding with their
  // positions (maxFramePosition is -1 on an empty table → base 0).
  final basePos = await db.maxFramePosition() + 1;

  var allOk = true;
  for (var i = 0; i < _pack.length; i++) {
    final f = _pack[i];
    try {
      final data = await rootBundle.load('$_assetDir/${f.file}');
      final bytes =
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      final imageId = await store.save(bytes, id: f.imageId);
      await db.insertFrame(FramesCompanion.insert(
        id: f.id,
        name: f.name,
        imageId: imageId,
        insetL: Value(f.insetL),
        insetT: Value(f.insetT),
        insetR: Value(f.insetR),
        insetB: Value(f.insetB),
        edgeMode: const Value('tile'),
        centerMode: const Value('tile'),
        position: Value(basePos + i),
      ));
    } catch (e) {
      // Typically a filename/pubspec mismatch. Never block launch over it.
      allOk = false;
      debugPrint('frame_seeder: failed to seed ${f.file}: $e');
    }
  }

  if (allOk) {
    await db.putSetting(_packVersionKey, '$_packVersion');
  }
}
