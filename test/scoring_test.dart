import 'package:flutter_test/flutter_test.dart';
import 'package:kromatik_sort/game/scoring.dart';

void main() {
  test('la difficulté suit les paliers de niveaux', () {
    const expected = <int, Difficulty>{
      1: Difficulty.easy,
      4: Difficulty.easy,
      5: Difficulty.medium,
      8: Difficulty.medium,
      9: Difficulty.hard,
      12: Difficulty.hard,
      13: Difficulty.expert,
      500: Difficulty.expert,
    };
    expected.forEach((level, difficulty) {
      expect(Difficulty.forLevel(level), difficulty, reason: 'niveau $level');
    });
  });

  test('chaque indice retire son coût du gain', () {
    expect(Difficulty.medium.reward(0), 160);
    expect(Difficulty.medium.reward(1), 120);
    expect(Difficulty.medium.reward(kMaxHintsPerLevel), 80);
  });

  test('le gain reste positif avec tous les indices', () {
    for (final difficulty in Difficulty.values) {
      expect(difficulty.reward(kMaxHintsPerLevel), greaterThan(0));
    }
  });
}
