// lib/features/template_editor/template_editor_screen.dart
//
// Template Editor: manage templates (create/duplicate/rename/delete) and edit
// their layout. Two panes via a Layout/Fields switch:
//   * Layout  — base colour, border, corner radius, card size.
//   * Fields  — add/remove fields and edit the selected field's type, position,
//               fill, outline, corners, and text style. The selected field is
//               outlined on the live preview.
// Edits go to an in-memory working copy; nothing persists until Save. Leaving
// with unsaved edits asks Save / Discard / Cancel. No schema change — fields
// already persist inside the template's JSON.
//
// This file is split across parts (one library): the State + its mutation logic
// + build/preview live here; the Layout pane, Fields pane, and shared widget
// helpers live in the template_editor_{layout,fields,widgets}.dart parts as
// extensions on _TemplateBodyState.

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/image_store.dart';
import '../../data/template_repository.dart';
import '../../model/card_model.dart';
import '../../model/font_catalog.dart';
import '../../model/layer_migration.dart';
import '../../model/layers.dart';
import '../../model/markup.dart';
import '../../model/sample_card.dart';
import '../../state/providers.dart';
import '../../widgets/card_preview.dart';
import '../../widgets/preview_backdrop.dart';
import '../../widgets/decoded_card_preview.dart';
import '../../widgets/labeled_slider.dart';
import '../../widgets/preview_dock.dart';
import '../../widgets/swatch_picker.dart';
import '../../widgets/color_picker/color_picker.dart';
import '../../data/image_import.dart';
import '../customization/frame_picker.dart';
import '../customization/frame_slice_editor.dart';
import '../customization/symbol_picker.dart';

part 'template_editor_widgets.dart';
part 'template_editor_layout.dart';
part 'template_editor_browser.dart';
part 'template_editor_layers.dart';
part 'template_editor_preview.dart';
part 'template_editor_layer_aspects.dart';
part 'template_editor_layer_dialogs.dart';

const Map<String, (double, double)> _sizePresets = {
  'Poker (2.5 × 3.5)': (2.5, 3.5),
  'Bridge (2.25 × 3.5)': (2.25, 3.5),
  'Tarot (2.75 × 4.75)': (2.75, 4.75),
  'Square (3.5 × 3.5)': (3.5, 3.5),
};

// Shown in the Template Editor preview only, so the footer can be seen and
// positioned. Real cards derive their footer from set/rarity/number instead.
const _footerPlaceholder = '001/XXX • CORE • R';

enum _Mode { layout, layers }

class TemplateEditorScreen extends ConsumerStatefulWidget {
  const TemplateEditorScreen({super.key});

  @override
  ConsumerState<TemplateEditorScreen> createState() =>
      _TemplateEditorScreenState();
}

class _TemplateEditorScreenState extends ConsumerState<TemplateEditorScreen> {
  // null → the browser is showing; non-null → that template is open for editing.
  String? _openId;
  // Lets the system back button route through the editor's unsaved-changes guard.
  final _bodyKey = GlobalKey<_TemplateBodyState>();

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(templatesProvider);
    final palette = ref.watch(paletteMapProvider);
    final swatches = ref.watch(paletteProvider).maybeWhen(
          data: (l) => l,
          orElse: () => const <PaletteSwatch>[],
        );
    final inUseIds = ref.watch(cardsProvider).maybeWhen(
          data: (cards) =>
              cards.map((c) => c.templateId).whereType<String>().toSet(),
          orElse: () => const <String>{},
        );
    final repo = ref.read(templateRepositoryProvider);

