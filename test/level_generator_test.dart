import 'package:flutter_test/flutter_test.dart';
import 'package:kromatik_sort/game/game_state.dart';
import 'package:kromatik_sort/game/level_generator.dart';

/// Résout un niveau avec les VRAIES règles du jeu (DFS borné) pour vérifier
/// que la génération inverse produit bien des niveaux jouables.
bool _solve(GameState s, Set<String> seen, List<int> budget) {
  if (s.isSolved) return true;
  if (budget[0]-- <= 0) return true; // budget épuisé : on ne conclut pas
  final key = (s.tubes.map((t) => t.join(',')).toList()..sort()).join('|');
  if (!seen.add(key)) return false;
  for (var a = 0; a < s.tubes.length; a++) {
    for (var b = 0; b < s.tubes.length; b++) {
      if (!s.canPour(a, b)) continue;
      if (s.tubes[b].isEmpty && GameState.isUniform(s.tubes[a])) continue;
      s.pour(a, b);
      final ok = _solve(s, seen, budget);
      s.undo();
      if (ok) return true;
    }
  }
  return false;
}

void main() {
  const generator = LevelGenerator();

  test('niveaux déterministes', () {
    expect(generator.generate(12), generator.generate(12));
  });

  test('niveaux valides, mélangés et jamais déjà résolus', () {
    for (var level = 1; level <= 80; level++) {
      final tubes = generator.generate(level);
      final config = LevelConfig.forLevel(level);
      expect(tubes.length, config.colors + config.emptyTubes);
      final counts = <int, int>{};
      for (final t in tubes) {
        expect(t.length <= LevelConfig.capacity, isTrue);
        for (final c in t) {
          counts[c] = (counts[c] ?? 0) + 1;
        }
      }
      expect(counts.length, config.colors);
      expect(counts.values.every((n) => n == LevelConfig.capacity), isTrue);
      final state = GameState(tubes: tubes, capacity: LevelConfig.capacity);
      expect(state.isSolved, isFalse, reason: 'niveau $level déjà résolu');
      expect(LevelGenerator.mixRatio(tubes), greaterThan(0.3),
          reason: 'niveau $level peu mélangé');
    }
  });

  test('niveaux solvables avec les règles réelles', () {
    for (var level = 1; level <= 40; level++) {
      final state = GameState(
        tubes: generator.generate(level),
        capacity: LevelConfig.capacity,
      );
      expect(_solve(state, <String>{}, <int>[200000]), isTrue,
          reason: 'niveau $level non solvable');
    }
  });

  test('annulation restaure l\'état', () {
    final state = GameState(tubes: [
      [0, 1],
      [1],
      []
    ], capacity: 4);
    state.pour(0, 1);
    expect(state.tubes, [
      [0],
      [1, 1],
      []
    ]);
    state.undo();
    expect(state.tubes, [
      [0, 1],
      [1],
      []
    ]);
  });
}
