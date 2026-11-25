/// Un versement effectué : sert à l'annulation.
class Move {
  const Move({required this.from, required this.to, required this.count});

  final int from;
  final int to;

  /// Nombre d'unités de liquide déplacées.
  final int count;
}

/// Règles du jeu, sans aucune dépendance à Flutter.
///
/// Chaque tube est une liste d'ids de couleur, du fond (index 0) vers le haut.
class GameState {
  GameState({required List<List<int>> tubes, required this.capacity})
      : tubes = <List<int>>[for (final t in tubes) List<int>.of(t)];

  final int capacity;
  final List<List<int>> tubes;
  final List<Move> _history = <Move>[];

  /// Le tube bonus ne peut être ajouté qu'une fois par niveau.
  bool extraTubeUsed = false;

  int get moveCount => _history.length;
  bool get canUndo => _history.isNotEmpty;

  /// Taille du groupe de même couleur tout en haut du tube.
  static int topRun(List<int> tube) {
    if (tube.isEmpty) return 0;
    var run = 1;
    while (run < tube.length && tube[tube.length - 1 - run] == tube.last) {
      run++;
    }
    return run;
  }

  static bool isUniform(List<int> tube) => topRun(tube) == tube.length;

  /// Tube plein et d'une seule couleur : il est terminé.
  bool isComplete(int index) {
    final tube = tubes[index];
    return tube.length == capacity && isUniform(tube);
  }

  bool get isSolved =>
      tubes.every((t) => t.isEmpty || (t.length == capacity && isUniform(t)));

  bool canPour(int from, int to) {
    if (from == to) return false;
    final src = tubes[from];
    final dst = tubes[to];
    if (src.isEmpty || dst.length >= capacity) return false;
    return dst.isEmpty || dst.last == src.last;
  }

  /// Nombre d'unités qui seraient réellement versées.
  int pourAmount(int from, int to) {
    final free = capacity - tubes[to].length;
    final run = topRun(tubes[from]);
    return run < free ? run : free;
  }

  /// Verse le groupe supérieur de [from] dans [to]. Renvoie null si illégal.
  Move? pour(int from, int to) {
    if (!canPour(from, to)) return null;
    final count = pourAmount(from, to);
    final color = tubes[from].last;
    for (var i = 0; i < count; i++) {
      tubes[from].removeLast();
      tubes[to].add(color);
    }
    final move = Move(from: from, to: to, count: count);
    _history.add(move);
    return move;
  }

  /// Annule le dernier versement. Renvoie ce qui a été annulé, ou null.
  Move? undo() {
    if (_history.isEmpty) return null;
    final move = _history.removeLast();
    final color = tubes[move.to].last;
    for (var i = 0; i < move.count; i++) {
      tubes[move.to].removeLast();
      tubes[move.from].add(color);
    }
    return move;
  }

  /// Ajoute un tube vide (bonus, une fois par niveau). Renvoie false si déjà utilisé.
  bool addTube() {
    if (extraTubeUsed) return false;
    tubes.add(<int>[]);
    extraTubeUsed = true;
    return true;
  }

  /// Existe-t-il encore un versement utile ? (verser un tube déjà uniforme
  /// dans un tube vide ne fait pas avancer la partie)
  bool get hasUsefulMove {
    for (var from = 0; from < tubes.length; from++) {
      for (var to = 0; to < tubes.length; to++) {
        if (!canPour(from, to)) continue;
        final pointless = tubes[to].isEmpty && isUniform(tubes[from]);
        if (!pointless) return true;
      }
    }
    return false;
  }
}
