// lib/state/settings.dart
//
// App-level preferences: the theme mode and the Pro entitlement, plus the
// providers the rest of the app reads. This is the "what is unlocked" SEAM:
// every locked feature watches `proUnlockedProvider` and nothing else; nobody
// talks to a billing API directly. In development the entitlement is flipped by
// a debug-only switch in Settings, so all the gating UI can be built and tested
// long before any real Google Play Billing is wired in (which then becomes a
// small, isolated change that just feeds this one provider).
//
// Persistence lives in the drift DB (a tiny key/value table), not in
// shared_preferences, so these settings ride along in any future library
// backup instead of being silently left out of it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/database.dart';
import 'providers.dart';

// --- storage keys (the columns are just text; we parse here) ---
const String _kThemeMode = 'theme_mode';
const String _kProUnlocked = 'pro_unlocked';

ThemeMode _decodeThemeMode(String? s) => switch (s) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };

String _encodeThemeMode(ThemeMode m) => switch (m) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };

/// The full set of app preferences, held in memory. Immutable; mutate via the
/// notifier so a write always pairs a state change with a DB write.
class AppSettingsState {
  final ThemeMode themeMode;
  final bool proUnlocked;

  const AppSettingsState({
    this.themeMode = ThemeMode.system,
    // Default ON: the app ships free with all functionality unlocked. The
    // toggle and the entitlement seam stay (in case monetisation ever comes
    // back), but out of the box everything is available.
    this.proUnlocked = true,
  });

  AppSettingsState copyWith({ThemeMode? themeMode, bool? proUnlocked}) =>
      AppSettingsState(
        themeMode: themeMode ?? this.themeMode,
        proUnlocked: proUnlocked ?? this.proUnlocked,
      );
}

/// Reads the persisted settings once (called from main() before the first
/// frame). Missing rows fall back to the code defaults — an empty table just
/// means "all defaults".
Future<AppSettingsState> loadAppSettings(AppDatabase db) async {
  final map = await db.readSettings();
  return AppSettingsState(
    themeMode: _decodeThemeMode(map[_kThemeMode]),
    // '!= 0' (not '== 1') so an ABSENT row also unlocks: fresh installs and
    // existing users who never touched the toggle get Pro by default, while a
    // deliberately stored '0' still means off.
    proUnlocked: map[_kProUnlocked] != '0',
  );
}

/// Holds the live settings. Hydrated once at startup so the very first frame
/// already shows the saved theme (no flash from default -> saved). Each setter
/// updates memory and writes through to the DB.
class AppSettingsNotifier extends Notifier<AppSettingsState> {
  @override
  AppSettingsState build() => const AppSettingsState();

  /// Called once from main() after the startup DB read.
  void hydrate(AppSettingsState s) => state = s;

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == state.themeMode) return;
    state = state.copyWith(themeMode: mode);
    await ref
        .read(databaseProvider)
        .putSetting(_kThemeMode, _encodeThemeMode(mode));
  }

  Future<void> setProUnlocked(bool unlocked) async {
    if (unlocked == state.proUnlocked) return;
    state = state.copyWith(proUnlocked: unlocked);
    await ref
        .read(databaseProvider)
        .putSetting(_kProUnlocked, unlocked ? '1' : '0');
  }
}

final appSettingsProvider =
    NotifierProvider<AppSettingsNotifier, AppSettingsState>(
        AppSettingsNotifier.new);

/// The theme mode for MaterialApp. Derived so the app root can watch just this.
final themeModeProvider =
    Provider<ThemeMode>((ref) => ref.watch(appSettingsProvider).themeMode);

/// THE entitlement gate. Every premium feature reads this and nothing else.
final proUnlockedProvider =
    Provider<bool>((ref) => ref.watch(appSettingsProvider).proUnlocked);
