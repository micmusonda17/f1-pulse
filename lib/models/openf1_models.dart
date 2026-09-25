import 'package:flutter/material.dart';

/// One session (practice, qualifying, sprint or race) from OpenF1.
class OpenF1Session {
  const OpenF1Session({
    required this.sessionKey,
    required this.meetingKey,
    required this.name,
    required this.type,
    required this.location,
    required this.country,
    required this.start,
    required this.end,
    required this.isCancelled,
  });

  final int sessionKey; // OpenF1's id for this session
  final int meetingKey; // OpenF1's id for the whole race weekend
  final String name; // "Race", "Sprint", "Qualifying"
  final String type;
  final String location; // "Monza"
  final String country; // "Italy"
  final DateTime start;
  final DateTime end;
  final bool isCancelled;

  factory OpenF1Session.fromJson(Map<String, dynamic> json) {
    return OpenF1Session(
      sessionKey: json['session_key'] as int,
      meetingKey: json['meeting_key'] as int,
      name: (json['session_name'] as String?) ?? '',
      type: (json['session_type'] as String?) ?? '',
      location: (json['location'] as String?) ?? '',
      country: (json['country_name'] as String?) ?? '',
      start: DateTime.parse(json['date_start'] as String),
      end: DateTime.parse(json['date_end'] as String),
      isCancelled: (json['is_cancelled'] as bool?) ?? false,
    );
  }

  /// "Monza Race"
  String get title => '$location $name';

  bool get hasFinished => DateTime.now().isAfter(end);

  /// OpenF1 counts data as live from 30 minutes before a session starts
  /// until 30 minutes after it ends.
  bool get isLiveNow {
    final now = DateTime.now();
    final opens = start.subtract(const Duration(minutes: 30));
    final closes = end.add(const Duration(minutes: 30));
    return now.isAfter(opens) && now.isBefore(closes);
  }
}

/// The session in [sessions] that starts closest to [start], if one starts
/// within 90 minutes of it. This is how a Jolpica session (from the race
/// calendar) is matched to the same session in OpenF1.
///
/// The closest, not the first: on a race weekend, practice 1 and practice 2
/// can start only a few hours apart.
OpenF1Session? closestSession(List<OpenF1Session> sessions, DateTime start) {
  OpenF1Session? closest;
  var closestGap = const Duration(minutes: 90);
  for (final session in sessions) {
    final gap = session.start.difference(start).abs();
    if (gap < closestGap) {
      closest = session;
      closestGap = gap;
    }
  }
  return closest;
}

/// A driver in one OpenF1 session, with their team colour.
class DriverInfo {
  const DriverInfo({
    required this.number,
    required this.acronym,
    required this.fullName,
    required this.team,
    required this.colour,
    this.headshotUrl,
  });

  final int number; // 12
  final String acronym; // "ANT"
  final String fullName;
  final String team;
  final Color colour;
  final String? headshotUrl; // A photo from formula1.com, if OpenF1 has one

  factory DriverInfo.fromJson(Map<String, dynamic> json) {
    final number = json['driver_number'] as int;
    return DriverInfo(
      number: number,
      acronym: (json['name_acronym'] as String?) ?? '$number',
      fullName: (json['full_name'] as String?) ?? 'Car $number',
      team: (json['team_name'] as String?) ?? '',
      colour: colourFromHex(json['team_colour'] as String?),
      headshotUrl: json['headshot_url'] as String?,
    );
  }
}

/// Turns a hex colour like "F58020" into a Flutter Color.
/// Grey if the team has no colour.
Color colourFromHex(String? hex) {
  if (hex == null || hex.length != 6) return Colors.grey;
  final value = int.tryParse(hex, radix: 16);
  if (value == null) return Colors.grey;
  return Color(0xFF000000 | value); // 0xFF at the front = fully opaque
}

/// Where one car was at one moment. About 4 of these per car per second.
class CarLocation {
  const CarLocation({
    required this.driverNumber,
    required this.date,
    required this.x,
    required this.y,
    this.z = 0,
  });

  final int driverNumber;
  final DateTime date;
  final double x;
  final double y;
  final double z; // Height above sea level, for the 3D view (Chapter 55)

