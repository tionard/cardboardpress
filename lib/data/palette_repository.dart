// lib/data/palette_repository.dart
//
// The repository is the data layer's PUBLIC api. Features talk to this, never
// to drift directly. It owns the translation between database rows
// (PaletteColor / PaletteColorsCompanion) and the domain type (PaletteSwatch),
// so storage stays an implementation detail behind it.

import 'dart:ui' show Color;

import 'package:drift/drift.dart';

import '../model/card_model.dart';
import 'database.dart';

class PaletteRepository {
  final AppDatabase _db;
  PaletteRepository(this._db);

  /// Live, ordered palette. Re-emits on any change to the colours table.
  Stream<List<PaletteSwatch>> watch() =>
      _db.watchColors().map((rows) => rows.map(_toSwatch).toList());

  /// Append a new colour at the end of the palette.
  Future<void> add(PaletteSwatch s) async {
    final position = await _db.maxColorPosition() + 1;
    await _db.insertColor(_toCompanion(s, position: Value(position)));
  }

  /// Persist edits to an existing colour (position is preserved).
  Future<void> save(PaletteSwatch s) => _db.updateColor(s.id, _toCompanion(s));

  Future<void> delete(String id) => _db.deleteColor(id);

  // --- mapping ---

  PaletteColorsCompanion _toCompanion(
    PaletteSwatch s, {
    Value<int> position = const Value.absent(),
  }) {
    final v = s.value;
    return PaletteColorsCompanion(
      id: Value(s.id),
      name: Value(s.name),
      c1: Value(v.c1.toARGB32()),
      c2: Value<int?>(v.isDouble ? v.c2!.toARGB32() : null),
      orientation: Value(
          v.orientation == MixOrientation.horizontal ? 'horizontal' : 'vertical'),
      mix: Value(v.mix),
      position: position,
    );
  }

  PaletteSwatch _toSwatch(PaletteColor row) {
    final c1 = Color(row.c1);
    final value = row.c2 == null
        ? ColorValue.single(c1)
        : ColorValue.duo(
            c1,
            Color(row.c2!),
            orientation: row.orientation == 'horizontal'
                ? MixOrientation.horizontal
                : MixOrientation.vertical,
            mix: row.mix,
          );
    return PaletteSwatch(id: row.id, name: row.name, value: value);
  }
}
