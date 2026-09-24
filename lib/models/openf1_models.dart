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
  });

  final int driverNumber;
  final DateTime date;
  final double x;
  final double y;

  factory CarLocation.fromJson(Map<String, dynamic> json) {
    return CarLocation(
      driverNumber: json['driver_number'] as int,
      date: DateTime.parse(json['date'] as String),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
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

/// One lap by one driver. We only need when it started and how long it took.
class Lap {
  const Lap({
    required this.driverNumber,
    required this.lapNumber,
    required this.start,
    required this.duration,
  });

  final int driverNumber;
  final int lapNumber;
  final DateTime? start;
  final double? duration; // seconds

  factory Lap.fromJson(Map<String, dynamic> json) {
    final start = json['date_start'] as String?;
    return Lap(
      driverNumber: json['driver_number'] as int,
      lapNumber: json['lap_number'] as int,
      start: start == null ? null : DateTime.parse(start),
      duration: (json['lap_duration'] as num?)?.toDouble(),
    );
  }
}
