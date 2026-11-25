import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../core/palette.dart';

/// Dégradé nocturne avec de grosses bulles floues qui dérivent lentement.
class AmbientBackground extends StatefulWidget {
  const AmbientBackground({super.key});

  @override
  State<AmbientBackground> createState() => _AmbientBackgroundState();
}

class _AmbientBackgroundState extends State<AmbientBackground>
    with SingleTickerProviderStateMixin {
  static const Duration _loop = Duration(seconds: 90);

  late final AnimationController _controller =
      AnimationController(vsync: this, duration: _loop)..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: CustomPaint(
        size: Size.infinite,
        painter: _AmbientPainter(_controller),
      ),
    );
  }
}

class _AmbientPainter extends CustomPainter {
  _AmbientPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  static const int _bubbleCount = 12;
  static final List<_Bubble> _bubbles = _makeBubbles();

  static List<_Bubble> _makeBubbles() {
    final rng = Random(42);
    return List<_Bubble>.generate(_bubbleCount, (_) {
      return _Bubble(
        x: rng.nextDouble(),
        y: rng.nextDouble(),
        radius: 0.08 + rng.nextDouble() * 0.16,
        phase: rng.nextDouble() * 2 * pi,
        cycles: 1 + rng.nextInt(2),
        color: kLiquidColors[rng.nextInt(kLiquidColors.length)],
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.bgTop, AppColors.bgBottom],
        ).createShader(rect),
    );
    final t = animation.value * 2 * pi;
    for (final b in _bubbles) {
      final cx = (b.x + 0.04 * sin(t * b.cycles + b.phase)) * size.width;
      final cy = (b.y + 0.05 * cos(t * b.cycles + b.phase)) * size.height;
      final r = b.radius * size.width;
      canvas.drawCircle(
        Offset(cx, cy),
        r,
        Paint()
          ..shader = RadialGradient(
            colors: [b.color.withValues(alpha: 0.14), b.color.withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: Offset(cx, cy), radius: r)),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientPainter oldDelegate) => false;
}

class _Bubble {
  const _Bubble({
    required this.x,
    required this.y,
    required this.radius,
    required this.phase,
    required this.cycles,
    required this.color,
  });

  final double x;
  final double y;
  final double radius;
  final double phase;
  final int cycles;
  final Color color;
}
