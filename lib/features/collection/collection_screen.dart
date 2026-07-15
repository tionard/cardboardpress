// lib/features/collection/collection_screen.dart
//
// Collection v2 — two levels inside one tab:
//
//   * ROOT: a browser of folders (sets). "Unassigned" leads and is permanent.
//     Large / Grid views, a density slider (Grid), search across all folders and
//     card names, and a top-right "New Set" action. Long-pressing a folder enters
//     selection mode (the action becomes "Cancel"); selected folders get the
//     accent ring + check and a docked Delete bar.
//
//   * OPENED SET: tap a folder to drill in to its cards. A back chevron, the set
//     name, a settings cog, search within the set, and a top-right "New Card"
//     action. Long-pressing a card enters selection mode (Export / Share / Delete
//     docked bar); each card also has a ⋯ menu (Edit / Duplicate / Move / Export /
//     Share / Delete).
//
// Navigation is an in-tab state switch (like the Template Editor's browser/editor),
// NOT a pushed route — so we never get a second editor instance fighting over
// autosave, and Android Back is handled by PopScope (exit selection → close set →
// leave tab).
//
// The screen is one library split across part files: this root holds all state and
// the action/mutation logic; the parts build the two views and the leaf widgets.

import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/card_exporter.dart';
import '../../data/image_store.dart';
import '../../model/card_model.dart';
import '../../model/layer_migration.dart';
import '../../model/card_json.dart';
import '../../model/sample_card.dart';
import '../../rendering/export.dart';
import '../../rendering/sheet_export.dart';
import '../../rendering/sheet_pdf.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../../widgets/decoded_card_preview.dart';
import '../../widgets/labeled_slider.dart';
import '../customization/symbol_picker.dart';

part 'collection_export.dart';
part 'collection_root.dart';
part 'collection_set.dart';
part 'collection_widgets.dart';

/// The permanent "Unassigned" bucket has no row, so it gets a sentinel key when
/// opened. Real folders are keyed by their set id.
const String _kUnassignedKey = '__unassigned__';

/// The two ways the root browser lays folders out.
enum _View { large, grid }

/// How the set folders are ordered (Unassigned always leads regardless).
enum _SetSort { created, name, year }

class CollectionScreen extends ConsumerStatefulWidget {
  const CollectionScreen({super.key});

  @override
  ConsumerState<CollectionScreen> createState() => _CollectionScreenState();
}

class _CollectionScreenState extends ConsumerState<CollectionScreen> {
  // ---- navigation ----
  // null => root browser; otherwise the key of the opened folder.
  String? _openKey;

  // ---- root view options ----
  _View _view = _View.large;
  double _density = 3; // grid columns (root grid + opened set), 2..5
  _SetSort _sort = _SetSort.created; // newest-created first by default

  // ---- search ----
  final TextEditingController _searchCtl = TextEditingController();
  String _query = '';

  // ---- selection ----
  // While selecting, this holds folder keys (at root) or card ids (in a set).
  // The two are never active at once, so one set suffices; cleared on navigation.
  final Set<String> _selected = {};
  bool _selecting = false;

  // ---- async export guard ----
  bool _busy = false;

  // ---- reorder mode (opened set only) ----
  // A dedicated mode (toggled from the set header) so dragging doesn't fight the
  // long-press that enters selection. _reorderIds is a local mirror of the set's
  // card order for snappy drags; the persisted order re-emits to match.
  bool _reordering = false;
  List<String> _reorderIds = const [];

  @override
  void initState() {
    super.initState();
    _searchCtl.addListener(() => _setQuery(_searchCtl.text));
  }

  @override
  void dispose() {
    _searchCtl.dispose();
    super.dispose();
  }

  // ---- small state transitions (extensions can't call setState directly) ----

  void _setView(_View v) => setState(() => _view = v);
  void _setBusy(bool v) => setState(() => _busy = v);
  void _setDensity(double d) => setState(() => _density = d);
  void _setSort(_SetSort s) => setState(() => _sort = s);

  void _setQuery(String q) {
    if (q == _query) return;
    setState(() => _query = q);
  }

