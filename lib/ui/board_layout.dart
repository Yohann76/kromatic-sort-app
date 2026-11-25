import 'dart:math';
import 'dart:ui';

/// Géométrie d'un tube au repos (coordonnées du plateau).
class TubeGeom {
  const TubeGeom({
    required this.cx,
    required this.top,
    required this.width,
    required this.height,
    required this.unitH,
    required this.cellW,
  });

  /// Centre horizontal.
  final double cx;

  /// Haut du tube (embouchure).
  final double top;
  final double width;
  final double height;

  /// Hauteur d'une couche de liquide.
  final double unitH;

  /// Largeur de la zone cliquable (toute la cellule de la grille).
  final double cellW;

  double get inset => width * _insetRatio;
  double get bottom => top + height;

  /// Distance embouchure -> niveau du liquide pour [level] unités (repère local).
  double surfaceDepth(double level) => height - inset - level * unitH;

  Rect get hitRect => Rect.fromLTWH(
        cx - cellW / 2,
        top - unitH * _hitMarginTop,
        cellW,
        height + unitH * (_hitMarginTop + _hitMarginBottom),
      );

  static const double _insetRatio = 0.08;
  static const double _hitMarginTop = 0.9;
  static const double _hitMarginBottom = 0.3;
}

/// Dispose les tubes sur 1 ou 2 rangées selon leur nombre.
abstract final class BoardLayout {
  /// Au-delà de ce nombre de tubes, on passe sur deux rangées.
  static const int _maxSingleRow = 5;
  static const double _maxTubeWidth = 56;
  static const double _tubeWidthOfCell = 0.62;
  static const double _unitOfWidth = 1.45;
  static const double _rowFill = 0.72;
  static const double _headroomUnits = 0.3;

  /// Hauteur max d'un tube (part de la largeur d'écran) : un tube penché pour
  /// verser doit rester dans l'écran.
  static const double _maxHeightOfWidth = 0.55;

  static List<TubeGeom> compute(Size size, int count, int capacity) {
    final rows = count <= _maxSingleRow ? 1 : 2;
    final firstRowCount = rows == 1 ? count : (count + 1) ~/ 2;
    final rowH = size.height / rows;

    final tubes = <TubeGeom>[];
    for (var r = 0; r < rows; r++) {
      final inRow = r == 0 ? firstRowCount : count - firstRowCount;
      // Cellule commune aux deux rangées pour des tubes de même taille.
      final cellW = size.width / firstRowCount;
      final tubeW = min(cellW * _tubeWidthOfCell, _maxTubeWidth);
      final unitH = [
        tubeW * _unitOfWidth,
        rowH * _rowFill / (capacity + _headroomUnits + 0.2),
        size.width * _maxHeightOfWidth / (capacity + _headroomUnits + 0.4),
      ].reduce(min);
      final height = capacity * unitH + tubeW * 0.16 + unitH * _headroomUnits;
      final rowLeft = (size.width - inRow * cellW) / 2;
      final top = r * rowH + (rowH - height) / 2;
      for (var c = 0; c < inRow; c++) {
        tubes.add(TubeGeom(
          cx: rowLeft + (c + 0.5) * cellW,
          top: top,
          width: tubeW,
          height: height,
          unitH: unitH,
          cellW: cellW,
        ));
      }
    }
    return tubes;
  }

  /// Index du tube touché en [p], ou null.
  static int? hitTest(List<TubeGeom> tubes, Offset p) {
    int? best;
    var bestDist = double.infinity;
    for (var i = 0; i < tubes.length; i++) {
      if (!tubes[i].hitRect.contains(p)) continue;
      final d = (tubes[i].cx - p.dx).abs();
      if (d < bestDist) {
        bestDist = d;
        best = i;
      }
    }
    return best;
  }
}
