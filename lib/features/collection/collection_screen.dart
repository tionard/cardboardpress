// lib/features/collection/collection_screen.dart
//
// Collection: cards grouped into folders (sets). "Unassigned" is the permanent
// null-setId bucket and leads. You can create cards into a folder, open one to
// edit, duplicate, delete, or move it between sets; and create new sets.
//
// This is Collection v1 — the structure and CRUD. Polish (Large/Grid toggle,
// density slider, search, multi-select, drag-reorder, footer numbering) follows.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/card_model.dart';
import '../../model/sample_card.dart';
import '../../state/providers.dart';
import '../../widgets/card_preview.dart';
import '../card_editor/card_editor_screen.dart';

class CollectionScreen extends ConsumerWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(cardsProvider);
    final setsAsync = ref.watch(setsProvider);
    final templatesMap = ref.watch(templatesMapProvider);
    final palette = ref.watch(paletteMapProvider);

    return cardsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load cards:\n$e')),
      data: (cards) => setsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not load sets:\n$e')),
        data: (sets) {
          // Unassigned first, then each set in order.
          final folders = <_Folder>[
            _Folder(
                id: null,
                title: 'Unassigned',
                abbr: '',
                cards: cards.where((c) => c.setId == null).toList()),
            for (final s in sets)
              _Folder(
                  id: s.id,
                  title: s.name,
                  abbr: s.abbreviation,
                  cards: cards.where((c) => c.setId == s.id).toList()),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Row(
                  children: [
                    Text('Collection',
                        style: Theme.of(context).textTheme.titleLarge),
                    const Spacer(),
                    OutlinedButton.icon(
                      onPressed: () => _newSet(context, ref),
                      icon: const Icon(Icons.create_new_folder_outlined),
                      label: const Text('New set'),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    for (final f in folders)
                      _section(context, ref, f, templatesMap, palette),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _section(
    BuildContext context,
    WidgetRef ref,
    _Folder folder,
    Map<String, TemplateData> templatesMap,
    Map<String, ColorValue> palette,
  ) {
    final heading = folder.abbr.isEmpty
        ? folder.title
        : '${folder.title} · ${folder.abbr}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(heading, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(width: 8),
            Text('${folder.cards.length}',
                style: Theme.of(context).textTheme.bodySmall),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _newCard(context, ref, folder.id),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New card'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (folder.cards.isEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('No cards in this folder yet.',
                style: Theme.of(context).textTheme.bodySmall),
          )
        else
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              for (final card in folder.cards)
                _thumb(context, ref, card, templatesMap, palette),
            ],
          ),
        const Divider(height: 28),
      ],
    );
  }

  Widget _thumb(
    BuildContext context,
    WidgetRef ref,
    CardEntry card,
    Map<String, TemplateData> templatesMap,
    Map<String, ColorValue> palette,
  ) {
    final effective = card.effectiveTemplate(templatesMap);
    final data =
        composeCard(effective, content: card.content, foil: card.foil);
    final name = _cardName(effective, card);

    return SizedBox(
      width: 92,
      child: Column(
        children: [
          InkWell(
            onTap: () => _openEditor(context, ref, card.id),
            onLongPress: () => _cardMenu(context, ref, card),
            child: CardPreview(
                card: data, refs: CardRefs(palette: palette), width: 92),
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
      ),
    );
  }

  String _cardName(TemplateData t, CardEntry card) {
    for (final f in t.fields) {
      if (f.type == FieldType.name) return card.content.text[f.id] ?? '';
    }
    return '';
  }

  void _openEditor(BuildContext context, WidgetRef ref, String cardId) {
    ref.read(currentCardIdProvider.notifier).set(cardId);
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const _EditCardRoute()),
    );
  }

  Future<void> _newCard(
      BuildContext context, WidgetRef ref, String? setId) async {
    final templates = ref.read(templatesProvider).maybeWhen(
          data: (l) => l,
          orElse: () => const <TemplateEntry>[],
        );
    if (templates.isEmpty) return;
    final t = templates.first;
    final id = await ref
        .read(cardRepositoryProvider)
        .create(templateId: t.id, templateSnapshot: t.data, setId: setId);
    if (!context.mounted) return;
    _openEditor(context, ref, id);
  }

  void _cardMenu(BuildContext context, WidgetRef ref, CardEntry card) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit'),
              onTap: () {
                Navigator.pop(sheet);
                _openEditor(context, ref, card.id);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy_outlined),
              title: const Text('Duplicate'),
              onTap: () {
                Navigator.pop(sheet);
                ref.read(cardRepositoryProvider).duplicate(card);
              },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move_outlined),
              title: const Text('Move to…'),
              onTap: () {
                Navigator.pop(sheet);
                _moveCard(context, ref, card);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete'),
              onTap: () {
                Navigator.pop(sheet);
                ref.read(cardRepositoryProvider).delete(card.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _moveCard(BuildContext context, WidgetRef ref, CardEntry card) {
    final sets = ref.read(setsProvider).maybeWhen(
          data: (l) => l,
          orElse: () => const <SetEntry>[],
        );
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.inbox_outlined),
              title: const Text('Unassigned'),
              selected: card.setId == null,
              onTap: () {
                ref.read(cardRepositoryProvider).setSet(card.id, null);
                Navigator.pop(sheet);
              },
            ),
            for (final s in sets)
              ListTile(
                leading: const Icon(Icons.folder_outlined),
                title: Text(s.name),
                selected: card.setId == s.id,
                onTap: () {
                  ref.read(cardRepositoryProvider).setSet(card.id, s.id);
                  Navigator.pop(sheet);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _newSet(BuildContext context, WidgetRef ref) async {
    final nameCtl = TextEditingController();
    final abbrCtl = TextEditingController();
    final create = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const Text('New set'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtl,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: abbrCtl,
              maxLength: 5,
              decoration: const InputDecoration(
                  labelText: 'Abbreviation (footer)', counterText: ''),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialog, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(dialog, true),
              child: const Text('Create')),
        ],
      ),
    );
    if (create == true) {
      await ref
          .read(setRepositoryProvider)
          .create(nameCtl.text, abbreviation: abbrCtl.text);
    }
    nameCtl.dispose();
    abbrCtl.dispose();
  }
}

class _Folder {
  final String? id; // null => Unassigned
  final String title;
  final String abbr;
  final List<CardEntry> cards;
  const _Folder(
      {required this.id,
      required this.title,
      required this.abbr,
      required this.cards});
}

// Full-screen editor pushed from the Collection; the editor reads the selected
// card from currentCardIdProvider.
class _EditCardRoute extends StatelessWidget {
  const _EditCardRoute();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Edit card')),
      body: const CardEditorScreen(),
    );
  }
}
