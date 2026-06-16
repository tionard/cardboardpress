// lib/widgets/card_preview.dart
//
// The bridge between Flutter's widget world and our pure paintCard. This is the
// ONLY widget that wraps the renderer for on-screen use; preview and thumbnails
// reuse it. (paint_card.dart itself stays pure dart:ui — this file is where the
// Flutter dependency lives.)

import 'package:flutter/widgets.dart';

import '../model/card_model.dart';
import '../rendering/paint_card.dart';

class CardPreview extends StatelessWidget {
  final CardData card;
  final CardRefs refs;
  final double width;

  const CardPreview({
    super.key,
    required this.card,
    required this.refs,
    this.width = 280,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: AspectRatio(
        aspectRatio: card.widthInches / card.heightInches,
        child: CustomPaint(painter: _CardPainter(card, refs)),
      ),
    );
  }
}

class _CardPainter extends CustomPainter {
  final CardData card;
  final CardRefs refs;
  const _CardPainter(this.card, this.refs);

  @override
  void paint(Canvas canvas, Size size) => paintCard(canvas, size, card, refs);

  // Inputs are rebuilt fresh whenever the palette or card changes, so always
  // repaint on rebuild — correctness over micro-optimisation here.
  @override
  bool shouldRepaint(_CardPainter oldDelegate) => true;
}
