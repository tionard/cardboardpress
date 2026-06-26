// lib/main.dart
//
// App entry point. For a C# dev: `main()` is your Program.Main, and runApp()
// hands the root widget to the Flutter engine to render.

import 'package:flutter/material.dart';
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
