// lib/features/template_editor/template_editor_browser.dart
//
// The template BROWSER: the grid you land on before opening a template.
// Search, folders, tiles with live previews, new / duplicate / export /
// import / delete. Selecting a template hands off to _TemplateBody
// (template_editor_screen.dart).
//
// Folders mirror the Collection's set browser on purpose, so the two browsers
// feel like one app: folder TILES at the root (2x2 cover of member previews,
// name + count) that you DRILL INTO, a back header inside a folder, long-press
// multi-select with a docked selection bar, and a delete flow that asks what
// to do with the contents. Folders are real rows (TemplateFolderEntry), so an
// empty folder is a normal thing to have.

part of 'template_editor_screen.dart';

// ---------------------------------------------------------------------------
// Template Browser — the grid you land on. Pick a template to edit it.
// ---------------------------------------------------------------------------

class _TemplateBrowser extends ConsumerStatefulWidget {
  final List<TemplateEntry> templates;
  final List<TemplateFolderEntry> folders;
  final Set<String> inUseIds;
  final Map<String, ColorValue> palette;
  final ValueChanged<String> onOpen;

  /// Create a template in the given folder id ('' = ungrouped) — so "New"
  /// while inside a folder puts the template there.
  final ValueChanged<String> onNew;
  final ValueChanged<TemplateEntry> onDuplicate;
  final ValueChanged<TemplateEntry> onDelete;

