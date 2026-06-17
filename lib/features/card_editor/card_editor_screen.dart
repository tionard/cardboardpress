// lib/features/card_editor/card_editor_screen.dart
//
// Edits a REAL persisted card. The Name content autosaves (debounced) and
// survives restarts; switching the template updates the card's template
// reference (and its retained snapshot). The preview composes the card's
// resolved template with its content and resolves palette colours live.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/card_repository.dart';
import '../../model/card_model.dart';
import '../../model/sample_card.dart';
import '../../state/providers.dart';
import '../../widgets/card_preview.dart';
import '../spike/spike_screen.dart';

class CardEditorScreen extends ConsumerWidget {
  const CardEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cardsAsync = ref.watch(cardsProvider);
    final templates = ref.watch(templatesProvider).maybeWhen(
          data: (list) => list,
          orElse: () => const <TemplateEntry>[],
        );
    final templatesMap = ref.watch(templatesMapProvider);
    final refs = CardRefs(palette: ref.watch(paletteMapProvider));

    return cardsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load cards:\n$e')),
      data: (cards) {
        if (cards.isEmpty) {
          return const Center(child: Text('No cards yet.'));
        }
        final card = cards.first;
        return _CardEditorBody(
          key: ValueKey(card.id),
          card: card,
          templates: templates,
          templatesMap: templatesMap,
          refs: refs,
          repo: ref.read(cardRepositoryProvider),
        );
      },
    );
  }
}

class _CardEditorBody extends StatefulWidget {
  final CardEntry card;
  final List<TemplateEntry> templates;
  final Map<String, TemplateData> templatesMap;
  final CardRefs refs;
  final CardRepository repo;

  const _CardEditorBody({
    super.key,
    required this.card,
    required this.templates,
    required this.templatesMap,
    required this.refs,
    required this.repo,
  });

  @override
  State<_CardEditorBody> createState() => _CardEditorBodyState();
}

class _CardEditorBodyState extends State<_CardEditorBody> {
  late CardEntry _working;
  late final TextEditingController _name;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _working = widget.card;
    final nameId = _nameFieldId();
    _name = TextEditingController(
        text: nameId == null ? '' : (_working.content.text[nameId] ?? ''))
      ..addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _name.removeListener(_onNameChanged);
    _saveTimer?.cancel();
    widget.repo.save(_working); // flush latest edit
    _name.dispose();
    super.dispose();
  }

  // The id of the Name field in the card's currently resolved template.
  String? _nameFieldId() {
    final t = _working.effectiveTemplate(widget.templatesMap);
    for (final f in t.fields) {
      if (f.type == FieldType.name) return f.id;
    }
    return null;
  }

  void _onNameChanged() {
    final nameId = _nameFieldId();
    if (nameId == null) return;
    _working = _working.copyWith(
        content: _working.content.withText(nameId, _name.text));
    _scheduleSave();
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(
        const Duration(milliseconds: 400), () => widget.repo.save(_working));
  }

  void _changeTemplate(String? id) {
    if (id == null) return;
    final snapshot = widget.templatesMap[id] ?? _working.templateSnapshot;
    setState(() => _working =
        _working.copyWith(templateId: id, templateSnapshot: snapshot));
    widget.repo.save(_working); // discrete change -> save immediately
  }

  @override
  Widget build(BuildContext context) {
    final effective = _working.effectiveTemplate(widget.templatesMap);
    final card = composeCard(
      effective,
      content: _working.content,
      foil: _working.foil,
    );
    final nameId = _nameFieldId();
    final dropdownValue =
        widget.templates.any((t) => t.id == _working.templateId)
            ? _working.templateId
            : null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('Template: '),
              DropdownButton<String>(
                value: dropdownValue,
                items: [
                  for (final t in widget.templates)
                    DropdownMenuItem(value: t.id, child: Text(t.name)),
                ],
                onChanged: _changeTemplate,
              ),
            ],
          ),
          const SizedBox(height: 12),
          CardPreview(card: card, refs: widget.refs, width: 300),
          const SizedBox(height: 20),
          if (nameId != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Card name',
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              'This is a real card in the database. Editing the name autosaves; '
              'restart the app and it persists. Switching the template updates '
              'the card\'s template reference and keeps a snapshot, so deleting '
              'a template later would never break this card.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SpikeScreen()),
            ),
            icon: const Icon(Icons.compare_outlined),
            label: const Text('Open preview-vs-PNG spike'),
          ),
        ],
      ),
    );
  }
}
