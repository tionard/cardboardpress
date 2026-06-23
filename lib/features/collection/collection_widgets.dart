part of 'collection_screen.dart';

// Leaf widgets and the small bundle of resolver maps shared by both views.

/// The resolver maps + image store a card needs to compose and render. Bundled
/// so the view builders and action methods take one argument instead of six.
class _CardCtx {
  final Map<String, TemplateData> templates;
  final Map<String, ColorValue> palette;
  final Map<String, RarityEntry> rarities;
  final Map<String, SymbolEntry> symbols;
  final Map<String, String> textSymbols;
  final ImageStore imageStore;

  const _CardCtx({
    required this.templates,
    required this.palette,
    required this.rarities,
    required this.symbols,
    required this.textSymbols,
    required this.imageStore,
  });
}

/// The header row both views share: a leading widget (title or back+name), and a
/// trailing action that flips to "Cancel" while selecting.
class _CollectionHeader extends StatelessWidget {
  final Widget leading;
  final List<Widget> trailing;
  const _CollectionHeader({required this.leading, this.trailing = const []});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
      child: Row(
        children: [
          Expanded(child: leading),
          ...trailing,
        ],
      ),
    );
  }
}

/// The pinned search field (spec §4.1 — search stays on top).
class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  const _SearchBar({required this.controller, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: TextField(
        controller: controller,
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Icon(Icons.search, size: 20),
          hintText: hint,
          border: const OutlineInputBorder(),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: controller.clear,
                ),
        ),
      ),
    );
  }
}

/// The docked bulk-action bar that slides up while selecting.
class _SelectionBar extends StatelessWidget {
  final int count;
  final List<Widget> actions;
  const _SelectionBar({required this.count, required this.actions});

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
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// Up to four card thumbnails arranged as a gallery folder cover. Shows a small
/// "empty" hint when the folder has no cards.
class _FolderCover extends StatelessWidget {
  final List<Widget> thumbs; // already-built mini previews (0..4)
  final double height;
  const _FolderCover({required this.thumbs, required this.height});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (thumbs.isEmpty) {
      return Container(
        height: height,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(10),
        ),
        alignment: Alignment.center,
        child: Icon(Icons.inbox_outlined,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.5)),
      );
    }
    return SizedBox(
      height: height,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final t in thumbs)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: t,
            ),
        ],
      ),
    );
  }
}

/// Wraps a tile with the selection affordance: an accent ring + check while the
/// item is selected.
class _Selectable extends StatelessWidget {
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final Widget child;
  const _Selectable({
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

/// Settings for a real set: footer-feeding fields, the numbering toggle, the set
/// symbol, and a delete entry that hands back to the screen's three-way flow.
class _SetSettingsSheet extends ConsumerStatefulWidget {
  final SetEntry set;
  final VoidCallback onDelete;
  const _SetSettingsSheet({required this.set, required this.onDelete});

  @override
  ConsumerState<_SetSettingsSheet> createState() => _SetSettingsSheetState();
}

class _SetSettingsSheetState extends ConsumerState<_SetSettingsSheet> {
  late final TextEditingController _name;
  late final TextEditingController _abbr;
  late final TextEditingController _owner;
  late final TextEditingController _year;
  late bool _numbering;

  @override
  void initState() {
    super.initState();
    final s = widget.set;
    _name = TextEditingController(text: s.name);
    _abbr = TextEditingController(text: s.abbreviation);
    _owner = TextEditingController(text: s.owner);
    _year = TextEditingController(text: s.year.toString());
    _numbering = s.numbering;
  }

  @override
  void dispose() {
    _name.dispose();
    _abbr.dispose();
    _owner.dispose();
    _year.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final yr = int.tryParse(_year.text.trim());
    await ref.read(setRepositoryProvider).update(
          widget.set.id,
          name: _name.text,
          abbreviation: _abbr.text,
          owner: _owner.text,
          year: yr,
          numbering: _numbering,
        );
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    // Reflect a live symbol change while the sheet is open.
    final sets = ref.watch(setsProvider).maybeWhen(data: (l) => l, orElse: () => const <SetEntry>[]);
    SetEntry current = widget.set;
    for (final s in sets) {
      if (s.id == widget.set.id) current = s;
    }
    final symbols = ref.watch(symbolsMapProvider);
    final chosen =
        current.symbolId == null ? null : symbols[current.symbolId];
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Text('Set settings',
                      style: Theme.of(context).textTheme.titleLarge),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _abbr,
                      maxLength: 5,
                      decoration: const InputDecoration(
                          labelText: 'Abbreviation', counterText: ''),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 96,
                    child: TextField(
                      controller: _year,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Year'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _owner,
                decoration: const InputDecoration(
                    labelText: 'Copyright owner',
                    helperText: 'Footer shows "© year owner"'),
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Collector numbering'),
                subtitle: const Text(
                    'Footer shows NNN/Total from each card\'s position'),
                value: _numbering,
                onChanged: (v) => setState(() => _numbering = v),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: chosen == null
                    ? const Icon(Icons.star_border)
                    : _SetSymbolThumb(imageId: chosen.imageId, size: 28),
                title: const Text('Set symbol'),
                subtitle: Text(chosen == null ? 'None' : chosen.name),
                trailing: TextButton(
                  onPressed: () async {
                    final choice = await pickSymbol(context, ref,
                        currentId: current.symbolId);
                    if (choice == null) return;
                    await ref
                        .read(setRepositoryProvider)
                        .setSymbol(current.id, choice.id);
                  },
                  child: Text(chosen == null ? 'Choose' : 'Change'),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      widget.onDelete();
                    },
                    icon: Icon(Icons.delete_outline,
                        color: Theme.of(context).colorScheme.error),
                    label: Text('Delete set',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                  ),
                  const Spacer(),
                  FilledButton(onPressed: _save, child: const Text('Save')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small thumbnail of a set's chosen symbol (folder header / settings). Loads
/// its bytes from the ImageStore once and caches across instances.
class _SetSymbolThumb extends ConsumerStatefulWidget {
  final String imageId;
  final double size;
  const _SetSymbolThumb({required this.imageId, required this.size});

  @override
  ConsumerState<_SetSymbolThumb> createState() => _SetSymbolThumbState();
}

class _SetSymbolThumbState extends ConsumerState<_SetSymbolThumb> {
  static final Map<String, Uint8List> _cache = {};
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant _SetSymbolThumb old) {
    super.didUpdateWidget(old);
    if (old.imageId != widget.imageId) _load();
  }

  Future<void> _load() async {
    final cached = _cache[widget.imageId];
    if (cached != null) {
      setState(() => _bytes = cached);
      return;
    }
    final bytes = await ref.read(imageStoreProvider).load(widget.imageId);
    if (!mounted || bytes == null) return;
    _cache[widget.imageId] = bytes;
    setState(() => _bytes = bytes);
  }

  @override
  Widget build(BuildContext context) {
    if (_bytes == null) return SizedBox(width: widget.size, height: widget.size);
    return Image.memory(_bytes!,
        width: widget.size, height: widget.size, fit: BoxFit.contain);
  }
}
