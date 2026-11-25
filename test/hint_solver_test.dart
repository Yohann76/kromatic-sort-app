import 'package:flutter_test/flutter_test.dart';
import 'package:kromatik_sort/game/game_state.dart';
import 'package:kromatik_sort/game/hint_solver.dart';
import 'package:kromatik_sort/game/level_generator.dart';

void main() {
  test('suivre les indices successifs résout les niveaux', () {
    const generator = LevelGenerator();
    // Un niveau par palier de difficulté, plus le plafond de mélange.
    for (final level in <int>[1, 5, 9, 13, 60]) {
      final state = GameState(
        tubes: generator.generate(level),
        capacity: LevelConfig.capacity,
      );
      final solution =
          findSolution((tubes: state.tubes, capacity: state.capacity));
      // Le chemin est sans boucle : au plus un coup par position mémorisée.
      var movesLeft = solution.length;
      while (!state.isSolved && movesLeft-- > 0) {
        final hint = solution[positionKey(state.tubes)];
        expect(hint, isNotNull, reason: 'niveau $level sans indice');
        expect(state.pour(hint!.from, hint.to), isNotNull);
      }
      expect(state.isSolved, isTrue, reason: 'niveau $level non résolu');
    }
  });

  test('aucun indice sur une position bloquée', () {
    final tubes = <List<int>>[
      [0, 1],
      [1, 0],
    ];
    expect(findSolution((tubes: tubes, capacity: 2)), isEmpty);
  });

  test('aucun indice sur un niveau résolu', () {
    final tubes = <List<int>>[
      [0, 0],
      <int>[],
    ];
    expect(findSolution((tubes: tubes, capacity: 2)), isEmpty);
  });

  test('la recherche ne modifie pas les tubes fournis', () {
    final tubes = <List<int>>[
      [0, 1],
      [1, 0],
      <int>[],
    ];
    findSolution((tubes: tubes, capacity: 2));
    expect(tubes, [
      [0, 1],
      [1, 0],
      <int>[],
    ]);
  });
}
