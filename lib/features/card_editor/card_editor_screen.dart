// lib/features/card_editor/card_editor_screen.dart
//
// Card Editor: preview + category rail + settings, arranged responsively. The
// "Card" category is the text content form; "Art" picks/removes the card's
// artwork. Art images are decoded by this widget and handed to the renderer via
// CardRefs.images — paintCard stays synchronous and never loads files itself.

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/card_exporter.dart';
import '../../data/card_repository.dart';
import '../../data/image_store.dart';
import '../../model/card_model.dart';
import '../../model/sample_card.dart';
import '../../state/providers.dart';
import '../../widgets/card_preview.dart';

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
    final result =
        await FilePicker.pickFiles(type: FileType.image, withData: true);
    if (result == null) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) return;
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

  // ---- layout ----

  @override
  Widget build(BuildContext context) {
    final refs = CardRefs(palette: widget.palette, images: _images);
    final card = _compose();

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        final preview = Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: CardPreview(card: card, refs: refs, width: wide ? 300 : 220),
          ),
        );

        if (wide) {
          return Row(
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
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: _settings(),
                ),
              ),
            ],
          );
        }

        return Column(
          children: [
            preview,
            _Rail(
                vertical: false,
                selected: _cat,
                onSelect: (c) => setState(() => _cat = c)),
            Expanded(child: _settings()),
          ],
        );
      },
    );
  }

  Widget _settings() {
    switch (_cat) {
      case _Cat.card:
        return _cardSettings();
      case _Cat.art:
        return _artSettings();
      case _Cat.color:
        return _colorSettings();
      case _Cat.set:
        return _setSettings();
      case _Cat.export:
        return _exportSettings();
      default:
        return Center(
          child: Text('${_catLabels[_cat]} — coming soon',
              style: Theme.of(context).textTheme.bodyMedium),
        );
    }
  }

  Widget _cardSettings() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Text('Template: '),
            DropdownButton<String>(
              value: widget.templates.any((t) => t.id == _working.templateId)
                  ? _working.templateId
                  : null,
              items: [
                for (final t in widget.templates)
                  DropdownMenuItem(value: t.id, child: Text(t.name)),
              ],
              onChanged: _changeTemplate,
            ),
          ],
        ),
        const Divider(height: 28),
        for (final f in _editableFields) ...[
          TextField(
            controller: _controllerFor(f),
            maxLines: f.type == FieldType.rules ? 4 : 1,
            decoration: InputDecoration(
              labelText: _fieldLabel(f.type),
              isDense: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
        ],
        Text(
          'Each field autosaves as you type and the preview updates live. The '
          'Footer is omitted — it shows values derived from the set and rarity.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _artSettings() {
    final artId = _artFieldId;
    if (artId == null) {
      return const Center(child: Text('This template has no Art field.'));
    }
    final imageId = _working.content.art[artId];
    final img = imageId == null ? null : _images[imageId];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SizedBox(
          height: 170,
          width: double.infinity,
          child: img != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: RawImage(image: img, fit: BoxFit.cover),
                )
              : DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: Theme.of(context).colorScheme.outlineVariant),
                  ),
                  child: const Center(child: Text('No art yet')),
                ),
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          children: [
            FilledButton.icon(
              onPressed: () => _pickArt(artId),
              icon: const Icon(Icons.upload_outlined),
              label: Text(imageId == null ? 'Pick image' : 'Replace image'),
            ),
            if (imageId != null)
              OutlinedButton.icon(
                onPressed: () => _removeArt(artId),
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove'),
              ),
          ],
        ),
        if (img != null) ...[
          const SizedBox(height: 8),
          _artTransformControls(artId),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _artist,
          decoration: const InputDecoration(
            labelText: 'Artist',
            isDense: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'The image is copied into the app and rendered through the same '
          'paintCard, so the preview and export match exactly. The artist '
          'credit is per-card content shown by the Footer.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _artTransformControls(String artId) {
    final tr = _working.content.artTransforms[artId] ?? const ArtTransform();

    Widget slider(String label, double value, double min, double max,
        ValueChanged<double> onChanged) {
      final shown = value.clamp(min, max);
      final step = (max - min) <= 0.15 ? 0.005 : 0.05;
      final divisions = ((max - min) / step).round().clamp(1, 1000);
      return Row(
        children: [
          SizedBox(
            width: 78,
            child: Text(label, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Slider(
              value: shown,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              shown.toStringAsFixed(2),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Position', style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            if (!tr.isIdentity)
              TextButton(
                onPressed: () =>
                    _setArtTransform(artId, const ArtTransform()),
                child: const Text('Reset'),
              ),
          ],
        ),
        slider('Zoom', tr.zoom, 1.0, 3.0,
            (v) => _setArtTransform(artId, tr.copyWith(zoom: v))),
        slider('Horizontal', tr.panX, -1.0, 1.0,
            (v) => _setArtTransform(artId, tr.copyWith(panX: v))),
        slider('Vertical', tr.panY, -1.0, 1.0,
            (v) => _setArtTransform(artId, tr.copyWith(panY: v))),
      ],
    );
  }

  Widget _setSettings() {
    final setId = _working.setId;
    final rarityId = _working.content.rarityId;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Set', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Unassigned'),
              selected: setId == null,
              onSelected: (_) => _changeSet(null),
            ),
            for (final s in widget.sets)
              ChoiceChip(
                label: Text(s.name),
                selected: setId == s.id,
                onSelected: (_) => _changeSet(s.id),
              ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Rarity', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('None'),
              selected: rarityId == null,
              onSelected: (_) => _setRarity(null),
            ),
            for (final r in widget.rarities)
              ChoiceChip(
                label: Text(r.abbreviation.isEmpty
                    ? r.name
                    : '${r.name} (${r.abbreviation})'),
                selected: rarityId == r.id,
                onSelected: (_) => _setRarity(r.id),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Membership and rarity feed the Footer (set abbreviation, collector '
          'number, copyright, and rarity). The Footer shows derived values, so '
          'changing these updates it live.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _colorSettings() {
    final refs = CardRefs(palette: widget.palette);
    final tintId = _working.content.tint?.id;
    final defaultBase = refs.resolveColor(_effective.baseColor);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Tint', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            _SwatchTile(
              value: defaultBase,
              label: 'Default',
              selected: _working.content.tint == null,
              onTap: _clearTint,
            ),
            for (final s in widget.swatches)
              _SwatchTile(
                value: s.value,
                label: s.name,
                selected: s.id == tintId,
                onTap: () => _setTint(s),
              ),
          ],
        ),
        if (_working.content.tint != null) ...[
          const SizedBox(height: 12),
          Row(children: [
            const SizedBox(width: 70, child: Text('Opacity')),
            Expanded(
              child: Slider(
                value: _working.content.tintAlpha.clamp(0.0, 1.0),
                divisions: 20,
                onChanged: _setTintAlpha,
              ),
            ),
            SizedBox(
              width: 40,
              child: Text(
                _working.content.tintAlpha.clamp(0.0, 1.0).toStringAsFixed(2),
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ]),
        ],
        const SizedBox(height: 20),
        Text('Foil', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            for (final f in FoilType.values)
              ChoiceChip(
                label: Text(_foilLabel(f)),
                selected: _working.foil == f,
                onSelected: (_) => _setFoil(f),
              ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Tint layers over the template\'s base colour at the opacity you set, '
          'so a partial value blends the two. "Default" removes it. Foil draws a '
          'sheen over the whole card.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _exportSettings() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Export', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Renders this card at 300 dpi (750×1050 px) through the same '
          'paintCard the preview uses, so the PNG matches exactly — including '
          'art and colours. You choose where to save it.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _exporting ? null : _exportPng,
          icon: _exporting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.download_outlined),
          label: Text(_exporting ? 'Exporting…' : 'Export PNG…'),
        ),
      ],
    );
  }
}

