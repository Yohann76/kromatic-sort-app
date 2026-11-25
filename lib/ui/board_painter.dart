import 'dart:math';

import 'package:flutter/animation.dart';
import 'package:flutter/rendering.dart';

import '../core/palette.dart';
import 'board_controller.dart';
import 'board_layout.dart';

/// Une couche continue d'une même couleur, en unités de liquide (fractionnaires
/// pendant un versement).
class _Run {
  _Run(this.color, this.from, this.to);
  final int color;
  final double from;
  final double to;
}

/// Position d'un tube : point d'ancrage (centre de l'embouchure) et inclinaison.
class _Pose {
  const _Pose(this.pivot, this.angle);
  final Offset pivot;
  final double angle;
}

/// Dessine tubes, liquides (surface ondulée en courbes de Bézier), flux de
/// versement et ombres.
class BoardPainter extends CustomPainter {
  BoardPainter(this.board) : super(repaint: board);

  final BoardController board;

  // --- Constantes de rendu ---------------------------------------------------
  static const double _liftUnits = 0.8;
  static const double _pourGapUnits = 0.5;
  static const double _minTilt = 0.35;
  static const double _maxTilt = 1.4;
  static const double _idleWaveAmp = 1.3;
  static const double _wobbleWaveAmp = 4.0;
  static const double _pourWaveAmp = 3.2;
  static const double _waveSpeed = 2.4;
  static const double _waveLengthOfWidth = 1.6;
  static const double _introStagger = 0.05;
  static const double _introDuration = 0.45;
  static const double _liquidSeamOverlap = 0.6;

  @override
  void paint(Canvas canvas, Size size) {
    final state = board.state;
    final geoms =
        BoardLayout.compute(size, state.tubes.length, state.capacity);
    final pour = board.pour;

    for (var i = 0; i < geoms.length; i++) {
      _drawShadow(canvas, geoms[i], _introOffset(geoms[i], i) == null);
    }
    for (var i = 0; i < geoms.length; i++) {
      if (pour != null && (i == pour.from || i == pour.to)) continue;
      _drawRestingTube(canvas, geoms, i);
    }
    if (pour != null) {
      _drawPouring(canvas, geoms, pour, size.width);
    }
  }

  // --- Tubes au repos --------------------------------------------------------

  /// Décalage vertical de l'animation d'entrée (null = tube pas encore apparu).
  double? _introOffset(TubeGeom g, int index) {
    final p = ((board.introTime - index * _introStagger) / _introDuration)
        .clamp(0.0, 1.0);
    if (p <= 0) return null;
    return -(1 - Curves.easeOutBack.transform(p)) * g.height * 1.2;
  }

  void _drawRestingTube(Canvas canvas, List<TubeGeom> geoms, int i) {
    final g = geoms[i];
    final offset = _introOffset(g, i);
    if (offset == null) return;
    final lift = board.lift[i];
    final pose = _Pose(
      Offset(g.cx, g.top - lift * g.unitH * _liftUnits + offset),
      0,
    );
    final runs = _runsOf(board.state.tubes[i]);
    final amp = _idleWaveAmp + _wobbleWaveAmp * board.wobble[i];
    final complete = board.state.isComplete(i);
    final age = board.time - (board.doneAt[i] ?? -10);
    final glow = complete
        ? kLiquidColors[board.state.tubes[i].first]
            .withValues(alpha: 0.3 + 0.5 * max(0.0, 1 - age / 0.9))
        : (lift > 0.02 ? AppColors.text.withValues(alpha: 0.35 * lift) : null);
    _drawTube(canvas, g, i, runs, pose, amp, glow);
  }

  // --- Versement -------------------------------------------------------------

