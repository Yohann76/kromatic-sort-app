import 'package:shared_preferences/shared_preferences.dart';

/// Sauvegarde locale : niveau courant et réglages audio. Aucune base de données.
class AppPrefs {
  AppPrefs._(this._prefs);

  static const String _levelKey = 'level';
  static const String _musicKey = 'music_on';
  static const String _sfxKey = 'sfx_on';

  final SharedPreferences _prefs;

  static Future<AppPrefs> load() async =>
      AppPrefs._(await SharedPreferences.getInstance());

  int get level => _prefs.getInt(_levelKey) ?? 1;
  set level(int value) => _prefs.setInt(_levelKey, value);

  bool get musicOn => _prefs.getBool(_musicKey) ?? true;
  set musicOn(bool value) => _prefs.setBool(_musicKey, value);

  bool get sfxOn => _prefs.getBool(_sfxKey) ?? true;
  set sfxOn(bool value) => _prefs.setBool(_sfxKey, value);
}
