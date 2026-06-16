// lib/features/spike/spike_screen.dart
//
// The de-risking spike. It shows, side by side:
//   LEFT  — the live preview (a CustomPainter calling paintCard on screen)
//   RIGHT — an ACTUAL PNG, rendered at 300 dpi by exportCardPng and decoded
//           back into the app via Image.memory.
//
// If the two look identical, the "single render path" guarantee is proven:
// preview == export, with no second drawing code path. The toggles change the
// card; both sides update from the same source.

import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../model/card_model.dart';
import '../../rendering/export.dart';
import '../../rendering/paint_card.dart';

class SpikeScreen extends StatefulWidget {
  const SpikeScreen({super.key});

  @override
  State<SpikeScreen> createState() => _SpikeScreenState();
}

class _SpikeScreenState extends State<SpikeScreen> {
  bool _foil = true;
  bool _doubleBase = true;
  bool _border = true;

  static const _refs = CardRefs();
  late CardData _card;
  late Future<Uint8List> _png;

  @override
  void initState() {
    super.initState();
    _rebuild();
  }

  // Rebuild the card from the toggles, and kick off a fresh export render.
  void _rebuild() {
    _card = _buildDemoCard(
      foil: _foil,
      doubleBase: _doubleBase,
      border: _border,
    );
    _png = exportCardPng(_card, _refs, dpi: 300);
  }

  void _set(void Function() change) => setState(() {
        change();
        _rebuild();
      });

  @override
  Widget build(BuildContext context) {
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
                _labelled(
                  'Live preview (CustomPainter)',
                  SizedBox(
                    width: 260,
                    child: AspectRatio(
                      aspectRatio: _card.widthInches / _card.heightInches,
                      child: CustomPaint(painter: _CardPainter(_card, _refs)),
                    ),
                  ),
                ),
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
            const SizedBox(height: 28),
            const Text('Toggles change the CardData; both sides redraw from it:'),
            SwitchListTile(
              title: const Text('Double base colour (split + mix band)'),
              value: _doubleBase,
              onChanged: (v) => _set(() => _doubleBase = v),
            ),
            SwitchListTile(
              title: const Text('Holographic foil overlay'),
              value: _foil,
              onChanged: (v) => _set(() => _foil = v),
            ),
            SwitchListTile(
              title: const Text('Black card border'),
              value: _border,
              onChanged: (v) => _set(() => _border = v),
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

/// Bridges Flutter's CustomPaint into our pure paintCard.
class _CardPainter extends CustomPainter {
  final CardData card;
  final CardRefs refs;
  const _CardPainter(this.card, this.refs);

  @override
  void paint(Canvas canvas, Size size) => paintCard(canvas, size, card, refs);

  @override
  bool shouldRepaint(_CardPainter old) => old.card != card || old.refs != refs;
}

// ---------------------------------------------------------------------------
// A hand-built demo card so we have something to draw before the editors exist.
// ---------------------------------------------------------------------------
CardData _buildDemoCard({
  required bool foil,
  required bool doubleBase,
  required bool border,
}) {
  const olive = Color(0xFFB8C49F);
  const sage = Color(0xFF8FAE6F);
  const parchment = Color(0xFFF1EFE8);
  const ink = Color(0xFF2C2B27);

  final base = doubleBase
      ? const ColorValue.duo(olive, sage,
          orientation: MixOrientation.vertical, mix: 0.5)
      : const ColorValue.single(olive);

  return CardData(
    cornerRadiusFrac: 0.055,
    baseColor: base,
    border: border ? const BorderSpec(black: true, thickness: 0.022) : null,
    foil: foil ? FoilType.holo : FoilType.none,
    textContent: const {
      FieldType.name: 'Thornwood Stag',
      FieldType.type: 'Creature — Beast',
      FieldType.rules: 'Vigilance. When this enters, scry 2.',
      FieldType.footer: '001/120 · TWD · © 26',
    },
    fields: const [
      // Name banner
      FieldSpec(
        type: FieldType.name,
        frac: Rect.fromLTRB(0.06, 0.05, 0.94, 0.15),
        fill: ColorValue.single(parchment),
        fillAlpha: 0.7,
        outline: OutlineSpec(lighter: false, intensity: 0.45),
        text: TextStyleSpec(sizeFrac: 0.05, bold: true, color: ink),
      ),
      // Art window
      FieldSpec(
        type: FieldType.art,
        frac: Rect.fromLTRB(0.06, 0.17, 0.94, 0.52),
      ),
      // Type line
      FieldSpec(
        type: FieldType.type,
        frac: Rect.fromLTRB(0.06, 0.54, 0.94, 0.62),
        fill: ColorValue.single(parchment),
        fillAlpha: 0.7,
        text: TextStyleSpec(sizeFrac: 0.032, bold: true, color: ink),
      ),
      // Rules box
      FieldSpec(
        type: FieldType.rules,
        frac: Rect.fromLTRB(0.06, 0.64, 0.94, 0.88),
        fill: ColorValue.single(parchment),
        fillAlpha: 0.55,
        outline: OutlineSpec(lighter: false, intensity: 0.3),
        text: TextStyleSpec(sizeFrac: 0.03, color: ink),
      ),
      // Footer line
      FieldSpec(
        type: FieldType.footer,
        frac: Rect.fromLTRB(0.06, 0.905, 0.94, 0.96),
        text: TextStyleSpec(
            sizeFrac: 0.022, color: Color(0x99000000), align: TextAlign.left),
      ),
    ],
  );
}
