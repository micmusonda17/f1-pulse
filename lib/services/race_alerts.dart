import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../models/planned_alert.dart';
import '../models/race.dart';
import 'app_preferences.dart';
import 'jolpica_api.dart';

/// Session reminders and "replay ready" alerts, as notifications the
/// phone shows by itself at the right time, even with Pitbeat closed.
///
/// Nothing is sent from a server: the app hands the phone a list of times,
/// and iOS does the rest. That is why it costs nothing to run.
class RaceAlerts {
  RaceAlerts._();

  static final RaceAlerts instance = RaceAlerts._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;
  List<Race> _races = []; // The calendar, once the Races tab has loaded it

  /// Only the iPhone app. A website cannot wake up when it is closed.
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  /// Sets the plugin up. [onTap] runs when you tap an alert while the app
  /// is open, with the alert's payload.
  Future<void> init({required void Function(String? payload) onTap}) async {
    if (!supported || _ready) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          // Do not ask for permission yet: we ask when you switch alerts on.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        ),
        onDidReceiveNotificationResponse: (response) => onTap(response.payload),
      );
      _ready = true;
    } catch (_) {
      // No alerts on this phone. Everything else still works.
    }
  }

  /// Asks iOS to allow notifications. It only asks you the first time;
  /// after that it just answers with what you chose.
  Future<bool> askPermission() async {
    if (!_ready) return false;
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final allowed = await ios?.requestPermissions(alert: true, sound: true);
    return allowed ?? false;
  }

  /// The payload of the alert you tapped to open the app, if you did.
  Future<String?> launchPayload() async {
    if (!_ready) return null;
    final details = await _plugin.getNotificationAppLaunchDetails();
    if (details == null || !details.didNotificationLaunchApp) return null;
    return details.notificationResponse?.payload;
  }

  /// Clears every planned alert and plans them again from the calendar and
  /// the switches in Settings. [races] is the calendar, when you have it.
  Future<void> refresh({List<Race>? races}) async {
    if (!_ready) return;
    if (races != null) _races = races;
    final preferences = AppPreferences.instance;
    try {
      await _plugin.cancelAll();
      if (!preferences.sessionReminders && !preferences.replayAlerts) return;
      if (_races.isEmpty) _races = await JolpicaApi().getSchedule();

      final plan = planAlerts(
        _races,
        now: DateTime.now(),
        reminders: preferences.sessionReminders,
        replays: preferences.replayAlerts,
      );
      for (var i = 0; i < plan.length; i++) {
        final alert = plan[i];
        await _plugin.zonedSchedule(
          id: i + 1,
          title: alert.title,
          body: alert.body,
          // A moment in UTC is the same moment everywhere, so the phone
          // shows it at the right local time on its own.
          scheduledDate: tz.TZDateTime.from(alert.time, tz.UTC),
          notificationDetails: const NotificationDetails(
            iOS: DarwinNotificationDetails(),
            android: AndroidNotificationDetails('race_alerts', 'Race alerts'),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: alert.payload,
        );
      }
    } catch (_) {
      // Alerts are a nice extra. If planning fails, the app carries on.
    }
  }
}
