// lib/data/frame_repository.dart
//
// Data API for the Frames library (Customization → Frames): shared 9-slice
// border sprites. A frame OWNS its slicing — the sprite image plus per-edge
// source cuts and stretch/tile modes; templates reference a frame by id on
// their border aspect (keeping a snapshot), so edits here update every
// referencing template live and deletes never break one.
//
// Use-site properties (thickness, drawCenter, tint) belong to the layer's
// border aspect, never to the library — same split as symbols, where colour
// tinting happens at the render site.

import 'package:drift/drift.dart' show Value;

import '../model/card_model.dart';
import 'database.dart';

class FrameRepository {
  final AppDatabase _db;
  FrameRepository(this._db);

  static SliceFillMode _mode(String name) =>
      name == SliceFillMode.tile.name ? SliceFillMode.tile : SliceFillMode.stretch;

  /// Live, ordered frames. Re-emits on any change to the table.
  Stream<List<FrameEntry>> watch() => _db.watchFrames().map((rows) => rows
      .map((r) => FrameEntry(
            id: r.id,
            name: r.name,
            imageId: r.imageId,
            insetL: r.insetL,
            insetT: r.insetT,
            insetR: r.insetR,
            insetB: r.insetB,
            edgeMode: _mode(r.edgeMode),
            centerMode: _mode(r.centerMode),
            position: r.position,
          ))
      .toList());

  /// Add a new frame with default slicing (equal thirds, stretch). [imageId]
  /// must already be in the ImageStore. Returns the new frame's id so pickers
  /// can select what they just uploaded.
  Future<String> add({required String name, required String imageId}) async {
    final pos = await _db.maxFramePosition() + 1;
    final clean = name.trim();
    final id = 'fr_${DateTime.now().microsecondsSinceEpoch}';
    await _db.insertFrame(FramesCompanion.insert(
      id: id,
      name: clean.isEmpty ? 'Untitled' : clean,
      imageId: imageId,
      position: Value(pos),
    ));
    return id;
  }

  Future<void> rename(String id, String name) {
    final n = name.trim();
    return _db.updateFrameRow(
        id, FramesCompanion(name: Value(n.isEmpty ? 'Untitled' : n)));
  }

  Future<void> replaceImage(String id, String imageId) =>
      _db.updateFrameRow(id, FramesCompanion(imageId: Value(imageId)));

  /// Update the slicing definition (cuts + modes) — the library-owned half of
  /// a 9-slice. Every referencing template re-renders via the watching
  /// providers as soon as drift re-emits.
  Future<void> updateSlicing(
    String id, {
    required double insetL,
    required double insetT,
    required double insetR,
    required double insetB,
    required SliceFillMode edgeMode,
    required SliceFillMode centerMode,
  }) =>
      _db.updateFrameRow(
          id,
          FramesCompanion(
            insetL: Value(insetL),
            insetT: Value(insetT),
            insetR: Value(insetR),
            insetB: Value(insetB),
            edgeMode: Value(edgeMode.name),
            centerMode: Value(centerMode.name),
          ));

  Future<void> delete(String id) => _db.deleteFrame(id);
}