    return templatesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load templates:\n$e')),
      data: (templates) {
        TemplateEntry? open;
        if (_openId != null) {
          for (final t in templates) {
            if (t.id == _openId) {
              open = t;
              break;
            }
          }
          // _openId is set but the template isn't in the list yet — it was just
          // created and the templates stream hasn't emitted it. Wait a beat and
          // it'll appear and open. (Deletion clears _openId explicitly, so this
          // never gets stuck on a removed template.)
          if (open == null) {
            return const Center(child: CircularProgressIndicator());
          }
        }

        if (open == null) {
          return _TemplateBrowser(
            templates: templates,
            inUseIds: inUseIds,
            palette: palette,
            onOpen: (id) => setState(() => _openId = id),
            onNew: () => _newTemplate(repo),
            onDuplicate: (entry) => _duplicate(repo, entry),
            onDelete: (entry) => _confirmDelete(repo, entry),
          );
        }

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _bodyKey.currentState?._handleBack();
          },
          child: _TemplateBody(
            key: _bodyKey,
            entry: open,
            palette: palette,
            swatches: swatches,
            repo: repo,
            imageStore: ref.read(imageStoreProvider),
            onClose: () => setState(() => _openId = null),
          ),
        );
      },
    );
  }

  Future<void> _newTemplate(TemplateRepository repo) async {
    final id = await repo.create('New template', starterTemplate());
    if (!mounted) return;
    setState(() => _openId = id); // open the blank template straight away
  }

  Future<void> _duplicate(TemplateRepository repo, TemplateEntry entry) async {
    await repo.create('${entry.name} copy', entry.data);
    // Stay in the browser; the copy appears in the grid.
  }

  Future<void> _confirmDelete(
      TemplateRepository repo, TemplateEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Delete "${entry.name}"?'),
        content: const Text(
            'Cards using this template keep rendering from their saved '
            'snapshot; they just lose the live link.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(d, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(d, true),
              child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) {
      await repo.delete(entry.id);
      if (mounted && _openId == entry.id) setState(() => _openId = null);
    }
  }
}

class _TemplateBody extends ConsumerStatefulWidget {
  final TemplateEntry entry;
  final Map<String, ColorValue> palette;
  final List<PaletteSwatch> swatches;
  final TemplateRepository repo;
  final ImageStore imageStore;
  final VoidCallback onClose;

  const _TemplateBody({
    super.key,
    required this.entry,
    required this.palette,
    required this.swatches,
    required this.repo,
    required this.imageStore,
    required this.onClose,
  });

  @override
  ConsumerState<_TemplateBody> createState() => _TemplateBodyState();
}

class _TemplateBodyState extends ConsumerState<_TemplateBody> {
  late TemplateEntry _working;
  late final TextEditingController _name;
  late final TextEditingController _widthCtl;
  late final TextEditingController _heightCtl;
  bool _syncingDims = false; // guards programmatic dim-field updates
  final Map<String, ui.Image> _images = {}; // imageId -> decoded bg image
  bool _dirty = false; // unsaved edits to the working copy
  _Mode _mode = _Mode.layout;
  String? _selectedLayerId; // selected layer in the Layers tab (editor-only UI)
  bool _layersReordering = false; // Layers tab: reorder mode vs edit mode
  // Horizontal scroll position of the Layers-tab chip strip. Keyed chips let us
  // scroll the selected one into view (see _selectLayer) so it never strands
  // off-screen on a template with many layers.
  final ScrollController _layerStripCtl = ScrollController();
  final Map<String, GlobalKey> _layerChipKeys = {};
  // Which field-editor sections are expanded (keyed by section). Remembered as
  // you move between fields so it doesn't keep snapping shut. Empty = all closed.
  final Set<String> _expandedSections = {};

  @override
  void initState() {
    super.initState();
    _working = widget.entry;
    _name = TextEditingController(text: _working.name)
      ..addListener(_onNameChanged);
    _widthCtl = TextEditingController(text: _fmtInches(_d.widthInches))
      ..addListener(_onDimsChanged);
    _heightCtl = TextEditingController(text: _fmtInches(_d.heightInches))
      ..addListener(_onDimsChanged);
    _syncImages(); // decode background + any watermark symbols
  }

  @override
  void dispose() {
    _name.dispose();
    _widthCtl.dispose();
    _heightCtl.dispose();
    _layerStripCtl.dispose();
    super.dispose();
  }

  TemplateData get _d => _working.data;

  void _onNameChanged() {
    if (_working.name == _name.text) return;
    setState(() {
      _working = _working.copyWith(name: _name.text);
      _dirty = true;
    });
  }

