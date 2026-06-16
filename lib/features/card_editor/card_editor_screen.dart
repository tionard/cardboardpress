// lib/features/card_editor/card_editor_screen.dart
//
// The Card Editor now renders from a PERSISTED template. A dropdown switches
// between the templates stored in the database; the preview composes the chosen
// template with sample content and resolves palette colours live.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/card_model.dart';
import '../../model/sample_card.dart';
import '../../state/providers.dart';
import '../../widgets/card_preview.dart';
import '../spike/spike_screen.dart';

class CardEditorScreen extends ConsumerStatefulWidget {
  const CardEditorScreen({super.key});

  @override
  ConsumerState<CardEditorScreen> createState() => _CardEditorScreenState();
}

class _CardEditorScreenState extends ConsumerState<CardEditorScreen> {
  String? _templateId;

  @override
  Widget build(BuildContext context) {
    final templatesAsync = ref.watch(templatesProvider);
    final refs = CardRefs(palette: ref.watch(paletteMapProvider));

    return templatesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load templates:\n$e')),
      data: (templates) {
        if (templates.isEmpty) {
          return const Center(child: Text('No templates yet.'));
        }
        // Resolve the current selection against the persisted list.
        final selected = templates.firstWhere(
          (t) => t.id == _templateId,
          orElse: () => templates.first,
        );
        final card = composeCard(
          selected.data,
          textContent: sampleContent(),
          foil: FoilType.holo,
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Template: '),
                  DropdownButton<String>(
                    value: selected.id,
                    items: [
                      for (final t in templates)
                        DropdownMenuItem(value: t.id, child: Text(t.name)),
                    ],
                    onChanged: (v) => setState(() => _templateId = v),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              CardPreview(card: card, refs: refs, width: 300),
              const SizedBox(height: 16),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Text(
                  'Both templates are loaded from the local database (they '
                  'survive restarts). Switching swaps the layout, base colour, '
                  'and border. Colours still resolve live from the palette.',
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
      },
    );
  }
}
