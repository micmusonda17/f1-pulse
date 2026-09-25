// Lap times and pit stops from Jolpica (Chapter 57). Jolpica never locks
// anyone out, so these make a lap-by-lap replay of any race, even while
// OpenF1 is closed for a live session.

/// One driver's time on one lap, and their place at the end of it.
class LapTiming {
  const LapTiming({
    required this.lap,
    required this.driverId,
    required this.position,
    required this.seconds,
  });

  final int lap;
  final String driverId; // Jolpica's id, like "leclerc"
  final int position; // Their place as they finished this lap
  final double seconds;
}

/// One pit stop: the lap it came on, and the time in the pit lane.
class JolpicaPitStop {
  const JolpicaPitStop({
    required this.driverId,
    required this.lap,
    this.seconds,
  });

  final String driverId;
  final int lap;
  final double? seconds;

  factory JolpicaPitStop.fromJson(Map<String, dynamic> json) {
    return JolpicaPitStop(
      driverId: json['driverId'] as String,
      lap: int.tryParse('${json['lap']}') ?? 0,
      seconds: parseTimeText(json['duration'] as String?),
    );
  }
}

/// "1:39.019" is 99.019 seconds, "22.345" is 22.345. Null if it cannot be
/// read. Each part before a colon is worth 60 of the part after it.
double? parseTimeText(String? text) {
  if (text == null || text.isEmpty) return null;
  var seconds = 0.0;
  for (final part in text.split(':')) {
    final value = double.tryParse(part);
    if (value == null) return null;
    seconds = seconds * 60 + value;
  }
  return seconds;
}

/// Jolpica's "Laps" list (each lap with every driver's timing) as one
/// LapTiming per driver per lap. Timings it cannot read are skipped.
List<LapTiming> lapTimingsFrom(List<dynamic> laps) {
  final timings = <LapTiming>[];
  for (final lap in laps.cast<Map<String, dynamic>>()) {
    final number = int.tryParse('${lap['number']}');
    if (number == null) continue;
    final rows = (lap['Timings'] as List<dynamic>?) ?? const [];
    for (final row in rows.cast<Map<String, dynamic>>()) {
      final seconds = parseTimeText(row['time'] as String?);
      if (seconds == null) continue;
      timings.add(
        LapTiming(
          lap: number,
          driverId: row['driverId'] as String,
          position: int.tryParse('${row['position']}') ?? 0,
          seconds: seconds,
        ),
      );
    }
  }
  return timings;
}