  void _drawPouring(
      Canvas canvas, List<TubeGeom> geoms, PourAnim a, double boardWidth) {
    final src = geoms[a.from];
    final dst = geoms[a.to];
    final srcTube = board.state.tubes[a.from];
    final dstTube = board.state.tubes[a.to];
    final pp = a.pourProgress;
    final moved = a.count * pp;

    // Tube cible : reçoit du liquide de la même couleur.
    final dstRuns = _runsOf(dstTube, add: moved, addColor: a.color);
    _drawTube(canvas, dst, a.to, dstRuns,
        _Pose(Offset(dst.cx, dst.top), 0), _pourWaveAmp, null);

    // Pose du tube source selon la phase.
    // Le tube penche du côté où il y a le plus de place (jamais hors écran).
    final sign = dst.cx > boardWidth / 2 ? 1.0 : -1.0;
    final spout = src.width / 2 - src.inset;
    double tiltFor(double level) => atan(src.surfaceDepth(level) / spout)
        .clamp(_minTilt, _maxTilt)
        .toDouble();
    _Pose pourPose(double tilt) => _Pose(
          Offset(
            dst.cx - sign * spout * cos(tilt),
            dst.top - src.unitH * _pourGapUnits - spout * sin(tilt),
          ),
          sign * tilt,
        );

    final startTilt = tiltFor(srcTube.length.toDouble());
    final endTilt = tiltFor((srcTube.length - a.count).toDouble());
    final liftedPivot =
        Offset(src.cx, src.top - a.startLift * src.unitH * _liftUnits);
    final restPivot = Offset(src.cx, src.top);

    late _Pose pose;
    double tiltNow;
    if (a.t < PourAnim.inDuration) {
      final e = Curves.easeInOut.transform(a.inProgress);
      final target = pourPose(startTilt);
      pose = _Pose(Offset.lerp(liftedPivot, target.pivot, e)!,
          target.angle * e);
      tiltNow = startTilt * e;
    } else if (pp < 1 || a.outProgress == 0) {
      tiltNow = tiltFor(srcTube.length - moved);
      pose = pourPose(tiltNow);
    } else {
      final e = Curves.easeInOut.transform(a.outProgress);
      final from = pourPose(endTilt);
      pose = _Pose(Offset.lerp(from.pivot, restPivot, e)!,
          from.angle * (1 - e));
      tiltNow = endTilt * (1 - e);
    }

    // Flux de liquide entre le bec du tube source et la surface du tube cible.
    if (a.t >= PourAnim.inDuration && a.outProgress == 0) {
      _drawStream(canvas, src, dst, a, pose, tiltNow, sign, spout, dstTube.length + moved);
    }

    final srcRuns = _runsOf(srcTube, remove: moved);
    _drawTube(canvas, src, a.from, srcRuns, pose, _pourWaveAmp, null);
  }