  const _TemplateBrowser({
    required this.templates,
    required this.folders,
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

  /// The folder currently drilled into (id); null = root. Like the
  /// Collection's `_openKey`. Session state, not persisted.
  String? _openFolder;

  /// Long-press multi-select over FOLDERS at the root (the Collection's root
  /// selection, same gestures: long-press starts it, tap toggles).
  bool _selecting = false;
  final Set<String> _selected = <String>{};

  // ---- grouping helpers ---------------------------------------------------

  List<TemplateEntry> _inFolder(String folderId) => [
        for (final t in widget.templates)
          if (t.folder.trim() == folderId) t,
      ];

  /// Templates with no folder — including any whose folder id no longer
  /// resolves, so a stray row can never become invisible.
  List<TemplateEntry> get _loose {
    final ids = {for (final f in widget.folders) f.id};
    return [
      for (final t in widget.templates)
        if (t.folder.trim().isEmpty || !ids.contains(t.folder.trim())) t,
    ];
  }

  TemplateFolderEntry? _folderById(String id) {
    for (final f in widget.folders) {
      if (f.id == id) return f;
    }
    return null;
  }

  String _folderName(String id) => _folderById(id)?.name ?? '';

  void _cancelSelection() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _enterSelection(String id) {
    setState(() {
      _selecting = true;
      _selected
        ..clear()
        ..add(id);
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

  @override
  Widget build(BuildContext context) {
    // The open folder can be deleted from under us (or emptied away).
    final open = _openFolder;
    if (open != null && _folderById(open) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _openFolder = null);
      });
    }
    // Selection only exists at the root; drop stale ids.
    if (_selecting && _selected.any((id) => _folderById(id) == null)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _selected.removeWhere((id) => _folderById(id) == null);
          if (_selected.isEmpty) _selecting = false;
        });
      });
    }

    return PopScope(
      // Back cancels selection first, then leaves the folder, then the browser.
      canPop: _openFolder == null && !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop || !mounted) return;
        if (_selecting) {
          _cancelSelection();
        } else {
          setState(() => _openFolder = null);
        }
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search),
                hintText: _openFolder == null
                    ? 'Search templates…'
                    : 'Search in ${_folderName(_openFolder!)}…',
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          Expanded(child: _body()),
          if (_selecting)
            _TemplateSelectionBar(
              count: _selected.length,
              onDelete: _selected.isEmpty ? null : _deleteSelectedFolders,
              onCancel: _cancelSelection,
            ),
        ],
      ),
    );
  }

  /// Header: title (or back + folder name) on the left, actions pinned RIGHT.
  /// The leading widget is Expanded and there is no Spacer — an earlier
  /// Flexible+Spacer pair split the free space between them, which is what
  /// left the buttons floating short of the right edge.
  Widget _header() {
    final scheme = Theme.of(context).colorScheme;
    final open = _openFolder;

    final Widget leading = _selecting
        ? Text('Select folders',
            style: Theme.of(context).textTheme.titleLarge,
            overflow: TextOverflow.ellipsis)
        : open == null
            ? Text('Templates',
                style: Theme.of(context).textTheme.titleLarge,
                overflow: TextOverflow.ellipsis)
            : Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: () => setState(() => _openFolder = null),
                  ),
                  Icon(Icons.folder_outlined,
                      size: 20, color: scheme.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(_folderName(open),
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleLarge),
                  ),
                ],
              );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
      child: LayoutBuilder(
        builder: (context, c) {
          // Three actions don't fit a phone header: keep "New" as the primary
          // button and fold the rest into an overflow menu when narrow.
          final wide = c.maxWidth >= 520;
          final actions = <Widget>[
            if (_selecting)
              TextButton(
                  onPressed: _cancelSelection, child: const Text('Cancel'))
            else if (wide) ...[
              if (open == null)
                OutlinedButton.icon(
                  onPressed: _newFolder,
                  icon: const Icon(Icons.create_new_folder_outlined, size: 18),
                  label: const Text('New folder'),
                ),
              if (open == null) const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _importTemplate,
                icon: const Icon(Icons.file_download_outlined, size: 18),
                label: const Text('Import'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => widget.onNew(open ?? ''),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New'),
              ),
            ] else ...[
              FilledButton.icon(
                onPressed: () => widget.onNew(open ?? ''),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('New'),
              ),
              PopupMenuButton<String>(
                tooltip: '',
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'folder') _newFolder();
                  if (v == 'import') _importTemplate();
                },
                itemBuilder: (context) => [
                  if (open == null)
                    const PopupMenuItem(
                        value: 'folder', child: Text('New folder…')),
                  const PopupMenuItem(
                      value: 'import', child: Text('Import JSON…')),
                ],
              ),
            ],
          ];

          return Row(
            children: [
              Expanded(child: leading),
              ...actions,
            ],
          );
        },
      ),
    );
  }

  Widget _body() {
    final q = _query.trim().toLowerCase();
    final open = _openFolder;

    // Inside a folder: its templates, filtered by the search box.
    if (open != null) {
      final items = [
        for (final t in _inFolder(open))
          if (q.isEmpty || t.name.toLowerCase().contains(q)) t,
      ];
      if (items.isEmpty) {
        return _empty(q.isEmpty
            ? 'This folder is empty — use New to add a template, or move one '
                'in from its ⋮ menu.'
            : 'Nothing in ${_folderName(open)} matches "$_query".');
      }
      return _grid([for (final t in items) _tile(context, t)]);
    }

    // Root while searching: flatten across folders (headers would hide
    // matches), and a folder NAME counts as a match so typing one finds its
    // contents — the Collection's root search rule.
    if (q.isNotEmpty) {
      final items = [
        for (final t in widget.templates)
          if (t.name.toLowerCase().contains(q) ||
              _folderName(t.folder.trim()).toLowerCase().contains(q))
            t,
      ];
      if (items.isEmpty) return _empty('No templates match "$_query".');
      return _grid([for (final t in items) _tile(context, t)]);
    }

    // Root: folder tiles first, then ungrouped templates.
    if (widget.templates.isEmpty && widget.folders.isEmpty) {
      return _empty('No templates yet — tap New to start one.');
    }
    return _grid([
      for (final f in widget.folders) _folderTile(f),
      for (final t in _loose) _tile(context, t),
    ]);
  }

  Widget _empty(String message) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );

  Widget _grid(List<Widget> children) => GridView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 180,
          childAspectRatio: 0.6,
          crossAxisSpacing: 14,
          mainAxisSpacing: 14,
        ),
        children: children,
      );

  // ---- folder tile (mirrors the Collection's set tile) --------------------

  /// A folder as a browsable tile: 2x2 cover of member previews, name, count.
  /// Tap opens it (or toggles selection while selecting); long-press starts
  /// selection — the Collection's gestures exactly.
  Widget _folderTile(TemplateFolderEntry folder) {
    final scheme = Theme.of(context).colorScheme;
    final members = _inFolder(folder.id);
    final selected = _selected.contains(folder.id);

    final tile = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: _folderCover(members)),
                if (!_selecting)
                  Positioned(right: -10, top: -10, child: _folderMenu(folder)),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.folder_outlined,
                  size: 14, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  folder.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${members.length}',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );

    return _SelectRing(
      selecting: _selecting,
      selected: selected,
      onTap: () {
        if (_selecting) {
          _toggleSelected(folder.id);
        } else {
          setState(() => _openFolder = folder.id);
        }
      },
      onLongPress: _selecting ? null : () => _enterSelection(folder.id),
      child: tile,
    );
  }

  Widget _folderMenu(TemplateFolderEntry folder) {
    return PopupMenuButton<String>(
      tooltip: '',
      icon: Icon(Icons.more_vert,
          size: 18, color: Theme.of(context).colorScheme.onSurfaceVariant),
      onSelected: (v) {
        if (v == 'open') setState(() => _openFolder = folder.id);
        if (v == 'rename') _renameFolder(folder);
        if (v == 'select') _enterSelection(folder.id);
        if (v == 'delete') _deleteFolders([folder]);
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'open', child: Text('Open')),
        PopupMenuItem(value: 'rename', child: Text('Rename…')),
        PopupMenuItem(value: 'select', child: Text('Select')),
        PopupMenuItem(value: 'delete', child: Text('Delete…')),
      ],
    );
  }

  /// Fixed 2x2 cover: up to four member previews in equal cells, empty cells
  /// filled with a placeholder so folder tiles never change size with count
  /// (and an empty folder still looks like a folder).
  Widget _folderCover(List<TemplateEntry> members) {
    const gap = 4.0;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final cellW = ((c.maxWidth - gap) / 2).floorToDouble();
        final cellH = ((c.maxHeight - gap) / 2).floorToDouble();
        if (cellW <= 0 || cellH <= 0) return const SizedBox.shrink();

        Widget cell(int i) {
          if (i >= members.length) {
            return Container(
              width: cellW,
              height: cellH,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(4),
              ),
            );
          }
          return SizedBox(
            width: cellW,
            height: cellH,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: FittedBox(
                fit: BoxFit.cover,
                clipBehavior: Clip.hardEdge,
                child: DecodedCardPreview(
                  card: _composeTile(members[i]),
                  palette: widget.palette,
                  imageStore: ref.read(imageStoreProvider),
                  width: cellW,
                  showPlaceholders: true,
                ),
              ),
            ),
          );
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [cell(0), const SizedBox(width: gap), cell(1)]),
            const SizedBox(height: gap),
            Row(children: [cell(2), const SizedBox(width: gap), cell(3)]),
          ],
        );
      },
    );
  }

  // ---- template tile ------------------------------------------------------

  /// Empty content: tiles show each text layer's PLACEHOLDER (plus the
  /// bound-text preview samples), so what you author is what the tile shows —
  /// sample content would mask the placeholders on the default field ids.
  CardData _composeTile(TemplateEntry t) => composeCard(
        t.data,
        content: const CardContent(),
        symbolImageIds: ref.watch(textSymbolMapProvider),
        symbolsById: ref.watch(symbolsMapProvider),
        frames: ref.watch(framesMapProvider),
        footerPlaceholder: _footerPlaceholder,
      );

  Widget _tile(BuildContext context, TemplateEntry t) {
    final scheme = Theme.of(context).colorScheme;
    final inUse = widget.inUseIds.contains(t.id);
    final data = _composeTile(t);
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
        if (v == 'folder') _moveToFolder(t);
        if (v == 'export') _exportTemplate(t);
        if (v == 'delete') widget.onDelete(t);
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'edit', child: Text('Edit')),
        PopupMenuItem(value: 'duplicate', child: Text('Duplicate')),
        PopupMenuItem(value: 'folder', child: Text('Move to folder…')),
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

  // ---- folder actions -----------------------------------------------------

  Future<void> _newFolder() async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const _FolderNameDialog(title: 'New folder'),
    );
    if (name == null) return;
    final id = await ref
        .read(templateFolderRepositoryProvider)
        .createWithUniqueName(name);
    if (!mounted) return;
    // Drop straight into the new (empty) folder, so "New folder → New" is the
    // natural way to start a themed set of templates.
    setState(() => _openFolder = id);
  }

  Future<void> _renameFolder(TemplateFolderEntry folder) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) =>
          _FolderNameDialog(title: 'Rename folder', initial: folder.name),
    );
    if (name == null || name.trim() == folder.name) return;
    await ref.read(templateFolderRepositoryProvider).rename(folder.id, name);
  }

  Future<void> _moveToFolder(TemplateEntry t) async {
    final chosen = await showDialog<String>(
      context: context,
      builder: (_) => _FolderPickerDialog(
        current: t.folder.trim(),
        folders: widget.folders,
      ),
    );
    if (chosen == null) return; // cancelled
    if (chosen == t.folder.trim()) return;
    await ref.read(templateRepositoryProvider).setFolder(t.id, chosen);
    if (!mounted) return;
    _snack(chosen.isEmpty
        ? 'Moved "${t.name}" out of its folder.'
        : 'Moved "${t.name}" to ${_folderName(chosen)}.');
  }

  Future<void> _deleteSelectedFolders() async {
    final picked = [
      for (final id in _selected)
        if (_folderById(id) != null) _folderById(id)!,
    ];
    if (picked.isEmpty) return;
    await _deleteFolders(picked);
  }

  /// The three-way delete, matching the Collection's set deletion: cancel,
  /// delete the folder only (its templates survive, unfiled), or delete the
  /// templates too — the destructive path always takes a second confirmation.
  Future<void> _deleteFolders(List<TemplateFolderEntry> folders) async {
    final members = <TemplateEntry>[
      for (final f in folders) ..._inFolder(f.id),
    ];
    final label = folders.length == 1
        ? '"${folders.first.name}"'
        : '${folders.length} folders';

    if (members.isEmpty) {
      final ok = await _confirmDialog(
        title: 'Delete $label?',
        message: folders.length == 1
            ? 'This empty folder will be removed.'
            : 'These empty folders will be removed.',
        danger: 'Delete',
      );
      if (ok != true) return;
      await _removeFolderRows(folders);
      return;
    }

    if (!mounted) return;
    final n = members.length;
    final choice = await showDialog<String>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: Text('Delete $label?'),
        content: Text(
            '${folders.length == 1 ? 'This folder holds' : 'These folders hold'} '
            '$n template${n == 1 ? '' : 's'}. Delete the templates too, or '
            'keep them by moving them out of the folder?'),
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

    final templateRepo = ref.read(templateRepositoryProvider);

    if (choice == 'all') {
      if (!mounted) return;
      final sure = await _confirmDialog(
        title: 'Are you sure?',
        message: 'All $n template${n == 1 ? '' : 's'} in $label will be '
            'permanently removed. Cards using them keep their retained '
            'snapshot, so existing cards still render.',
        danger: 'Delete all',
      );
      if (sure != true) return;
      for (final t in members) {
        await templateRepo.delete(t.id);
      }
    } else {
      // 'folder' — keep the templates, drop them out of the folder.
      for (final t in members) {
        await templateRepo.setFolder(t.id, '');
      }
    }
    await _removeFolderRows(folders);
  }

  Future<void> _removeFolderRows(List<TemplateFolderEntry> folders) async {
    final repo = ref.read(templateFolderRepositoryProvider);
    for (final f in folders) {
      await repo.delete(f.id);
    }
    if (!mounted) return;
    setState(() {
      _selected.removeAll(folders.map((f) => f.id));
      if (_selected.isEmpty) _selecting = false;
      if (folders.any((f) => f.id == _openFolder)) _openFolder = null;
    });
  }

  Future<bool?> _confirmDialog({
    required String title,
    required String message,
    required String danger,
  }) =>
      showDialog<bool>(
        context: context,
        builder: (d) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(d, false),
                child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error),
              onPressed: () => Navigator.pop(d, true),
              child: Text(danger),
            ),
          ],
        ),
      );

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
    // sender exported one of the seeded defaults. Imports land in the folder
    // you are currently browsing.
    await ref.read(templateRepositoryProvider).createWithUniqueName(
        share.name, share.data,
        folder: _openFolder ?? '');
    _snack('Imported "${share.name}". Images aren\'t included in template '
        'files, so any custom sprites need re-attaching.');
  }
}

