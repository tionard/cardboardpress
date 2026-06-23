part of 'collection_screen.dart';

// The ROOT browser: folders (sets) as Large or Grid tiles, with search, a
// density slider (Grid), "New Set", and long-press folder selection. Pure view
// construction — every state change routes back through the screen State.

extension _RootView on _CollectionScreenState {
  Widget _buildRoot(List<_Folder> folders, _CardCtx ctx) {
    final visible = _query.isEmpty
        ? folders
        : folders.where((f) => _folderMatches(f, ctx)).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CollectionHeader(
          leading: Text('Collection',
              style: Theme.of(context).textTheme.titleLarge),
          trailing: [_rootAction()],
        ),
        _SearchBar(controller: _searchCtl, hint: 'Search all cards…'),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Row(
            children: [
              SegmentedButton<_View>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                      value: _View.large,
                      icon: Icon(Icons.view_agenda_outlined, size: 18),
                      label: Text('Large')),
                  ButtonSegment(
                      value: _View.grid,
                      icon: Icon(Icons.grid_view, size: 18),
                      label: Text('Grid')),
                ],
                selected: {_view},
                onSelectionChanged: (s) => _setView(s.first),
              ),
            ],
          ),
        ),
        if (_view == _View.grid)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: LabeledSlider(
              label: 'Per row',
              value: _density,
              min: 2,
              max: 5,
              step: 1,
              decimals: 0,
              labelWidth: 64,
              onChanged: _setDensity,
            ),
          ),
        Expanded(
          child: _view == _View.large
              ? _largeList(visible, ctx)
              : _gridList(visible, ctx),
        ),
        if (_selecting)
          _SelectionBar(
            count: _selected.length,
            actions: [
              IconButton(
                tooltip: 'Delete',
                icon: const Icon(Icons.delete_outline),
                onPressed: _selected.isEmpty ? null : _bulkDeleteFolders,
              ),
            ],
          ),
      ],
    );
  }

  Widget _rootAction() {
    if (_selecting) {
      return TextButton(
          onPressed: _cancelSelection, child: const Text('Cancel'));
    }
    return OutlinedButton.icon(
      onPressed: _newSet,
      icon: const Icon(Icons.create_new_folder_outlined, size: 18),
      label: const Text('New Set'),
    );
  }

  bool _folderMatches(_Folder f, _CardCtx ctx) {
    final q = _query.toLowerCase();
    if (f.title.toLowerCase().contains(q)) return true;
    for (final c in f.cards) {
      if (_cardName(c, ctx).toLowerCase().contains(q)) return true;
    }
    return false;
  }

  List<Widget> _folderThumbs(
      _Folder f, _CardCtx ctx, double width, int max) {
    final out = <Widget>[];
    for (var i = 0; i < f.cards.length && i < max; i++) {
      out.add(DecodedCardPreview(
        card: _compose(f, f.cards[i], i, ctx),
        palette: ctx.palette,
        imageStore: ctx.imageStore,
        width: width,
      ));
    }
    return out;
  }

  // ---- Large ----

  Widget _largeList(List<_Folder> folders, _CardCtx ctx) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [for (final f in folders) _largeFolderTile(f, ctx)],
    );
  }

  Widget _largeFolderTile(_Folder f, _CardCtx ctx) {
    final scheme = Theme.of(context).colorScheme;
    final selectable = !f.isUnassigned;
    final selected = _selected.contains(f.key);
    final dim = _selecting && !selectable;
    final symbol = f.set?.symbolId == null ? null : ctx.symbols[f.set!.symbolId];

    const previewW = 64.0; // bigger than before; fills the row better
    final previews = _folderThumbs(f, ctx, previewW, 4);
    final count = f.cards.length;
    final cardWord = count == 1 ? 'card' : 'cards';
    final subtitle = f.isUnassigned
        ? 'Permanent · $count $cardWord'
        : (f.abbr.isEmpty ? '$count $cardWord' : '${f.abbr} · $count $cardWord');

    final tile = Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: previewW * 1.4,
            child: previews.isEmpty
                ? Container(
                    width: previewW,
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.inbox_outlined,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
                  )
                : Row(
                    children: [
                      for (final p in previews)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: p,
                        ),
                    ],
                  ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              if (f.isUnassigned) ...[
                Icon(Icons.lock_outline,
                    size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      f.title,
                      style: Theme.of(context).textTheme.titleMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (symbol != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: _SetSymbolThumb(imageId: symbol.imageId, size: 26),
                ),
              if (f.set != null && !_selecting)
                IconButton(
                  tooltip: 'Set settings',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => _openSetSettings(f.set!),
                ),
            ],
          ),
        ],
      ),
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Opacity(
        opacity: dim ? 0.4 : 1,
        child: _Selectable(
          selecting: _selecting && selectable,
          selected: selected,
          onTap: () {
            if (_selecting) {
              if (selectable) _toggleSelected(f.key);
            } else {
              _openFolder(f.key);
            }
          },
          onLongPress: (selectable && !_selecting)
              ? () => _enterSelection(f.key)
              : null,
          child: tile,
        ),
      ),
    );
  }

  // ---- Grid ----

  Widget _gridList(List<_Folder> folders, _CardCtx ctx) {
    return LayoutBuilder(
      builder: (c, cns) {
        final cols = _density.round().clamp(2, 5);
        const gap = 12.0;
        final tileW = (cns.maxWidth - 32 - gap * (cols - 1)) / cols;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          child: Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final f in folders)
                SizedBox(width: tileW, child: _gridFolderTile(f, ctx)),
            ],
          ),
        );
      },
    );
  }

  Widget _gridFolderTile(_Folder f, _CardCtx ctx) {
    final scheme = Theme.of(context).colorScheme;
    final selectable = !f.isUnassigned;
    final selected = _selected.contains(f.key);
    final dim = _selecting && !selectable;

    final tile = Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          _gridFolderCover(f, ctx),
          const SizedBox(height: 8),
          Row(
            children: [
              if (f.isUnassigned) ...[
                const Icon(Icons.lock_outline, size: 13),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  f.title,
                  style: Theme.of(context).textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (f.set != null && !_selecting)
                SizedBox(
                  width: 28,
                  height: 28,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    tooltip: 'Set settings',
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    onPressed: () => _openSetSettings(f.set!),
                  ),
                ),
            ],
          ),
          Text(
            f.abbr.isEmpty
                ? '${f.cards.length} cards'
                : '${f.abbr} · ${f.cards.length}',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );

    return Opacity(
      opacity: dim ? 0.4 : 1,
      child: _Selectable(
        selecting: _selecting && selectable,
        selected: selected,
        onTap: () {
          if (_selecting) {
            if (selectable) _toggleSelected(f.key);
          } else {
            _openFolder(f.key);
          }
        },
        onLongPress:
            (selectable && !_selecting) ? () => _enterSelection(f.key) : null,
        child: tile,
      ),
    );
  }

  /// A fixed 2×2 folder cover: up to four card thumbnails in equal cells, empty
  /// cells filled with a placeholder so every set tile is the SAME size
  /// regardless of how many cards it holds. Measures its own available width
  /// (rather than being told), so ancestor padding/borders can't make it
  /// overflow.
  Widget _gridFolderCover(_Folder f, _CardCtx ctx) {
    const gap = 6.0;
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, c) {
        final cellW = ((c.maxWidth - gap) / 2).floorToDouble();
        final cellH = cellW * 1.4; // card-ish aspect; identical for every tile

        Widget cell(int i) {
          if (i >= f.cards.length) {
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
                  card: _compose(f, f.cards[i], i, ctx),
                  palette: ctx.palette,
                  imageStore: ctx.imageStore,
                  width: cellW,
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
}
