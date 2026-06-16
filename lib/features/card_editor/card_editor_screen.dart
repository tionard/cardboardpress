// lib/features/card_editor/card_editor_screen.dart
//
// The Card Editor now shows a LIVE preview. Its colours reference palette
// swatches, and it watches the palette map — so editing a colour in the
// Customize tab restyles this card automatically (switch back here to see it).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/card_model.dart';
import '../../model/sample_card.dart';
import '../../state/providers.dart';
import '../../widgets/card_preview.dart';
import '../spike/spike_screen.dart';

class CardEditorScreen extends ConsumerWidget {
  const CardEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(paletteMapProvider);
    final refs = CardRefs(palette: palette);
    final card = sampleCard();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text('Live preview', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 12),
          CardPreview(card: card, refs: refs, width: 300),
          const SizedBox(height: 16),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Text(
              'The card base references the "Forest Fade" palette colour and the '
              'text panels reference "Paper". Edit either in the Customize tab and '
              'this preview updates. Delete one and the card keeps rendering from '
              'its retained snapshot.',
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
