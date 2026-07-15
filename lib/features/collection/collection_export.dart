part of 'collection_screen.dart';

// Bulk EXPORT flows for the opened set's selection. The bar's Export action
// opens a chooser: individual PNGs (the original flow, still _bulkExport),
// print sheets (PNG pages or a true-size PDF), Tabletop Simulator deck
// sheets, or card data as JSON. Composition lives in rendering/sheet_export
// (+ sheet_pdf) and model/card_json; delivery in data/card_exporter — this
// file is the glue: gather the selection in collection order, ask for
// settings, expand copy counts, merge decoded refs, run, report.
//
// State-mutation rule of this library applies: extension methods never call
// setState — busy toggling goes through _setBusy on the State.

extension _ExportFlows on _CollectionScreenState {
  Future<void> _bulkExportChooser() async {
    if (_selected.isEmpty) return;
    final android = defaultTargetPlatform == TargetPlatform.android;
    final n = _selected.length;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Export $n card${n == 1 ? '' : 's'}'),
        children: [
          _chooserOption(
              ctx,
              'png',
              android ? Icons.photo_library_outlined : Icons.download_outlined,
              android ? 'Save to Photos' : 'Individual PNGs',
              'One image per card'),
          _chooserOption(ctx, 'sheet', Icons.grid_on_outlined, 'Print sheet…',
              'Cards on A4/Letter pages, ready to print and cut'),
          _chooserOption(ctx, 'tts', Icons.casino_outlined, 'TTS deck sheet',
              'Gapless grid for Tabletop Simulator\'s deck importer'),
          _chooserOption(ctx, 'json', Icons.data_object, 'Card data (JSON)',
              'Names, text, rarity, numbers — for digital games'),
        ],
      ),
    );
    switch (choice) {
      case 'png':
        await _bulkExport();
      case 'sheet':
        await _exportPrintSheet();
      case 'tts':
        await _exportTtsSheets();
      case 'json':
        await _exportCardsJson();
    }
  }

  Widget _chooserOption(BuildContext ctx, String value, IconData icon,
      String title, String subtitle) {
    return SimpleDialogOption(
      onPressed: () => Navigator.pop(ctx, value),
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon),
        title: Text(title),
        subtitle: Text(subtitle),
      ),
    );
  }

  /// The selection, in the folder's (collector) order, with each card's index
  /// in the FULL set — footer numbers and JSON numbers both key off it.
  List<(CardEntry, int)> _selectedCardsInOrder(_Folder folder) => [
        for (var i = 0; i < folder.cards.length; i++)
          if (_selected.contains(folder.cards[i].id)) (folder.cards[i], i),
      ];

  String _entryName(CardEntry e, _CardCtx ctx) {
    final t = e.effectiveTemplate(ctx.templates);
    for (final f in t.fields) {
      if (f.type == FieldType.name) {
        final v = e.content.text[f.id]?.trim();
        if (v != null && v.isNotEmpty) return v;
      }
    }
    return 'Untitled';
  }

  /// `ABBR_kind_yyyymmdd` (abbr omitted when the set has none).
  String _exportBase(SetEntry? set, String kind) {
    final abbr = _abbrOf(set);
    final t = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${t.year}${two(t.month)}${two(t.day)}';
    return '${abbr == null || abbr.isEmpty ? '' : '${abbr}_'}${kind}_$stamp';
  }

  /// Deliver a list of named PNGs the platform-appropriate way; returns the
  /// success message, or null when the user cancelled the folder pick.
  Future<String?> _deliverImages(List<(String, Uint8List)> files,
      {required String what}) async {
    final exporter = ref.read(cardExporterProvider);
    if (defaultTargetPlatform == TargetPlatform.android) {
      final n = await exporter.saveImagesToGallery(files);
      return 'Saved $n $what${n == 1 ? '' : 's'} to your photos';
    }
    final dir = await exporter.saveImagesToDirectory(files);
    if (dir == null) return null;
    return 'Saved ${files.length} $what${files.length == 1 ? '' : 's'} to $dir';
  }

  // ---- print sheets ----

  Future<void> _exportPrintSheet() async {
    final folder = _currentFolder();
    if (folder == null) return;
    final ctx = _ctxNow();
    final picked = _selectedCardsInOrder(folder);
    if (picked.isEmpty) return;
    final pro = ref.read(proUnlockedProvider);
    final cardT = picked.first.$1.effectiveTemplate(ctx.templates);

    final choice = await showDialog<_SheetChoice>(
      context: context,
      builder: (_) => _SheetSettingsDialog(
        pro: pro,
        cardWidthIn: cardT.widthInches,
        cardHeightIn: cardT.heightInches,
        entries: [for (final (c, _) in picked) (c.id, _entryName(c, ctx))],
      ),
    );
    if (choice == null || !mounted) return;

    _setBusy(true);
    String? message;
    var ok = false;
    try {
      final q = resolveExportQuality(
          requestedDpi: choice.dpi.toDouble(), proUnlocked: pro);
      final settings = SheetSettings(
        paper: choice.paper,
        landscape: choice.landscape,
        dpi: q.dpi,
        gapMm: choice.gapMm,
        marginMm: choice.marginMm,
        cutMarks: choice.cutMarks,
      );
      // Compose each unique card once; copies reuse the same CardData. Refs
      // merge into one map (palette is shared; image ids are content-hashed,
      // so collisions are identical images anyway).
      final datas = <CardData>[];
      final images = <String, ui.Image>{};
      for (final (card, idx) in picked) {
        final data = _compose(folder, card, idx, ctx);
        final refs = await _decodeRefs(data, ctx);
        images.addAll(refs.images);
        final copies = choice.copies[card.id] ?? 1;
        for (var c = 0; c < copies; c++) {
          datas.add(data);
        }
      }
      final refs = CardRefs(palette: ctx.palette, images: images);
      final pages = await composeSheetPages(datas, refs, settings,
          watermark: q.watermark);
      final base = _exportBase(folder.set, 'sheet');
      if (choice.pdf) {
        final pdf = await sheetPagesToPdf(pages, choice.paper,
            landscape: choice.landscape);
        final path = await ref.read(cardExporterProvider).saveDocument(pdf,
            fileName: '$base.pdf',
            extension: 'pdf',
            dialogTitle: 'Save print sheets (PDF)');
        ok = path != null;
        message = path == null ? 'Export cancelled' : 'Saved $path';
      } else {
        final files = [
          for (var i = 0; i < pages.length; i++)
            ('${base}_p${i + 1}.png', pages[i]),
        ];
        message = await _deliverImages(files, what: 'page');
        ok = message != null;
        message ??= 'Export cancelled';
      }
    } on GalleryAccessDenied {
      message = 'Photo access was denied — enable it in Settings.';
    } on StateError catch (e) {
      message = e.message;
    } catch (e) {
      message = 'Export failed: $e';
    } finally {
      _setBusy(false);
    }
    if (!mounted) return;
    _snack(message);
    if (ok) _cancelSelection();
  }

  // ---- Tabletop Simulator sheets ----

  Future<void> _exportTtsSheets() async {
    final folder = _currentFolder();
    if (folder == null) return;
    final ctx = _ctxNow();
    final picked = _selectedCardsInOrder(folder);
    if (picked.isEmpty) return;
    final pro = ref.read(proUnlockedProvider);

    _setBusy(true);
    String? message;
    var ok = false;
    try {
      final datas = <CardData>[];
      final images = <String, ui.Image>{};
      for (final (card, idx) in picked) {
        final data = _compose(folder, card, idx, ctx);
        final refs = await _decodeRefs(data, ctx);
        images.addAll(refs.images);
        datas.add(data);
      }
      final refs = CardRefs(palette: ctx.palette, images: images);
      final sheets = await composeTtsSheets(datas, refs, watermark: !pro);
      final base = _exportBase(folder.set, 'tts');
      final files = [
        for (var i = 0; i < sheets.length; i++)
          ('${base}_s${i + 1}_${sheets[i].cols}x${sheets[i].rows}.png',
              sheets[i].png),
      ];
      message = await _deliverImages(files, what: 'sheet');
      ok = message != null;
      if (ok) {
        final grids =
            sheets.map((s) => '${s.cols}×${s.rows}').join(', ');
        message = '$message — tell TTS the grid: $grids';
      }
      message ??= 'Export cancelled';
    } on GalleryAccessDenied {
      message = 'Photo access was denied — enable it in Settings.';
    } on StateError catch (e) {
      message = e.message;
    } catch (e) {
      message = 'Export failed: $e';
    } finally {
      _setBusy(false);
    }
    if (!mounted) return;
    _snack(message);
    if (ok) _cancelSelection();
  }

  // ---- card data (JSON) ----

  Future<void> _exportCardsJson() async {
    final folder = _currentFolder();
    if (folder == null) return;
    final ctx = _ctxNow();
    final picked = _selectedCardsInOrder(folder);
    if (picked.isEmpty) return;

    _setBusy(true);
    String? message;
    var ok = false;
    try {
      final numbered = folder.set?.numbering ?? false;
      final json = cardsToJson(
        [for (final (c, _) in picked) c],
        liveTemplates: ctx.templates,
        rarities: ctx.rarities,
        set: folder.set,
        // Numbers are positions within the FULL set (matching the footer),
        // not within the selection.
        numbers: numbered ? [for (final (_, i) in picked) i + 1] : null,
        total: numbered ? folder.cards.length : null,
      );
      final path = await ref.read(cardExporterProvider).saveDocument(
            Uint8List.fromList(utf8.encode(json)),
            fileName: '${_exportBase(folder.set, 'cards')}.json',
            extension: 'json',
            dialogTitle: 'Export card data (JSON)',
          );
      ok = path != null;
      message = path == null ? 'Export cancelled' : 'Saved $path';
    } catch (e) {
      message = 'Export failed: $e';
    } finally {
      _setBusy(false);
    }
    if (!mounted) return;
    _snack(message);
    if (ok) _cancelSelection();
  }
}

