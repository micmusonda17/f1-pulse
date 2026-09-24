import '../utils/formatting.dart';

/// One session in a race weekend, for example Qualifying on Saturday.
class WeekendSession {
  const WeekendSession({required this.name, required this.start});

  final String name;
  final DateTime start; // In UTC. Call toLocal() when you show it.
}

/// One Grand Prix on the calendar.
class Race {
  const Race({
    required this.season,
    required this.round,
    required this.name,
    required this.circuitId,
    required this.circuitName,
    required this.locality,
    required this.country,
    required this.start,
    required this.sessions,
  });

  final int season;
  final int round;
  final String name;
  final String circuitId; // Jolpica's name for the track: "baku", "monza"
  final String circuitName;
  final String locality;
  final String country;
  final DateTime? start; // Lights out. Null if not announced yet.
  final List<WeekendSession> sessions;

  /// Jolpica gives each session its own key. This maps key to label.
  static const Map<String, String> _sessionLabels = {
    'FirstPractice': 'Practice 1',
    'SecondPractice': 'Practice 2',
    'ThirdPractice': 'Practice 3',
    'SprintQualifying': 'Sprint Qualifying',
    'SprintShootout': 'Sprint Shootout',
    'Sprint': 'Sprint',
    'Qualifying': 'Qualifying',
  };

  /// Builds a Race from one item in Jolpica's "Races" list.
  factory Race.fromJson(Map<String, dynamic> json) {
    final circuit = json['Circuit'] as Map<String, dynamic>;
    final location = circuit['Location'] as Map<String, dynamic>;
    final start = parseApiDateTime(json['date'], json['time']);

    final sessions = <WeekendSession>[];
    for (final entry in _sessionLabels.entries) {
      final session = json[entry.key];
      if (session is Map<String, dynamic>) {
        final sessionStart = parseApiDateTime(session['date'], session['time']);
        if (sessionStart != null) {
          sessions.add(WeekendSession(name: entry.value, start: sessionStart));
        }
      }
    }
    if (start != null) {
      sessions.add(WeekendSession(name: 'Race', start: start));
    }
    sessions.sort((a, b) => a.start.compareTo(b.start));

    return Race(
      season: int.parse(json['season'] as String),
      round: int.parse(json['round'] as String),
      name: json['raceName'] as String,
      circuitId: circuit['circuitId'] as String,
      circuitName: circuit['circuitName'] as String,
      locality: location['locality'] as String,
      country: location['country'] as String,
      start: start,
      sessions: sessions,
    );
  }

  /// We call a race finished two hours after lights out.
  bool get isFinished {
    final raceStart = start;
    if (raceStart == null) return false;
    return DateTime.now().isAfter(raceStart.add(const Duration(hours: 2)));
  }

  /// The first session that has not started yet, or null if it is all done.
  WeekendSession? get nextSession {
    final now = DateTime.now();
    for (final session in sessions) {
      if (session.start.isAfter(now)) return session;
    }
    return null;
  }
}

/// The session that is on right now, or null if nothing is.
///
/// Every session counts as "on" for two hours after it starts: right for
/// a race, a little long for practice. [now] is only there for the tests.
WeekendSession? findLiveSession(List<Race> races, {DateTime? now}) {
  final time = now ?? DateTime.now();
  for (final race in races) {
    for (final session in race.sessions) {
      final end = session.start.add(const Duration(hours: 2));
      if (!time.isBefore(session.start) && time.isBefore(end)) return session;
    }
  }
  return null;
}

/// The first race that has not finished, or null at the end of the season.
Race? findNextRace(List<Race> races) {
  for (final race in races) {
    if (!race.isFinished) return race;
  }
  return null;
}
