import '../models/standing.dart';
import '../predictions/predictor.dart' show ordinal;
import '../utils/formatting.dart';

// The personal message on the Races tab when someone signs in (Chapter 47).
// Plain text from plain facts, so it is easy to test.

/// "in 3 days", "in 5 hours", "in 20 minutes", "now".
String inWords(Duration duration) {
  if (duration.inMinutes < 1) return 'now';
  String count(int n, String unit) => n == 1 ? '1 $unit' : '$n ${unit}s';
  if (duration.inHours < 1) return 'in ${count(duration.inMinutes, 'minute')}';
  if (duration.inDays < 1) return 'in ${count(duration.inHours, 'hour')}';
  return 'in ${count(duration.inDays, 'day')}';
}

/// A few short lines for [name], from whatever we know. Anything unknown
/// is simply left out, and results are left out in spoiler-free mode.
List<String> welcomeLines({
  required String name,
  required DateTime now,
  String? nextSession, // "Qualifying"
  DateTime? nextSessionStart,
  String? raceName, // "Azerbaijan Grand Prix"
  DriverStanding? favouriteDriver,
  ConstructorStanding? favouriteTeam,
  int? fantasyPoints, // Their fantasy team at the latest race
  String? fantasyRace,
  bool spoilerFree = false,
}) {
  final firstName = name.trim().split(RegExp(r'\s+')).first;
  final lines = <String>['${greetingFor(firstName, now: now)}. Welcome back.'];

  final start = nextSessionStart;
  if (nextSession != null && start != null) {
    final when = start.isAfter(now) ? inWords(start.difference(now)) : 'now';
    final race = raceName == null ? '' : ' at the $raceName';
    lines.add(
      when == 'now'
          ? '$nextSession$race is on now.'
          : '$nextSession$race starts $when.',
    );
  }

  if (spoilerFree) {
    lines.add('Spoiler-free mode is on, so no results here.');
    return lines;
  }

  final driver = favouriteDriver;
  if (driver != null && driver.position > 0) {
    final place = driver.position == 1
        ? 'leads the championship'
        : 'is ${ordinal(driver.position)} in the championship';
    lines.add(
      '${driver.driver.lastName} $place '
      'with ${formatPoints(driver.points)} points.',
    );
  }

  final team = favouriteTeam;
  if (team != null && team.position > 0) {
    lines.add(
      team.position == 1
          ? '${team.name} lead the constructors.'
          : '${team.name} are ${ordinal(team.position)} in the constructors.',
    );
  }

  final points = fantasyPoints;
  if (points != null && fantasyRace != null) {
    lines.add('Your fantasy team scored $points points at the $fantasyRace.');
  }
  return lines;
}
