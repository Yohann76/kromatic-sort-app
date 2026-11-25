import 'dart:math';

import '../core/palette.dart';

/// Paramètres de difficulté d'un niveau.
class LevelConfig {
  const LevelConfig({
    required this.colors,
    required this.emptyTubes,
    required this.scrambleMoves,
  });

  /// Nombre d'unités par tube.
  static const int capacity = 4;

  /// Nombre de tubes vides au départ.
  static const int defaultEmptyTubes = 2;

  /// Une nouvelle couleur tous les [_levelsPerNewColor] niveaux.
  static const int _levelsPerNewColor = 2;
  static const int _startColors = 3;

  /// Mouvements inverses : base + par couleur + par niveau (plafonné).
  static const int _scrambleBase = 30;
  static const int _scramblePerColor = 12;
  static const int _scramblePerLevel = 2;
  static const int _scrambleLevelCap = 60;

  final int colors;
  final int emptyTubes;
  final int scrambleMoves;

  factory LevelConfig.forLevel(int level) {
    final colors = min(
      _startColors + (level - 1) ~/ _levelsPerNewColor,
      kLiquidColors.length,
    );
    return LevelConfig(
      colors: colors,
      emptyTubes: defaultEmptyTubes,
      scrambleMoves: _scrambleBase +
          colors * _scramblePerColor +
          min(level, _scrambleLevelCap) * _scramblePerLevel,
    );
  }
}

/// Génère des niveaux par **mélange inverse** : on part de l'état résolu et on
/// applique des mouvements légaux à l'envers. Le niveau obtenu est donc
/// toujours solvable, et déterministe pour un numéro de niveau donné.
class LevelGenerator {
  const LevelGenerator();

  /// Nombre max de tentatives pour obtenir un mélange assez poussé.
  static const int _maxAttempts = 40;

  /// Part minimale de paires voisines de couleurs différentes (sur le total
  /// de paires possibles) pour considérer un niveau suffisamment mélangé.
  static const double _minMixRatio = 0.55;

  /// Probabilité de préférer un tube d'arrivée qui mélange les couleurs.
  static const double _preferMixingChance = 0.8;

  /// Multiplicateur du numéro de niveau dans la graine (nombre premier).
  static const int _seedPrime = 7919;

  List<List<int>> generate(int level) {
    final config = LevelConfig.forLevel(level);
    List<List<int>>? best;
    var bestMix = -1.0;
    for (var attempt = 0; attempt < _maxAttempts; attempt++) {
      final rng = Random(level * _seedPrime + attempt);
      final tubes = _scramble(config, rng);
      final mix = mixRatio(tubes);
      if (mix > bestMix) {
        best = tubes;
        bestMix = mix;
      }
      if (mix >= _minMixRatio) break;
    }
    return best!;
  }

  /// Part des paires de couches voisines qui ont des couleurs différentes.
  static double mixRatio(List<List<int>> tubes) {
    var pairs = 0;
    var different = 0;
    for (final tube in tubes) {
      for (var i = 1; i < tube.length; i++) {
        pairs++;
        if (tube[i] != tube[i - 1]) different++;
      }
    }
    return pairs == 0 ? 0 : different / pairs;
  }

  List<List<int>> _scramble(LevelConfig config, Random rng) {
    const capacity = LevelConfig.capacity;
    final tubes = <List<int>>[
      for (var c = 0; c < config.colors; c++) List<int>.filled(capacity, c, growable: true),
      for (var e = 0; e < config.emptyTubes; e++) <int>[],
    ];

    var lastFrom = -1;
    var lastTo = -1;
    var done = 0;
    var guard = config.scrambleMoves * 20;
    while (done < config.scrambleMoves && guard-- > 0) {
      final sources = _unpourableTubes(tubes);
      if (sources.isEmpty) break;
      final from = sources[rng.nextInt(sources.length)];
      final unit = tubes[from].last;

      final targets = _targets(tubes, from, unit, lastFrom, lastTo, rng);
      if (targets.isEmpty) continue;
      final to = targets[rng.nextInt(targets.length)];

      tubes[from].removeLast();
      tubes[to].add(unit);
      lastFrom = from;
      lastTo = to;
      done++;
    }
    return tubes;
  }

  /// Tubes dont l'unité du haut peut être « dé-versée » : elle doit pouvoir
  /// avoir été versée là, donc être seule ou posée sur la même couleur.
  List<int> _unpourableTubes(List<List<int>> tubes) {
    return <int>[
      for (var i = 0; i < tubes.length; i++)
        if (tubes[i].isNotEmpty &&
            (tubes[i].length == 1 ||
                tubes[i][tubes[i].length - 1] == tubes[i][tubes[i].length - 2]))
          i,
    ];
  }

  List<int> _targets(
    List<List<int>> tubes,
    int from,
    int unit,
    int lastFrom,
    int lastTo,
    Random rng,
  ) {
    final all = <int>[
      for (var j = 0; j < tubes.length; j++)
        if (j != from &&
            tubes[j].length < LevelConfig.capacity &&
            // inutile de déplacer une unité seule vers un tube vide
            !(tubes[j].isEmpty && tubes[from].length == 1) &&
            // évite l'aller-retour immédiat qui annulerait le mouvement
            !(from == lastTo && j == lastFrom))
          j,
    ];
    if (rng.nextDouble() >= _preferMixingChance) return all;
    final mixing = all
        .where((j) => tubes[j].isEmpty || tubes[j].last != unit)
        .toList();
    return mixing.isEmpty ? all : mixing;
  }
}
