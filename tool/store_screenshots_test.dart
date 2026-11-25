// Génère les visuels de la fiche Play Store dans store/ (captures et image de
// présentation), à partir du vrai rendu du jeu. Nécessite Python 3 et Pillow.
//
//   flutter test tool/store_screenshots_test.dart
//
// Ce script s'exécute comme un test, d'où l'usage des aides réservées aux tests.
// ignore_for_file: invalid_use_of_visible_for_testing_member
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kromatik_sort/core/palette.dart';
import 'package:kromatik_sort/game/game_state.dart';
import 'package:kromatik_sort/game/hint_solver.dart';
import 'package:kromatik_sort/game/level_generator.dart';
import 'package:kromatik_sort/main.dart';
import 'package:kromatik_sort/services/app_prefs.dart';
import 'package:kromatik_sort/services/audio_service.dart';
import 'package:kromatik_sort/ui/board_controller.dart';
import 'package:kromatik_sort/ui/board_painter.dart';
import 'package:kromatik_sort/ui/win_overlay.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _outputDir = 'store/screenshots';
const String _featureGraphicPath = 'store/feature_graphic.png';

/// Rendu 512 × 250 points à l'échelle 2 = 1024 × 500 pixels (format imposé).
const Size _featureCanvasSize = Size(512, 250);
const double _featurePixelRatio = 2;
const Size _featureBoardSize = Size(280, 240);

/// Tubes de l'image de présentation (couleurs du fond vers le haut) : le
/// premier se verse dans le deuxième.
const List<List<int>> _featureTubes = <List<int>>[
  <int>[5, 6, 0, 0],
  <int>[2, 0],
  <int>[4, 4, 4, 4],
  <int>[7, 3, 1],
  <int>[6, 2, 5, 3],
];

/// Images avancées après le début du versement, pour le saisir en plein flux.
const int _pourFrames = 8;

/// Rendu 360 × 640 points à l'échelle 3 = 1080 × 1920 pixels (format 9:16).
const Size _canvasSize = Size(360, 640);
const double _pixelRatio = 3;

/// Taille d'écran simulée pour le jeu, réduite ensuite dans le cadre.
const Size _phoneSize = Size(360, 700);

const Duration _frame = Duration(milliseconds: 50);

/// Images avancées après l'apparition de la carte de victoire (0,8 s).
const int _confettiFrames = 16;

/// Canaux du plugin audio, neutralisés (aucun son pendant la génération).
const List<String> _audioChannels = <String>[
  'xyz.luan/audioplayers',
  'xyz.luan/audioplayers.global',
  'xyz.luan/audioplayers.global/events',
  'xyz.luan/audioplayers/events/music',
];

/// Une capture : l'état du jeu à montrer et son accroche.
class _Shot {
  const _Shot({
    required this.file,
    required this.title,
    required this.subtitle,
    required this.level,
    required this.score,
    this.solvedShare = 0,
    this.selectTube = false,
    this.askHint = false,
    this.win = false,
  });

  final String file;
  final String title;
  final String subtitle;
  final int level;
  final int score;

  /// Part de la solution déjà jouée.
  final double solvedShare;
  final bool selectTube;
  final bool askHint;

  /// Montre la carte de victoire du niveau.
  final bool win;
}

const List<_Shot> _shots = <_Shot>[
  _Shot(
    file: '01_trie_les_couleurs',
    title: 'Trie les couleurs',
    subtitle: 'Une seule couleur par tube',
    level: 7,
    score: 640,
    solvedShare: 0.5,
    selectTube: true,
  ),
  _Shot(
    file: '02_facile_a_apprendre',
    title: 'Simple à apprendre',
    subtitle: 'Touche un tube, puis un autre',
    level: 1,
    score: 0,
  ),
  _Shot(
    file: '03_indices',
    title: 'Bloqué ?',
    subtitle: 'Jusqu\'à 2 indices par niveau',
    level: 11,
    score: 1480,
    askHint: true,
  ),
  _Shot(
    file: '04_score',
    title: 'Marque des points',
    subtitle: 'Plus c\'est difficile, plus ça rapporte',
    level: 9,
    score: 1040,
    win: true,
  ),
  _Shot(
    file: '05_defi',
    title: 'Relève le défi',
    subtitle: 'Jusqu\'à 10 couleurs en même temps',
    level: 24,
    score: 4860,
  ),
  _Shot(
    file: '06_niveaux_illimites',
    title: 'Niveaux illimités',
    subtitle: 'Joue partout, même hors ligne',
    level: 58,
    score: 14920,
    solvedShare: 0.75,
  ),
];

