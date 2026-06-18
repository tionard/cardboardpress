// lib/main.dart
//
// App entry point. For a C# dev: `main()` is your Program.Main, and runApp()
// hands the root widget to the Flutter engine to render.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_shell.dart';
import 'data/symbol_seeder.dart';
import 'state/providers.dart';

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
  runApp(UncontrolledProviderScope(
    container: container,
    child: const CardboardPressApp(),
  ));
}

class CardboardPressApp extends StatelessWidget {
  const CardboardPressApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CardboardPress',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: const Color(0xFF3F6FB0),
      ),
      home: const AppShell(),
    );
  }
}
