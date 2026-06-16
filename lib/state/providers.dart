// lib/state/providers.dart
//
// Riverpod providers. A "provider" exposes a value; widgets `watch` it and
// rebuild when it changes — a DI container whose registrations are observable.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/palette_repository.dart';
import '../model/card_model.dart';

/// The single database instance, disposed when no longer needed.
final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// The data API for palette colours.
final paletteRepositoryProvider = Provider<PaletteRepository>(
  (ref) => PaletteRepository(ref.watch(databaseProvider)),
);

/// A live list of palette swatches. Writes through the repository cause drift
/// to re-emit here automatically — no manual refresh.
final paletteProvider = StreamProvider<List<PaletteSwatch>>(
  (ref) => ref.watch(paletteRepositoryProvider).watch(),
);

/// Palette as an id -> value map, ready for the renderer's CardRefs. Empty
/// while the stream is still loading (reference snapshots cover that case).
final paletteMapProvider = Provider<Map<String, ColorValue>>((ref) {
  final async = ref.watch(paletteProvider);
  return async.maybeWhen(
    data: (list) => {for (final s in list) s.id: s.value},
    orElse: () => const <String, ColorValue>{},
  );
});
