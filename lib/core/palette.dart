import 'package:flutter/painting.dart';

/// Couleurs de l'interface (thème sombre « nuit violette »).
abstract final class AppColors {
  static const Color bgTop = Color(0xFF2B2266);
  static const Color bgBottom = Color(0xFF0D0B22);
  static const Color accent = Color(0xFFFFD93D);
  static const Color text = Color(0xFFF4F1FF);
  static const Color textDim = Color(0xFFA9A3D6);
  static const Color glass = Color(0x1AFFFFFF);
}

/// Couleurs des liquides, indexées par l'id de couleur utilisé dans la logique.
/// Choisies pour rester bien distinctes entre elles sur fond sombre.
const List<Color> kLiquidColors = <Color>[
  Color(0xFFFF4D6D), // rouge
  Color(0xFFFF9F1C), // orange
  Color(0xFFFFD93D), // jaune
  Color(0xFFA7E22E), // vert citron
  Color(0xFF22D3EE), // cyan
  Color(0xFF3B82F6), // bleu
  Color(0xFF8B5CF6), // violet
  Color(0xFFEC4899), // rose
  Color(0xFFB9722F), // marron
  Color(0xFFE2E8F0), // blanc
];