/// Wraps a folder tile with the selection affordance — an accent ring plus a
/// check while selecting. The Collection's `_Selectable`, reimplemented here
/// because that one is private to the collection library.
class _SelectRing extends StatelessWidget {
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;

  const _SelectRing({
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? scheme.primary : Colors.transparent,
                width: 2.5,
              ),
            ),
            padding: const EdgeInsets.all(4),
            child: child,
          ),
          if (selecting)
            Positioned(
              top: 8,
              left: 8,
              child: Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
                size: 22,
              ),
            ),
        ],
      ),
    );
  }
}

/// The docked bulk-action bar shown while folders are selected (the
/// Collection's `_SelectionBar`, reimplemented for this library).
class _TemplateSelectionBar extends StatelessWidget {
  final int count;
  final VoidCallback? onDelete;
  final VoidCallback onCancel;

  const _TemplateSelectionBar({
    required this.count,
    required this.onDelete,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 8,
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            children: [
              Text('$count selected',
                  style: Theme.of(context).textTheme.titleSmall),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                onPressed: onDelete,
              ),
              TextButton(onPressed: onCancel, child: const Text('Done')),
            ],
          ),
        ),
      ),
    );
  }
}

/// Name a new folder / rename an existing one. Owns its controller and
/// disposes it in State (dialog-lifecycle rule).
class _FolderNameDialog extends StatefulWidget {
  final String title;
  final String initial;
  const _FolderNameDialog({required this.title, this.initial = ''});

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  late final TextEditingController _ctl =
      TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _pop(String? value) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) {
    final name = _ctl.text.trim();
    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _ctl,
        autofocus: true,
        onChanged: (_) => setState(() {}),
        onSubmitted: name.isEmpty ? null : (v) => _pop(v.trim()),
        decoration: const InputDecoration(
          labelText: 'Folder name',
          border: OutlineInputBorder(),
        ),
      ),
      actions: [
        TextButton(onPressed: () => _pop(null), child: const Text('Cancel')),
        FilledButton(
          onPressed: name.isEmpty ? null : () => _pop(name),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Move-to-folder picker: existing folders as selectable rows plus "No
/// folder". Plain ListTiles with a trailing check rather than RadioListTile —
/// Radio's groupValue/onChanged are deprecated after Flutter 3.32 in favour of
/// a RadioGroup ancestor, and a check row reads the same. Pops a folder ID
/// ('' = ungrouped). New folders are made from the browser's New folder
/// button, so this dialog stays a pure chooser.
class _FolderPickerDialog extends StatefulWidget {
  final String current;
  final List<TemplateFolderEntry> folders;
  const _FolderPickerDialog({required this.current, required this.folders});

  @override
  State<_FolderPickerDialog> createState() => _FolderPickerDialogState();
}

class _FolderPickerDialogState extends State<_FolderPickerDialog> {
  late String _selected = widget.current;

  void _pop(String? value) {
    FocusManager.instance.primaryFocus?.unfocus();
    Navigator.pop(context, value);
  }

  Widget _choice({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    IconData icon = Icons.folder_outlined,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon,
          size: 20,
          color: selected ? scheme.primary : scheme.onSurfaceVariant),
      title: Text(
        label,
        overflow: TextOverflow.ellipsis,
        style: selected
            ? TextStyle(color: scheme.primary, fontWeight: FontWeight.w600)
            : null,
      ),
      trailing:
          selected ? Icon(Icons.check, size: 18, color: scheme.primary) : null,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Move to folder'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _choice(
                label: 'No folder',
                icon: Icons.folder_off_outlined,
                selected: _selected.isEmpty,
                onTap: () => setState(() => _selected = ''),
              ),
              if (widget.folders.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No folders yet — make one with New folder in the '
                    'template browser.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              for (final f in widget.folders)
                _choice(
                  label: f.name,
                  selected: _selected == f.id,
                  onTap: () => setState(() => _selected = f.id),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => _pop(null), child: const Text('Cancel')),
        FilledButton(
            onPressed: () => _pop(_selected), child: const Text('Move')),
      ],
    );
  }
}
