// lib/features/spike/spike_screen.dart
//
// The de-risking spike: live preview (CustomPainter) beside an ACTUAL 300-dpi
// PNG (Image.memory), both from the same paintCard. Now it also watches the
// palette map, so the card's referenced colours are live here too — and the
// export is recomputed only when the inputs actually change.

import 'dart:typed_data';

import 'package:flutter/foundation.dart' show mapEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/card_model.dart';
import '../../model/sample_card.dart';
import '../../rendering/export.dart';
import '../../state/providers.dart';
import '../../widgets/card_preview.dart';

class SpikeScreen extends ConsumerStatefulWidget {
  const SpikeScreen({super.key});

  @override
  ConsumerState<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends ConsumerState<SpikeScreen> {
  bool _foil = true;
  bool _border = true;

  // Cached export + the inputs it was built from, so we don't re-render the
  // 750x1050 PNG on every unrelated rebuild.
  Future<Uint8List>? _png;
  bool _pngFoil = true;
  bool _pngBorder = true;
  Map<String, ColorValue> _pngMap = const {};

  @override
  Widget build(BuildContext context) {
    final palette = ref.watch(paletteMapProvider);
    final refs = CardRefs(palette: palette);
    final card = sampleCard(foil: _foil, border: _border);

    final inputsChanged = _png == null ||
        _foil != _pngFoil ||
        _border != _pngBorder ||
        !mapEquals(palette, _pngMap);
    if (inputsChanged) {
      _pngFoil = _foil;
      _pngBorder = _border;
      _pngMap = palette;
      _png = exportCardPng(card, refs, dpi: 300);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Renderer spike — preview vs PNG')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 32,
              runSpacing: 24,
              children: [
                _labelled('Live preview (CustomPainter)',
                    CardPreview(card: card, refs: refs, width: 260)),
                _labelled(
                  'Exported PNG @ 300 dpi (Image.memory)',
                  SizedBox(
                    width: 260,
                    child: FutureBuilder<Uint8List>(
                      future: _png,
                      builder: (context, snap) {
                        if (snap.connectionState != ConnectionState.done) {
                          return const AspectRatio(
                            aspectRatio: 2.5 / 3.5,
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snap.hasError) {
                          return Text('Export error:\n${snap.error}');
                        }
                        return Image.memory(snap.data!);
                      },
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const Text(
              'Both sides resolve the card\'s colour references against the live '
              'palette. Edit "Forest Fade" / "Paper" in Customize to see them '
              'change; delete one to see the snapshot keep the card intact.',
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Holographic foil overlay'),
              value: _foil,
              onChanged: (v) => setState(() => _foil = v),
            ),
            SwitchListTile(
              title: const Text('Black card border'),
              value: _border,
              onChanged: (v) => setState(() => _border = v),
            ),
          ],
        ),
      ),
    );
  }

  Widget _labelled(String label, Widget child) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}
