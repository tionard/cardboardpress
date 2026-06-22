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
import '../../model/sample_card.dart';
import '../../state/providers.dart';
import '../../widgets/card_preview.dart';
import '../../widgets/decoded_card_preview.dart';
import '../../widgets/labeled_slider.dart';
import '../../widgets/preview_dock.dart';
import '../../widgets/swatch_picker.dart';
import '../customization/symbol_picker.dart';

part 'template_editor_widgets.dart';
part 'template_editor_layout.dart';
part 'template_editor_fields.dart';

const Map<String, (double, double)> _sizePresets = {
  'Poker (2.5 × 3.5)': (2.5, 3.5),
  'Bridge (2.25 × 3.5)': (2.25, 3.5),
  'Tarot (2.75 × 4.75)': (2.75, 4.75),
  'Square (3.5 × 3.5)': (3.5, 3.5),
};

// Defaults for newly-added fields (seeded palette ids).
const _paperRef =
    ColorRef(id: 'c_paper', snapshot: ColorValue.single(Color(0xFFF1EFE8)));
const _inkRef =
    ColorRef(id: 'c_ink', snapshot: ColorValue.single(Color(0xFF2C2B27)));

/// Default text style for a freshly created/changed field. Multi-line types
/// (rules, flavor) default to shrink-to-fit so long text stays inside the box.
/// Everything is middle-anchored except Rules, which stays top-anchored so
/// multi-line rules text reads top-down.
TextStyleSpec _defaultTextFor(FieldType type) {
  final multiline = type == FieldType.rules || type == FieldType.flavor;
  final isRules = type == FieldType.rules;
  return TextStyleSpec(
    sizeFrac: 0.035,
    colorRef: _inkRef,
    vAlign: isRules ? VAlign.top : VAlign.middle,
    padX: 0.025,
    padY: isRules ? 0.015 : 0.0,
    fit: multiline ? TextFit.shrink : TextFit.fixed,
  );
}

const double _previewW = 280;

// Shown in the Template Editor preview only, so the footer can be seen and
// positioned. Real cards derive their footer from set/rarity/number instead.
const _footerPlaceholder = '001/XXX • CORE • R';

enum _Mode { layout, fields }

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

// ---------------------------------------------------------------------------
// Template Browser — the grid you land on. Pick a template to edit it.
// ---------------------------------------------------------------------------

class _TemplateBrowser extends ConsumerStatefulWidget {
  final List<TemplateEntry> templates;
  final Set<String> inUseIds;
  final Map<String, ColorValue> palette;
  final ValueChanged<String> onOpen;
  final VoidCallback onNew;
  final ValueChanged<TemplateEntry> onDuplicate;
  final ValueChanged<TemplateEntry> onDelete;

  const _TemplateBrowser({
    required this.templates,
    required this.inUseIds,
    required this.palette,
    required this.onOpen,
    required this.onNew,
    required this.onDuplicate,
    required this.onDelete,
  });

  @override
  ConsumerState<_TemplateBrowser> createState() => _TemplateBrowserState();
}

