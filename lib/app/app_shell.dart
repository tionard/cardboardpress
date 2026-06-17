// lib/app/app_shell.dart
//
// The persistent navigation shell (spec §2). One Scaffold holds the bottom tab
// bar; switching tabs swaps the body. The four product tabs are visible;
// Profile is reserved and hidden behind a flag until its contents are decided.
//
// The selected tab lives in selectedTabProvider so other screens can navigate
// the shell (e.g. Collection opening a card in the Card Editor tab) — and so
// there is exactly ONE editor instance, never a pushed duplicate.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/card_editor/card_editor_screen.dart';
import '../features/collection/collection_screen.dart';
import '../features/customization/customization_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/template_editor/template_editor_screen.dart';
import '../state/providers.dart';

/// Profile is reserved (theme + premium) and stays hidden until decided
/// (spec §2). Flip this to `true` later to surface it — no other change needed.
const bool kShowProfile = false;

class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  // Tab order follows spec §2 (and kCardEditorTabIndex in providers.dart).
  static const List<_TabDef> _coreTabs = [
    _TabDef('Collection', Icons.grid_view_outlined, Icons.grid_view,
        CollectionScreen()),
    _TabDef('Template', Icons.dashboard_outlined, Icons.dashboard,
        TemplateEditorScreen()),
    _TabDef('Card', Icons.style_outlined, Icons.style, CardEditorScreen()),
    _TabDef('Customize', Icons.palette_outlined, Icons.palette,
        CustomizationScreen()),
  ];

  List<_TabDef> get _tabs => [
        ..._coreTabs,
        if (kShowProfile)
          const _TabDef(
              'Profile', Icons.person_outline, Icons.person, ProfileScreen()),
      ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tabs = _tabs;
    final index = ref.watch(selectedTabProvider).clamp(0, tabs.length - 1);

    return Scaffold(
      appBar: AppBar(title: Text(tabs[index].label)),
      // IndexedStack keeps every tab alive and preserves its state (scroll
      // position, selections) instead of rebuilding from scratch on each switch.
      body: IndexedStack(
        index: index,
        children: [for (final t in tabs) t.screen],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            ref.read(selectedTabProvider.notifier).set(i),
        destinations: [
          for (final t in tabs)
            NavigationDestination(
              icon: Icon(t.icon),
              selectedIcon: Icon(t.selectedIcon),
              label: t.label,
            ),
        ],
      ),
    );
  }
}

/// A tab's metadata: its label, its two icons (idle/selected), and the screen
/// that fills the body when it's active.
class _TabDef {
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
  const _TabDef(this.label, this.icon, this.selectedIcon, this.screen);
}