// ---------------------------------------------------------------------------
// Print-sheet settings dialog
// ---------------------------------------------------------------------------

class _SheetChoice {
  final SheetPaper paper;
  final bool landscape;
  final int dpi;
  final double gapMm;
  final double marginMm;
  final bool cutMarks;
  final bool pdf;
  final Map<String, int> copies; // card id -> copy count

  const _SheetChoice({
    required this.paper,
    required this.landscape,
    required this.dpi,
    required this.gapMm,
    required this.marginMm,
    required this.cutMarks,
    required this.pdf,
    required this.copies,
  });
}

class _SheetSettingsDialog extends StatefulWidget {
  final bool pro;
  final double cardWidthIn;
  final double cardHeightIn;
  final List<(String, String)> entries; // (card id, display name)

  const _SheetSettingsDialog({
    required this.pro,
    required this.cardWidthIn,
    required this.cardHeightIn,
    required this.entries,
  });

  @override
  State<_SheetSettingsDialog> createState() => _SheetSettingsDialogState();
}

class _SheetSettingsDialogState extends State<_SheetSettingsDialog> {
  SheetPaper _paper = SheetPaper.a4;
  bool _landscape = false;
  int _dpi = 300;
  double _gapMm = 0;
  double _marginMm = 5;
  bool _cutMarks = true;
  bool _pdf = false;
  late final Map<String, int> _copies = {
    for (final (id, _) in widget.entries) id: 1,
  };

