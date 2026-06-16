// lib/features/customization/customization_screen.dart

import 'package:flutter/material.dart';

import '../../app/feature_placeholder.dart';

class CustomizationScreen extends StatelessWidget {
  const CustomizationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      icon: Icons.palette,
      title: 'Customization',
      subtitle:
          'Manage the reusable building blocks: colors (single & double), '
          'rarities, text symbols, and standalone symbols.',
    );
  }
}
