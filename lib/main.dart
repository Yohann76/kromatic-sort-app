import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';

import 'core/palette.dart';
import 'services/app_prefs.dart';
import 'services/audio_service.dart';
import 'ui/game_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations(
    const [DeviceOrientation.portraitUp],
  );
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: AppColors.bgBottom,
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final prefs = await AppPrefs.load();
  final audio = AudioService(musicOn: prefs.musicOn, sfxOn: prefs.sfxOn);
  // Le son s'initialise en parallèle : on n'attend pas pour afficher le jeu.
  unawaited(audio.init());

  runApp(KromatikSortApp(prefs: prefs, audio: audio));
}

class KromatikSortApp extends StatelessWidget {
  const KromatikSortApp({super.key, required this.prefs, required this.audio});

  final AppPrefs prefs;
  final AudioService audio;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kromatik Sort',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.dark,
        ),
      ),
      home: GameScreen(prefs: prefs, audio: audio),
    );
  }
}
