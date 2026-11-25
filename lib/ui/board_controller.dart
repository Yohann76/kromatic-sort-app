import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../game/game_state.dart';

/// Événements émis vers l'UI (sons, vibrations, messages, victoire).
enum BoardEvent {
  select,
  deselect,
  pourStart,
  pourEnd,
  tubeDone,
  win,
  stuck,
  undo,
  addTube,
  blocked,
}

/// Animation d'un versement : le tube source se penche au-dessus du tube cible.
class PourAnim {
  PourAnim({
    required this.from,
    required this.to,
    required this.count,
    required this.color,
    required this.startLift,
  }) : pourDuration = _pourBase + _pourPerUnit * count;

  static const double inDuration = 0.22;
  static const double outDuration = 0.2;
  static const double _pourBase = 0.18;
  static const double _pourPerUnit = 0.12;

  final int from;
  final int to;
  final int count;
  final int color;

  /// Hauteur de levée du tube source quand le versement démarre (0..1).
  final double startLift;
  final double pourDuration;

  /// Temps écoulé en secondes.
  double t = 0;

  double get total => inDuration + pourDuration + outDuration;
  double get inProgress => (t / inDuration).clamp(0.0, 1.0);
  double get pourProgress => ((t - inDuration) / pourDuration).clamp(0.0, 1.0);
  double get outProgress =>
      ((t - inDuration - pourDuration) / outDuration).clamp(0.0, 1.0);
}

/// État visuel du plateau : sélection, animations, interactions.
/// Repeint le plateau à chaque image via [ChangeNotifier].
class BoardController extends ChangeNotifier {
  BoardController({
    required TickerProvider vsync,
    required this.state,
    required this.onEvent,
  }) {
    _syncArrays();
    _ticker = vsync.createTicker(_onTick)..start();
  }

  /// Vitesse de retour de la levée / de la décroissance de l'oscillation.
  static const double _liftSpeed = 16;
  static const double _wobbleDecay = 2.2;

  /// Les touches sont ignorées juste après l'arrivée des tubes.
  static const double _introLockSeconds = 0.35;

  final GameState state;
  final void Function(BoardEvent event) onEvent;

  late final Ticker _ticker;
  Duration _last = Duration.zero;

  /// Temps global (s), pour les vagues et l'ambiance.
  double time = 0;

  /// Temps depuis l'affichage du niveau (animation d'entrée des tubes).
  double introTime = 0;

  int? selected;
  PourAnim? pour;

  /// Coup conseillé à mettre en évidence, jusqu'au prochain changement.
  Move? hint;
  bool solved = false;
  final List<double> lift = <double>[];
  final List<double> wobble = <double>[];
  final Map<int, double> doneAt = <int, double>{};

  bool get _locked => pour != null || solved || introTime < _introLockSeconds;

  void _syncArrays() {
    while (lift.length < state.tubes.length) {
      lift.add(0);
      wobble.add(0);
    }
  }

  void _onTick(Duration elapsed) {
    final dt = min(0.05, (elapsed - _last).inMicroseconds / 1e6);
    _last = elapsed;
    time += dt;
    introTime += dt;

    final liftEase = 1 - exp(-dt * _liftSpeed);
    final wobbleKeep = exp(-dt * _wobbleDecay);
    for (var i = 0; i < lift.length; i++) {
      lift[i] += ((i == selected ? 1.0 : 0.0) - lift[i]) * liftEase;
      wobble[i] *= wobbleKeep;
    }

    final anim = pour;
    if (anim != null) {
      anim.t += dt;
      if (anim.t >= anim.total) _finishPour(anim);
    }
    notifyListeners();
  }

  /// Touche sur le tube [index].
  void tap(int index) {
    if (_locked || index < 0 || index >= state.tubes.length) return;
    final from = selected;
    if (from == null) {
      _trySelect(index);
    } else if (from == index) {
      selected = null;
      wobble[index] = 0.5;
      onEvent(BoardEvent.deselect);
    } else if (state.canPour(from, index)) {
      _startPour(from, index);
    } else {
      // Versement impossible : on bascule la sélection sur le tube touché.
      selected = null;
      _trySelect(index);
    }
  }

  void _trySelect(int index) {
    if (state.tubes[index].isEmpty || state.isComplete(index)) {
      wobble[index] = 0.6;
      onEvent(BoardEvent.blocked);
      return;
    }
    selected = index;
    wobble[index] = 1;
    onEvent(BoardEvent.select);
  }

  void _startPour(int from, int to) {
    pour = PourAnim(
      from: from,
      to: to,
      count: state.pourAmount(from, to),
      color: state.tubes[from].last,
      startLift: lift[from],
    );
    selected = null;
    hint = null;
    onEvent(BoardEvent.pourStart);
  }

  void _finishPour(PourAnim anim) {
    state.pour(anim.from, anim.to);
    pour = null;
    wobble[anim.to] = 1;
    wobble[anim.from] = 0.6;
    onEvent(BoardEvent.pourEnd);

    if (state.isComplete(anim.to)) {
      doneAt[anim.to] = time;
      onEvent(BoardEvent.tubeDone);
    }
    if (state.isSolved) {
      solved = true;
      selected = null;
      onEvent(BoardEvent.win);
    } else if (!state.hasUsefulMove) {
      onEvent(BoardEvent.stuck);
    }
  }

  bool get canUndo => !_locked && state.canUndo;

  void undo() {
    if (!canUndo) return;
    final move = state.undo();
    if (move == null) return;
    selected = null;
    hint = null;
    doneAt.remove(move.to);
    wobble[move.from] = 1;
    wobble[move.to] = 1;
    onEvent(BoardEvent.undo);
  }

  bool get canAddTube => !_locked && !state.extraTubeUsed;

  void addTube() {
    if (!canAddTube || !state.addTube()) return;
    _syncArrays();
    hint = null;
    wobble[state.tubes.length - 1] = 1;
    onEvent(BoardEvent.addTube);
  }

  bool get canShowHint => !_locked && hint == null;

  /// Met en évidence [move] ; la sélection en cours est abandonnée.
  void showHint(Move move) {
    selected = null;
    hint = move;
    wobble[move.from] = 1;
    wobble[move.to] = 1;
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }
}