  factory CarLocation.fromJson(Map<String, dynamic> json) {
    return CarLocation(
      driverNumber: json['driver_number'] as int,
      date: DateTime.parse(json['date'] as String),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      z: (json['z'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// "At this moment, this driver moved to this position."
class PositionUpdate {
  const PositionUpdate({
    required this.driverNumber,
    required this.date,
    required this.position,
  });

  final int driverNumber;
  final DateTime date;
  final int position;

  factory PositionUpdate.fromJson(Map<String, dynamic> json) {
    return PositionUpdate(
      driverNumber: json['driver_number'] as int,
      date: DateTime.parse(json['date'] as String),
      position: json['position'] as int,
    );
  }
}

/// One lap by one driver: when it started, how long it took, and its three
/// sector times (Chapter 50).
class Lap {
  const Lap({
    required this.driverNumber,
    required this.lapNumber,
    required this.start,
    required this.duration,
    this.sectors = const [null, null, null],
    this.isPitOutLap = false,
  });

  final int driverNumber;
  final int lapNumber;
  final DateTime? start;
  final double? duration; // seconds
  final List<double?> sectors; // Sectors 1, 2 and 3, in seconds
  final bool isPitOutLap; // The lap that started in the pit lane

  factory Lap.fromJson(Map<String, dynamic> json) {
    final start = json['date_start'] as String?;
    double? seconds(String key) => (json[key] as num?)?.toDouble();
    return Lap(
      driverNumber: json['driver_number'] as int,
      lapNumber: json['lap_number'] as int,
      start: start == null ? null : DateTime.parse(start),
      duration: seconds('lap_duration'),
      sectors: [
        seconds('duration_sector_1'),
        seconds('duration_sector_2'),
        seconds('duration_sector_3'),
      ],
      isPitOutLap: (json['is_pit_out_lap'] as bool?) ?? false,
    );
  }
}

/// One set of tyres: a driver ran [compound] from lap [lapStart] to
/// [lapEnd]. [lapEnd] is null while the stint is still going.
class Stint {
  const Stint({
    required this.driverNumber,
    required this.lapStart,
    required this.lapEnd,
    required this.compound,
    this.tyreAgeAtStart = 0,
  });

  final int driverNumber;
  final int lapStart;
  final int? lapEnd;
  final String compound; // "SOFT", "MEDIUM", "HARD", "INTERMEDIATE", "WET"
  final int tyreAgeAtStart; // Laps these tyres had done before this stint

  factory Stint.fromJson(Map<String, dynamic> json) {
    return Stint(
      driverNumber: json['driver_number'] as int,
      lapStart: (json['lap_start'] as int?) ?? 1,
      lapEnd: json['lap_end'] as int?,
      compound: (json['compound'] as String?) ?? 'UNKNOWN',
      tyreAgeAtStart: (json['tyre_age_at_start'] as int?) ?? 0,
    );
  }
}

/// One trip through the pit lane.
class PitStop {
  const PitStop({
    required this.driverNumber,
    required this.date,
    required this.laneSeconds,
    this.lapNumber,
    this.stopSeconds,
  });

  final int driverNumber;
  final DateTime date; // When the car came into the pit lane
  final double? laneSeconds; // Time from pit entry to pit exit
  final int? lapNumber;
  final double? stopSeconds; // Standing still: the crew's time (2024 on)

  factory PitStop.fromJson(Map<String, dynamic> json) {
    // lane_duration is the new name. Older data only has pit_duration.
    final seconds = json['lane_duration'] ?? json['pit_duration'];
    return PitStop(
      driverNumber: json['driver_number'] as int,
      date: DateTime.parse(json['date'] as String),
      laneSeconds: (seconds as num?)?.toDouble(),
      lapNumber: json['lap_number'] as int?,
      stopSeconds: (json['stop_duration'] as num?)?.toDouble(),
    );
  }
}

/// A message from race control: flags, safety cars, penalties.
class RaceControlMessage {
  const RaceControlMessage({
    required this.date,
    required this.category,
    required this.message,
    this.flag,
    this.qualifyingPhase,
    this.lapNumber,
    this.driverNumber,
    this.scope,
    this.sector,
  });

  final DateTime date;
  final String category; // "Flag", "SafetyCar", "Drs", "Other"...
  final String message; // "SAFETY CAR DEPLOYED"
  final String? flag; // "YELLOW", "RED", "CHEQUERED"... Null if not a flag
  final int? qualifyingPhase; // 1, 2 or 3 in qualifying, otherwise null
  final int? lapNumber; // The race's lap when it was sent
  final int? driverNumber; // The car it is about, if it is about one
  final String? scope; // "Track", "Sector" or "Driver"
  final int? sector; // Which marshal sector, for a sector flag

  factory RaceControlMessage.fromJson(Map<String, dynamic> json) {
    return RaceControlMessage(
      date: DateTime.parse(json['date'] as String),
      category: (json['category'] as String?) ?? '',
      message: (json['message'] as String?) ?? '',
      flag: json['flag'] as String?,
      qualifyingPhase: json['qualifying_phase'] as int?,
      lapNumber: json['lap_number'] as int?,
      driverNumber: json['driver_number'] as int?,
      scope: json['scope'] as String?,
      sector: json['sector'] as int?,
    );
  }
}

/// The weather at the track, measured about once a minute.
class WeatherReading {
  const WeatherReading({
    required this.date,
    required this.airTemperature,
    required this.trackTemperature,
    required this.isRaining,
    this.humidity,
    this.windSpeed,
    this.windDirection,
  });

  final DateTime date;
  final double airTemperature; // Degrees Celsius
  final double trackTemperature;
  final bool isRaining;
  final double? humidity; // Percent (Chapter 53)
  final double? windSpeed; // Metres a second
  final int? windDirection; // Degrees: 0 is from the north, 90 the east

  factory WeatherReading.fromJson(Map<String, dynamic> json) {
    return WeatherReading(
      date: DateTime.parse(json['date'] as String),
      airTemperature: (json['air_temperature'] as num?)?.toDouble() ?? 0,
      trackTemperature: (json['track_temperature'] as num?)?.toDouble() ?? 0,
      isRaining: ((json['rainfall'] as num?) ?? 0) > 0,
      humidity: (json['humidity'] as num?)?.toDouble(),
      windSpeed: (json['wind_speed'] as num?)?.toDouble(),
      windDirection: (json['wind_direction'] as num?)?.toInt(),
    );
  }
}
