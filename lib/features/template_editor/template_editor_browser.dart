// lib/features/template_editor/template_editor_browser.dart
//
// The template BROWSER: the grid you land on before opening a template.
// Search, tiles with live previews, new / duplicate / delete. Selecting a
// template hands off to _TemplateBody (template_editor_screen.dart).

part of 'template_editor_screen.dart';

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
              OutlinedButton.icon(
                onPressed: _importTemplate,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Import'),
              ),
              const SizedBox(width: 8),
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
    // Empty content: the tile shows each text layer's PLACEHOLDER (plus the
    // bound-text preview samples), so what you author is what the tile shows —
    // sample content would mask the placeholders on the default field ids.
    final data = composeCard(
      t.data,
      content: const CardContent(),
      symbolImageIds: ref.watch(textSymbolMapProvider),
      symbolsById: ref.watch(symbolsMapProvider),
      frames: ref.watch(framesMapProvider),
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
                          showPlaceholders: true,
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
        if (v == 'export') _exportTemplate(t);
        if (v == 'delete') widget.onDelete(t);
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        PopupMenuItem(value: 'export', child: Text('Export JSON…')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- Template share: export / import (model/template_share.dart) --------
  // Images are not part of a template file: the spec references ImageStore ids
  // that only exist on the exporting machine. Seeded-frame borders and palette
  // snapshots travel intact; anything else image-backed shows placeholders on
  // the importing side.

  Future<void> _exportTemplate(TemplateEntry t) async {
    final json = templateShareToJson(t.name, t.data);
    final path = await ref.read(cardExporterProvider).saveDocument(
          Uint8List.fromList(utf8.encode(json)),
          fileName: '${t.name.trim().isEmpty ? 'template' : t.name}_template',
          extension: 'json',
          dialogTitle: 'Export template JSON',
        );
    if (path == null) return; // cancelled
    _snack('Template exported: $path');
  }

  Future<void> _importTemplate() async {
    // FileType.any, same reasoning as Backup restore: json-extension filters
    // are unreliable on some Android pickers.
    final res = await FilePicker.pickFiles(type: FileType.any);
    if (res == null || res.files.isEmpty) return;
    final picked = res.files.single;
    final Uint8List bytes;
    try {
      bytes = picked.path != null
          ? await File(picked.path!).readAsBytes()
          : await picked.readAsBytes();
    } catch (_) {
      _snack("Couldn't read the selected file.");
      return;
    }

    final TemplateShare share;
    try {
      share = templateShareFromJson(utf8.decode(bytes, allowMalformed: true));
    } on FormatException catch (e) {
      _snack(e.message);
      return;
    }

    // Always a NEW template (fresh id, appended position, name de-duplicated
    // to "Name (2)" on collision) — imports never overwrite, even if the
    // sender exported one of the seeded defaults.
    await ref
        .read(templateRepositoryProvider)
        .createWithUniqueName(share.name, share.data);
    _snack('Imported "${share.name}". Images aren\'t included in template '
        'files, so any custom sprites need re-attaching.');
  }
}
