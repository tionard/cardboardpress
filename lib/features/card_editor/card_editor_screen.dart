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

import 'dart:async';
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
import '../../widgets/card_preview.dart';
import '../../widgets/preview_dock.dart';

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
  });

  @override
  State<_CardEditorBody> createState() => _CardEditorBodyState();
}

class _CardEditorBodyState extends State<_CardEditorBody> {
  late CardEntry _working;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, ui.Image> _images = {}; // imageId -> decoded image
  late final TextEditingController _artist;
  Timer? _saveTimer;
  _Cat _cat = _Cat.card;
  bool _exporting = false;

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
    _saveTimer?.cancel();
    widget.repo.save(_working);
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
    if ((_working.content.text[fieldId] ?? '') == value) return;
    setState(() => _working =
        _working.copyWith(content: _working.content.withText(fieldId, value)));
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
        const Duration(milliseconds: 400), () => widget.repo.save(_working));
  }

  void _changeTemplate(String? id) {
    if (id == null) return;
    final snapshot = widget.templatesMap[id] ?? _working.templateSnapshot;
    setState(() => _working =
        _working.copyWith(templateId: id, templateSnapshot: snapshot));
    widget.repo.save(_working);
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
    });
    widget.repo.save(_working);
  }

  void _removeArt(String artFieldId) {
    setState(() => _working =
        _working.copyWith(content: _working.content.withArt(artFieldId, null)));
    widget.repo.save(_working);
    // (The file is left on disk; orphan cleanup comes with Collection delete.)
  }

  void _setArtTransform(String fieldId, ArtTransform t) {
    setState(() => _working = _working.copyWith(
        content: _working.content.withArtTransform(fieldId, t)));
    _scheduleSave();
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
      final path = await widget.exporter.exportToFile(card, refs);
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
      final name = await widget.exporter.saveToGallery(card, refs);
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
      await widget.exporter.shareImage(card, refs);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Share failed: $e')));
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _setTint(PaletteSwatch s) {
    setState(() => _working = _working.copyWith(
        content:
            _working.content.withTint(ColorRef(id: s.id, snapshot: s.value))));
    widget.repo.save(_working);
  }

  void _clearTint() {
    setState(() =>
        _working = _working.copyWith(content: _working.content.withTint(null)));
    widget.repo.save(_working);
  }

  void _setTintAlpha(double a) {
    setState(() => _working =
        _working.copyWith(content: _working.content.withTintAlpha(a)));
    _scheduleSave();
  }

  void _setFoil(FoilType f) {
    setState(() => _working = _working.copyWith(foil: f));
    widget.repo.save(_working);
  }

  void _onArtistChanged() {
    if (_working.content.artist == _artist.text) return;
    setState(() => _working =
        _working.copyWith(content: _working.content.withArtist(_artist.text)));
    _scheduleSave();
  }

  void _changeSet(String? setId) {
    setState(() => _working = _working.copyWith(setId: setId));
    widget.repo.setSet(_working.id, setId);
  }

  void _setRarity(String? rarityId) {
    setState(() => _working =
        _working.copyWith(content: _working.content.withRarity(rarityId)));
    widget.repo.save(_working);
  }

  // ---- shared chrome ----

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

    return LayoutBuilder(
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
                        color:
                            Theme.of(context).colorScheme.surfaceContainerLow,
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
          header: _templateHeader(),
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
    );
  }
}
