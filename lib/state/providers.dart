// lib/state/providers.dart
//
// Riverpod providers. A "provider" exposes a value; widgets `watch` it and
// rebuild when it changes — a DI container whose registrations are observable.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/image_store.dart';
import '../data/card_exporter.dart';
import '../data/card_repository.dart';
import '../data/palette_repository.dart';
import '../data/rarity_repository.dart';
import '../data/set_repository.dart';
import '../data/template_repository.dart';
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

/// Data API for templates.
final templateRepositoryProvider = Provider<TemplateRepository>(
  (ref) => TemplateRepository(ref.watch(databaseProvider)),
);

/// Live list of persisted templates.
final templatesProvider = StreamProvider<List<TemplateEntry>>(
  (ref) => ref.watch(templateRepositoryProvider).watch(),
);

/// Templates as an id -> layout map, for resolving a card's template reference.
final templatesMapProvider = Provider<Map<String, TemplateData>>((ref) {
  final async = ref.watch(templatesProvider);
  return async.maybeWhen(
    data: (list) => {for (final t in list) t.id: t.data},
    orElse: () => const <String, TemplateData>{},
  );
});

/// Data API for cards.
final cardRepositoryProvider = Provider<CardRepository>(
  (ref) => CardRepository(ref.watch(databaseProvider)),
);

/// Live list of persisted cards.
final cardsProvider = StreamProvider<List<CardEntry>>(
  (ref) => ref.watch(cardRepositoryProvider).watch(),
);

/// Disk-backed store for picked art images.
final imageStoreProvider = Provider<ImageStore>((ref) => ImageStore());

/// Renders + saves a card as PNG (Card Editor export, Collection export later).
final cardExporterProvider = Provider<CardExporter>((ref) => CardExporter());

/// Data API for sets.
final setRepositoryProvider = Provider<SetRepository>(
  (ref) => SetRepository(ref.watch(databaseProvider)),
);

/// Live list of persisted sets (Unassigned is the null-setId bucket, not here).
final setsProvider = StreamProvider<List<SetEntry>>(
  (ref) => ref.watch(setRepositoryProvider).watch(),
);

/// The card currently open in the editor (chosen from Collection).
class CurrentCardId extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? id) => state = id;
}

final currentCardIdProvider =
    NotifierProvider<CurrentCardId, String?>(CurrentCardId.new);

/// Data API for rarities.
final rarityRepositoryProvider = Provider<RarityRepository>(
  (ref) => RarityRepository(ref.watch(databaseProvider)),
);

/// Live list of rarities.
final raritiesProvider = StreamProvider<List<RarityEntry>>(
  (ref) => ref.watch(rarityRepositoryProvider).watch(),
);

/// Rarities as an id -> entry map, for resolving a card's rarity reference.
final raritiesMapProvider = Provider<Map<String, RarityEntry>>((ref) {
  final async = ref.watch(raritiesProvider);
  return async.maybeWhen(
    data: (list) => {for (final r in list) r.id: r},
    orElse: () => const <String, RarityEntry>{},
  );
});

/// The visible tab index in the app shell, so screens can navigate the shell
/// (e.g. Collection opening a card in the Card Editor tab). Order matches
/// AppShell: 0 Collection · 1 Template · 2 Card · 3 Customize.
const int kCardEditorTabIndex = 2;

class SelectedTab extends Notifier<int> {
  @override
  int build() => 0;

  void set(int index) => state = index;
}

final selectedTabProvider =
    NotifierProvider<SelectedTab, int>(SelectedTab.new);
