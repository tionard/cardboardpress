// lib/main.dart
//
// App entry point. For a C# dev: `main()` is your Program.Main, and runApp()
// hands the root widget to the Flutter engine to render.

import 'package:flutter/material.dart';

import 'app/app_shell.dart';

void main() => runApp(const CardboardPressApp());

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
      // The app now opens onto the tabbed shell. The renderer spike is reachable
      // from the Card Editor tab until the real editor replaces it.
      home: const AppShell(),
    );
  }
}