  int get _totalCards =>
      _copies.values.fold(0, (a, b) => a + b);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    // Live fit line — the same math the export will use.
    String fitLine;
    var fits = true;
    try {
      final l = computeSheetLayout(
          SheetSettings(
              paper: _paper,
              landscape: _landscape,
              dpi: _dpi.toDouble(),
              gapMm: _gapMm,
              marginMm: _marginMm),
          widget.cardWidthIn,
          widget.cardHeightIn);
      final pages = (_totalCards + l.perPage - 1) ~/ l.perPage;
      fitLine = '${l.cols} × ${l.rows} per page — $_totalCards card'
          '${_totalCards == 1 ? '' : 's'} on $pages page'
          '${pages == 1 ? '' : 's'}';
    } on StateError {
      fits = false;
      fitLine = 'Cards don\'t fit this page with these margins.';
    }

    Widget seg<T>(String label, List<(T, String, bool)> options, T selected,
        ValueChanged<T> onChanged) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          SizedBox(width: 86, child: Text(label)),
          Expanded(
            child: SegmentedButton<T>(
              showSelectedIcon: false,
              style: const ButtonStyle(
                  visualDensity: VisualDensity(horizontal: -2, vertical: -2)),
              segments: [
                for (final (v, l, locked) in options)
                  ButtonSegment(
                      value: v,
                      label: Text(l),
                      icon: locked
                          ? const Icon(Icons.lock_outline, size: 14)
                          : null),
              ],
              selected: {selected},
              onSelectionChanged: (s) => onChanged(s.first),
            ),
          ),
        ]),
      );
    }

    return AlertDialog(
      title: const Text('Print sheet'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              seg<SheetPaper>(
                  'Paper',
                  [
                    (SheetPaper.a4, 'A4', false),
                    (SheetPaper.letter, 'Letter', false),
                  ],
                  _paper,
                  (v) => setState(() => _paper = v)),
              seg<bool>(
                  'Orientation',
                  [(false, 'Portrait', false), (true, 'Landscape', false)],
                  _landscape,
                  (v) => setState(() => _landscape = v)),
              seg<int>(
                  'Resolution',
                  [(300, '300 DPI', false), (600, '600 DPI', !widget.pro)],
                  _dpi, (v) {
                if (v == 600 && !widget.pro) {
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                      content: Text(
                          '600 DPI is a Pro feature — free sheets render at '
                          '300 DPI with a watermark.')));
                  return;
                }
                setState(() => _dpi = v);
              }),
              seg<bool>(
                  'Format',
                  [(false, 'PNG pages', false), (true, 'PDF', false)],
                  _pdf,
                  (v) => setState(() => _pdf = v)),
              LabeledSlider(
                label: 'Gap (mm)',
                value: _gapMm,
                min: 0,
                max: 5,
                step: 0.5,
                labelWidth: 86,
                onChanged: (v) => setState(() => _gapMm = v),
              ),
              LabeledSlider(
                label: 'Margin (mm)',
                value: _marginMm,
                min: 0,
                max: 15,
                step: 1,
                labelWidth: 86,
                onChanged: (v) => setState(() => _marginMm = v),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Cut guides'),
                subtitle: Text(_gapMm <= 0
                    ? 'Hairlines along the shared cut edges'
                    : 'Crop marks at each card\'s corners'),
                value: _cutMarks,
                onChanged: (v) => setState(() => _cutMarks = v),
              ),
              const SizedBox(height: 4),
              Text(fitLine,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: fits ? null : theme.colorScheme.error)),
              const Divider(height: 24),
              Text('Copies', style: theme.textTheme.labelLarge),
              const SizedBox(height: 4),
              for (final (id, name) in widget.entries)
                Row(children: [
                  Expanded(
                      child: Text(name,
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                  IconButton(
                    icon: const Icon(Icons.remove, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: _copies[id]! <= 1
                        ? null
                        : () => setState(() => _copies[id] = _copies[id]! - 1),
                  ),
                  SizedBox(
                      width: 24,
                      child: Text('${_copies[id]}',
                          textAlign: TextAlign.center)),
                  IconButton(
                    icon: const Icon(Icons.add, size: 18),
                    visualDensity: VisualDensity.compact,
                    onPressed: _copies[id]! >= 99
                        ? null
                        : () => setState(() => _copies[id] = _copies[id]! + 1),
                  ),
                ]),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: !fits
              ? null
              : () => Navigator.pop(
                  context,
                  _SheetChoice(
                    paper: _paper,
                    landscape: _landscape,
                    dpi: _dpi,
                    gapMm: _gapMm,
                    marginMm: _marginMm,
                    cutMarks: _cutMarks,
                    pdf: _pdf,
                    copies: Map.of(_copies),
                  )),
          child: const Text('Export'),
        ),
      ],
    );
  }
}
