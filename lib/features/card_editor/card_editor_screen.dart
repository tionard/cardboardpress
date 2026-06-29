// lib/features/card_editor/card_editor_screen.dart
//
// Card Editor: preview + category rail + settings, arranged responsively. The
// "Card" category is the text content form; "Art" picks/removes the card's
// artwork. Art images are decoded by this widget and handed to the renderer via
// CardRefs.images — paintCard stays synchronous and never loads files itself.
//
// Layout (one set of widgets, switched by width breakpoint):
//   * Phone (<720) — a TEMPLATE header on top, the preview filling the area
//     above a slide-up DOCK (PreviewDockScaffold). The dock's grab handle drags
//     to resize/collapse; the preview shrinks/grows to fill the space left over.
//   * Tablet/desktop (>=720) — the same header on top, then preview · rail ·
//     settings side-by-side (the established Windows arrangement).
//
// Split across parts (one library): the State + its logic + build live here;
// the per-category settings panels and the leaf widgets (rail, swatch tile)
// live in card_editor_panels.dart / card_editor_widgets.dart as, respectively,
// an extension on _CardEditorBodyState and plain widget classes.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/card_exporter.dart';
import '../../data/card_repository.dart';
import '../../data/image_store.dart';
import '../../model/card_model.dart';
import '../../model/sample_card.dart';
import '../../state/providers.dart';
import '../../state/settings.dart';
import '../../widgets/card_preview.dart';
import '../../widgets/labeled_slider.dart';
import '../../widgets/preview_dock.dart';
import '../../widgets/swatch_picker.dart';

part 'card_editor_panels.dart';
part 'card_editor_widgets.dart';

class CardEditorScreen extends ConsumerWidget {
  const CardEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(cardsProvider);
    final templates = ref.watch(templatesProvider).maybeWhen(
          data: (list) => list,
          orElse: () => const <TemplateEntry>[],
        );
    final templatesMap = ref.watch(templatesMapProvider);
    final palette = ref.watch(paletteMapProvider);
    final swatches = ref.watch(paletteProvider).maybeWhen(
          data: (list) => list,
          orElse: () => const <PaletteSwatch>[],
        );
    final sets = ref.watch(setsProvider).maybeWhen(
          data: (list) => list,
          orElse: () => const <SetEntry>[],
        );
    final rarities = ref.watch(raritiesProvider).maybeWhen(
          data: (list) => list,
          orElse: () => const <RarityEntry>[],
        );

    return cardsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load cards:\n$e')),
      data: (cards) {
        if (cards.isEmpty) {
          return const Center(child: Text('No cards yet.'));
        }
        final selectedId = ref.watch(currentCardIdProvider);
        final card = cards.firstWhere((c) => c.id == selectedId,
            orElse: () => cards.first);
        return _CardEditorBody(
          key: ValueKey(card.id),
          card: card,
          allCards: cards,
          templates: templates,
          templatesMap: templatesMap,
          palette: palette,
          swatches: swatches,
          sets: sets,
          rarities: rarities,
          symbolMap: ref.watch(textSymbolMapProvider),
          symbolsById: ref.watch(symbolsMapProvider),
          repo: ref.read(cardRepositoryProvider),
          imageStore: ref.read(imageStoreProvider),
          exporter: ref.read(cardExporterProvider),
          proUnlocked: ref.watch(proUnlockedProvider),
          onLeave: () => ref.read(selectedTabProvider.notifier).set(0),
          onOpenSettings: () =>
              ref.read(selectedTabProvider.notifier).set(kSettingsTabIndex),
          active: ref.watch(selectedTabProvider) == kCardEditorTabIndex,
          onOpenCard: (id) =>
              ref.read(currentCardIdProvider.notifier).set(id),
        );
      },
    );
  }
}

enum _Cat { card, art, color, set, export }

const _catLabels = {
  _Cat.card: 'Card',
  _Cat.art: 'Art',
  _Cat.color: 'Color',
  _Cat.set: 'Set',
  _Cat.export: 'Export',
};
const _catIcons = {
  _Cat.card: Icons.style_outlined,
  _Cat.art: Icons.image_outlined,
  _Cat.color: Icons.palette_outlined,
  _Cat.set: Icons.folder_outlined,
  _Cat.export: Icons.ios_share_outlined,
};

