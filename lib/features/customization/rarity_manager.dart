// lib/features/customization/rarity_manager.dart
//
// Self-contained management UI for rarities (spec §3.4). Drop it into the
// Customization "Rarities" sub-tab:
//
//     const RarityManager()
//
// It binds to raritiesProvider / rarityRepositoryProvider, so no extra wiring
// is needed. Add, edit (name + 1–3-letter abbreviation), reorder, and delete.
// The footer renders a card's rarity *abbreviation*, so edits show up there and
// everywhere the rarity is used the moment drift re-emits.
//
// (A rarity's palette colour + transparency aren't authored here yet — they
// only render as the set-symbol tint, which doesn't exist as a feature yet.)

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/card_model.dart';
import '../../state/providers.dart';

class RarityManager extends ConsumerWidget {
  const RarityManager({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(raritiesProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load rarities: $e')),
      data: (rarities) => _body(context, ref, rarities),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, List<RarityEntry> rarities) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Rarities', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              FilledButton.icon(
                onPressed: () => _edit(context, ref, null),
                icon: const Icon(Icons.add),
                label: const Text('Add rarity'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'A rarity has a name and a 1–3-letter abbreviation. The footer shows '
            'the abbreviation of the card\'s chosen rarity. Order sets the rank '
            '(top = lowest), e.g. Common · Uncommon · Rare.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          if (rarities.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text('No rarities yet — add one to get started.',
                  style: Theme.of(context).textTheme.bodyMedium),
            )
          else
            for (var i = 0; i < rarities.length; i++)
              _RarityRow(
                key: ValueKey(rarities[i].id),
                rarity: rarities[i],
                isFirst: i == 0,
                isLast: i == rarities.length - 1,
                onMoveUp: () =>
                    ref.read(rarityRepositoryProvider).swap(rarities[i], rarities[i - 1]),
                onMoveDown: () =>
                    ref.read(rarityRepositoryProvider).swap(rarities[i], rarities[i + 1]),
                onEdit: () => _edit(context, ref, rarities[i]),
                onDelete: () => _delete(context, ref, rarities[i]),
              ),
        ],
      ),
    );
  }

  // ---- actions ----

  /// Shared add/edit dialog. [existing] null => add a new rarity.
  Future<void> _edit(
      BuildContext context, WidgetRef ref, RarityEntry? existing) async {
    final nameCtl = TextEditingController(text: existing?.name ?? '');
    final abbrCtl = TextEditingController(text: existing?.abbreviation ?? '');

    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add rarity' : 'Edit rarity'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              autofocus: existing == null,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Name',
                hintText: 'e.g. Rare',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: abbrCtl,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[A-Za-z]')),
                LengthLimitingTextInputFormatter(3),
                _UpperCaseFormatter(),
              ],
              decoration: const InputDecoration(
                labelText: 'Abbreviation',
                hintText: 'e.g. R',
                helperText: '1–3 letters; shown in the footer',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (nameCtl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: Text(existing == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );

    if (saved == true) {
      final repo = ref.read(rarityRepositoryProvider);
      if (existing == null) {
        await repo.add(name: nameCtl.text, abbreviation: abbrCtl.text);
      } else {
        await repo.update(existing.id,
            name: nameCtl.text, abbreviation: abbrCtl.text);
      }
    }
    nameCtl.dispose();
    abbrCtl.dispose();
  }

  Future<void> _delete(
      BuildContext context, WidgetRef ref, RarityEntry r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${r.name}"?'),
        content: const Text(
            'Any card set to this rarity will simply stop showing a rarity '
            'abbreviation in its footer until you pick another one.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await ref.read(rarityRepositoryProvider).delete(r.id);
    }
  }
}

// ---------------------------------------------------------------------------
// One rarity row: abbreviation badge · name · reorder · edit · delete.
// ---------------------------------------------------------------------------
class _RarityRow extends StatelessWidget {
  final RarityEntry rarity;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _RarityRow({
    super.key,
    required this.rarity,
    required this.isFirst,
    required this.isLast,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
        child: Row(
          children: [
            _AbbrBadge(text: rarity.abbreviation),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                rarity.name,
                style: Theme.of(context).textTheme.bodyLarge,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: '', // avoid the Tooltip-in-scrollview AXTree spam
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              onPressed: isFirst ? null : onMoveUp,
              icon: const Icon(Icons.keyboard_arrow_up),
            ),
            IconButton(
              tooltip: '',
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              onPressed: isLast ? null : onMoveDown,
              icon: const Icon(Icons.keyboard_arrow_down),
            ),
            IconButton(
              tooltip: '',
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: '',
              iconSize: 20,
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: Icon(Icons.delete_outline, color: scheme.error),
            ),
          ],
        ),
      ),
    );
  }
}

/// A small rounded badge showing the abbreviation (or a dash when blank), a
/// quick visual echo of how it reads in the footer.
class _AbbrBadge extends StatelessWidget {
  final String text;
  const _AbbrBadge({required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = text.isEmpty ? '–' : text;
    return Container(
      width: 40,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: scheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

/// Forces typed text to upper-case so the abbreviation field shows C / U / R …
/// as you type (the repository upper-cases on save too, as a backstop).
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue, TextEditingValue newValue) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}