  void _update(TemplateData data) {
    setState(() {
      _working = _working.copyWith(data: data);
      _dirty = true;
    });
  }

  // ---- save / discard ----

  Future<void> _save() async {
    await widget.repo.save(_working);
    if (!mounted) return;
    setState(() => _dirty = false);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Template saved')));
  }

  // Back arrow + Android system back both route here. Nothing is persisted
  // unless the user explicitly saves, so leaving with edits asks first.
  Future<void> _handleBack() async {
    if (!_dirty) {
      widget.onClose();
      return;
    }
    final action = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Unsaved changes'),
        content:
            const Text('Save your changes to this template before leaving?'),
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
    if (action == 'save') {
      await _save();
      widget.onClose();
    } else if (action == 'discard') {
      widget.onClose();
    }
    // cancel / dismissed → stay in the editor
  }

  Widget _editorHeader() {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: _handleBack,
            ),
            // Title + tag share ONE tight Expanded. With a loose Flexible next
            // to a Spacer, Flutter splits the free space between them and a
            // short title's unused share becomes dead space AFTER the buttons —
            // stranding Save mid-row on wide (desktop) windows.
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      _working.name.isEmpty ? 'Untitled' : _working.name,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'TEMPLATE',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _dirty ? _save : null,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Select a layer in the Layers tab (or clear with null). Editor-only UI
  /// state. Extensions route through this since they can't call setState.
  void _selectLayer(String? id) {
    setState(() => _selectedLayerId = id);
    if (id != null) _scrollChipIntoView(id);
  }

