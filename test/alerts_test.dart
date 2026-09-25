import 'package:flutter_test/flutter_test.dart';
import 'package:pitbeat/models/planned_alert.dart';
import 'package:pitbeat/models/race.dart';

// A made-up weekend: Practice 1 on Friday at 10:00 UTC, the race on Sunday
// at 13:00 UTC.
final practice = WeekendSession(
  name: 'Practice 1',
  start: DateTime.utc(2026, 9, 25, 10),
);
final race = WeekendSession(name: 'Race', start: DateTime.utc(2026, 9, 27, 13));

final weekend = Race(
  season: 2026,
  round: 17,
  name: 'Test Grand Prix',
  circuitId: 'baku',
  circuitName: 'Test Circuit',
  locality: 'Baku',
  country: 'Azerbaijan',
  start: race.start,
  sessions: [practice, race],
);

void main() {
  test('reminders come 15 minutes before each session', () {
    final plan = planAlerts(
      [weekend],
      now: DateTime.utc(2026, 9, 24),
      reminders: true,
      replays: false,
    );
    expect(plan.map((alert) => alert.time).toList(), [
      DateTime.utc(2026, 9, 25, 9, 45),
      DateTime.utc(2026, 9, 27, 12, 45),
    ]);
    expect(plan.first.title, 'Practice 1 in 15 minutes');
    expect(plan.first.payload, isNull); // Tapping it just opens the app
  });

  test('replay alerts come 30 minutes after each session ends', () {
    final plan = planAlerts(
      [weekend],
      now: DateTime.utc(2026, 9, 24),
      reminders: false,
      replays: true,
    );
    // Practice: 1 hour long, then 30 minutes. The race: 2 hours, then 30.
    expect(plan.map((alert) => alert.time).toList(), [
      DateTime.utc(2026, 9, 25, 11, 30),
      DateTime.utc(2026, 9, 27, 15, 30),
    ]);
    expect(plan.last.title, 'Race replay is ready');
    // The payload is the start time, so a tap can find the session.
    expect(DateTime.parse(plan.last.payload!), race.start);
  });

  test('nothing is planned in the past, and the soonest come first', () {
    final plan = planAlerts(
      [weekend],
      now: DateTime.utc(2026, 9, 26), // After practice, before the race
      reminders: true,
      replays: true,
    );
    expect(plan.map((alert) => alert.title).toList(), [
      'Race in 15 minutes',
      'Race replay is ready',
    ]);
  });

  test('never more than the limit, because iPhones keep only 64', () {
    final plan = planAlerts(
      [weekend],
      now: DateTime.utc(2026, 9, 24),
      reminders: true,
      replays: true,
      limit: 3,
    );
    expect(plan.length, 3);
  });

  test('sessionLength', () {
    expect(sessionLength('Race'), const Duration(hours: 2));
    expect(sessionLength('Sprint Qualifying'), const Duration(minutes: 45));
    expect(sessionLength('Practice 2'), const Duration(hours: 1));
  });
}
