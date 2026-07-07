// lib/widgets/preview_backdrop.dart
//
// A subtle theme-aware gradient behind card previews, so the card's silhouette
// always reads against the editor background: a flat surface colour lets a
// BLACK card border vanish in dark mode and a WHITE one vanish in light mode.
// The gradient spans two surface-container tones — never pure black or pure
// white — so some part of the card edge always contrasts. Material's surface
// containers already flip with the theme, giving the requested "dark gradient
// in dark mode, light gradient in light mode" from one implementation.

import 'package:flutter/material.dart';

class PreviewBackdrop extends StatelessWidget {
  final Widget child;

  const PreviewBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [
            scheme.surfaceContainerLowest,
            scheme.surfaceContainerHighest,
          ],
        ),
      ),
      child: child,
    );
  }
}