  void _openFolder(String key) {
    setState(() {
      _openKey = key;
      _selecting = false;
      _selected.clear();
      _reordering = false;
      _reorderIds = const [];
      _searchCtl.clear();
      _query = '';
    });
  }

  void _closeFolder() {
    setState(() {
      _openKey = null;
      _selecting = false;
      _selected.clear();
      _reordering = false;
      _reorderIds = const [];
      _searchCtl.clear();
      _query = '';
    });
  }

  void _cancelSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _enterSelection(String firstId) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(firstId);
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selected.contains(id)) {
        _selected.remove(id);
        if (_selected.isEmpty) _selecting = false;
      } else {
        _selected.add(id);
      }
    });
  }

  void _enterReorder(List<String> ids) {
    setState(() {
      _reordering = true;
      _reorderIds = ids;
      _selecting = false;
      _selected.clear();
      _searchCtl.clear();
      _query = '';
    });
  }

  void _exitReorder() {
    setState(() {
      _reordering = false;
      _reorderIds = const [];
    });
  }

  /// Apply a ReorderableListView move to the local mirror and persist it. The
  /// renderer's collector numbers follow this order (when numbering is on).
  void _applyReorder(int oldIndex, int newIndex, String? setId) {
    final ids = List<String>.from(_reorderIds);
    if (oldIndex < 0 || oldIndex >= ids.length) return;
    // ReorderableListView reports newIndex as an insertion point; adjust when
    // moving an item downward.
    if (newIndex > oldIndex) newIndex -= 1;
    final moved = ids.removeAt(oldIndex);
    newIndex = newIndex.clamp(0, ids.length);
    ids.insert(newIndex, moved);
    setState(() => _reorderIds = ids);
    ref.read(cardRepositoryProvider).reorderInSet(setId, ids);
  }

  // ---- build ----

  @override
  Widget build(BuildContext context) {
    final cardsAsync = ref.watch(cardsProvider);
    final setsAsync = ref.watch(setsProvider);

    final ctx = _CardCtx(
      templates: ref.watch(templatesMapProvider),
      palette: ref.watch(paletteMapProvider),
      rarities: ref.watch(raritiesMapProvider),
      symbols: ref.watch(symbolsMapProvider),
      textSymbols: ref.watch(textSymbolMapProvider),
      frames: ref.watch(framesMapProvider),
      imageStore: ref.read(imageStoreProvider),
    );

    final body = cardsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load cards:\n$e')),
      data: (cards) => setsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load sets:\n$e')),
        data: (sets) => _buildBody(cards, sets, ctx),
      ),
    );

    // Intercept Back while we have somewhere to go inside the tab.
    return PopScope(
      canPop: _openKey == null && !_selecting && !_reordering,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_reordering) {
          _exitReorder();
        } else if (_selecting) {
          _cancelSelection();
        } else if (_openKey != null) {
          _closeFolder();
        }
      },
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            body,
            if (_busy)
              const Positioned.fill(
                child: ColoredBox(
                  color: Color(0x66000000),
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(
      List<CardEntry> cards, List<SetEntry> sets, _CardCtx ctx) {
    final folders = _folders(cards, sets);

    if (_openKey == null) return _buildRoot(folders, ctx);

    _Folder? open;
    for (final f in folders) {
      if (f.key == _openKey) {
        open = f;
        break;
      }
    }
    if (open == null) {
      // The set was deleted while open — fall back to the root next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _closeFolder();
      });
      return const SizedBox.shrink();
    }
    return _buildOpenedSet(open, ctx);
  }

  /// Unassigned first, then each persisted set in the chosen sort order.
  List<_Folder> _folders(List<CardEntry> cards, List<SetEntry> sets) {
    final sorted = [...sets];
    switch (_sort) {
      case _SetSort.created:
        // position increments on creation (no set reordering), so descending
        // position == newest created first.
        sorted.sort((a, b) => b.position.compareTo(a.position));
        break;
      case _SetSort.name:
        sorted.sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
        break;
      case _SetSort.year:
        sorted.sort((a, b) {
          final byYear = b.year.compareTo(a.year); // newest year first
          return byYear != 0
              ? byYear
              : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
        break;
    }
    return [
      _Folder(
        key: _kUnassignedKey,
        set: null,
        title: 'Unassigned',
        abbr: '',
        cards: cards.where((c) => c.setId == null).toList(),
      ),
      for (final s in sorted)
        _Folder(
          key: s.id,
          set: s,
          title: s.name,
          abbr: s.abbreviation,
          cards: cards.where((c) => c.setId == s.id).toList(),
        ),
    ];
  }

  // ---- compose / decode (for thumbnails and export) ----

  /// The card's display name (its name LAYER's content — the Name field's
  /// layer, or the first free text layer exposed to the Card tab), so cards on
  /// pure-layer templates still get a name in the Collection.
  String _cardName(CardEntry card, _CardCtx ctx) {
    final t = card.effectiveTemplate(ctx.templates);
    final id = nameTextLayerId(t);
    return id == null ? '' : (card.content.text[id] ?? '');
  }

  /// Compose [card] (member [index] of [folder]) into a renderable CardData,
  /// resolving collector number/total only when the set has numbering on.
  CardData _compose(_Folder folder, CardEntry card, int index, _CardCtx ctx) {
    final set = folder.set;
    final numberingOn = set != null && set.numbering;
    return composeCard(
      card.effectiveTemplate(ctx.templates),
      content: card.content,
      foil: card.foil,
      set: set,
      rarity: ctx.rarities[card.content.rarityId],
      number: numberingOn ? index + 1 : null,
      total: numberingOn ? folder.cards.length : null,
      symbolImageIds: ctx.textSymbols,
      symbolsById: ctx.symbols,
      frames: ctx.frames,
    );
  }

  /// Decode every image a composed card references, into the CardRefs the
  /// exporter needs. (Thumbnails decode themselves via DecodedCardPreview; the
  /// PNG export path needs its own decode pass.)
  Future<CardRefs> _decodeRefs(CardData card, _CardCtx ctx) async {
    final images = <String, ui.Image>{};
    for (final id in card.imageIdsToDecode()) {
      if (images.containsKey(id)) continue;
      final bytes = await ctx.imageStore.load(id);
      if (bytes == null) continue;
      final codec = await ui.instantiateImageCodec(bytes);
      images[id] = (await codec.getNextFrame()).image;
    }
    return CardRefs(palette: ctx.palette, images: images);
  }

  // ---- helpers used by bulk actions ----

  _Folder? _currentFolder() {
    final cards = ref.read(cardsProvider).maybeWhen(data: (l) => l, orElse: () => const <CardEntry>[]);
    final sets = ref.read(setsProvider).maybeWhen(data: (l) => l, orElse: () => const <SetEntry>[]);
    for (final f in _folders(cards, sets)) {
      if (f.key == _openKey) return f;
    }
    return null;
  }

  // ---- card actions ----

  void _openEditor(String cardId) {
    // Select the card and switch to the Card Editor tab — one editor instance,
    // never a pushed duplicate (which would fight over autosave).
    ref.read(currentCardIdProvider.notifier).set(cardId);
    ref.read(selectedTabProvider.notifier).set(kCardEditorTabIndex);
  }

  Future<void> _newCard(String? setId) async {
    final templates = ref.read(templatesProvider).maybeWhen(
          data: (l) => l,
          orElse: () => const <TemplateEntry>[],
        );
    if (templates.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Make a template first (Template tab).')));
      return;
    }
    final t = templates.first;
    final id = await ref
        .read(cardRepositoryProvider)
        .create(templateId: t.id, templateSnapshot: t.data, setId: setId);
    _openEditor(id);
  }

  void _cardMenu(CardEntry card, _Folder folder, int index, _CardCtx ctx) {
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(sheet);
                _openEditor(card.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Duplicate'),
              onTap: () {
                Navigator.pop(sheet);
                ref.read(cardRepositoryProvider).duplicate(card);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Move to…'),
              onTap: () {
                Navigator.pop(sheet);
                _moveCard(card);
              },
            ),
            ListTile(
              leading: Icon(isAndroid
                  ? Icons.photo_library_outlined
                  : Icons.download_outlined),
              title: Text(isAndroid ? 'Export (save to Photos)' : 'Export PNG…'),
              onTap: () {
                Navigator.pop(sheet);
                _exportOne(_compose(folder, card, index, ctx), folder.set);
              },
            ),
            ListTile(
              leading: const Icon(Icons.ios_share_outlined),
              title: const Text('Share…'),
              onTap: () {
                Navigator.pop(sheet);
                _shareOne(_compose(folder, card, index, ctx), folder.set, ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(sheet);
                _deleteCards([card.id], confirmEvenIfSingle: true);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _moveCard(CardEntry card) {
    final sets = ref.read(setsProvider).maybeWhen(
          data: (l) => l,
          orElse: () => const <SetEntry>[],
        );
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Unassigned'),
              selected: card.setId == null,
              onTap: () {
                ref.read(cardRepositoryProvider).setSet(card.id, null);
                Navigator.pop(sheet);
              },
            ),
            for (final s in sets)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(s.name),
                selected: card.setId == s.id,
                onTap: () {
                  ref.read(cardRepositoryProvider).setSet(card.id, s.id);
                  Navigator.pop(sheet);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteCards(List<String> ids,
      {bool confirmEvenIfSingle = false}) async {
    if (ids.isEmpty) return;
    final many = ids.length > 1;
    if (many || confirmEvenIfSingle) {
      final ok = await _confirm(
        title: many ? 'Delete ${ids.length} cards?' : 'Delete card?',
        message: 'This permanently removes '
            '${many ? 'these cards' : 'this card'}. This cannot be undone.',
        danger: 'Delete',
      );
      if (ok != true) return;
    }
    final all = ref.read(cardsProvider).maybeWhen(
          data: (l) => l,
          orElse: () => const <CardEntry>[],
        );
    final idSet = ids.toSet();
    final removed = all.where((c) => idSet.contains(c.id)).toList();
    final survivors = all.where((c) => !idSet.contains(c.id)).toList();

    final repo = ref.read(cardRepositoryProvider);
    await repo.deleteMany(ids);
    await _cleanupOrphanImages(removed: removed, survivors: survivors);
    if (mounted && _selecting) _cancelSelection();
  }

  /// Delete image files owned by [removed] cards that nothing else still
  /// references. We only ever consider the *art* of the just-deleted cards as
  /// deletion candidates, and we keep any image still referenced by a surviving
  /// card (duplicates share an art id), a template background, or a symbol — so
  /// this can never break a live card or wipe a library asset.
  Future<void> _cleanupOrphanImages({
    required List<CardEntry> removed,
    required List<CardEntry> survivors,
  }) async {
    if (removed.isEmpty) return;

    final candidates = <String>{};
    for (final c in removed) {
      candidates.addAll(c.content.art.values);
    }
    if (candidates.isEmpty) return;

    final protected = <String>{};
    for (final c in survivors) {
      protected.addAll(c.content.art.values);
      final bg = c.templateSnapshot.bgImageId;
      if (bg != null) protected.add(bg);
    }
    for (final t in ref.read(templatesMapProvider).values) {
      final bg = t.bgImageId;
      if (bg != null) protected.add(bg);
    }
    for (final s in ref.read(symbolsMapProvider).values) {
      protected.add(s.imageId);
    }
    protected.addAll(ref.read(textSymbolMapProvider).values);

    final store = ref.read(imageStoreProvider);
    for (final id in candidates) {
      if (!protected.contains(id)) {
        await store.delete(id);
      }
    }
  }

  // ---- bulk card actions (operate on the opened folder's selection) ----

  Future<void> _bulkDeleteCards() => _deleteCards(_selected.toList());

  Future<void> _bulkExport() async {
    final folder = _currentFolder();
    if (folder == null) return;
    final ctx = _ctxNow();
    final picked = <(_Folder, CardEntry, int)>[];
    for (var i = 0; i < folder.cards.length; i++) {
      if (_selected.contains(folder.cards[i].id)) {
        picked.add((folder, folder.cards[i], i));
      }
    }
    if (picked.isEmpty) return;

    setState(() => _busy = true);
    var done = 0;
    String? error;
    try {
      for (final (f, card, idx) in picked) {
        final data = _compose(f, card, idx, ctx);
        final refs = await _decodeRefs(data, ctx);
        final abbr = _abbrOf(f.set);
        final exporter = ref.read(cardExporterProvider);
        if (defaultTargetPlatform == TargetPlatform.android) {
          await exporter.saveToGallery(data, refs, setAbbr: abbr, proUnlocked: ref.read(proUnlockedProvider));
        } else {
          final path = await exporter.exportToFile(data, refs, setAbbr: abbr, proUnlocked: ref.read(proUnlockedProvider));
          if (path == null) break; // user cancelled the Save-as dialog
        }
        done++;
      }
    } on GalleryAccessDenied {
      error = 'Photo access was denied — enable it in Settings.';
    } catch (e) {
      error = 'Export failed: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    final android = defaultTargetPlatform == TargetPlatform.android;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(error ??
          (android
              ? 'Saved $done card${done == 1 ? '' : 's'} to your photos'
              : 'Exported $done card${done == 1 ? '' : 's'}')),
    ));
    if (error == null) _cancelSelection();
  }

  Future<void> _bulkShare() async {
    final folder = _currentFolder();
    if (folder == null) return;
    final ctx = _ctxNow();
    // share_plus can take multiple files at once, but our exporter shares one at
    // a time; share them sequentially so the user gets a sheet per card.
    setState(() => _busy = true);
    try {
      for (var i = 0; i < folder.cards.length; i++) {
        final card = folder.cards[i];
        if (!_selected.contains(card.id)) continue;
        final data = _compose(folder, card, i, ctx);
        await _shareOne(data, folder.set, ctx, silent: true);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Share failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) _cancelSelection();
  }

  // ---- single export / share ----

  Future<void> _exportOne(CardData data, SetEntry? set) async {
    setState(() => _busy = true);
    final ctx = _ctxNow();
    try {
      final refs = await _decodeRefs(data, ctx);
      final abbr = _abbrOf(set);
      final exporter = ref.read(cardExporterProvider);
      if (defaultTargetPlatform == TargetPlatform.android) {
        final name = await exporter.saveToGallery(data, refs, setAbbr: abbr, proUnlocked: ref.read(proUnlockedProvider));
        _snack('Saved "$name" to your photos');
      } else {
        final path = await exporter.exportToFile(data, refs, setAbbr: abbr, proUnlocked: ref.read(proUnlockedProvider));
        _snack(path == null ? 'Export cancelled' : 'Exported to $path');
      }
    } on GalleryAccessDenied {
      _snack('Photo access was denied — enable it in Settings to save cards.');
    } catch (e) {
      _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareOne(CardData data, SetEntry? set, _CardCtx ctx,
      {bool silent = false}) async {
    if (!silent) setState(() => _busy = true);
    try {
      final refs = await _decodeRefs(data, ctx);
      await ref
          .read(cardExporterProvider)
          .shareImage(data, refs,
              setAbbr: _abbrOf(set), proUnlocked: ref.read(proUnlockedProvider));
    } catch (e) {
      if (!silent) _snack('Share failed: $e');
      if (silent) rethrow;
    } finally {
      if (!silent && mounted) setState(() => _busy = false);
    }
  }

  // ---- set / folder actions ----

  Future<void> _newSet() async {
    final nameCtl = TextEditingController();
    final abbrCtl = TextEditingController();
    final create = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('New set'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: abbrCtl,
              maxLength: 5,
              decoration: const InputDecoration(
                  labelText: 'Abbreviation (footer)', counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (create == true) {
      await ref
          .read(setRepositoryProvider)
          .create(nameCtl.text, abbreviation: abbrCtl.text);
    }
    nameCtl.dispose();
    abbrCtl.dispose();
  }

  void _openSetSettings(SetEntry set) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SetSettingsSheet(
        set: set,
        onDelete: () => _deleteSet(set),
      ),
    );
  }

  /// Single-folder delete with the spec's three-way choice when it has cards.
  Future<void> _deleteSet(SetEntry set) async {
    final cards = ref.read(cardsProvider).maybeWhen(data: (l) => l, orElse: () => const <CardEntry>[]);
    final inSet = cards.where((c) => c.setId == set.id).toList();

    if (inSet.isEmpty) {
      final ok = await _confirm(
        title: 'Delete "${set.name}"?',
        message: 'This empty set will be removed.',
        danger: 'Delete',
      );
      if (ok == true) await ref.read(setRepositoryProvider).delete(set.id);
      return;
    }

    if (!mounted) return;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Delete "${set.name}"?'),
        content: Text(
            'This set holds ${inSet.length} card${inSet.length == 1 ? '' : 's'}. '
            'Delete the cards too, or keep them by moving them to Unassigned?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, 'cancel'),
              child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(dialog, 'folder'),
            child: const Text('Delete folder only'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(dialog, 'all'),
            child: const Text('Delete all'),
          ),
        ],
      ),
    );

    if (choice == null || choice == 'cancel') return;

    final cardRepo = ref.read(cardRepositoryProvider);
    final setRepo = ref.read(setRepositoryProvider);

    if (choice == 'all') {
      if (!mounted) return;
      final sure = await _confirm(
        title: 'Are you sure?',
        message:
            'All ${inSet.length} cards in "${set.name}" will be permanently removed.',
        danger: 'Delete all',
      );
      if (sure != true) return;
      final all = ref.read(cardsProvider).maybeWhen(
            data: (l) => l,
            orElse: () => const <CardEntry>[],
          );
      final inSetIds = inSet.map((c) => c.id).toSet();
      final survivors = all.where((c) => !inSetIds.contains(c.id)).toList();
      await cardRepo.deleteMany(inSetIds.toList());
      await _cleanupOrphanImages(removed: inSet, survivors: survivors);
    } else {
      // 'folder' — keep the cards, drop them into Unassigned.
      for (final c in inSet) {
        await cardRepo.setSet(c.id, null);
      }
    }
    await setRepo.delete(set.id);
  }

  /// Bulk folder delete (the root selection bar). To avoid destroying cards in
  /// bulk, this always keeps cards (moves them to Unassigned) and removes the
  /// folders — the single-folder cog still offers "Delete all".
  Future<void> _bulkDeleteFolders() async {
    final ids = _selected.toList();
    if (ids.isEmpty) return;
    final cards = ref.read(cardsProvider).maybeWhen(data: (l) => l, orElse: () => const <CardEntry>[]);
    final affected = cards.where((c) => ids.contains(c.setId)).length;

    final ok = await _confirm(
      title: 'Delete ${ids.length} set${ids.length == 1 ? '' : 's'}?',
      message: affected == 0
          ? 'The selected sets will be removed.'
          : 'The selected sets will be removed. Their $affected '
              'card${affected == 1 ? '' : 's'} move to Unassigned (not deleted).',
      danger: 'Delete',
    );
    if (ok != true) return;

    final cardRepo = ref.read(cardRepositoryProvider);
    final setRepo = ref.read(setRepositoryProvider);
    for (final id in ids) {
      for (final c in cards.where((c) => c.setId == id)) {
        await cardRepo.setSet(c.id, null);
      }
      await setRepo.delete(id);
    }
    if (mounted) _cancelSelection();
  }

  // ---- small shared helpers ----

  _CardCtx _ctxNow() => _CardCtx(
        templates: ref.read(templatesMapProvider),
        palette: ref.read(paletteMapProvider),
        rarities: ref.read(raritiesMapProvider),
        symbols: ref.read(symbolsMapProvider),
        textSymbols: ref.read(textSymbolMapProvider),
        frames: ref.read(framesMapProvider),
        imageStore: ref.read(imageStoreProvider),
      );

  String? _abbrOf(SetEntry? set) =>
      (set != null && set.abbreviation.isNotEmpty) ? set.abbreviation : null;

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String danger,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(danger),
          ),
        ],
      ),
    );
  }
}

/// A folder row in the Collection: a set (or the permanent Unassigned bucket)
/// plus its member cards in display order.
class _Folder {
  final String key; // _kUnassignedKey or the set id
  final SetEntry? set; // null => Unassigned
  final String title;
  final String abbr;
  final List<CardEntry> cards;
  const _Folder({
    required this.key,
    required this.set,
    required this.title,
    required this.abbr,
    required this.cards,
  });

  bool get isUnassigned => set == null;
}