class _TemplateBrowserState extends ConsumerState<_TemplateBrowser> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final q = _query.trim().toLowerCase();
    final list = q.isEmpty
        ? widget.templates
        : widget.templates
            .where((t) => t.name.toLowerCase().contains(q))
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Row(
            children: [
              Text('Templates', style: Theme.of(context).textTheme.titleLarge),
              const Spacer(),
              FilledButton.icon(
                onPressed: widget.onNew,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            onChanged: (v) => setState(() => _query = v),
            decoration: const InputDecoration(
              isDense: true,
              prefixIcon: Icon(Icons.search),
              hintText: 'Search templates…',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: list.isEmpty
              ? Center(
                  child: Text(
                    widget.templates.isEmpty
                        ? 'No templates yet — tap New to start one.'
                        : 'No templates match "$_query".',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                )
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  gridDelegate:
                      const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 180,
                    childAspectRatio: 0.6,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemCount: list.length,
                  itemBuilder: (context, i) => _tile(context, list[i]),
                ),
        ),
      ],
    );
  }

  Widget _tile(BuildContext context, TemplateEntry t) {
    final scheme = Theme.of(context).colorScheme;
    final inUse = widget.inUseIds.contains(t.id);
    final data = composeCard(
      t.data,
      content: sampleContent(),
      symbolImageIds: ref.watch(textSymbolMapProvider),
      symbolsById: ref.watch(symbolsMapProvider),
      footerPlaceholder: _footerPlaceholder,
    );
    final aspect = data.widthInches / data.heightInches;
    return InkWell(
      onTap: () => widget.onOpen(t.id),
      borderRadius: BorderRadius.circular(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: LayoutBuilder(
                    builder: (context, c) {
                      double w = c.maxWidth;
                      if (w / aspect > c.maxHeight) w = c.maxHeight * aspect;
                      return Center(
                        child: DecodedCardPreview(
                          card: data,
                          palette: widget.palette,
                          imageStore: ref.read(imageStoreProvider),
                          width: w,
                        ),
                      );
                    },
                  ),
                ),
                if (inUse)
                  Positioned(
                    left: 4,
                    top: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        'IN USE',
                        style: TextStyle(
                          fontSize: 9,
                          letterSpacing: 0.5,
                          fontWeight: FontWeight.w700,
                          color: scheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ),
                Positioned(right: -6, top: -6, child: _tileMenu(t)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              t.name.isEmpty ? '(unnamed)' : t.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _tileMenu(TemplateEntry t) {
    return PopupMenuButton<String>(
      tooltip: '',
      icon: Icon(Icons.more_vert,
          size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
      onSelected: (v) {
        if (v == 'edit') widget.onOpen(t.id);
        if (v == 'duplicate') widget.onDuplicate(t);
        if (v == 'delete') widget.onDelete(t);
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
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
  String? _selectedFieldId;
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
    super.dispose();
  }

  TemplateData get _d => _working.data;

  FieldSpec? get _selectedField {
    for (final f in _d.fields) {
      if (f.id == _selectedFieldId) return f;
    }
    return null;
  }

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
            const Spacer(),
            FilledButton(
              onPressed: _dirty ? _save : null,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  /// Select a field for editing (or clear with null). Editor-only UI state,
  /// not part of the template data.
  void _selectField(String? id) {
    setState(() => _selectedFieldId = id);
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

  void _updateField(FieldSpec updated) {
    final fields =
        _d.fields.map((f) => f.id == updated.id ? updated : f).toList();
    _update(_d.copyWith(fields: fields));
  }

  void _toggleSection(String key) {
    setState(() {
      if (!_expandedSections.remove(key)) _expandedSections.add(key);
    });
  }

  // ---- single-placement rule (spec §3.6) ----
  //
  // Every field type is placeable exactly once EXCEPT Stat, which may repeat.
  // We enforce it where a type is chosen: the Add-field menu and the per-field
  // type dropdown both grey out a type that's already in use.

  Set<FieldType> get _placedTypes => _d.fields.map((f) => f.type).toSet();

  /// Can a NEW field of [type] be added? Stat always; others only if absent.
  bool _canAdd(FieldType type) =>
      type == FieldType.stat || !_placedTypes.contains(type);

  /// Can field [self] be CHANGED to [type]? Always its current type or Stat;
  /// otherwise only if no OTHER field already uses that type.
  bool _canChangeTo(FieldType type, FieldSpec self) =>
      type == self.type ||
      type == FieldType.stat ||
      !_d.fields.any((f) => f.id != self.id && f.type == type);

  void _addField(FieldType type) {
    if (!_canAdd(type)) return; // defensive; the menu already disables it
    final id = 'f_${DateTime.now().microsecondsSinceEpoch}';
    final isArt = type == FieldType.art;
    final f = FieldSpec(
      id: id,
      type: type,
      frac: const Rect.fromLTRB(0.1, 0.1, 0.9, 0.24),
      fill: isArt ? null : _paperRef,
      fillAlpha: 0.85,
      text: isArt ? null : _defaultTextFor(type),
    );
    _update(_d.copyWith(fields: [..._d.fields, f]));
    setState(() => _selectedFieldId = id);
  }

  void _removeField(String id) {
    _update(_d.copyWith(fields: _d.fields.where((f) => f.id != id).toList()));
    setState(() => _selectedFieldId = null);
  }

  void _moveField(String id, int delta) {
    final fields = [..._d.fields];
    final i = fields.indexWhere((f) => f.id == id);
    final j = i + delta;
    if (i < 0 || j < 0 || j >= fields.length) return;
    final f = fields.removeAt(i);
    fields.insert(j, f);
    _update(_d.copyWith(fields: fields));
  }

  void _changeFieldType(FieldSpec f, FieldType type) {
    var updated = f.copyWith(type: type);
    if (type == FieldType.art) {
      updated = updated.copyWith(text: null, fill: null);
    } else if (f.text == null) {
      updated = updated.copyWith(
          text: _defaultTextFor(type));
    }
    // The watermark belongs to the Rules field; drop it if the type changes away.
    if (type != FieldType.rules && f.watermark != null) {
      updated = updated.copyWith(watermark: null);
    }
    _updateField(updated);
  }

  void _setFrac(FieldSpec f, {double? l, double? t, double? r, double? b}) {
    const min = 0.03;
    var left = l ?? f.frac.left;
    var top = t ?? f.frac.top;
    var right = r ?? f.frac.right;
    var bottom = b ?? f.frac.bottom;
    if (l != null) left = left.clamp(0.0, right - min);
    if (r != null) right = right.clamp(left + min, 1.0);
    if (t != null) top = top.clamp(0.0, bottom - min);
    if (b != null) bottom = bottom.clamp(top + min, 1.0);
    _updateField(f.copyWith(frac: Rect.fromLTRB(left, top, right, bottom)));
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
    final card = composeCard(_d,
        content: sampleContent(),
        symbolImageIds: ref.read(textSymbolMapProvider),
        symbolsById: ref.read(symbolsMapProvider),
        footerPlaceholder: _footerPlaceholder);
    for (final id in card.imageIdsToDecode()) {
      if (_images.containsKey(id)) continue;
      final bytes = await widget.imageStore.load(id);
      if (bytes == null) continue;
      final img = await _decode(bytes);
      if (!mounted) return;
      setState(() => _images[id] = img);
    }
  }

  Future<void> _pickBgImage() async {
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
      // Replacing resets zoom/pan — a fresh image shouldn't inherit the old crop.
      _working = _working.copyWith(
          data: _d.copyWith(bgImageId: imageId, bgTransform: const ArtTransform()));
      _dirty = true;
    });
  }

  void _removeBgImage() {
    setState(() {
      _working = _working.copyWith(
          data: _d.copyWith(bgImageId: null, bgTransform: const ArtTransform()));
      _dirty = true;
    });
    // (The file is left on disk; orphan cleanup comes with Collection delete.)
  }

  void _setBgTransform(ArtTransform t) => _update(_d.copyWith(bgTransform: t));

  @override
  Widget build(BuildContext context) {
    final pane = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: SegmentedButton<_Mode>(
            segments: const [
              ButtonSegment(value: _Mode.layout, label: Text('Layout')),
              ButtonSegment(value: _Mode.fields, label: Text('Fields')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) => setState(() => _mode = s.first),
          ),
        ),
        Expanded(
          child: _mode == _Mode.layout ? _layoutForm() : _fieldsPane(),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 720;
        if (wide) {
          // Desktop: header on top, fixed-width preview beside the pane.
          final preview = Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: _previewWithOverlay(_previewW)),
          );
          return Column(
            children: [
              _editorHeader(),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(flex: 5, child: preview),
                    Expanded(flex: 5, child: pane),
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
          preview: _fittingPreviewWithOverlay(),
          dock: pane,
        );
      },
    );
  }

  // Fit the preview (and its overlays) into whatever box it's handed, so it can
  // scale as the dock grows/shrinks on the phone.
  Widget _fittingPreviewWithOverlay() {
    final aspect = _d.widthInches / _d.heightInches;
    return LayoutBuilder(
      builder: (context, c) {
        const pad = 16.0;
        final double availW = c.maxWidth - pad * 2;
        final double availH = c.maxHeight - pad * 2;
        if (availW <= 0 || availH <= 0) return const SizedBox.shrink();
        double w = availW;
        if (w / aspect > availH) w = availH * aspect;
        return Padding(
          padding: const EdgeInsets.all(pad),
          child: Center(child: _previewWithOverlay(w)),
        );
      },
    );
  }

  Widget _previewWithOverlay(double w) {
    final h = w * _d.heightInches / _d.widthInches;
    final sel = _selectedField;
    final card = composeCard(_d,
        content: sampleContent(),
        symbolImageIds: ref.watch(textSymbolMapProvider),
        symbolsById: ref.watch(symbolsMapProvider),
        footerPlaceholder: _footerPlaceholder);
    return SizedBox(
      width: w,
      height: h,
      child: Stack(
        children: [
          CardPreview(
              card: card,
              refs: CardRefs(palette: widget.palette, images: _images),
              width: w),
          if (_mode == _Mode.fields && sel != null)
            Positioned(
              left: sel.frac.left * w,
              top: sel.frac.top * h,
              width: sel.frac.width * w,
              height: sel.frac.height * h,
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Theme.of(context).colorScheme.primary, width: 2),
                  ),
                ),
              ),
            ),
          // Set-symbol placement guide (the symbol itself only renders on real
          // cards, where the set has chosen one — here we just show the zone).
          if (_d.setSymbol.enabled)
            Positioned(
              left: _d.setSymbol.frac.left * w,
              top: _d.setSymbol.frac.top * h,
              width: _d.setSymbol.frac.width * w,
              height: _d.setSymbol.frac.height * h,
              child: IgnorePointer(
                child: Container(
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    border: Border.all(
                        color: Theme.of(context).colorScheme.tertiary,
                        width: 1.5),
                    color: Theme.of(context)
                        .colorScheme
                        .tertiary
                        .withValues(alpha: 0.12),
                  ),
                  child: Icon(Icons.star_border,
                      size: 16,
                      color: Theme.of(context).colorScheme.tertiary),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
