// lib/features/settings/settings_screen.dart
//
// The Settings tab (formerly the reserved "Profile" tab, spec §2). A plain
// settings hub: Appearance (theme), CardboardPress Pro (the purchase entry
// point), and About. Everything here is provider-backed, so the screen itself
// is a stateless ConsumerWidget.
//
// The Pro section is deliberately split: a real "Unlock" button that is, for
// now, a stub (no billing yet), and — only in debug builds — a developer switch
// that flips the entitlement directly so the locked features can be built and
// tested before Google Play Billing is wired in.

import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/settings.dart';

/// Shown on the About row and the licenses page. Bump on release; can later be
/// wired to package_info_plus if you want it read from the build automatically.
const String _appVersion = '0.1.0';

/// Public repo, surfaced under About. Copied to the clipboard rather than
/// launched, so we add no url_launcher dependency and stay fully offline.
const String _repoUrl = 'https://github.com/tionard/cardboardpress';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(appSettingsProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: ListView(
        children: [
          Text('Settings', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 16),
          const _SectionHeader('Appearance'),
          _ThemeSelector(mode: settings.themeMode),
          const SizedBox(height: 24),
          const _SectionHeader('CardboardPress Pro'),
          _ProCard(unlocked: settings.proUnlocked),
          const SizedBox(height: 24),
          const _SectionHeader('About'),
          const _AboutSection(),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, left: 4),
      child: Text(
        text.toUpperCase(),
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 0.8,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// System / Light / Dark. Writes straight through the notifier (which persists).
class _ThemeSelector extends ConsumerWidget {
  final ThemeMode mode;
  const _ThemeSelector({required this.mode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SegmentedButton<ThemeMode>(
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(value: ThemeMode.system, label: Text('System')),
        ButtonSegment(value: ThemeMode.light, label: Text('Light')),
        ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
      ],
      selected: {mode},
      onSelectionChanged: (s) =>
          ref.read(appSettingsProvider.notifier).setThemeMode(s.first),
    );
  }
}

class _ProCard extends ConsumerWidget {
  final bool unlocked;
  const _ProCard({required this.unlocked});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.workspace_premium_outlined,
                    color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text('CardboardPress Pro',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
              ],
            ),
            const SizedBox(height: 12),
            if (unlocked)
              _ProActive(theme: theme)
            else
              _ProUpsell(theme: theme),
            // Debug-only entitlement override — the seam that lets the locked
            // features be built/tested before real billing exists. Never ships
            // to users (stripped from release builds by kDebugMode).
            if (kDebugMode) ...[
              const Divider(height: 28),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                secondary: const Icon(Icons.developer_mode_outlined),
                title: const Text('Developer: simulate Pro'),
                subtitle: const Text('Debug builds only — not in release.'),
                value: unlocked,
                onChanged: (v) =>
                    ref.read(appSettingsProvider.notifier).setProUnlocked(v),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProActive extends StatelessWidget {
  final ThemeData theme;
  const _ProActive({required this.theme});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.check_circle, color: theme.colorScheme.primary, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text('Pro is unlocked. Thank you for the support!',
              style: theme.textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _ProUpsell extends StatelessWidget {
  final ThemeData theme;
  const _ProUpsell({required this.theme});

  static const _features = [
    'Export your cards at full 600 DPI',
    'Remove the watermark from exports',
    'Support ongoing development',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in _features)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check, size: 18, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text(f, style: theme.textTheme.bodyMedium)),
              ],
            ),
          ),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            icon: const Icon(Icons.lock_open_outlined),
            label: const Text('Unlock Pro'),
            onPressed: () {
              // Stub: real in-app purchase is wired in a later session.
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('In-app purchase is coming soon.'),
              ));
            },
          ),
        ),
      ],
    );
  }
}

class _AboutSection extends StatelessWidget {
  const _AboutSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.info_outline),
          title: const Text('Version'),
          trailing: Text(_appVersion),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.description_outlined),
          title: const Text('Open-source licenses'),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'CardboardPress',
            applicationVersion: _appVersion,
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.code),
          title: const Text('Source code'),
          subtitle: const Text(_repoUrl),
          onTap: () {
            Clipboard.setData(const ClipboardData(text: _repoUrl));
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Repository link copied to clipboard.'),
            ));
          },
        ),
      ],
    );
  }
}
