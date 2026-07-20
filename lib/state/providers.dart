// lib/state/providers.dart
//
// Riverpod providers. A "provider" exposes a value; widgets `watch` it and
// rebuild when it changes — a DI container whose registrations are observable.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import '../data/image_store.dart';
import '../data/backup_service.dart';
import '../data/card_exporter.dart';
import '../data/card_repository.dart';
import '../data/frame_repository.dart';
import '../data/palette_repository.dart';
import '../data/rarity_repository.dart';
import '../data/set_repository.dart';
import '../data/symbol_repository.dart';
import '../data/template_folder_repository.dart';
import '../data/template_repository.dart';
import '../data/text_symbol_repository.dart';
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
final templateFolderRepositoryProvider = Provider<TemplateFolderRepository>(
    (ref) => TemplateFolderRepository(ref.watch(databaseProvider)));

/// Template-browser folders, in display order.
final templateFoldersProvider = StreamProvider<List<TemplateFolderEntry>>(
    (ref) => ref.watch(templateFolderRepositoryProvider).watch());

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

final backupServiceProvider = Provider<BackupService>((ref) => BackupService(
      ref.watch(databaseProvider),
      ref.watch(imageStoreProvider),
    ));

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

/// Data API for inline text symbols (spec §3.2).
final textSymbolRepositoryProvider = Provider<TextSymbolRepository>(
  (ref) => TextSymbolRepository(ref.watch(databaseProvider)),
);

/// Live list of text symbols (for the Customization "Text" tab).
final textSymbolsProvider = StreamProvider<List<TextSymbolEntry>>(
  (ref) => ref.watch(textSymbolRepositoryProvider).watch(),
);

/// tag (lower-cased) -> imageId, for compose/renderer to resolve {TAG}s. Empty
/// while loading. Tags are matched case-insensitively.
final textSymbolMapProvider = Provider<Map<String, String>>((ref) {
  final async = ref.watch(textSymbolsProvider);
  return async.maybeWhen(
    data: (list) => {for (final s in list) s.tag.toLowerCase(): s.imageId},
    orElse: () => const <String, String>{},
  );
});

/// Data API for standalone symbols (spec §3.3: set symbol / watermark library).
final symbolRepositoryProvider = Provider<SymbolRepository>(
  (ref) => SymbolRepository(ref.watch(databaseProvider)),
);

/// Live list of standalone symbols (for the Customization "Symbols" tab).
final symbolsProvider = StreamProvider<List<SymbolEntry>>(
  (ref) => ref.watch(symbolRepositoryProvider).watch(),
);

/// Standalone symbols as an id -> entry map, for resolving a set's chosen
/// symbol or a watermark reference once those render sites exist.
final symbolsMapProvider = Provider<Map<String, SymbolEntry>>((ref) {
  final async = ref.watch(symbolsProvider);
  return async.maybeWhen(
    data: (list) => {for (final s in list) s.id: s},
    orElse: () => const <String, SymbolEntry>{},
  );
});

/// Data API for the Frames library (shared 9-slice border sprites).
final frameRepositoryProvider = Provider<FrameRepository>(
  (ref) => FrameRepository(ref.watch(databaseProvider)),
);

/// Live list of frames (for the Customization "Frames" tab and the picker).
final framesProvider = StreamProvider<List<FrameEntry>>(
  (ref) => ref.watch(frameRepositoryProvider).watch(),
);

/// Frames as an id -> entry map, for resolving a border aspect's frame
/// reference at compose time (live value wins; the snapshot covers deletes).
/// Empty while loading — the snapshot renders in the meantime.
final framesMapProvider = Provider<Map<String, FrameEntry>>((ref) {
  final async = ref.watch(framesProvider);
  return async.maybeWhen(
    data: (list) => {for (final f in list) f.id: f},
    orElse: () => const <String, FrameEntry>{},
  );
});

/// The visible tab index in the app shell, so screens can navigate the shell
/// (e.g. Collection opening a card in the Card Editor tab). Order matches
/// AppShell: 0 Collection · 1 Template · 2 Card · 3 Customize · 4 Settings.
const int kCardEditorTabIndex = 2;
const int kSettingsTabIndex = 4; // Settings is appended (kShowSettings)

class SelectedTab extends Notifier<int> {
  @override
  int build() => 0;

  void set(int index) => state = index;
}

final selectedTabProvider =
    NotifierProvider<SelectedTab, int>(SelectedTab.new);
