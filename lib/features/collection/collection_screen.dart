// lib/features/collection/collection_screen.dart

import 'package:flutter/material.dart';

import '../../app/feature_placeholder.dart';

class CollectionScreen extends StatelessWidget {
  const CollectionScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      icon: Icons.grid_view,
      title: 'Collection',
      subtitle:
          'Your sets and cards will live here — gallery folders, search across '
          'all sets, multi-select, and drag-to-reorder.',
    );
  }
}
