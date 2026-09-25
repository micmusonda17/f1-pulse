import 'jolpica_api.dart';
import 'settings_store.dart';

/// Saves copies of Jolpica's answers on the phone, with shared_preferences.
///
/// This is the other half of ResponseCache in jolpica_api.dart: that file
/// says what a cache can do, this one does it. `implements` promises Dart
/// that this class has every method ResponseCache lists.
class PhoneCache implements ResponseCache {
  final SettingsStore _store = SettingsStore();

  @override
  Future<String?> read(String key) => _store.getText(key);

  @override
  Future<void> write(String key, String value) => _store.setText(key, value);
}
