import 'level_generator.dart';

/// Nombre maximum d'indices par niveau.
const int kMaxHintsPerLevel = 2;

/// Barème : la difficulté dépend du nombre de couleurs du niveau.
/// Un indice coûte 25 % des points du niveau.
enum Difficulty {
  easy(label: 'Facile', maxColors: 4, points: 100, hintCost: 25),
  medium(label: 'Moyen', maxColors: 6, points: 160, hintCost: 40),
  hard(label: 'Difficile', maxColors: 8, points: 220, hintCost: 55),

  /// Dernier palier : couvre toutes les couleurs restantes.
  expert(label: 'Expert', maxColors: null, points: 300, hintCost: 75);

  const Difficulty({
    required this.label,
    required this.maxColors,
    required this.points,
    required this.hintCost,
  });

  final String label;

  /// Plus grand nombre de couleurs du palier (null = sans limite).
  final int? maxColors;

  /// Points gagnés en résolvant le niveau sans indice.
  final int points;

  /// Points retirés du gain par indice demandé.
  final int hintCost;

  static Difficulty forLevel(int level) {
    final colors = LevelConfig.forLevel(level).colors;
    return values.firstWhere(
      (d) => d.maxColors == null || colors <= d.maxColors!,
    );
  }

  /// Points que rapporte le niveau après [hintsUsed] indices.
  int reward(int hintsUsed) => points - hintsUsed * hintCost;
}
