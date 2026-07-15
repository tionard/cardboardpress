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

    // Compose each unique card once and decode refs BEFORE the dialog — the
    // live preview needs them, and the final export reuses the exact same
    // objects (CardData is dpi-independent). Refs merge into one map (palette
    // is shared; image ids are content-hashed, so collisions are identical
    // images anyway).
    _setBusy(true);
    final uniqueDatas = <CardData>[];
    final images = <String, ui.Image>{};
    try {
      for (final (card, idx) in picked) {
        final data = _compose(folder, card, idx, ctx);
        final refs = await _decodeRefs(data, ctx);
        images.addAll(refs.images);
        uniqueDatas.add(data);
      }
    } finally {
      _setBusy(false);
    }
    if (!mounted) return;
    final refs = CardRefs(palette: ctx.palette, images: images);

    final choice = await showDialog<_SheetChoice>(
      context: context,
      builder: (_) => _SheetSettingsDialog(
        pro: pro,
        cardWidthIn: cardT.widthInches,
        cardHeightIn: cardT.heightInches,
        entries: [for (final (c, _) in picked) (c.id, _entryName(c, ctx))],
        datas: uniqueDatas,
        refs: refs,
        watermark: !pro,
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
      final datas = <CardData>[];
      for (var i = 0; i < picked.length; i++) {
        final copies = choice.copies[picked[i].$1.id] ?? 1;
        for (var c = 0; c < copies; c++) {
          datas.add(uniqueDatas[i]);
        }
      }
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
  final List<CardData> datas; // aligned with [entries]
  final CardRefs refs;
  final bool watermark; // preview honestly shows the free-tier watermark

  const _SheetSettingsDialog({
    required this.pro,
    required this.cardWidthIn,
    required this.cardHeightIn,
    required this.entries,
    required this.datas,
    required this.refs,
    required this.watermark,
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

  // Live preview: the REAL composer at a thumbnail dpi, current page only,
  // debounced so slider drags don't render per tick.
  Uint8List? _previewPng;
  int _previewPageCount = 0;
  int _page = 0;
  bool _previewStale = true;
  Timer? _debounce;

  // Responsive shape: wide (desktop) puts settings left and a BIG preview in
  // its own right pane; compact (phone) is a single column with the preview
  // collapsed behind a toggle — nothing renders while it's hidden.
  bool? _wide; // null until the first build measures the window
  bool _showPreviewCompact = false;
  bool? _copiesOpen; // null = default: open when wide, collapsed when compact

  /// Preview render resolution follows the pane size, so the big desktop
  /// preview is actually crisp instead of an upscaled thumbnail.
  double get _previewDpi => (_wide ?? false) ? 90 : 55;

  bool get _previewVisible => (_wide ?? false) || _showPreviewCompact;

  int get _totalCards => _copies.values.fold(0, (a, b) => a + b);

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  /// Apply a setting change and refresh the preview after a short quiet
  /// period (drags fire per tick; the preview follows on release-ish).
  void _set(VoidCallback fn) {
    setState(() {
      fn();
      _previewStale = true;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _renderPreview);
  }

  SheetSettings _settingsAt(double dpi) => SheetSettings(
        paper: _paper,
        landscape: _landscape,
        dpi: dpi,
        gapMm: _gapMm,
        marginMm: _marginMm,
        cutMarks: _cutMarks,
      );

  List<CardData> _expanded() => [
        for (var i = 0; i < widget.entries.length; i++)
          for (var c = 0; c < (_copies[widget.entries[i].$1] ?? 1); c++)
            widget.datas[i],
      ];

  Future<void> _renderPreview() async {
    if (!_previewVisible) return; // hidden on mobile — skip the work entirely
    final SheetLayout l;
    try {
      l = computeSheetLayout(
          _settingsAt(_previewDpi), widget.cardWidthIn, widget.cardHeightIn);
    } on StateError {
      if (mounted) {
        setState(() {
          _previewPng = null;
          _previewPageCount = 0;
          _previewStale = false;
        });
      }
      return;
    }
    final expanded = _expanded();
    final pages = (expanded.length + l.perPage - 1) ~/ l.perPage;
    final page = _page.clamp(0, pages - 1);
    final slice = expanded.sublist(
        page * l.perPage,
        (page + 1) * l.perPage > expanded.length
            ? expanded.length
            : (page + 1) * l.perPage);
    final png = await composeSheetPage(slice, widget.refs, l,
        cutMarks: _cutMarks, watermark: widget.watermark);
    if (!mounted) return;
    setState(() {
      _previewPng = png;
      _previewPageCount = pages;
      _page = page;
      _previewStale = false;
    });
  }

  void _goToPage(int delta) {
    setState(() {
      _page = (_page + delta).clamp(0, _previewPageCount - 1);
      _previewStale = true;
    });
    _debounce?.cancel();
    _renderPreview(); // page flips render immediately, no debounce
  }

  _SheetChoice _choice() => _SheetChoice(
        paper: _paper,
        landscape: _landscape,
        dpi: _dpi,
        gapMm: _gapMm,
        marginMm: _marginMm,
        cutMarks: _cutMarks,
        pdf: _pdf,
        copies: Map.of(_copies),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final wide = MediaQuery.sizeOf(context).width >= 700;
    if (wide != _wide) {
      // First build, or the window crossed the breakpoint mid-dialog: the
      // preview dpi (and visibility) changed, so re-render after this frame.
      _wide = wide;
      _debounce?.cancel();
      Future.microtask(_renderPreview);
    }

    // Live fit line — the same math the export will use.
    String fitLine;
    var fits = true;
    try {
      final l = computeSheetLayout(_settingsAt(_dpi.toDouble()),
          widget.cardWidthIn, widget.cardHeightIn);
      final pages = (_totalCards + l.perPage - 1) ~/ l.perPage;
      fitLine = '${l.cols} × ${l.rows} per page — $_totalCards card'
          '${_totalCards == 1 ? '' : 's'} on $pages page'
          '${pages == 1 ? '' : 's'}';
    } on StateError {
      fits = false;
      fitLine = 'Cards don\'t fit this page with these margins.';
    }

    return wide
        ? _wideDialog(theme, fitLine, fits)
        : _compactDialog(theme, fitLine, fits);
  }

  // ---- shared pieces ----

  Widget _seg<T>(String label, List<(T, String, bool)> options, T selected,
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

  List<Widget> _settingRows() => [
        _seg<SheetPaper>(
            'Paper',
            [
              (SheetPaper.a4, 'A4', false),
              (SheetPaper.letter, 'Letter', false),
            ],
            _paper,
            (v) => _set(() => _paper = v)),
        _seg<bool>(
            'Orientation',
            [(false, 'Portrait', false), (true, 'Landscape', false)],
            _landscape,
            (v) => _set(() => _landscape = v)),
        _seg<int>('Resolution',
            [(300, '300 DPI', false), (600, '600 DPI', !widget.pro)], _dpi,
            (v) {
          if (v == 600 && !widget.pro) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text(
                    '600 DPI is a Pro feature — free sheets render at 300 DPI '
                    'with a watermark.')));
            return;
          }
          _set(() => _dpi = v);
        }),
        _seg<bool>(
            'Format',
            [(false, 'PNG pages', false), (true, 'PDF', false)],
            _pdf,
            (v) => _set(() => _pdf = v)),
        LabeledSlider(
          label: 'Gap (mm)',
          value: _gapMm,
          min: 0,
          max: 5,
          step: 0.5,
          labelWidth: 86,
          onChanged: (v) => _set(() => _gapMm = v),
        ),
        LabeledSlider(
          label: 'Margin (mm)',
          value: _marginMm,
          min: 0,
          max: 15,
          step: 1,
          labelWidth: 86,
          onChanged: (v) => _set(() => _marginMm = v),
        ),
        SwitchListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          title: const Text('Cut guides'),
          subtitle: Text(_gapMm <= 0
              ? 'Hairlines along the shared cut edges'
              : 'Crop marks at each card\'s corners'),
          value: _cutMarks,
          onChanged: (v) => _set(() => _cutMarks = v),
        ),
      ];

  /// Collapsible, scroll-bounded copies list. Open by default on desktop,
  /// collapsed by default on mobile; the header always shows the total.
  Widget _copiesSection(ThemeData theme) {
    final open = _copiesOpen ?? (_wide ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _copiesOpen = !open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              Text('Copies', style: theme.textTheme.labelLarge),
              const SizedBox(width: 8),
              Text(
                  '$_totalCards card${_totalCards == 1 ? '' : 's'} from '
                  '${widget.entries.length}',
                  style: theme.textTheme.bodySmall),
              const Spacer(),
              Icon(open ? Icons.expand_less : Icons.expand_more, size: 20),
            ]),
          ),
        ),
        if (open)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 190),
            child: ListView(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              children: [
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
                          : () => _set(() => _copies[id] = _copies[id]! - 1),
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
                          : () => _set(() => _copies[id] = _copies[id]! + 1),
                    ),
                  ]),
              ],
            ),
          ),
      ],
    );
  }

  Widget _previewBox(ThemeData theme, bool fits, {double? height}) {
    final png = _previewPng;
    return Container(
      height: height,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: png == null
            ? SizedBox(
                width: 160,
                child: Center(
                  child: fits
                      ? const CircularProgressIndicator()
                      : Icon(Icons.block, color: theme.colorScheme.error),
                ),
              )
            : AnimatedOpacity(
                opacity: _previewStale ? 0.4 : 1,
                duration: const Duration(milliseconds: 120),
                child: Image.memory(
                  png,
                  gaplessPlayback: true,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                ),
              ),
      ),
    );
  }

  Widget _pager(ThemeData theme, {required bool large}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          iconSize: large ? 28 : 24,
          visualDensity: large ? null : VisualDensity.compact,
          onPressed: _page <= 0 ? null : () => _goToPage(-1),
        ),
        Text('Page ${_page + 1} / $_previewPageCount',
            style: large
                ? theme.textTheme.titleMedium
                : theme.textTheme.bodySmall),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          iconSize: large ? 28 : 24,
          visualDensity: large ? null : VisualDensity.compact,
          onPressed:
              _page >= _previewPageCount - 1 ? null : () => _goToPage(1),
        ),
      ],
    );
  }

  // ---- desktop: settings left, big preview right ----

  Widget _wideDialog(ThemeData theme, String fitLine, bool fits) {
    final size = MediaQuery.sizeOf(context);
    final w = (size.width - 160).clamp(640.0, 920.0);
    final h = (size.height - 140).clamp(400.0, 660.0);
    return Dialog(
      child: SizedBox(
        width: w,
        height: h,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Print sheet', style: theme.textTheme.headlineSmall),
              const SizedBox(height: 16),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 380,
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            ..._settingRows(),
                            const Divider(height: 20),
                            _copiesSection(theme),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Column(
                        children: [
                          Expanded(child: _previewBox(theme, fits)),
                          if (_previewPageCount > 1)
                            _pager(theme, large: true)
                          else
                            const SizedBox(height: 10),
                          Text(fitLine,
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: fits
                                      ? null
                                      : theme.colorScheme.error)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: !fits
                        ? null
                        : () => Navigator.pop(context, _choice()),
                    child: const Text('Export'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- phone: single column, preview behind a toggle ----

  Widget _compactDialog(ThemeData theme, String fitLine, bool fits) {
    return AlertDialog(
      title: const Text('Print sheet'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ..._settingRows(),
              const SizedBox(height: 4),
              Text(fitLine,
                  style: theme.textTheme.bodySmall?.copyWith(
                      color: fits ? null : theme.colorScheme.error)),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: Icon(_showPreviewCompact
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined),
                  label: Text(_showPreviewCompact
                      ? 'Hide preview'
                      : 'Show preview'),
                  onPressed: () {
                    setState(() {
                      _showPreviewCompact = !_showPreviewCompact;
                      _previewStale = true;
                    });
                    if (_showPreviewCompact) _renderPreview();
                  },
                ),
              ),
              if (_showPreviewCompact) ...[
                Center(child: _previewBox(theme, fits, height: 320)),
                if (_previewPageCount > 1) _pager(theme, large: false),
              ],
              const Divider(height: 24),
              _copiesSection(theme),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: !fits ? null : () => Navigator.pop(context, _choice()),
          child: const Text('Export'),
        ),
      ],
    );
  }
}
