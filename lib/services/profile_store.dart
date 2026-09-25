import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/profile.dart';
import 'settings_store.dart';

/// Everyone who uses Pitbeat on this phone, and who is signed in now.
///
/// There are no passwords and no server: a profile is a name and a colour,
/// kept on the phone, like "Who's watching?" on a streaming app. It is a
/// ChangeNotifier, so the first screen (StartGate) redraws on its own when
/// someone signs in, signs out or adds a profile.
class ProfileStore extends ChangeNotifier {
  ProfileStore._();

  static final ProfileStore instance = ProfileStore._();

  static const String _profilesKey = 'profiles';
  static const String _currentKey = 'current_profile';

  // late: made on first use, so tests that never save need no phone.
  late final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  List<Profile> profiles = [];
  String? currentId; // Null when nobody is signed in
  bool isLoaded = false;

  /// The signed-in profile, or null.
  Profile? get current {
    for (final profile in profiles) {
      if (profile.id == currentId) return profile;
    }
    return null;
  }

  /// Reads the profiles once, when the app starts.
  Future<void> load() async {
    try {
      profiles = decodeProfiles(await _prefs.getString(_profilesKey));
      currentId = await _prefs.getString(_currentKey);
      if (profiles.isEmpty) await _moveOldSettings();
    } catch (_) {
      // Could not read them: start with nobody, like a new phone.
    }
    SettingsStore.profileId = current?.id;
    isLoaded = true;
    notifyListeners();
  }

  /// Adds a profile with its favourites, and signs it in.
  Future<Profile> add({
    required String name,
    String? favouriteDriver,
    String? favouriteTeam,
  }) async {
    final profile = Profile(
      id: 'p${DateTime.now().microsecondsSinceEpoch}',
      name: name.trim().isEmpty ? 'Player ${profiles.length + 1}' : name.trim(),
      colourIndex: profiles.length,
    );
    profiles = [...profiles, profile];
    await _saveProfiles();

    // Save the favourites under the new id before anyone can see them.
    SettingsStore.profileId = profile.id;
    final settings = SettingsStore();
    await settings.setFavouriteDriver(favouriteDriver);
    await settings.setFavouriteTeam(favouriteTeam);

    await signIn(profile.id);
    return profile;
  }

  Future<void> signIn(String id) async {
    currentId = id;
    SettingsStore.profileId = id;
    notifyListeners();
    await _save(_currentKey, id);
  }

  /// Back to "Who's watching?". The profile itself stays on the phone.
  Future<void> signOut() async {
    currentId = null;
    SettingsStore.profileId = null;
    notifyListeners();
    try {
      await _prefs.remove(_currentKey);
    } catch (_) {
      // Not saved: this profile may be signed in again next time.
    }
  }

  Future<void> rename(String id, String name) async {
    profiles = [
      for (final profile in profiles)
        profile.id == id ? profile.copyWith(name: name.trim()) : profile,
    ];
    notifyListeners();
    await _saveProfiles();
  }

  /// Removes a profile for good. Signs it out first if it is signed in.
  Future<void> delete(String id) async {
    if (currentId == id) await signOut();
    profiles = profiles.where((profile) => profile.id != id).toList();
    notifyListeners();
    await _saveProfiles();
  }

  /// Before profiles, Pitbeat saved one name and one set of favourites.
  /// Anyone updating keeps them, as their first profile.
  Future<void> _moveOldSettings() async {
    final oldName = await _prefs.getString('user_name');
    final welcomeDone = (await _prefs.getBool('welcome_done')) ?? false;
    if (oldName == null && !welcomeDone) return; // A brand new phone

    final profile = Profile(
      id: 'p1',
      name: (oldName ?? '').trim().isEmpty ? 'Me' : oldName!.trim(),
      colourIndex: 0,
    );
    profiles = [profile];
    await _saveProfiles();

    SettingsStore.profileId = profile.id;
    final settings = SettingsStore();
    await settings.setFavouriteDriver(
      await _prefs.getString('favourite_driver'),
    );
    await settings.setFavouriteTeam(await _prefs.getString('favourite_team'));
    currentId = profile.id;
    await _save(_currentKey, profile.id);
  }

  Future<void> _saveProfiles() => _save(_profilesKey, encodeProfiles(profiles));

  Future<void> _save(String key, String value) async {
    try {
      await _prefs.setString(key, value);
    } catch (_) {
      // Not saved, but it still works until the app closes.
    }
  }
}
