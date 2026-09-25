import 'package:flutter/foundation.dart';

import 'jolpica_api.dart';
import 'settings_store.dart';

/// The switches in Settings that change how the whole app behaves: data
/// saver, spoiler-free mode, the race weekend alerts and saving replays.
///
/// Many screens need them, so there is one shared copy ([instance]). It is
/// a ChangeNotifier: flip a switch, and every screen listening redraws.
class AppPreferences extends ChangeNotifier {
  AppPreferences._();

  static final AppPreferences instance = AppPreferences._();

  static const String _dataSaverKey = 'data_saver';
  static const String _spoilerFreeKey = 'spoiler_free';
  static const String _remindersKey = 'session_reminders';
  static const String _replayAlertsKey = 'replay_alerts';
  // Saved replays are on unless switched off, so the key is the other way
  // round: a missing key means "off", which here means "save them".
  static const String _noSavedReplaysKey = 'no_saved_replays';

  // late: only made the first time it is used (loading or saving). Tests
  // that just read a switch never touch the phone's storage, which does
  // not exist in a test.
  late final SettingsStore _store = SettingsStore();

  bool dataSaver = false;
  bool spoilerFree = false;
  bool sessionReminders = false;
  bool replayAlerts = false;
  bool saveReplays = true; // Chapter 56

  // Spoilers you chose to see, like 'standings'. Only until the app closes,
  // so next time everything starts hidden again.
  final Set<String> _revealed = {};

  /// Reads the saved switches. Called once, when the app starts.
  Future<void> load() async {
    try {
      dataSaver = await _store.getFlag(_dataSaverKey);
      spoilerFree = await _store.getFlag(_spoilerFreeKey);
      sessionReminders = await _store.getFlag(_remindersKey);
      replayAlerts = await _store.getFlag(_replayAlertsKey);
      saveReplays = !await _store.getFlag(_noSavedReplaysKey);
    } catch (_) {
      // Could not read them: everything stays off.
    }
    _applyDataSaver();
    notifyListeners();
  }

  Future<void> setDataSaver(bool on) async {
    dataSaver = on;
    _applyDataSaver();
    notifyListeners();
    await _save(_dataSaverKey, on);
  }

  Future<void> setSpoilerFree(bool on) async {
    spoilerFree = on;
    notifyListeners();
    await _save(_spoilerFreeKey, on);
  }

  Future<void> setSessionReminders(bool on) async {
    sessionReminders = on;
    notifyListeners();
    await _save(_remindersKey, on);
  }

  Future<void> setReplayAlerts(bool on) async {
    replayAlerts = on;
    notifyListeners();
    await _save(_replayAlertsKey, on);
  }

  Future<void> setSaveReplays(bool on) async {
    saveReplays = on;
    notifyListeners();
    await _save(_noSavedReplaysKey, !on);
  }

  /// True if [topic] should be hidden: spoiler-free mode is on and you have
  /// not tapped Show for it since the app started.
  bool isHidden(String topic) => spoilerFree && !_revealed.contains(topic);

  void reveal(String topic) {
    _revealed.add(topic);
    notifyListeners();
  }

  /// Data saver reuses saved Jolpica answers for 30 minutes.
  void _applyDataSaver() {
    JolpicaApi.reuseCopiesFor =
        dataSaver ? const Duration(minutes: 30) : Duration.zero;
  }

  Future<void> _save(String key, bool on) async {
    try {
      await _store.setFlag(key, on);
    } catch (_) {
      // Not saved, but it still works until the app closes.
    }
  }
}
