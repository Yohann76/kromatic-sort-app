import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../core/palette.dart';
import '../game/game_state.dart';
import '../game/hint_solver.dart';
import '../game/level_generator.dart';
import '../game/scoring.dart';
import '../services/app_prefs.dart';
import '../services/audio_service.dart';
import 'ambient_background.dart';
import 'board_controller.dart';
import 'board_layout.dart';
import 'board_painter.dart';
import 'win_overlay.dart';

/// Écran unique du jeu : on arrive directement dans le niveau en cours.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, required this.prefs, required this.audio});

  final AppPrefs prefs;
  final AudioService audio;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  /// Délai avant la carte de victoire, pour laisser voir le dernier tube.
  static const Duration _winDelay = Duration(milliseconds: 750);

  static const double _hintLineHeight = 22;

  static const LevelGenerator _generator = LevelGenerator();

  late int _level;
  late BoardController _board;
  bool _showWin = false;
  bool _showTutorial = false;
  bool _searchingHint = false;

  /// Points gagnés sur le niveau qui vient d'être résolu.
  int _wonPoints = 0;
  int _wonHintsUsed = 0;

  /// Coups déjà calculés pour le niveau courant (voir [findSolution]).
  final Map<String, Move> _knownMoves = <String, Move>{};
  late bool _musicOn = widget.audio.musicOn;
  late bool _sfxOn = widget.audio.sfxOn;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _level = widget.prefs.level;
    _board = _createBoard(_level);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _board.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      widget.audio.resumeMusic();
    } else if (state == AppLifecycleState.paused) {
      widget.audio.pauseMusic();
    }
  }

  // --- Niveaux ---------------------------------------------------------------

  BoardController _createBoard(int level) {
    _showTutorial = level == 1;
    final state = GameState(
      tubes: _generator.generate(level),
      capacity: LevelConfig.capacity,
    );
    return BoardController(vsync: this, state: state, onEvent: _onBoardEvent);
  }

  void _loadLevel(int level) {
    final old = _board;
    if (level != _level) _knownMoves.clear();
    setState(() {
      _level = level;
      _showWin = false;
      _board = _createBoard(level);
    });
    old.dispose();
  }

  void _restart() {
    widget.audio.play(Sfx.click);
    _loadLevel(_level);
  }

  void _nextLevel() {
    widget.audio.play(Sfx.click);
    _loadLevel(_level + 1);
  }

  // --- Événements du plateau (sons, vibrations, messages) ---------------------

  void _haptic(Future<void> Function() fn) {
    if (_sfxOn) fn();
  }

  void _onBoardEvent(BoardEvent event) {
    final audio = widget.audio;
    switch (event) {
      case BoardEvent.select:
        audio.play(Sfx.select);
        _haptic(HapticFeedback.selectionClick);
        if (_showTutorial) setState(() => _showTutorial = false);
      case BoardEvent.deselect:
      case BoardEvent.undo:
        audio.play(Sfx.deselect);
      case BoardEvent.addTube:
        audio.play(Sfx.select);
      case BoardEvent.pourStart:
        audio.play(Sfx.pour);
      case BoardEvent.pourEnd:
        _haptic(HapticFeedback.lightImpact);
      case BoardEvent.tubeDone:
        audio.play(Sfx.tubeDone);
        _haptic(HapticFeedback.mediumImpact);
      case BoardEvent.blocked:
        audio.play(Sfx.error);
      case BoardEvent.stuck:
        _showStuckMessage();
      case BoardEvent.win:
        audio.play(Sfx.win);
        _haptic(HapticFeedback.heavyImpact);
        _recordWin();
        Timer(_winDelay, () {
          if (mounted) setState(() => _showWin = true);
        });
    }
  }

  void _showStuckMessage() => _showMessage(
      'Plus de mouvement possible : annule un coup ou ajoute un tube.');

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // --- Score et indices ------------------------------------------------------

  /// Crédite les points et passe la sauvegarde au niveau suivant.
  void _recordWin() {
    final prefs = widget.prefs;
    setState(() {
      _wonHintsUsed = prefs.hintsUsed;
      _wonPoints = Difficulty.forLevel(_level).reward(_wonHintsUsed);
      prefs.score = prefs.score + _wonPoints;
      prefs.hintsUsed = 0;
      prefs.level = _level + 1;
    });
  }

  bool get _canRequestHint =>
      !_searchingHint &&
      _board.canShowHint &&
      widget.prefs.hintsUsed < kMaxHintsPerLevel;

  /// L'indice n'est décompté que s'il est réellement affiché.
  Future<void> _requestHint() async {
    if (!_canRequestHint) return;
    widget.audio.play(Sfx.click);
    final board = _board;
    final tubes = _copyTubes(board);
    final key = positionKey(tubes);
    setState(() => _searchingHint = true);
    try {
      if (!_knownMoves.containsKey(key)) {
        // Recherche hors du fil d'affichage pour ne pas figer l'écran.
        final solution = await compute(
            findSolution, (tubes: tubes, capacity: board.state.capacity));
        // Le joueur a pu jouer ou changer de niveau entre-temps.
        final isOutdated = !mounted ||
            board != _board ||
            !board.canShowHint ||
            !_hasSameTubes(board, tubes);
        if (isOutdated) return;
        for (final entry in solution.entries) {
          _knownMoves.putIfAbsent(entry.key, () => entry.value);
        }
      }
      final move = _knownMoves[key];
      if (move == null) {
        _showMessage(
            'Aucune solution trouvée d\'ici : annule des coups ou recommence. Indice non décompté.');
        return;
      }
      widget.prefs.hintsUsed = widget.prefs.hintsUsed + 1;
      board.showHint(move);
    } finally {
      if (mounted) setState(() => _searchingHint = false);
    }
  }

  List<List<int>> _copyTubes(BoardController board) =>
      <List<int>>[for (final tube in board.state.tubes) List<int>.of(tube)];

  bool _hasSameTubes(BoardController board, List<List<int>> tubes) {
    final current = board.state.tubes;
    if (current.length != tubes.length) return false;
    for (var i = 0; i < tubes.length; i++) {
      if (!listEquals(current[i], tubes[i])) return false;
    }
    return true;
  }

  // --- Réglages --------------------------------------------------------------

  void _toggleMusic() {
    setState(() => _musicOn = !_musicOn);
    widget.prefs.musicOn = _musicOn;
    widget.audio.setMusic(_musicOn);
  }

  void _toggleSfx() {
    setState(() => _sfxOn = !_sfxOn);
    widget.prefs.sfxOn = _sfxOn;
    widget.audio.setSfx(_sfxOn);
    widget.audio.play(Sfx.click);
  }

  // --- UI --------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bgBottom,
      body: Stack(
        children: [
          const Positioned.fill(child: AmbientBackground()),
          SafeArea(
            child: Column(
              children: [
                _buildTopBar(),
                _buildScorePanel(),
                Expanded(child: _buildBoard()),
                _buildBottomBar(),
                const SizedBox(height: 14),
              ],
            ),
          ),
          if (_showWin)
            Positioned.fill(
              child: WinOverlay(
                level: _level,
                moves: _board.state.moveCount,
                points: _wonPoints,
                hintsUsed: _wonHintsUsed,
                totalScore: widget.prefs.score,
                onNext: _nextLevel,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTopBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'NIVEAU $_level',
              style: const TextStyle(
                color: AppColors.text,
                fontSize: 22,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
          ),
          _RoundButton(
            icon: _musicOn ? Icons.music_note_rounded : Icons.music_off_rounded,
            tooltip: 'Musique',
            onTap: _toggleMusic,
            size: 42,
          ),
          const SizedBox(width: 10),
          _RoundButton(
            icon: _sfxOn ? Icons.volume_up_rounded : Icons.volume_off_rounded,
            tooltip: 'Sons',
            onTap: _toggleSfx,
            size: 42,
          ),
        ],
      ),
    );
  }

  /// Score total, gain possible sur ce niveau et coût d'un indice.
  Widget _buildScorePanel() {
    final difficulty = Difficulty.forLevel(_level);
    return ListenableBuilder(
      listenable: _board,
      builder: (context, _) {
        // Après la victoire, la sauvegarde pointe déjà sur le niveau suivant.
        final hintsUsed = _board.solved ? _wonHintsUsed : widget.prefs.hintsUsed;
        final hintsLeft = kMaxHintsPerLevel - hintsUsed;
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: _ScoreTile(
                      label: 'SCORE',
                      value: '${widget.prefs.score}',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ScoreTile(
                      label: 'À GAGNER · ${difficulty.label.toUpperCase()}',
                      value: '+${difficulty.reward(hintsUsed)}',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Hauteur fixe : le plateau ne bouge pas quand le texte change.
              SizedBox(
                height: _hintLineHeight,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: _board.hint != null
                        ? const Text(
                            'Indice : verse le tube 1 dans le tube 2.',
                            style: TextStyle(
                                color: AppColors.accent,
                                fontSize: 15,
                                fontWeight: FontWeight.w700),
                          )
                        : Text(
                            hintsLeft > 0
                                ? 'Indices restants : $hintsLeft/$kMaxHintsPerLevel · chacun coûte ${difficulty.hintCost} points'
                                : 'Plus d\'indice pour ce niveau',
                            style: const TextStyle(
                                color: AppColors.textDim, fontSize: 13),
                          ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBoard() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final geoms = BoardLayout.compute(
                size, _board.state.tubes.length, _board.state.capacity);
            final index = BoardLayout.hitTest(geoms, details.localPosition);
            if (index != null) _board.tap(index);
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(painter: BoardPainter(_board)),
              ),
              if (_showTutorial)
                const Positioned(
                  left: 24,
                  right: 24,
                  bottom: 6,
                  child: Text(
                    'Touche un tube, puis un autre pour verser.\nRegroupe chaque couleur dans un seul tube.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textDim, fontSize: 14, height: 1.4),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBottomBar() {
    return ListenableBuilder(
      listenable: _board,
      builder: (context, _) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _RoundButton(
            icon: Icons.undo_rounded,
            tooltip: 'Annuler',
            onTap: _board.canUndo ? _board.undo : null,
          ),
          const SizedBox(width: 22),
          _RoundButton(
            icon: Icons.refresh_rounded,
            tooltip: 'Recommencer',
            onTap: _restart,
          ),
          const SizedBox(width: 22),
          _RoundButton(
            icon: Icons.lightbulb_rounded,
            tooltip: 'Indice',
            onTap: _canRequestHint ? _requestHint : null,
            badge: widget.prefs.hintsUsed < kMaxHintsPerLevel
                ? '${kMaxHintsPerLevel - widget.prefs.hintsUsed}'
                : null,
          ),
          const SizedBox(width: 22),
          _RoundButton(
            icon: Icons.add_rounded,
            tooltip: 'Ajouter un tube',
            onTap: _board.canAddTube ? _board.addTube : null,
            badge: _board.state.extraTubeUsed ? null : '1',
          ),
        ],
      ),
    );
  }
}

/// Encadré affichant une valeur de score sous son intitulé.
class _ScoreTile extends StatelessWidget {
  const _ScoreTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.glass,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Text(label,
              style: const TextStyle(
                  color: AppColors.textDim, fontSize: 11, letterSpacing: 1)),
          Text(value,
              style: const TextStyle(
                  color: AppColors.accent, fontSize: 20, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

/// Bouton rond translucide, grisé quand [onTap] est null.
class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.badge,
    this.size = 56,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final String? badge;
  final double size;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Material(
            color: const Color(0x26FFFFFF),
            shape: const CircleBorder(side: BorderSide(color: Color(0x22FFFFFF))),
            child: InkResponse(
              onTap: onTap == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      onTap!();
                    },
              customBorder: const CircleBorder(),
              child: SizedBox(
                width: size,
                height: size,
                child: Icon(
                  icon,
                  size: size * 0.5,
                  color: enabled ? AppColors.text : AppColors.text.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
          if (badge != null)
            Positioned(
              right: -2,
              top: -2,
              child: Container(
                width: 20,
                height: 20,
                alignment: Alignment.center,
                decoration: const BoxDecoration(color: AppColors.accent, shape: BoxShape.circle),
                child: Text(badge!,
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.onAccent)),
              ),
            ),
        ],
      ),
    );
  }
}
