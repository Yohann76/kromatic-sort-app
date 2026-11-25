import 'dart:math';

import 'package:material_ui/material_ui.dart';

import '../core/palette.dart';

/// Carte de victoire + pluie de confettis.
class WinOverlay extends StatefulWidget {
  const WinOverlay({
    super.key,
    required this.level,
    required this.moves,
    required this.onNext,
  });

  final int level;
  final int moves;
  final VoidCallback onNext;

  @override
  State<WinOverlay> createState() => _WinOverlayState();
}

class _WinOverlayState extends State<WinOverlay>
    with SingleTickerProviderStateMixin {
  static const Duration _confettiDuration = Duration(milliseconds: 3600);

  late final AnimationController _confetti =
      AnimationController(vsync: this, duration: _confettiDuration)..forward();

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: ColoredBox(color: Colors.black.withValues(alpha: 0.45))),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(painter: _ConfettiPainter(_confetti)),
          ),
        ),
        Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0.6, end: 1),
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) => Transform.scale(
              scale: scale,
              child: Opacity(opacity: scale.clamp(0.0, 1.0), child: child),
            ),
            child: _card(),
          ),
        ),
      ],
    );
  }

  Widget _card() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 36),
      padding: const EdgeInsets.fromLTRB(28, 26, 28, 24),
      decoration: BoxDecoration(
        color: const Color(0xF21E1850),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: const Color(0x33FFFFFF)),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 30)],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Bravo !',
              style: TextStyle(
                  fontSize: 34, fontWeight: FontWeight.w800, color: AppColors.accent)),
          const SizedBox(height: 6),
          Text('Niveau ${widget.level} terminé',
              style: const TextStyle(fontSize: 17, color: AppColors.text)),
          const SizedBox(height: 4),
          Text('${widget.moves} coups',
              style: const TextStyle(fontSize: 14, color: AppColors.textDim)),
          const SizedBox(height: 22),
          FilledButton(
            onPressed: widget.onNext,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: const Color(0xFF241B00),
              padding: const EdgeInsets.symmetric(horizontal: 34, vertical: 14),
              textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              shape: const StadiumBorder(),
            ),
            child: const Text('Niveau suivant'),
          ),
        ],
      ),
    );
  }
}

class _ConfettiPainter extends CustomPainter {
  _ConfettiPainter(this.animation) : super(repaint: animation);

  final Animation<double> animation;

  static const int _count = 70;
  static const double _gravity = 900;
  static const double _seconds = 3.6;
  static final List<_Piece> _pieces = _makePieces();

  static List<_Piece> _makePieces() {
    final rng = Random(5);
    return List<_Piece>.generate(_count, (_) {
      return _Piece(
        x: rng.nextDouble(),
        vx: (rng.nextDouble() - 0.5) * 220,
        vy: -300 - rng.nextDouble() * 500,
        size: 6 + rng.nextDouble() * 7,
        spin: (rng.nextDouble() - 0.5) * 14,
        color: kLiquidColors[rng.nextInt(kLiquidColors.length)],
      );
    });
  }

  @override
  void paint(Canvas canvas, Size size) {
    final t = animation.value * _seconds;
    for (final p in _pieces) {
      final x = p.x * size.width + p.vx * t;
      final y = size.height * 0.55 + p.vy * t + 0.5 * _gravity * t * t;
      if (y > size.height + 20) continue;
      canvas.save();
      canvas.translate(x, y);
      canvas.rotate(p.spin * t);
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: p.size, height: p.size * 0.55),
        Paint()..color = p.color.withValues(alpha: (1 - animation.value * 0.6)),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _ConfettiPainter oldDelegate) => false;
}

class _Piece {
  const _Piece({
    required this.x,
    required this.vx,
    required this.vy,
    required this.size,
    required this.spin,
    required this.color,
  });

  final double x;
  final double vx;
  final double vy;
  final double size;
  final double spin;
  final Color color;
}
