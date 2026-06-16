// lib/features/profile/profile_screen.dart
//
// Reserved tab (spec §2): app theme + premium entry point. Hidden by default
// via `kShowProfile` in app_shell.dart. Exists so the seam is real, not so it
// shows up.

import 'package:flutter/material.dart';

import '../../app/feature_placeholder.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const FeaturePlaceholder(
      icon: Icons.person,
      title: 'Profile',
      subtitle: 'Reserved for app theme and future premium features.',
    );
  }
}
