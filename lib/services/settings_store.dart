import 'package:shared_preferences/shared_preferences.dart';

import 'openf1_api.dart';

/// Saves small settings on the phone so they survive closing the app.
///
/// shared_preferences is a simple key-value store, like a Python dictionary
/// that is saved to disk.
class SettingsStore {
  final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  /// The signed-in profile's id, set by ProfileStore. Everything personal
  /// (favourites, fantasy team, betting stats) is saved under a key that
  /// ends in it, so everyone on the phone keeps their own.
  static String? profileId;

  static const String _favouriteKey = 'favourite_driver';
  static const String _teamKey = 'favourite_team';
  static const String _fantasyDriversKey = 'fantasy_drivers';
  static const String _fantasyTeamsKey = 'fantasy_teams';
  static const String _bettingKey = 'betting_stats';
  static const String _usernameKey = 'openf1_username';
  static const String _passwordKey = 'openf1_password';

  /// "favourite_driver" becomes "favourite_driver_p1727254...".
  String _personal(String key) {
    final id = profileId;
    return id == null ? key : '${key}_$id';
  }

  /// Saves [value], or removes the key when [value] is null.
  Future<void> _setOrRemove(String key, String? value) async {
    if (value == null) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, value);
    }
  }

  /// Your favourite team, as Jolpica names it, like "Ferrari".
  Future<String?> getFavouriteTeam() => _prefs.getString(_personal(_teamKey));

  Future<void> setFavouriteTeam(String? team) =>
      _setOrRemove(_personal(_teamKey), team);

  /// The driverId of your favourite driver, like "antonelli".
  Future<String?> getFavouriteDriver() =>
      _prefs.getString(_personal(_favouriteKey));

  Future<void> setFavouriteDriver(String? driverId) =>
      _setOrRemove(_personal(_favouriteKey), driverId);

  /// Your fantasy team: driverIds and team names (Chapter 48).
  Future<List<String>> getFantasyDrivers() async =>
      _split(await _prefs.getString(_personal(_fantasyDriversKey)));

  Future<List<String>> getFantasyTeams() async =>
      _split(await _prefs.getString(_personal(_fantasyTeamsKey)));

  Future<void> setFantasyTeam(List<String> drivers, List<String> teams) async {
    await _prefs.setString(_personal(_fantasyDriversKey), drivers.join('|'));
    await _prefs.setString(_personal(_fantasyTeamsKey), teams.join('|'));
  }

  List<String> _split(String? text) =>
      text == null || text.isEmpty ? [] : text.split('|');

  /// Betting stats (Chapter 49), off until this profile says it is 18+.
  Future<bool> getBettingStats() async =>
      (await _prefs.getBool(_personal(_bettingKey))) ?? false;

  Future<void> setBettingStats(bool on) async {
    await _prefs.setBool(_personal(_bettingKey), on);
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
