// lib/features/customization/symbol_picker.dart
//
// A reusable picker over the standalone Symbol library (spec §3.3). Used to
// choose a set's set symbol now, and the Rules-field watermark later. Returns:
//
//   * null                 -> cancelled (caller does nothing)
//   * SymbolChoice(null)    -> "None" chosen (clear the symbol)
//   * SymbolChoice('sym_…') -> that symbol chosen
//
// Usage:
//   final choice = await pickSymbol(context, ref, currentId: set.symbolId);
//   if (choice != null) repo.setSymbol(set.id, choice.id);

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/card_model.dart';
import '../../state/providers.dart';

/// The result of [pickSymbol]. [id] null means the user chose "None".
class SymbolChoice {
  final String? id;
  const SymbolChoice(this.id);
}

Future<SymbolChoice?> pickSymbol(
  BuildContext context,
  WidgetRef ref, {
  String? currentId,
}) {
  return showDialog<SymbolChoice>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Choose symbol'),
      content: SizedBox(
        width: 360,
        child: Consumer(
          builder: (ctx, ref, _) {
            final async = ref.watch(symbolsProvider);
            return async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('Could not load symbols: $e'),
              data: (symbols) => _grid(ctx, ref, symbols, currentId),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
      ],
    ),
  );
}

Widget _grid(
    BuildContext context, WidgetRef ref, List<SymbolEntry> symbols, String? currentId) {
  if (symbols.isEmpty) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Text(
        'No symbols yet — add some in Customize → Symbols first.',
        style: Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
  return SingleChildScrollView(
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _noneTile(context, selected: currentId == null),
        for (final s in symbols)
          _symbolTile(context, ref, s, selected: s.id == currentId),
      ],
    ),
  );
}

Widget _noneTile(BuildContext context, {required bool selected}) {
  final scheme = Theme.of(context).colorScheme;
  return _Tile(
    selected: selected,
    onTap: () => Navigator.pop(context, const SymbolChoice(null)),
    label: 'None',
    child: Icon(Icons.block, color: scheme.onSurfaceVariant),
  );
}

Widget _symbolTile(BuildContext context, WidgetRef ref, SymbolEntry s,
    {required bool selected}) {
  return _Tile(
    selected: selected,
    onTap: () => Navigator.pop(context, SymbolChoice(s.id)),
    label: s.name,
    child: _PickerThumb(imageId: s.imageId, size: 48),
  );
}

class _Tile extends StatelessWidget {
  final bool selected;
  final VoidCallback onTap;
  final String label;
  final Widget child;

  const _Tile({
    required this.selected,
    required this.onTap,
    required this.label,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 80,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant,
                  width: selected ? 3 : 1,
                ),
              ),
              child: child,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

/// Loads a symbol's bytes from the ImageStore once and shows them, with a small
/// process-wide cache so reopening the picker doesn't re-read the file.
class _PickerThumb extends ConsumerStatefulWidget {
  final String imageId;
  final double size;
  const _PickerThumb({required this.imageId, required this.size});

  @override
  ConsumerState<_PickerThumb> createState() => _PickerThumbState();
}

class _PickerThumbState extends ConsumerState<_PickerThumb> {
  static final Map<String, Uint8List> _cache = {};
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
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
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: _bytes == null
          ? const Center(
              child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2)))
          : Image.memory(_bytes!, fit: BoxFit.contain),
    );
  }
}