  void _drawStream(Canvas canvas, TubeGeom src, TubeGeom dst, PourAnim a,
      _Pose pose, double tilt, double sign, double spout, double dstLevel) {
    final pp = a.pourProgress;
    final x = pose.pivot.dx + sign * spout * cos(tilt);
    // Le flux démarre légèrement sous le bec pour ne pas dépasser du verre.
    final yStart = pose.pivot.dy + spout * sin(tilt) + dst.width * 0.08;
    final yEnd = dst.top + dst.surfaceDepth(dstLevel);
    // Le flux descend au début, puis remonte vers la cible à la fin.
    final head = yStart + (yEnd - yStart) * Curves.easeOut.transform((pp / 0.12).clamp(0.0, 1.0));
    final tail = pp > 0.9
        ? yStart + (yEnd - yStart) * Curves.easeIn.transform((pp - 0.9) / 0.1)
        : yStart;
    if (head - tail < 1) return;

    final sway = sin(board.time * 14) * dst.width * 0.025;
    final path = Path()
      ..moveTo(x, tail)
      ..cubicTo(x + sway, tail + (head - tail) * 0.3, x - sway,
          tail + (head - tail) * 0.7, x, head);
    final color = kLiquidColors[a.color];
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = dst.width * 0.2,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0x55FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = dst.width * 0.06,
    );
    // Petite éclaboussure à l'impact.
    canvas.drawOval(
      Rect.fromCenter(
          center: Offset(x, head), width: dst.width * 0.5, height: dst.width * 0.14),
      Paint()..color = color.withValues(alpha: 0.7),
    );
  }

  // --- Couches ---------------------------------------------------------------

  /// Regroupe les unités consécutives de même couleur ; permet de retirer
  /// ([remove]) du liquide au sommet ou d'en ajouter ([add]).
  List<_Run> _runsOf(List<int> tube,
      {double remove = 0, double add = 0, int? addColor}) {
    final runs = <_Run>[];
    var i = 0;
    while (i < tube.length) {
      var j = i;
      while (j < tube.length && tube[j] == tube[i]) {
        j++;
      }
      runs.add(_Run(tube[i], i.toDouble(), j.toDouble()));
      i = j;
    }
    if (remove > 0 && runs.isNotEmpty) {
      final top = runs.removeLast();
      final to = top.to - remove;
      if (to > top.from) runs.add(_Run(top.color, top.from, to));
    }
    if (add > 0 && addColor != null) {
      final start = tube.length.toDouble();
      if (runs.isNotEmpty && runs.last.color == addColor) {
        final last = runs.removeLast();
        runs.add(_Run(addColor, last.from, start + add));
      } else {
        runs.add(_Run(addColor, start, start + add));
      }
    }
    return runs;
  }

  // --- Dessin d'un tube ------------------------------------------------------

  void _drawShadow(Canvas canvas, TubeGeom g, bool hidden) {
    if (hidden) return;
    final rect = Rect.fromCenter(
      center: Offset(g.cx, g.bottom + g.unitH * 0.12),
      width: g.width * 1.5,
      height: g.width * 0.4,
    );
    canvas.drawOval(
      rect,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0x66000000), Color(0x00000000)],
        ).createShader(rect),
    );
  }

  void _drawTube(Canvas canvas, TubeGeom g, int index, List<_Run> runs,
      _Pose pose, double amp, Color? glow) {
    final w = g.width;
    final h = g.height;
    final inset = g.inset;
    final outer = RRect.fromRectAndCorners(
      Rect.fromLTWH(-w / 2, 0, w, h),
      topLeft: const Radius.circular(5),
      topRight: const Radius.circular(5),
      bottomLeft: Radius.circular(w / 2),
      bottomRight: Radius.circular(w / 2),
    );
    final inner = RRect.fromRectAndCorners(
      Rect.fromLTWH(-w / 2 + inset, 0, w - 2 * inset, h - inset),
      bottomLeft: Radius.circular(w / 2 - inset),
      bottomRight: Radius.circular(w / 2 - inset),
    );

    // Verre (fond) + halo éventuel.
    canvas.save();
    canvas.translate(pose.pivot.dx, pose.pivot.dy);
    canvas.rotate(pose.angle);
    if (glow != null) {
      canvas.drawRRect(
        outer.inflate(2),
        Paint()
          ..color = glow
          ..style = PaintingStyle.stroke
          ..strokeWidth = 5
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7),
      );
    }
    canvas.drawRRect(outer, Paint()..color = AppColors.glass);
    canvas.restore();

    // Liquide : clip « monde » horizontal (surface ondulée) + clip du tube.
    final level = runs.isEmpty ? 0.0 : runs.last.to;
    if (level > 0) {
      final depth = g.surfaceDepth(level);
      final surfaceWorld = Offset(
        pose.pivot.dx - depth * sin(pose.angle),
        pose.pivot.dy + depth * cos(pose.angle),
      );
      final open = _wavePath(surfaceWorld, g, amp, index);
      final halfPlane = Path.from(open)
        ..lineTo(surfaceWorld.dx + h * 1.5 + w, surfaceWorld.dy + h * 3)
        ..lineTo(surfaceWorld.dx - h * 1.5 - w, surfaceWorld.dy + h * 3)
        ..close();

      canvas.save();
      canvas.clipPath(halfPlane);
      canvas.translate(pose.pivot.dx, pose.pivot.dy);
      canvas.rotate(pose.angle);
      canvas.clipRRect(inner);
      _paintRuns(canvas, g, runs);
      canvas.restore();

      // Reflet fin le long de la surface.
      _paintSurfaceLine(canvas, open, pose, inner);
    }

    // Verre (avant) : contour et reflets.
    canvas.save();
    canvas.translate(pose.pivot.dx, pose.pivot.dy);
    canvas.rotate(pose.angle);
    canvas.drawRRect(
      outer,
      Paint()
        ..color = const Color(0xB3FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2,
    );
    final hl = RRect.fromRectAndRadius(
      Rect.fromLTWH(-w / 2 + w * 0.17, h * 0.07, w * 0.1, h * 0.58),
      Radius.circular(w * 0.05),
    );
    canvas.drawRRect(hl, Paint()..color = const Color(0x38FFFFFF));
    canvas.restore();
  }

  void _paintRuns(Canvas canvas, TubeGeom g, List<_Run> runs) {
    final w = g.width;
    final base = g.height - g.inset;
    for (var k = 0; k < runs.length; k++) {
      final run = runs[k];
      final isTop = k == runs.length - 1;
      final yBottom = k == 0 ? g.height + 2 : base - run.from * g.unitH + _liquidSeamOverlap;
      // La couche du dessus est prolongée vers le haut : la surface réelle est
      // définie par le clip horizontal du monde.
      final yTop = isTop ? -g.height * 2 : base - run.to * g.unitH;
      final rect = Rect.fromLTRB(-w / 2, yTop, w / 2, yBottom);
      canvas.drawRect(rect, Paint()..color = kLiquidColors[run.color]);
    }
    // Ombrage cylindrique : clair à gauche, sombre à droite.
    final shade = Rect.fromLTRB(-w / 2, -g.height * 2, w / 2, g.height + 2);
    canvas.drawRect(
      shade,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0x40FFFFFF), Color(0x00FFFFFF), Color(0x2E000000)],
          stops: [0.0, 0.45, 1.0],
        ).createShader(Rect.fromLTRB(-w / 2, 0, w / 2, 1)),
    );
  }

  void _paintSurfaceLine(Canvas canvas, Path open, _Pose pose, RRect inner) {
    canvas.save();
    canvas.translate(pose.pivot.dx, pose.pivot.dy);
    canvas.rotate(pose.angle);
    canvas.clipRRect(inner);
    // On repasse en repère monde pour tracer la ligne de surface.
    canvas.rotate(-pose.angle);
    canvas.translate(-pose.pivot.dx, -pose.pivot.dy);
    canvas.drawPath(
      open,
      Paint()
        ..color = const Color(0x66FFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.restore();
  }

  /// Surface ondulée : suite de courbes de Bézier quadratiques lissées.
  Path _wavePath(Offset surface, TubeGeom g, double amp, int index) {
    final half = g.height * 1.5 + g.width;
    final step = max(8.0, g.width / 4);
    final k = 2 * pi / (g.width * _waveLengthOfWidth);
    final phase = board.time * _waveSpeed + index * 1.3;

    Offset point(double x) =>
        Offset(x, surface.dy + amp * sin(phase + (x - surface.dx) * k));

    final path = Path();
    var prev = point(surface.dx - half);
    path.moveTo(prev.dx, prev.dy);
    for (var x = surface.dx - half + step; x <= surface.dx + half; x += step) {
      final cur = point(x);
      final mid = Offset((prev.dx + cur.dx) / 2, (prev.dy + cur.dy) / 2);
      path.quadraticBezierTo(prev.dx, prev.dy, mid.dx, mid.dy);
      prev = cur;
    }
    path.lineTo(prev.dx, prev.dy);
    return path;
  }

  @override
  bool shouldRepaint(covariant BoardPainter oldDelegate) => true;
}
