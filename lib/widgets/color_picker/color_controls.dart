part of 'color_picker.dart';

// Small colour helpers shared by the picker: hex <-> channels, a duo-aware
// preview decoration, and a checkerboard so translucency reads against it.
// (These are the pieces a later pass would share with the customization
// screen's colour editor when the two are consolidated.)

// RRGGBB when opaque, RRGGBBAA when the alpha byte < 255. Upper-case, no '#'.
// Keeping the first six digits as plain RGB means existing #RRGGBB muscle memory
// still works and alpha is just an optional two-digit suffix.
String _hexString(int a, int r, int g, int b) {
  final rgb = ((r << 16) | (g << 8) | b).toRadixString(16).padLeft(6, '0');
  final s = a >= 255 ? rgb : rgb + a.toRadixString(16).padLeft(2, '0');
  return s.toUpperCase();
}

// Parse #RRGGBB or #RRGGBBAA (the '#' optional) into channels, or null if the
// string isn't a complete 6- or 8-digit hex colour. Caller treats null as
// "incomplete — do nothing", so half-typed input never disturbs the sliders.
({int a, int r, int g, int b})? _parseHex(String input) {
  var s = input.trim();
  if (s.startsWith('#')) s = s.substring(1);
  if (s.length != 6 && s.length != 8) return null;
  final n = int.tryParse(s, radix: 16);
  if (n == null) return null;
  if (s.length == 6) {
    return (a: 255, r: (n >> 16) & 0xFF, g: (n >> 8) & 0xFF, b: n & 0xFF);
  }
  return (
    a: n & 0xFF,
    r: (n >> 24) & 0xFF,
    g: (n >> 16) & 0xFF,
    b: (n >> 8) & 0xFF,
  );
}

// A BoxDecoration previewing a ColorValue (single = flat, double = split
// gradient), with an optional [border]. A preview only — cards use paintCard.
BoxDecoration _previewDecoration(ColorValue v,
    {double radius = 10, Border? border}) {
  final br = BorderRadius.circular(radius);
  if (!v.isDouble) {
    return BoxDecoration(color: v.c1, borderRadius: br, border: border);
  }
  final vertical = v.orientation == MixOrientation.vertical;
  final half = v.mix / 2;
  return BoxDecoration(
    borderRadius: br,
    border: border,
    gradient: LinearGradient(
      begin: vertical ? Alignment.topCenter : Alignment.centerLeft,
      end: vertical ? Alignment.bottomCenter : Alignment.centerRight,
      colors: [v.c1, v.c1, v.c2!, v.c2!],
      stops: [0.0, 0.5 - half, 0.5 + half, 1.0],
    ),
  );
}

// A neutral checkerboard, drawn behind a translucent preview so its alpha is
// visible instead of blending invisibly into the surface.
class _CheckerPainter extends CustomPainter {
  const _CheckerPainter();

  @override
  void paint(Canvas canvas, Size size) {
    const cell = 8.0;
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    final dark = Paint()..color = const Color(0xFFD9D9D9);
    for (var y = 0.0; y < size.height; y += cell) {
      for (var x = 0.0; x < size.width; x += cell) {
        if (((x ~/ cell) + (y ~/ cell)).isEven) {
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), dark);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
