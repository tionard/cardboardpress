part of 'collection_screen.dart';

// The OPENED SET: a folder's cards as a grid, with search within the set, a
// settings cog, "New Card", per-card ⋯ menu, and long-press card selection
// (Export / Share / Delete bar). A dedicated Reorder mode (toggled from the
// header) swaps the grid for a drag-handle list so reordering never collides
// with the long-press that starts selection; collector numbers follow the new
// order live. Pure view construction.

extension _SetView on _CollectionScreenState {
  Widget _buildOpenedSet(_Folder folder, _CardCtx ctx) {
    final q = _query.toLowerCase();

    // Keep each card's ORIGINAL index in the folder so collector numbering and
    // composition stay correct even when search narrows the visible list.
    final entries = <(CardEntry, int)>[];
    for (var i = 0; i < folder.cards.length; i++) {
      final c = folder.cards[i];
      if (_query.isEmpty || _cardName(c, ctx).toLowerCase().contains(q)) {
        entries.add((c, i));
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _CollectionHeader(
          leading: Row(
            children: [
              IconButton(
                tooltip: _reordering ? 'Done reordering' : 'Back to Collection',
                icon: const Icon(Icons.arrow_back),
                onPressed: _reordering ? _exitReorder : _closeFolder,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      folder.title,
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      _reordering
                          ? 'Drag the handles to reorder'
                          : (folder.abbr.isEmpty
                              ? '${folder.cards.length} cards'
                              : '${folder.abbr} · ${folder.cards.length} cards'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
          trailing: _setHeaderTrailing(folder),
        ),
        if (!_reordering) _SearchBar(controller: _searchCtl, hint: 'Search this set…'),
        Expanded(
          child: _reordering
              ? _reorderList(folder, ctx)
              : (entries.isEmpty
                  ? _emptyState(folder)
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 12,
                        children: [
                          for (final (card, index) in entries)
                            _cardTile(folder, card, index, ctx),
                        ],
                      ),
                    )),
        ),
        if (_selecting && !_reordering) _cardSelectionBar(),
      ],
    );
  }

  List<Widget> _setHeaderTrailing(_Folder folder) {
    if (_reordering) {
      return [
        TextButton(onPressed: _exitReorder, child: const Text('Done')),
      ];
    }
    if (_selecting) {
      return [_setAction(folder)];
    }
    return [
      if (folder.cards.length >= 2)
        IconButton(
          tooltip: 'Reorder',
          icon: const Icon(Icons.swap_vert),
          onPressed: () =>
              _enterReorder([for (final c in folder.cards) c.id]),
        ),
      if (folder.set != null)
        IconButton(
          tooltip: 'Set settings',
          icon: const Icon(Icons.settings_outlined),
          onPressed: () => _openSetSettings(folder.set!),
        ),
      _setAction(folder),
    ];
  }

  Widget _setAction(_Folder folder) {
    if (_selecting) {
      return TextButton(
          onPressed: _cancelSelection, child: const Text('Cancel'));
    }
    return OutlinedButton.icon(
      onPressed: () => _newCard(folder.set?.id),
      icon: const Icon(Icons.add, size: 18),
      label: const Text('New Card'),
    );
  }

  Widget _emptyState(_Folder folder) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.style_outlined,
              size: 40,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            _query.isEmpty
                ? 'No cards here yet.'
                : 'No cards match "$_query".',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (_query.isEmpty) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: () => _newCard(folder.set?.id),
              icon: const Icon(Icons.add),
              label: const Text('New Card'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _cardTile(
      _Folder folder, CardEntry card, int index, _CardCtx ctx) {
    final scheme = Theme.of(context).colorScheme;
    final selected = _selected.contains(card.id);
    final name = _cardName(card, ctx);

    final tile = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecodedCardPreview(
          card: _compose(folder, card, index, ctx),
          palette: ctx.palette,
          imageStore: ctx.imageStore,
          width: 96,
        ),
        const SizedBox(height: 3),
        Text(
          name.isEmpty ? '(unnamed)' : name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    );

    // The ⋯ button is a sibling OVERLAY (not a child of _Selectable's gesture
    // detector), so its taps don't compete with the tile's open-editor tap.
    return SizedBox(
      width: 104,
      child: Stack(
        children: [
          _Selectable(
            selecting: _selecting,
            selected: selected,
            onTap: () =>
                _selecting ? _toggleSelected(card.id) : _openEditor(card.id),
            onLongPress: () => _selecting
                ? _toggleSelected(card.id)
                : _enterSelection(card.id),
            child: tile,
          ),
          if (!_selecting)
            Positioned(
              top: 6,
              right: 6,
              child: Material(
                color: scheme.surface.withValues(alpha: 0.85),
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _cardMenu(card, folder, index, ctx),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.more_horiz, size: 18),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _cardSelectionBar() {
    final empty = _selected.isEmpty;
    return _SelectionBar(
      count: _selected.length,
      actions: [
        IconButton(
          tooltip: 'Export…',
          icon: const Icon(Icons.download_outlined),
          onPressed: empty ? null : _bulkExportChooser,
        ),
        IconButton(
          tooltip: 'Share',
          icon: const Icon(Icons.ios_share_outlined),
          onPressed: empty ? null : _bulkShare,
        ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: empty ? null : _bulkDeleteCards,
        ),
      ],
    );
  }

  // ---- reorder mode ----

  Widget _reorderList(_Folder folder, _CardCtx ctx) {
    // Resolve the local id order to current card entries (skip any deleted
    // mid-reorder). Building from _reorderIds (not the stream order) keeps the
    // drag smooth and independent of when the persisted order re-emits.
    final byId = {for (final c in folder.cards) c.id: c};
    final ordered = <CardEntry>[];
    for (final id in _reorderIds) {
      final c = byId[id];
      if (c != null) ordered.add(c);
    }
    final numbering = folder.set?.numbering ?? false;
    final scheme = Theme.of(context).colorScheme;

    return ReorderableListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
      buildDefaultDragHandles: false,
      itemCount: ordered.length,
      onReorderItem: (oldIndex, newIndex) =>
          _applyReorder(oldIndex, newIndex, folder.set?.id),
      itemBuilder: (context, i) {
        final card = ordered[i];
        final name = _cardName(card, ctx);
        return Container(
          key: ValueKey(card.id),
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              if (numbering)
                SizedBox(
                  width: 42,
                  child: Text(
                    (i + 1).toString().padLeft(3, '0'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: scheme.onSurfaceVariant, letterSpacing: 0.5),
                  ),
                ),
              DecodedCardPreview(
                card: _compose(folder, card, i, ctx),
                palette: ctx.palette,
                imageStore: ctx.imageStore,
                width: 38,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name.isEmpty ? '(unnamed)' : name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              ReorderableDragStartListener(
                index: i,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
