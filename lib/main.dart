// lib/main.dart
//
// App entry point. For a C# dev: `main()` is your Program.Main, and runApp()
// hands the root widget to the Flutter engine to render.

import 'package:flutter/foundation.dart' show LicenseEntryWithLineBreaks, LicenseRegistry;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_shell.dart';
import 'data/symbol_seeder.dart';
import 'state/providers.dart';
import 'state/settings.dart';

// ProviderScope is the root that holds all Riverpod provider state. We build the
// container ourselves so startup work (seeding default text-symbol images) runs
// against the SAME database + image store the app then uses.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  final container = ProviderContainer();
  await seedDefaultTextSymbols(
    container.read(databaseProvider),
    container.read(imageStoreProvider),
  );
  // Preload persisted settings (theme, Pro) and hand them to the notifier
  // BEFORE the first frame, so the saved theme is applied with no flash.
  final settings = await loadAppSettings(container.read(databaseProvider));
  container.read(appSettingsProvider.notifier).hydrate(settings);

  runApp(UncontrolledProviderScope(
    container: container,
    child: const CardboardPressApp(),
  ));
}

/// Surfaces the bundled fonts' SIL OFL texts in Flutter's licenses page
/// (Settings → About → Licenses via showLicensePage / AboutDialog). The OFL
/// requires the license to accompany the fonts in any distribution — this is
/// what keeps the Play Store / itch.io builds compliant. One entry per family,
/// streamed lazily from assets so startup cost is nil until the page opens.
void _registerFontLicenses() {
  const families = {
    'Cinzel': 'cinzel',
    'Uncial Antiqua': 'uncialantiqua',
    'Almendra': 'almendra',
    'Almendra SC': 'almendrasc',
    'EB Garamond': 'ebgaramond',
    'Alegreya': 'alegreya',
    'Alegreya SC': 'alegreyasc',
    'Inter': 'inter',
    'Dancing Script': 'dancingscript',
    'Great Vibes': 'greatvibes',
    'VT323': 'vt323',
    'Orbitron': 'orbitron',
    'Bangers': 'bangers',
  };
  LicenseRegistry.addLicense(() async* {
    for (final e in families.entries) {
      final text =
          await rootBundle.loadString('assets/fonts/licenses/OFL-${e.value}.txt');
      yield LicenseEntryWithLineBreaks([e.key], text);
    }
  });
}

class CardboardPressApp extends ConsumerWidget {
  const CardboardPressApp({super.key});

  // One seed colour generates both schemes; brightness picks light vs dark.
  static const Color _seed = Color(0xFF3F6FB0);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'CardboardPress',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seed,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: _seed,
        brightness: Brightness.dark,
      ),
      themeMode: themeMode,
      home: const AppShell(),
    );
  }
}
