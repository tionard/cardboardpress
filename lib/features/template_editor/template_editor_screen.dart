// lib/features/template_editor/template_editor_screen.dart

import 'package:flutter/material.dart';

import '../../app/feature_placeholder.dart';

class TemplateEditorScreen extends StatelessWidget {
  const TemplateEditorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      icon: Icons.dashboard,
      title: 'Template Editor',
      subtitle:
          'Design the card layout — place fields, set backgrounds and outlines, '
          'and restack the nine field types.',
    );
  }
}
