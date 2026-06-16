// lib/state/providers.dart
//
// Riverpod providers. A "provider" exposes a value; widgets `watch` it and
// rebuild when it changes. For a C# dev: think of this as a DI container whose
// registrations are also observable.
//
// This file is the seam between the database and the UI: it maps raw drift
// rows into domain `PaletteSwatch` objects, so feature screens import the
// model + these providers, never the database directly.

import 'dart:ui' show Color;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../model/card_model.dart';

/// The single database instance for the app, disposed when no longer needed.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// A live list of palette swatches. Because it's built on drift's `watch()`,
/// any change to the colours table pushes a new value here automatically.
final paletteProvider = StreamProvider<List<PaletteSwatch>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.watchColors().map((rows) => rows.map(_toSwatch).toList());
});

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