void main() {
  testWidgets('génère les captures Play Store', (tester) async {
    for (final channel in _audioChannels) {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(channel), (_) async => null);
    }
    await _prepareView(tester, _canvasSize);
    for (final shot in _shots) {
      await _capture(tester, shot);
    }

    debugDisableShadows = true;
    tester.view.reset();
  });

  testWidgets('génère l\'image de présentation', (tester) async {
    await _prepareView(tester, _featureCanvasSize);
    final board = BoardController(
      vsync: tester,
      state: GameState(tubes: _featureTubes, capacity: LevelConfig.capacity),
      onEvent: (_) {},
    );
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: boundary,
      child: _FeatureGraphic(board: board),
    ));
    await _settle(tester);
    board.tap(0);
    board.tap(1);
    for (var i = 0; i < _pourFrames; i++) {
      await tester.pump(_frame);
    }
    expect(board.pour, isNotNull);

    await _savePng(tester, boundary, _featureGraphicPath, _featurePixelRatio);

    await tester.pumpWidget(const SizedBox());
    board.dispose();
    debugDisableShadows = true;
    tester.view.reset();
  });
}

/// Fixe la taille de rendu, charge les polices et active les vraies ombres.
Future<void> _prepareView(WidgetTester tester, Size size) async {
  await tester.runAsync(_loadFonts);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  // Les tests remplacent les ombres par des aplats : on rétablit le rendu réel.
  debugDisableShadows = false;
}

/// Enregistre le contenu de [boundary] en PNG sans transparence.
Future<void> _savePng(WidgetTester tester, GlobalKey boundary, String path,
    double pixelRatio) async {
  await tester.runAsync(() async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: pixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsBytes(png!.buffer.asUint8List());
    await _removeAlpha(path);
  });
}

/// Charge les polices du SDK : sans elles, les tests dessinent des carrés.
Future<void> _loadFonts() async {
  final dir =
      '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts';
  Future<ByteData> read(String file) async =>
      ByteData.sublistView(await File('$dir/$file').readAsBytes());
  final roboto = FontLoader('Roboto');
  for (final weight in <String>['Regular', 'Medium', 'Bold', 'Black']) {
    roboto.addFont(read('Roboto-$weight.ttf'));
  }
  await roboto.load();
  await (FontLoader('MaterialIcons')
        ..addFont(read('MaterialIcons-Regular.otf')))
      .load();
}

Future<void> _capture(WidgetTester tester, _Shot shot) async {
  SharedPreferences.setMockInitialValues(<String, Object>{
    'level': shot.level,
    'score': shot.score,
  });
  // L'instance est mise en cache par le plugin : on la vide entre deux captures.
  SharedPreferences.resetStatic();
  final prefs = (await tester.runAsync(AppPrefs.load))!;
  final boundary = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: boundary,
    child: _StoreFrame(
      key: UniqueKey(),
      shot: shot,
      app: KromatikSortApp(
        prefs: prefs,
        audio: AudioService(musicOn: true, sfxOn: true),
      ),
    ),
  ));
  await _settle(tester);

  final board = _boardOf(tester);
  if (shot.solvedShare > 0) await _playSolution(tester, board, shot.solvedShare);
  if (shot.win) await _winLevel(tester, board);
  if (shot.selectTube) {
    final next = findSolution(
        (tubes: board.state.tubes, capacity: board.state.capacity));
    board.tap(next[positionKey(board.state.tubes)]!.from);
    await _settle(tester);
  }
  if (shot.askHint) {
    await tester.tap(find.byTooltip('Indice'));
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 2)));
    await _settle(tester);
    expect(board.hint, isNotNull);
  }

  await _savePng(
      tester, boundary, '$_outputDir/${shot.file}.png', _pixelRatio);
  await tester.pumpWidget(const SizedBox());
}

/// La Play Console refuse la transparence : conversion en PNG 24 bits.
Future<void> _removeAlpha(String path) async {
  final result = await Process.run('python3', <String>[
    '-c',
    'import sys; from PIL import Image; '
        'Image.open(sys.argv[1]).convert("RGB").save(sys.argv[1], optimize=True)',
    path,
  ]);
  if (result.exitCode != 0) {
    throw ProcessException('python3', <String>[path], '${result.stderr}');
  }
}