String _fieldLabel(FieldType t) =>
    t.name[0].toUpperCase() + t.name.substring(1);

String _foilLabel(FoilType f) =>
    f.name[0].toUpperCase() + f.name.substring(1);

// A tappable colour swatch (single or double) with a caption and selection ring.
class _SwatchTile extends StatelessWidget {
  final ColorValue value;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SwatchTile({
    required this.value,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    final outline = scheme.outlineVariant;
    final radius = BorderRadius.circular(8);

    final decoration = value.c2 == null
        ? BoxDecoration(color: value.c1, borderRadius: radius)
        : BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              colors: [value.c1, value.c2!],
              begin: value.orientation == MixOrientation.vertical
                  ? Alignment.topCenter
                  : Alignment.centerLeft,
              end: value.orientation == MixOrientation.vertical
                  ? Alignment.bottomCenter
                  : Alignment.centerRight,
            ),
          );

    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: decoration.copyWith(
              border: Border.all(
                  color: selected ? accent : outline, width: selected ? 3 : 1),
            ),
          ),
          const SizedBox(height: 3),
          SizedBox(
            width: 48,
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rail extends StatelessWidget {
  final bool vertical;
  final _Cat selected;
  final ValueChanged<_Cat> onSelect;

  const _Rail(
      {required this.vertical, required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tiles = [
      for (final c in _Cat.values)
        _RailTile(
          icon: _catIcons[c]!,
          label: _catLabels[c]!,
          selected: c == selected,
          accent: scheme.primary,
          onTap: () => onSelect(c),
        ),
    ];
    if (vertical) {
      return Container(
        width: 84,
        color: scheme.surfaceContainerHighest,
        child: Column(
            mainAxisAlignment: MainAxisAlignment.center, children: tiles),
      );
    }
    return Container(
      color: scheme.surfaceContainerHighest,
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: tiles),
    );
  }
}

class _RailTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  const _RailTile(
      {required this.icon,
      required this.label,
      required this.selected,
      required this.accent,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color =
        selected ? accent : Theme.of(context).colorScheme.onSurfaceVariant;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 4),
            Text(label,
                style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}