class _CardEditorBody extends StatefulWidget {
  final CardEntry card;
  final List<CardEntry> allCards;
  final List<TemplateEntry> templates;
  final Map<String, TemplateData> templatesMap;
  final Map<String, ColorValue> palette;
  final List<PaletteSwatch> swatches;
  final List<SetEntry> sets;
  final List<RarityEntry> rarities;
  final Map<String, String> symbolMap; // text-symbol tag (lower) -> imageId
  final Map<String, SymbolEntry> symbolsById; // standalone symbol id -> entry
  final CardRepository repo;
  final ImageStore imageStore;
  final CardExporter exporter;
  final bool proUnlocked; // gates export DPI + watermark
  final VoidCallback onLeave; // return to the Collection tab
  final VoidCallback onOpenSettings; // jump to the Settings tab (Pro upsell)
  final bool active; // is the Card Editor the visible tab? (gates back handling)
  final ValueChanged<String> onOpenCard; // switch the editor to another card id

  const _CardEditorBody({
    super.key,
    required this.card,
    required this.allCards,
    required this.templates,
    required this.templatesMap,
    required this.palette,
    required this.swatches,
    required this.sets,
    required this.rarities,
    required this.symbolMap,
    required this.symbolsById,
    required this.repo,
    required this.imageStore,
    required this.exporter,
    required this.proUnlocked,
    required this.onLeave,
    required this.onOpenSettings,
    required this.active,
    required this.onOpenCard,
  });

  @override
  State<_CardEditorBody> createState() => _CardEditorBodyState();
}

class _CardEditorBodyState extends State<_CardEditorBody> {
  late CardEntry _working;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, ui.Image> _images = {}; // imageId -> decoded image
  late final TextEditingController _artist;
  bool _dirty = false; // unsaved edits to the working copy
  bool _suppressDirty = false; // guards controller resync during revert
  _Cat _cat = _Cat.card;
  bool _exporting = false;
  int _dpi = 300; // requested export DPI (300/600); free is pinned to 300

  @override
  void initState() {
    super.initState();
    _working = widget.card;
    _artist = TextEditingController(text: _working.content.artist)
      ..addListener(_onArtistChanged);
    _syncArtImages(); // decode any art the card already references
  }

