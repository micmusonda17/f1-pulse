import 'standing.dart';

/// One driver's result in one race.
class RaceResult {
  const RaceResult({
    required this.position,
    required this.driver,
    required this.team,
    required this.grid,
    required this.laps,
    required this.status,
    required this.time,
    required this.points,
    this.classified = true,
    this.fastestLapRank,
  });

  final int position;
  final Driver driver;
  final String team;
  final int grid; // Where they started. 0 means the pit lane.
  final int laps;
  final String status; // "Finished", "Retired", "+1 Lap"...
  final String? time; // "1:34:23.754" for the winner, "+4.351" for others
  final double points;
  // False for "R" (retired), "D" (disqualified), "N" (not classified) and
  // the like in Jolpica's positionText. Fantasy points need to know.
  final bool classified;
  final int? fastestLapRank; // 1 = fastest lap of the race

  factory RaceResult.fromJson(Map<String, dynamic> json) {
    // Drivers who did not finish have no "Time" at all, so this can be null.
    final timeData = json['Time'] as Map<String, dynamic>?;
    final fastestLap = json['FastestLap'] as Map<String, dynamic>?;
    return RaceResult(
      position: int.parse(json['position'] as String),
      driver: Driver.fromJson(json['Driver'] as Map<String, dynamic>),
      team: (json['Constructor'] as Map<String, dynamic>)['name'] as String,
      grid: int.tryParse('${json['grid']}') ?? 0,
      laps: int.tryParse('${json['laps']}') ?? 0,
      status: (json['status'] as String?) ?? '',
      time: timeData?['time'] as String?,
      points: double.parse(json['points'] as String),
      classified: int.tryParse('${json['positionText']}') != null,
      fastestLapRank: int.tryParse('${fastestLap?['rank']}'),
    );
  }

  /// The race time or gap, or the reason they stopped.
  String get timeOrStatus => time ?? status;

  /// Positive means they gained places from where they started.
  int get placesGained => grid == 0 ? 0 : grid - position;
}

/// One driver's place in qualifying: where they will start the race
/// (before any grid penalties).
class QualifyingResult {
  const QualifyingResult({
    required this.position,
    required this.driver,
    required this.team,
    this.setTime = true,
    this.reachedQ2 = false,
    this.reachedQ3 = false,
  });

  final int position;
  final Driver driver;
  final String team;
  final bool setTime; // False if they never set a lap time in Q1
  final bool reachedQ2;
  final bool reachedQ3;

  factory QualifyingResult.fromJson(Map<String, dynamic> json) {
    // Each part has a time only for drivers who took part in it.
    bool hasTime(Object? time) => time is String && time.isNotEmpty;
    return QualifyingResult(
      position: int.parse(json['position'] as String),
      driver: Driver.fromJson(json['Driver'] as Map<String, dynamic>),
      team: (json['Constructor'] as Map<String, dynamic>)['name'] as String,
      setTime: hasTime(json['Q1']),
      reachedQ2: hasTime(json['Q2']),
      reachedQ3: hasTime(json['Q3']),
    );
  }
}
