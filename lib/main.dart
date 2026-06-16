// lib/main.dart
//
// App entry point. For a C# dev: `main()` is your Program.Main, and runApp()
// hands the root widget to the Flutter engine to render.

import 'package:flutter/material.dart';

import 'features/spike/spike_screen.dart';

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
      // For now the app opens straight onto the renderer spike.
      // The 5-tab navigation shell comes in the next session.
      home: const SpikeScreen(),
    );
  }
}
