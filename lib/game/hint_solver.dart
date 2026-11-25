import 'game_state.dart';

/// Données d'une recherche d'indice (transmissibles à un autre isolate).
typedef HintRequest = ({List<List<int>> tubes, int capacity});

/// Nombre max de positions explorées avant d'abandonner : borne le temps de
/// recherche sur un téléphone.
const int _maxExploredPositions = 200000;

/// Identifie une position exacte, ordre des tubes compris (les coups
/// désignent les tubes par leur rang).
String positionKey(List<List<int>> tubes) =>
    tubes.map((t) => t.join(',')).join('|');

/// Cherche une solution depuis la position donnée et associe à chaque position
/// traversée le coup à jouer. Les indices suivants relisent ce chemin : deux
/// recherches indépendantes pourraient se contredire (aller-retour).
///
/// Le résultat est vide si le niveau est déjà résolu, sans solution depuis
/// cette position, ou si la recherche dépasse sa limite.
Map<String, Move> findSolution(HintRequest request) {
  final state = GameState(tubes: request.tubes, capacity: request.capacity);
  final search = _Search(state);
  return search.solve() ? search.solution : <String, Move>{};
}

/// Recherche en profondeur avec les règles réelles du jeu.
class _Search {
  _Search(this.state);

  final GameState state;
  final Set<String> _visited = <String>{};

  /// Position -> coup menant à la victoire, rempli en remontant la recherche.
  final Map<String, Move> solution = <String, Move>{};

  bool solve() {
    if (state.isSolved) return true;
    if (_visited.length >= _maxExploredPositions) return false;
    if (!_visited.add(_equivalenceKey())) return false;
    for (final (from, to) in _candidateMoves()) {
      final move = state.pour(from, to)!;
      final solved = solve();
      state.undo();
      if (solved) {
        solution[positionKey(state.tubes)] = move;
        return true;
      }
    }
    return false;
  }

  /// L'ordre des tubes ne change rien à la solvabilité : on les trie pour ne
  /// pas explorer deux fois des positions équivalentes.
  String _equivalenceKey() =>
      (state.tubes.map((t) => t.join(',')).toList()..sort()).join('|');

  /// Coups utiles, les versements sur une même couleur avant ceux vers un tube
  /// vide (ils libèrent de la place au lieu d'en consommer).
  List<(int, int)> _candidateMoves() {
    final ontoColor = <(int, int)>[];
    final intoEmpty = <(int, int)>[];
    // Tous les tubes vides sont équivalents : un seul suffit.
    final firstEmpty = state.tubes.indexWhere((t) => t.isEmpty);
    for (var from = 0; from < state.tubes.length; from++) {
      if (state.isComplete(from)) continue;
      for (var to = 0; to < state.tubes.length; to++) {
        if (!state.canPour(from, to)) continue;
        if (state.tubes[to].isNotEmpty) {
          ontoColor.add((from, to));
        } else if (to == firstEmpty &&
            !GameState.isUniform(state.tubes[from])) {
          intoEmpty.add((from, to));
        }
      }
    }
    return <(int, int)>[...ontoColor, ...intoEmpty];
  }
}
