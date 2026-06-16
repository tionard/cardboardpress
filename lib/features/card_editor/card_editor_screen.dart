// lib/features/card_editor/card_editor_screen.dart

import 'package:flutter/material.dart';

import '../../app/feature_placeholder.dart';
import '../spike/spike_screen.dart';

class CardEditorScreen extends StatelessWidget {
  const CardEditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return FeaturePlaceholder(
      icon: Icons.style,
      title: 'Card Editor',
      subtitle:
          'Pick a template, then pour in content: name, art, rules, tint, foil, '
          'rarity. Until that exists, here is the renderer spike that proves '
          'the preview and the exported PNG come from the same code.',
      child: ElevatedButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const SpikeScreen()),
        ),
        icon: const Icon(Icons.image_outlined),
        label: const Text('Open renderer spike'),
      ),
    );
  }
}