  @override
  void dispose() {
    // No autosave / flush-on-dispose: edits persist only via the Save button.
    // (This is what lets a card deleted from the Collection stay deleted instead
    // of being re-inserted when this editor body is torn down.)
    _artist.dispose();
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _CardEditorBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The live template can change underneath us (e.g. a background image was
    // added in the Template Editor). Decode any newly-referenced image; the
    // call is idempotent — already-decoded ids are skipped.
    _syncArtImages();
  }

  TemplateData get _effective => _working.effectiveTemplate(widget.templatesMap);

  // The card's set / rarity, resolved from the live lists.
  SetEntry? get _currentSet {
    for (final s in widget.sets) {
      if (s.id == _working.setId) return s;
    }
    return null;
  }

  RarityEntry? get _currentRarity {
    final id = _working.content.rarityId;
    if (id == null) return null;
    for (final r in widget.rarities) {
      if (r.id == id) return r;
    }
    return null;
  }

  // (collectorNumber, total) within the card's set, or (null, null).
  (int?, int?) get _collectorInfo {
    final setId = _working.setId;
    if (setId == null) return (null, null);
    final inSet = widget.allCards.where((c) => c.setId == setId).toList();
    final idx = inSet.indexWhere((c) => c.id == _working.id);
    if (idx < 0) return (null, null);
    return (idx + 1, inSet.length);
  }

  List<FieldSpec> get _editableFields => _effective.fields
      .where((f) => f.text != null && f.type != FieldType.footer)
      .toList();

  String? get _artFieldId {
    for (final f in _effective.fields) {
      if (f.type == FieldType.art) return f.id;
    }
    return null;
  }

  // ---- text content ----

  TextEditingController _controllerFor(FieldSpec f) {
    return _controllers.putIfAbsent(f.id, () {
      final c = TextEditingController(text: _working.content.text[f.id] ?? '');
      c.addListener(() => _onFieldChanged(f.id, c.text));
      return c;
    });
  }

  void _onFieldChanged(String fieldId, String value) {
    if (_suppressDirty) return;
    if ((_working.content.text[fieldId] ?? '') == value) return;
    _markDirty(() => _working =
        _working.copyWith(content: _working.content.withText(fieldId, value)));
  }

  /// Apply an in-memory edit and flag the working copy dirty. Nothing persists
  /// until the user taps Save (mirrors the Template Editor's working-copy model).
  void _markDirty(VoidCallback change) {
    setState(() {
      change();
      _dirty = true;
    });
  }

  void _changeTemplate(String? id) {
    if (id == null) return;
    final snapshot = widget.templatesMap[id] ?? _working.templateSnapshot;
    _markDirty(() => _working =
        _working.copyWith(templateId: id, templateSnapshot: snapshot));
    _syncArtImages();
  }

  // ---- art images ----

  Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<void> _syncArtImages() async {
    // Decode everything the composed card references — art, template bg, and
    // any {tag} symbol glyphs used in the Cost field.
    final ids = _compose().imageIdsToDecode();
    for (final imageId in ids) {
      if (_images.containsKey(imageId)) continue;
      final bytes = await widget.imageStore.load(imageId);
      if (bytes == null) continue;
      final img = await _decode(bytes);
      if (!mounted) return;
      setState(() => _images[imageId] = img);
    }
  }

  Future<void> _pickArt(String artFieldId) async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result == null) return;
    final file = result.files.first;
    final bytes = await file.readAsBytes();
    final imageId = await widget.imageStore
        .save(bytes, ext: (file.extension ?? 'png').toLowerCase());
    final img = await _decode(bytes);
    if (!mounted) return;
    setState(() {
      _images[imageId] = img;
      _working = _working.copyWith(
          content: _working.content.withArt(artFieldId, imageId));
      _dirty = true;
    });
  }

  void _removeArt(String artFieldId) {
    _markDirty(() => _working =
        _working.copyWith(content: _working.content.withArt(artFieldId, null)));
    // (The file is left on disk; orphan cleanup comes with Collection delete.)
  }

  // Called from _CardEditorPanels extension (extensions can't call setState).
  void _selectDpi(int dpi) => setState(() => _dpi = dpi);

  void _setArtTransform(String fieldId, ArtTransform t) {
    _markDirty(() => _working = _working.copyWith(
        content: _working.content.withArtTransform(fieldId, t)));
  }

  CardData _compose() {
    final (number, total) = _collectorInfo;
    return composeCard(
      _effective,
      content: _working.content,
      foil: _working.foil,
      set: _currentSet,
      rarity: _currentRarity,
      number: number,
      total: total,
      symbolImageIds: widget.symbolMap,
      symbolsById: widget.symbolsById,
    );
  }

  Future<void> _exportPng() async {
    setState(() => _exporting = true);
    try {
      final card = _compose();
      final refs = CardRefs(palette: widget.palette, images: _images);
      final path = await widget.exporter
          .exportToFile(card, refs, dpi: _dpi.toDouble(), proUnlocked: widget.proUnlocked);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(path == null ? 'Export cancelled' : 'Exported to $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // Android: save the rendered PNG straight into the photo gallery.
  Future<void> _saveToGallery() async {
    setState(() => _exporting = true);
    try {
      final card = _compose();
      final refs = CardRefs(palette: widget.palette, images: _images);
      final name = await widget.exporter
          .saveToGallery(card, refs, dpi: _dpi.toDouble(), proUnlocked: widget.proUnlocked);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved "$name" to your photos')));
    } on GalleryAccessDenied {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text(
              'Photo access was denied — enable it in Settings to save cards.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  // Android: render to a temp PNG and open the system share sheet.
  Future<void> _shareImage() async {
    setState(() => _exporting = true);
    try {
      final card = _compose();
      final refs = CardRefs(palette: widget.palette, images: _images);
      await widget.exporter
          .shareImage(card, refs, dpi: _dpi.toDouble(), proUnlocked: widget.proUnlocked);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Share failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _setTint(PaletteSwatch s) {
    _markDirty(() => _working = _working.copyWith(
        content:
            _working.content.withTint(ColorRef(id: s.id, snapshot: s.value))));
  }

  void _clearTint() {
    _markDirty(() =>
        _working = _working.copyWith(content: _working.content.withTint(null)));
  }

  void _setTintAlpha(double a) {
    _markDirty(() => _working =
        _working.copyWith(content: _working.content.withTintAlpha(a)));
  }

  void _setFoil(FoilType f) {
    _markDirty(() => _working = _working.copyWith(foil: f));
  }

  void _onArtistChanged() {
    if (_suppressDirty) return;
    if (_working.content.artist == _artist.text) return;
    _markDirty(() => _working =
        _working.copyWith(content: _working.content.withArtist(_artist.text)));
  }

  void _changeSet(String? setId) {
    _markDirty(() => _working = _working.copyWith(setId: setId));
  }

  void _setRarity(String? rarityId) {
    _markDirty(() => _working =
        _working.copyWith(content: _working.content.withRarity(rarityId)));
  }

  // ---- save / cancel / leave ----

  Future<void> _save() async {
    // save() writes the editable fields; setSet() persists membership (which
    // save() deliberately leaves untouched). Both reflect the working copy.
    await widget.repo.save(_working);
    await widget.repo.setSet(_working.id, _working.setId);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Card saved')));
  }

  /// Discard unsaved edits, snapping the working copy back to the persisted card
  /// and resyncing the text controllers (without re-marking dirty).
  void _revert() {
    setState(() {
      _working = widget.card;
      _dirty = false;
    });
    _suppressDirty = true;
    _artist.text = _working.content.artist;
    for (final entry in _controllers.entries) {
      entry.value.text = _working.content.text[entry.key] ?? '';
    }
    _suppressDirty = false;
    _syncArtImages();
  }

  /// Ask what to do about unsaved edits. Returns 'save' | 'discard' | 'cancel'
  /// (or null if dismissed, treated as cancel).
  Future<String?> _promptUnsaved() => showDialog<String>(
        context: context,
        builder: (d) => AlertDialog(
          title: const Text('Unsaved changes'),
          content: const Text('Save your changes to this card first?'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, 'cancel'),
                child: const Text('Cancel')),
            TextButton(
                onPressed: () => Navigator.pop(d, 'discard'),
                child: const Text('Discard')),
            FilledButton(
                onPressed: () => Navigator.pop(d, 'save'),
                child: const Text('Save')),
          ],
        ),
      );

  // Back arrow + Android system back both route here. Nothing persists unless
  // the user saves, so leaving with edits asks first.
  Future<void> _handleBack() async {
    if (!_dirty) {
      widget.onLeave();
      return;
    }
    final action = await _promptUnsaved();
    if (action == 'save') {
      await _save();
      widget.onLeave();
    } else if (action == 'discard') {
      _revert();
      widget.onLeave();
    }
    // cancel / dismissed → stay in the editor
  }

  /// Create a fresh card (same template + set as the current one) and open it
  /// in place, without leaving the editor. Unsaved edits prompt first.
  Future<void> _newCard() async {
    if (_dirty) {
      final action = await _promptUnsaved();
      if (action == null || action == 'cancel') return;
      if (action == 'save') await _save();
      // 'discard' → just proceed; this body is replaced when the card switches.
    }
    final id = await widget.repo.create(
      templateId: _working.templateId,
      templateSnapshot: _working.templateSnapshot,
      setId: _working.setId,
    );
    widget.onOpenCard(id);
  }

  // ---- shared chrome ----

  /// The card's display name, taken from its Name field's content.
  String _cardDisplayName() {
    for (final f in _effective.fields) {
      if (f.type == FieldType.name) {
        final t = (_working.content.text[f.id] ?? '').trim();
        if (t.isNotEmpty) return t;
      }
    }
    return 'Untitled card';
  }

  /// Header with a back arrow (to Collection), the card name, and Save/Cancel.
  /// Save is enabled only when there are unsaved edits; Cancel reverts them.
  Widget _cardHeader() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 4),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Back to Collection',
              icon: const Icon(Icons.arrow_back),
              onPressed: _handleBack,
            ),
            Flexible(
              child: Text(
                _cardDisplayName(),
                style: Theme.of(context).textTheme.titleMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'CARD',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
            ),
            const Spacer(),
            IconButton(
              tooltip: 'New card',
              icon: const Icon(Icons.note_add_outlined),
              onPressed: _newCard,
            ),
            if (_dirty)
              TextButton(onPressed: _revert, child: const Text('Cancel')),
            const SizedBox(width: 4),
            FilledButton(
              onPressed: _dirty ? _save : null,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// The TEMPLATE header row (picker) shown above the preview on every layout.
  /// Moved here from the Card settings panel so there is one picker, always in
  /// the same place, matching the phone wireframes.
  Widget _templateHeader() {
    final scheme = Theme.of(context).colorScheme;
    final currentId = widget.templates.any((t) => t.id == _working.templateId)
        ? _working.templateId
        : null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
      child: Row(
        children: [
          Text(
            'TEMPLATE',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
          ),
          const Spacer(),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isDense: true,
                  isExpanded: true,
                  value: currentId,
                  hint: const Text('No template'),
                  icon: const Icon(Icons.expand_more, size: 20),
                  borderRadius: BorderRadius.circular(12),
                  items: [
                    for (final t in widget.templates)
                      DropdownMenuItem(
                        value: t.id,
                        child:
                            Text(t.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  // Show a little template glyph beside the name in the closed
                  // state, like the pill in the wireframe.
                  selectedItemBuilder: (context) => [
                    for (final t in widget.templates)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.style_outlined,
                              size: 16, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(t.name,
                                overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                  ],
                  onChanged: _changeTemplate,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A preview that fits the card into whatever box it is handed — used on the
  /// phone so the card scales as the dock grows/shrinks. Keeps the card's
  /// aspect ratio, constrained by both the available width and height.
  Widget _fittingPreview(CardData card, CardRefs refs) {
    final aspect = card.widthInches / card.heightInches;
    return LayoutBuilder(
      builder: (context, c) {
        const pad = 16.0;
        final double availW = c.maxWidth - pad * 2;
        final double availH = c.maxHeight - pad * 2;
        if (availW <= 0 || availH <= 0) return const SizedBox.shrink();
        double w = availW;
        if (w / aspect > availH) w = availH * aspect; // height-constrained
        return Padding(
          padding: const EdgeInsets.all(pad),
          child: Center(child: CardPreview(card: card, refs: refs, width: w)),
        );
      },
    );
  }

  // ---- layout ----

  @override
  Widget build(BuildContext context) {
    final refs = CardRefs(palette: widget.palette, images: _images);
    final card = _compose();

    return PopScope(
      // Only intercept Back while this tab is the visible one — every tab lives
      // in the shell's IndexedStack, so an always-on PopScope would swallow Back
      // from other tabs too.
      canPop: !widget.active,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && widget.active) _handleBack();
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;

          if (wide) {
            // Tablet / desktop: header on top, then preview · rail · settings.
            final preview = Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: CardPreview(card: card, refs: refs, width: 300),
              ),
            );
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _cardHeader(),
                _templateHeader(),
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 5, child: preview),
                      _Rail(
                          vertical: true,
                          selected: _cat,
                          onSelect: (c) => setState(() => _cat = c)),
                      Expanded(
                        flex: 4,
                        child: Material(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHigh,
                          child: _settings(),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }

          // Phone: header on top, preview filling the space above a slide-up dock.
          return PreviewDockScaffold(
            header: Column(
              mainAxisSize: MainAxisSize.min,
              children: [_cardHeader(), _templateHeader()],
            ),
            preview: _fittingPreview(card, refs),
            dock: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Rail(
                  vertical: true,
                  scroll: true,
                  selected: _cat,
                  onSelect: (c) => setState(() => _cat = c),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _settings()),
              ],
            ),
          );
        },
      ),
    );
  }
}
