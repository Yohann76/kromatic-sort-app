import 'package:shared_preferences/shared_preferences.dart';

/// Sauvegarde locale : progression, score et réglages audio. Aucune base de données.
class AppPrefs {
  AppPrefs._(this._prefs);

  static const String _levelKey = 'level';
  static const String _musicKey = 'music_on';
  static const String _sfxKey = 'sfx_on';
  static const String _scoreKey = 'score';
  static const String _hintsUsedKey = 'hints_used';

  final SharedPreferences _prefs;

  static Future<AppPrefs> load() async =>
      AppPrefs._(await SharedPreferences.getInstance());

  int get level => _prefs.getInt(_levelKey) ?? 1;
  set level(int value) => _prefs.setInt(_levelKey, value);

  /// Total des points gagnés.
  int get score => _prefs.getInt(_scoreKey) ?? 0;
  set score(int value) => _prefs.setInt(_scoreKey, value);

  /// Indices déjà utilisés sur le niveau courant (conservés si on recommence).
  int get hintsUsed => _prefs.getInt(_hintsUsedKey) ?? 0;
  set hintsUsed(int value) => _prefs.setInt(_hintsUsedKey, value);

  bool get musicOn => _prefs.getBool(_musicKey) ?? true;
  set musicOn(bool value) => _prefs.setBool(_musicKey, value);

  bool get sfxOn => _prefs.getBool(_sfxKey) ?? true;
  set sfxOn(bool value) => _prefs.setBool(_sfxKey, value);
}