  /// Bring the given layer's chip fully into view in the horizontal strip.
  /// A freshly added layer's chip doesn't exist until the strip rebuilds, and
  /// a single post-frame callback often fires before that chip is laid out —
  /// so we retry across a few frames until its key resolves, then animate.
  /// Safe when the strip isn't mounted: it just runs out of attempts and stops.
  void _scrollChipIntoView(String id, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final ctx = _layerChipKeys[id]?.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.5, // centre it
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      } else if (attempt < 5) {
        // Chip not built/laid-out yet — try again next frame.
        _scrollChipIntoView(id, attempt: attempt + 1);
      }
    });
  }

  /// Toggle the Layers tab between edit mode and reorder mode. Extensions can't
  /// call setState, so they route through this.
  void _setLayersReordering(bool v) {
    setState(() => _layersReordering = v);
  }

  // ---- custom dimensions ----
  //
  // Width/height are entered directly in inches; the preset dropdown is a
  // shortcut that fills these fields. Inches are the authored unit — print
  // pixels are derived at export (300 dpi), so dimensions stay resolution
  // independent like everything else.

  String _fmtInches(double v) =>
      v.toStringAsFixed(2).replaceAll(RegExp(r'\.?0+$'), '');

  void _onDimsChanged() {
    if (_syncingDims) return; // programmatic fill from a preset; ignore
    final w = double.tryParse(_widthCtl.text.trim());
    final h = double.tryParse(_heightCtl.text.trim());
    if (w == null || h == null) return; // mid-edit / invalid: wait
    final cw = w.clamp(0.5, 12.0);
    final ch = h.clamp(0.5, 12.0);
    if ((cw - _d.widthInches).abs() < 0.0001 &&
        (ch - _d.heightInches).abs() < 0.0001) {
      return;
    }
    _update(_d.copyWith(widthInches: cw, heightInches: ch));
  }

  void _setDims(double w, double h) {
    _syncingDims = true;
    _widthCtl.text = _fmtInches(w);
    _heightCtl.text = _fmtInches(h);
    _syncingDims = false;
    _update(_d.copyWith(widthInches: w, heightInches: h));
  }

  void _toggleSection(String key) {
    setState(() {
      if (!_expandedSections.remove(key)) _expandedSections.add(key);
    });
  }

  // ---- background image ----
  //
  // The bg image lives on the TEMPLATE (it's layout, not per-card content) and
  // is decoded here, then handed to the renderer via CardRefs.images — exactly
  // like the Card Editor decodes card art. paintCard draws it between the base
  // colour and the tint, so a card's tint still layers over it.

  Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<void> _syncImages() async {
    // Decode every image the previewed card needs (background + any Rules
    // watermark). composeCard resolves the watermark symbol ids to image ids.
    final symbolMap = ref.read(textSymbolMapProvider);
    final card = composeCard(_d,
        content: const CardContent(),
        symbolImageIds: symbolMap,
        symbolsById: ref.read(symbolsMapProvider),
        frames: ref.read(framesMapProvider),
        footerPlaceholder: _footerPlaceholder);
    // The preview renders text PLACEHOLDERS (empty content), so any {tag}
    // glyphs inside them need decoding too — they're not in textContent.
    final ids = card.imageIdsToDecode().toSet();
    for (final l in effectiveTemplateLayers(_d)) {
      final ph = l.text?.placeholder ?? '';
      if (ph.isEmpty) continue;
      for (final tag in referencedTags(ph)) {
        final imgId = symbolMap[tag];
        if (imgId != null) ids.add(imgId);
      }
    }
    for (final id in ids) {
      if (_images.containsKey(id)) continue;
      final bytes = await widget.imageStore.load(id);
      if (bytes == null) continue;
      final img = await _decode(bytes);
      if (!mounted) return;
      setState(() => _images[id] = img);
    }
  }

  /// Pick an image file, store it, decode it for the preview, and return its
  /// id (or null if cancelled). Shared by the layer image + border pickers; the
  /// caller decides which model field the id goes on.
  Future<String?> _pickAndStoreImage() async {
    final result = await FilePicker.pickFiles(type: FileType.image);
    if (result == null) return null;
    final file = result.files.first;
    final bytes = await file.readAsBytes();
    final ImportedImage imported;
    try {
      imported = await processImportedImage(bytes,
          kind: ImageImportKind.artwork,
          ext: (file.extension ?? 'png').toLowerCase());
    } on ImageImportException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return null;
    }
    final imageId = await widget.imageStore
        .save(imported.bytes, ext: imported.ext);
    final img = await _decode(imported.bytes);
    if (!mounted) return null;
    final notice = imported.notice;
    if (notice != null) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(notice)));
    }
    setState(() => _images[imageId] = img);
    return imageId;
  }

  @override
  Widget build(BuildContext context) {
    final pane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: SegmentedButton<_Mode>(
                  segments: const [
                    ButtonSegment(value: _Mode.layout, label: Text('Layout')),
                    ButtonSegment(value: _Mode.layers, label: Text('Layers')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
              ),
              // Layer actions ride on this row (only in Layers mode) instead of
              // a dedicated header band below, buying back that vertical space
              // for the aspect controls. Hidden in reorder mode, which has its
              // own "Done" affordance.
              if (_mode == _Mode.layers && !_layersReordering) ...[
                const SizedBox(width: 8),
                if (_hasReorderableLayers)
                  IconButton(
                    tooltip: 'Reorder layers',
                    icon: const Icon(Icons.swap_vert),
                    onPressed: () => _setLayersReordering(true),
                  ),
                IconButton.filledTonal(
                  tooltip: 'Add layer',
                  icon: const Icon(Icons.add),
                  onPressed: _addGenericLayer,
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: _mode == _Mode.layout ? _layoutForm() : _layersPane(),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        if (wide) {
          // Desktop: header on top, preview beside the pane. The preview FITS
          // its column (width and height, like the phone dock) instead of a
          // fixed 280px card lost in the space, and sits on the gradient
          // backdrop so black/white card borders read in both themes.
          final preview = PreviewBackdrop(child: _fittingPreviewWithOverlay());
          return Column(
            children: [
              _editorHeader(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: preview),
                    Expanded(
                      flex: 5,
                      child: Material(
                        color:
                            Theme.of(context).colorScheme.surfaceContainerHigh,
                        child: pane,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        }
        // Phone: the same slide-up dock as the Card Editor. The preview scales
        // to fill the space above the dock as the handle is dragged.
        return PreviewDockScaffold(
          header: _editorHeader(),
          preview: PreviewBackdrop(child: _fittingPreviewWithOverlay()),
          dock: pane,
        );
      },
    );
  }
}
