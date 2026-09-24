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
  });

  final int position;
  final Driver driver;
  final String team;
  final int grid; // Where they started. 0 means the pit lane.
  final int laps;
  final String status; // "Finished", "Retired", "+1 Lap"...
  final String? time; // "1:34:23.754" for the winner, "+4.351" for others
  final double points;

  factory RaceResult.fromJson(Map<String, dynamic> json) {
    // Drivers who did not finish have no "Time" at all, so this can be null.
    final timeData = json['Time'] as Map<String, dynamic>?;
    return RaceResult(
      position: int.parse(json['position'] as String),
      driver: Driver.fromJson(json['Driver'] as Map<String, dynamic>),
      team: (json['Constructor'] as Map<String, dynamic>)['name'] as String,
      grid: int.tryParse('${json['grid']}') ?? 0,
      laps: int.tryParse('${json['laps']}') ?? 0,
      status: (json['status'] as String?) ?? '',
      time: timeData?['time'] as String?,
      points: double.parse(json['points'] as String),
    );
  }

  /// The race time or gap, or the reason they stopped.
  String get timeOrStatus => time ?? status;

  /// Positive means they gained places from where they started.
  int get placesGained => grid == 0 ? 0 : grid - position;
}