BoardController _boardOf(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .map((paint) => paint.painter)
    .whereType<BoardPainter>()
    .single
    .board;

/// Avance les animations (le jeu tourne en continu : pumpAndSettle bouclerait).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 30; i++) {
    await tester.pump(_frame);
  }
}

Future<void> _playSolution(
    WidgetTester tester, BoardController board, double share) async {
  final solution = findSolution(
      (tubes: board.state.tubes, capacity: board.state.capacity));
  expect(solution, isNotEmpty);
  final moveCount = (solution.length * share).round();
  for (var i = 0; i < moveCount; i++) {
    final move = solution[positionKey(board.state.tubes)]!;
    board.tap(move.from);
    board.tap(move.to);
    await _settle(tester);
  }
}

/// Résout le niveau puis s'arrête quand la carte de victoire est bien en place
/// et les confettis encore à l'écran.
Future<void> _winLevel(WidgetTester tester, BoardController board) async {
  final solution = findSolution(
      (tubes: board.state.tubes, capacity: board.state.capacity));
  expect(solution, isNotEmpty);
  while (!board.solved) {
    final move = solution[positionKey(board.state.tubes)]!;
    board.tap(move.from);
    board.tap(move.to);
    // Pas à pas, pour ne pas dépasser l'apparition de la carte.
    while (board.pour != null) {
      await tester.pump(_frame);
    }
  }
  while (find.byType(WinOverlay).evaluate().isEmpty) {
    await tester.pump(_frame);
  }
  for (var i = 0; i < _confettiFrames; i++) {
    await tester.pump(_frame);
  }
}

const LinearGradient _storeBackground = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: <Color>[Color(0xFF5B3FC4), AppColors.bgTop, AppColors.bgBottom],
);

/// Image de présentation : nom du jeu à gauche, versement en cours à droite.
class _FeatureGraphic extends StatelessWidget {
  const _FeatureGraphic({required this.board});

  final BoardController board;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'Roboto', height: 1.05),
        child: DecoratedBox(
          decoration: const BoxDecoration(gradient: _storeBackground),
          child: Padding(
            padding: const EdgeInsets.only(left: 36, right: 16),
            child: Row(
              children: <Widget>[
                const Expanded(child: _FeatureTitle()),
                CustomPaint(
                  size: _featureBoardSize,
                  painter: BoardPainter(board),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureTitle extends StatelessWidget {
  const _FeatureTitle();

  @override
  Widget build(BuildContext context) {
    const title = TextStyle(fontSize: 40, fontWeight: FontWeight.w900);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Kromatik', style: title.copyWith(color: AppColors.text)),
        Text('Sort', style: title.copyWith(color: AppColors.accent)),
        const SizedBox(height: 12),
        const Text('Trie les couleurs',
            style: TextStyle(
                color: AppColors.text,
                fontSize: 18,
                fontWeight: FontWeight.w500)),
      ],
    );
  }
}

/// Habillage d'une capture : accroche en haut, écran du jeu encadré dessous.
class _StoreFrame extends StatelessWidget {
  const _StoreFrame({super.key, required this.shot, required this.app});

  final _Shot shot;
  final Widget app;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.ltr,
      child: DefaultTextStyle(
        style: const TextStyle(fontFamily: 'Roboto'),
        child: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: _storeBackground,
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 22),
            child: Column(
              children: <Widget>[
                _headline(shot.title, 32, FontWeight.w900, AppColors.accent),
                const SizedBox(height: 6),
                _headline(shot.subtitle, 17, FontWeight.w500, AppColors.text),
                const SizedBox(height: 20),
                Expanded(child: FittedBox(child: _phone())),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _headline(String text, double size, FontWeight weight, Color color) {
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(text,
          style: TextStyle(fontSize: size, fontWeight: weight, color: color)),
    );
  }

  Widget _phone() {
    return Container(
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: const Color(0xFF05040F),
        borderRadius: BorderRadius.circular(44),
        border: Border.all(color: const Color(0x66FFFFFF), width: 2),
        boxShadow: const <BoxShadow>[
          BoxShadow(color: Color(0x99000000), blurRadius: 34, offset: Offset(0, 14)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: SizedBox.fromSize(
          size: _phoneSize,
          // L'app reprend la taille de la vue : on la recale sur le téléphone.
          child: MediaQuery(
            data: const MediaQueryData(size: _phoneSize),
            child: app,
          ),
        ),
      ),
    );
  }
}
