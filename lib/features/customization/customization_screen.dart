// lib/features/customization/customization_screen.dart
//
// First data-backed screen. It WATCHES the palette provider and renders the
// seeded colours. `ConsumerWidget` is like StatelessWidget but with a `ref`
// you use to watch providers. The `.when(...)` handles the three states a
// streamed/async value can be in: loading, error, or data.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../model/card_model.dart';

import '../../state/providers.dart';

class CustomizationScreen extends ConsumerWidget {
  const CustomizationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = ref.watch(paletteProvider);

    return palette.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load palette:\n$e')),
      data: (swatches) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text('Colors', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            '${swatches.length} in the palette — loaded from the local database.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: [for (final s in swatches) _SwatchTile(swatch: s)],
          ),
        ],
      ),
    );
  }
}

class _SwatchTile extends StatelessWidget {
  final PaletteSwatch swatch;
  const _SwatchTile({required this.swatch});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 56,
          height: 56,
          decoration: _decorationFor(swatch.value),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: 64,
          child: Text(
            swatch.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    );
  }

  // A small preview only — NOT the card renderer. It mirrors the same
  // two-stop split so a double colour reads the way it will on a card.
  BoxDecoration _decorationFor(ColorValue v) {
    final border = Border.all(color: Colors.black.withOpacity(0.12));
    final radius = BorderRadius.circular(10);
    if (!v.isDouble) {
      return BoxDecoration(color: v.c1, borderRadius: radius, border: border);
    }
    final vertical = v.orientation == MixOrientation.vertical;
    final half = v.mix / 2;
    return BoxDecoration(
      borderRadius: radius,
      border: border,
      gradient: LinearGradient(
        begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
        end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
        colors: [v.c1, v.c1, v.c2!, v.c2!],
        stops: [0.0, 0.5 - half, 0.5 + half, 1.0],
      ),
    );
  }
}
