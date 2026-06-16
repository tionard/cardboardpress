// lib/main.dart
//
// App entry point. For a C# dev: `main()` is your Program.Main, and runApp()
// hands the root widget to the Flutter engine to render.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app_shell.dart';

// ProviderScope is the root that holds all Riverpod provider state. Every app
// using Riverpod wraps its root widget in exactly one of these.
void main() => runApp(const ProviderScope(child: CardboardPressApp()));

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
