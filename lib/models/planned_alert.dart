import '../utils/formatting.dart';
import 'race.dart';

/// One notification we plan to show on the phone at [time].
class PlannedAlert {
  const PlannedAlert({
    required this.time,
    required this.title,
    required this.body,
    this.payload,
  });

  final DateTime time; // In UTC
  final String title;
  final String body;
  final String? payload; // Replay alerts: the session's start time
}

/// How early a session reminder arrives.
const Duration reminderLead = Duration(minutes: 15);

/// OpenF1 opens a session's data to everyone about 30 minutes after it
/// ends, so that is when a replay can be watched.
const Duration replayDelay = Duration(minutes: 30);

/// Roughly how long each kind of session lasts, so we know when it ends.
/// Races are given the full two hours they are allowed.
Duration sessionLength(String name) {
  return switch (name) {
    'Race' => const Duration(hours: 2),
    'Sprint Qualifying' || 'Sprint Shootout' => const Duration(minutes: 45),
    _ => const Duration(hours: 1), // Practice, qualifying and the sprint
  };
}

/// Every alert still to come for [races], soonest first, at most [limit].
///
/// An iPhone keeps at most 64 alerts waiting, so we plan the next [limit]
/// and plan again every time the app opens. [now] is there for the tests.
List<PlannedAlert> planAlerts(
  List<Race> races, {
  required DateTime now,
  required bool reminders,
  required bool replays,
  int limit = 40,
}) {
  final alerts = <PlannedAlert>[];
  for (final race in races) {
    for (final session in race.sessions) {
      final remindAt = session.start.subtract(reminderLead);
      if (reminders && remindAt.isAfter(now)) {
        alerts.add(
          PlannedAlert(
            time: remindAt,
            title: '${session.name} in 15 minutes',
            body: '${race.name}. Starts ${formatDayTime(session.start)}.',
          ),
        );
      }
      final readyAt =
          session.start.add(sessionLength(session.name)).add(replayDelay);
      if (replays && readyAt.isAfter(now)) {
        alerts.add(
          PlannedAlert(
            time: readyAt,
            title: '${session.name} replay is ready',
            body: 'Watch the ${race.name} ${session.name.toLowerCase()} '
                'on the tracker.',
            payload: session.start.toUtc().toIso8601String(),
          ),
        );
      }
    }
  }
  alerts.sort((a, b) => a.time.compareTo(b.time));
  return alerts.take(limit).toList();
}
