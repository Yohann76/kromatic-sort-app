import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Effets sonores du jeu (fichiers dans assets/audio).
enum Sfx {
  select('select.wav'),
  deselect('deselect.wav'),
  pour('pour.wav'),
  tubeDone('tube_done.wav'),
  win('win.wav'),
  error('error.wav'),
  click('click.wav');

  const Sfx(this.file);
  final String file;
}

/// Musique d'ambiance en boucle + effets à faible latence.
/// Toute erreur audio est avalée : le son ne doit jamais faire planter le jeu.
class AudioService {
  AudioService({required this.musicOn, required this.sfxOn});

  /// Volume de la musique (discret, sous les effets).
  static const double _musicVolume = 0.32;
  static const String _musicFile = 'audio/music.ogg';

  bool musicOn;
  bool sfxOn;

  final AudioPlayer _music = AudioPlayer(playerId: 'music');
  final Map<Sfx, AudioPlayer> _sfx = <Sfx, AudioPlayer>{};

  Future<void> init() async {
    try {
      // Ne coupe pas la musique/le podcast de l'utilisateur.
      await AudioPlayer.global.setAudioContext(
        AudioContextConfig(focus: AudioContextConfigFocus.mixWithOthers).build(),
      );
      for (final sfx in Sfx.values) {
        final player = AudioPlayer(playerId: 'sfx_${sfx.name}');
        await player.setPlayerMode(PlayerMode.lowLatency);
        await player.setReleaseMode(ReleaseMode.stop);
        _sfx[sfx] = player;
      }
      await _music.setReleaseMode(ReleaseMode.loop);
      await _music.setVolume(_musicVolume);
      if (musicOn) await _playMusic();
    } catch (e) {
      debugPrint('Audio init: $e');
    }
  }

  Future<void> _playMusic() => _music.play(AssetSource(_musicFile));

  void play(Sfx sfx) {
    if (!sfxOn) return;
    _sfx[sfx]?.play(AssetSource('audio/${sfx.file}')).catchError((Object e) {
      debugPrint('Sfx ${sfx.name}: $e');
    });
  }

  Future<void> setMusic(bool on) async {
    musicOn = on;
    try {
      if (on) {
        await _playMusic();
      } else {
        await _music.pause();
      }
    } catch (e) {
      debugPrint('Music toggle: $e');
    }
  }

  void setSfx(bool on) => sfxOn = on;

  /// À appeler quand l'app passe en arrière-plan.
  Future<void> pauseMusic() async {
    try {
      await _music.pause();
    } catch (_) {}
  }

  /// À appeler au retour au premier plan.
  Future<void> resumeMusic() async {
    if (!musicOn) return;
    try {
      await _playMusic();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await _music.dispose();
    for (final p in _sfx.values) {
      await p.dispose();
    }
  }
}
