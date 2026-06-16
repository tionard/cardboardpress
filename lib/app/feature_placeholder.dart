// lib/app/feature_placeholder.dart
//
// A small reusable "this screen is coming" placeholder, so each feature tab is
// a real file in the right folder now and we just fill in its body later.

import 'package:flutter/material.dart';

class FeaturePlaceholder extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  /// Optional extra widget (e.g. a button) shown beneath the text.
  final Widget? child;

  const FeaturePlaceholder({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (child != null) ...[
              const SizedBox(height: 24),
              child!,
            ],
          ],
        ),
      ),
    );
  }
}
