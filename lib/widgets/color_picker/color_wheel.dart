part of 'color_picker.dart';

// The hue/saturation wheel: angle = hue, radius = saturation. Value (brightness)
// and alpha are separate sliders. Hand-rolled (no colour-picker package) with a
// SweepGradient for hue and a white RadialGradient for the saturation falloff —
// two shader circles, no per-pixel loop, so it stays cheap at any size. A raw
// Listener drives selection (not GestureDetector) to avoid tap/pan arena fights
// over the paint surface.

class _HueWheel extends StatelessWidget {
  final double hue; // 0..360
  final double saturation; // 0..1
  final void Function(double hue, double saturation) onChanged;
  final double diameter;

  const _HueWheel({
    required this.hue,
    required this.saturation,
    required this.onChanged,
  }) : diameter = 200;

  // Map a local touch point to (hue, saturation) about the wheel centre.
  void _report(Offset local) {
    final radius = diameter / 2;
    final d = local - Offset(radius, radius);
    final sat = (d.distance / radius).clamp(0.0, 1.0);
    var deg = math.atan2(d.dy, d.dx) * 180 / math.pi;
    if (deg < 0) deg += 360;
    onChanged(deg, sat);
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: diameter,
      height: diameter,
      child: Listener(
        onPointerDown: (e) => _report(e.localPosition),
        onPointerMove: (e) => _report(e.localPosition),
        child: CustomPaint(
          size: Size.square(diameter),
          painter: _WheelPainter(hue: hue, saturation: saturation),
        ),
      ),
    );
  }
}

class _WheelPainter extends CustomPainter {
  final double hue;
  final double saturation;
  _WheelPainter({required this.hue, required this.saturation});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Hue around the ring (13 stops so 0deg red meets 360deg red seamlessly).
    final hueColors = <Color>[
      for (var h = 0; h <= 360; h += 30)
        HSVColor.fromAHSV(1, (h % 360).toDouble(), 1, 1).toColor(),
    ];
    canvas.drawCircle(
      center,
      radius,
      Paint()..shader = SweepGradient(colors: hueColors).createShader(rect),
    );
    // Saturation: white at the centre, fading to transparent at the rim.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = RadialGradient(
          colors: [Colors.white, Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
    // Thin rim.
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black.withValues(alpha: 0.12),
    );

    // Marker at (hue angle, saturation radius): a white ring with a dark halo so
    // it reads on any hue.
    final theta = hue * math.pi / 180;
    final mp = center +
        Offset(math.cos(theta), math.sin(theta)) *
            (saturation.clamp(0.0, 1.0) * radius);
    final outer = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.black.withValues(alpha: 0.5);
    final inner = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white;
    canvas.drawCircle(mp, 7, outer);
    canvas.drawCircle(mp, 7, inner);
  }

  @override
  bool shouldRepaint(_WheelPainter old) =>
      old.hue != hue || old.saturation != saturation;
}
