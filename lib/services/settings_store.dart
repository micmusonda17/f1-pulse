import 'package:shared_preferences/shared_preferences.dart';

import 'openf1_api.dart';

/// Saves small settings on the phone so they survive closing the app.
///
/// shared_preferences is a simple key-value store, like a Python dictionary
/// that is saved to disk.
class SettingsStore {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  static const String _favouriteKey = 'favourite_driver';
  static const String _teamKey = 'favourite_team';
  static const String _nameKey = 'user_name';
  static const String _welcomeDoneKey = 'welcome_done';
  static const String _usernameKey = 'openf1_username';
  static const String _passwordKey = 'openf1_password';

  /// True once the welcome pages have been finished (or skipped).
  Future<bool> isWelcomeDone() async {
    return (await _prefs.getBool(_welcomeDoneKey)) ?? false;
  }

  Future<void> setWelcomeDone(bool done) async {
    await _prefs.setBool(_welcomeDoneKey, done);
  }

  /// The name typed on the welcome page, like "Michael".
  Future<String?> getName() => _prefs.getString(_nameKey);

  Future<void> setName(String name) async {
    await _prefs.setString(_nameKey, name);
  }

  /// Your favourite team, as Jolpica names it, like "Ferrari".
  Future<String?> getFavouriteTeam() => _prefs.getString(_teamKey);

  Future<void> setFavouriteTeam(String? team) async {
    if (team == null) {
      await _prefs.remove(_teamKey);
    } else {
      await _prefs.setString(_teamKey, team);
    }
  }

  /// The driverId of your favourite driver, like "antonelli".
  Future<String?> getFavouriteDriver() => _prefs.getString(_favouriteKey);

  Future<void> setFavouriteDriver(String? driverId) async {
    if (driverId == null) {
      await _prefs.remove(_favouriteKey);
    } else {
      await _prefs.setString(_favouriteKey, driverId);
    }
  }

  /// An on or off setting, like data saver. Off until it is switched on.
  Future<bool> getFlag(String key) async {
    return (await _prefs.getBool(key)) ?? false;
  }

  Future<void> setFlag(String key, bool on) async {
    await _prefs.setBool(key, on);
  }

  /// Any saved text, by key. PhoneCache keeps copies of answers here.
  Future<String?> getText(String key) => _prefs.getString(key);

  Future<void> setText(String key, String value) async {
    await _prefs.setString(key, value);
  }

  Future<String?> getOpenF1Username() => _prefs.getString(_usernameKey);
  Future<String?> getOpenF1Password() => _prefs.getString(_passwordKey);

  Future<void> saveOpenF1Login(String username, String password) async {
    await _prefs.setString(_usernameKey, username);
    await _prefs.setString(_passwordKey, password);
  }

  Future<void> clearOpenF1Login() async {
    await _prefs.remove(_usernameKey);
    await _prefs.remove(_passwordKey);
  }
}

/// Signs in to OpenF1 with the login saved in Settings.
/// Returns false if no login has been saved yet.
Future<bool> signInWithSavedLogin() async {
  final api = OpenF1Api.instance;
  if (api.hasValidToken) return true;

  final store = SettingsStore();
  final username = await store.getOpenF1Username();
  final password = await store.getOpenF1Password();
  if (username == null || password == null || username.isEmpty) return false;

  await api.signIn(username, password);
  return true;
}
