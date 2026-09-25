import 'dart:math' as math;
import 'dart:ui' show Offset;

import '../models/openf1_models.dart';

// The maths behind the tracker. These are plain functions with no screens
// and no internet, which makes them easy to test (see test/tracker_math_test.dart).

/// Finds the index of the first point whose time is AFTER [time].
///
/// A binary search: the list is sorted by time, so we can keep cutting it
/// in half instead of checking every point. With 1,000 points that is about 10 checks instead of 1,000.
int firstIndexAfter(List<CarLocation> points, DateTime time) {
  var low = 0;
  var high = points.length;
  while (low < high) {
    final middle = (low + high) ~/ 2; // ~/ divides and drops the remainder
    if (points[middle].date.isAfter(time)) {
      high = middle; // the answer is in the left half (or is middle itself)
    } else {
      low = middle + 1; // the answer is in the right half
    }
  }
  return low;
}

/// Where a car is at [time], worked out from its location points.
///
/// OpenF1 gives us a point about every quarter of a second. If we only drew
/// those, the cars would jump. Instead we find the point just before [time]
/// and the point just after it, and slide the car part of the way between
/// them. That is called linear interpolation.
Offset? positionAt(List<CarLocation> points, DateTime time) {
  if (points.isEmpty) return null;

  final after = firstIndexAfter(points, time);
  if (after == 0) return Offset(points.first.x, points.first.y);
  if (after == points.length) return Offset(points.last.x, points.last.y);

  final before = points[after - 1];
  final next = points[after];
  final gap = next.date.difference(before.date).inMicroseconds;
  if (gap == 0) return Offset(next.x, next.y);

  // 0.0 means "at before", 1.0 means "at next", 0.5 means halfway.
  final fraction = time.difference(before.date).inMicroseconds / gap;
  return Offset(
    before.x + (next.x - before.x) * fraction,
    before.y + (next.y - before.y) * fraction,
  );
}

/// The running order at [time]: driver numbers, leader first.
///
/// [updates] must be sorted by time. We walk through them, remembering each
/// driver's latest position, and stop as soon as we reach the future.
List<int> runningOrderAt(List<PositionUpdate> updates, DateTime time) {
  final latest = <int, int>{}; // driver number -> position
  for (final update in updates) {
    if (update.date.isAfter(time)) break;
    latest[update.driverNumber] = update.position;
  }
  final order = latest.keys.toList();
  order.sort((a, b) => latest[a]!.compareTo(latest[b]!));
  return order;
}

/// The moment the race moved on to a new lap.
class LapMark {
  const LapMark(this.date, this.lap);

  final DateTime date;
  final int lap;
}

/// Turns OpenF1's laps (every driver's) into the race's own lap timeline.
///
/// The race is on lap 12 as soon as the leader starts lap 12. So we sort
/// every lap start by time and keep only the ones that beat the highest
/// lap number so far. What is left is one mark per lap, in order.
List<LapMark> buildLapTimeline(List<Lap> laps) {
  final starts = <LapMark>[
    for (final lap in laps)
      if (lap.start != null) LapMark(lap.start!, lap.lapNumber),
  ];
  starts.sort((a, b) => a.date.compareTo(b.date));

  final timeline = <LapMark>[];
  var highest = 0;
  for (final mark in starts) {
    if (mark.lap > highest) {
      highest = mark.lap;
      timeline.add(mark);
    }
  }
  return timeline;
}

/// The race's lap at [time], or null before the first lap has started.
///
/// A race has about 60 laps, so a simple walk through the list is quick
/// enough. (The car locations need firstIndexAfter's binary search because
/// there are tens of thousands of them.)
int? lapAt(List<LapMark> timeline, DateTime time) {
  int? lap;
  for (final mark in timeline) {
    if (mark.date.isAfter(time)) break;
    lap = mark.lap;
  }
  return lap;
}

/// Each driver's best lap time in seconds, counting only the laps that had
/// finished by [time]. It is what the timing screen shows in practice and
/// qualifying, where the order is about one fast lap, not who is ahead.
Map<int, double> bestLapsAt(List<Lap> laps, DateTime time) {
  final best = <int, double>{}; // Driver number -> seconds
  for (final lap in laps) {
    final start = lap.start;
    final seconds = lap.duration;
    if (start == null || seconds == null) continue; // No time for this lap
    final end = start.add(Duration(milliseconds: (seconds * 1000).round()));
    if (end.isAfter(time)) continue; // Still on this lap at [time]
    final current = best[lap.driverNumber];
    if (current == null || seconds < current) best[lap.driverNumber] = seconds;
  }
  return best;
}

/// The quickest complete lap in [laps], or null if none has a time.
/// A fastest lap is flat out from start to finish, so it draws the
/// cleanest track outline.
Lap? fastestLap(List<Lap> laps) {
  Lap? fastest;
  for (final lap in laps) {
    final seconds = lap.duration;
    if (lap.start == null || seconds == null) continue;
    final best = fastest?.duration;
    if (best == null || seconds < best) fastest = lap;
  }
  return fastest;
}

/// True if the car was in its garage around [time].
///
/// While a car sits in the garage, OpenF1 reports it at exactly (0, 0).
/// That happens a lot in practice. We hide those cars instead of drawing
/// them in the middle of the map, or sliding across it on their way out.
bool isInGarageAt(List<CarLocation> points, DateTime time) {
  bool atZero(CarLocation point) => point.x == 0 && point.y == 0;
  final after = firstIndexAfter(points, time);
  if (after > 0 && atZero(points[after - 1])) return true;
  if (after < points.length && atZero(points[after])) return true;
  return false;
}

// ----------------------------------------------------------------------
// Tyres, pit stops, race control and weather (Chapter 44)
// ----------------------------------------------------------------------

/// Every driver's laps, keyed by driver number, in lap order.
Map<int, List<Lap>> lapsByDriver(List<Lap> laps) {
  final byDriver = <int, List<Lap>>{};
  for (final lap in laps) {
    byDriver.putIfAbsent(lap.driverNumber, () => []).add(lap);
  }
  for (final list in byDriver.values) {
    list.sort((a, b) => a.lapNumber.compareTo(b.lapNumber));
  }
  return byDriver;
}

/// The lap one driver is on at [time]: the last lap they had started.
/// [driverLaps] is one driver's laps in lap order. Null before lap 1.
int? driverLapAt(List<Lap> driverLaps, DateTime time) {
  int? lap;
  for (final candidate in driverLaps) {
    final start = candidate.start;
    if (start == null) continue;
    if (start.isAfter(time)) break;
    lap = candidate.lapNumber;
  }
  return lap;
}

/// The set of tyres [driverNumber] is on during [lap]: their latest stint
/// that had started by then.
Stint? stintOn(List<Stint> stints, int driverNumber, int lap) {
  Stint? current;
  for (final stint in stints) {
    if (stint.driverNumber != driverNumber || stint.lapStart > lap) continue;
    if (current == null || stint.lapStart > current.lapStart) current = stint;
  }
  return current;
}

/// The compound [driverNumber] is on during [lap]: "SOFT", "MEDIUM"...
String? compoundOn(List<Stint> stints, int driverNumber, int lap) =>
    stintOn(stints, driverNumber, lap)?.compound;

/// True while [driverNumber] is in the pit lane at [time]. Stops without a
/// time are counted as the usual 25 seconds or so.
bool isInPitLane(List<PitStop> stops, int driverNumber, DateTime time) {
  for (final stop in stops) {
    if (stop.driverNumber != driverNumber || stop.date.isAfter(time)) continue;
    final seconds = stop.laneSeconds ?? 25;
    final exit =
        stop.date.add(Duration(milliseconds: (seconds * 1000).round()));
    if (time.isBefore(exit)) return true;
  }
  return false;
}

/// How many times [driverNumber] had come into the pits by [time].
int pitStopsBefore(List<PitStop> stops, int driverNumber, DateTime time) {
  var count = 0;
  for (final stop in stops) {
    if (stop.driverNumber == driverNumber && !stop.date.isAfter(time)) {
      count++;
    }
  }
  return count;
}

/// The newest race control message at [time], if it is no older than
/// [within]. [messages] must be sorted by time, oldest first.
RaceControlMessage? latestMessageAt(
  List<RaceControlMessage> messages,
  DateTime time, {
  Duration within = const Duration(seconds: 60),
}) {
  RaceControlMessage? latest;
  for (final message in messages) {
    if (message.date.isAfter(time)) break;
    latest = message;
  }
  if (latest == null || time.difference(latest.date) > within) return null;
  return latest;
}

/// Which part of qualifying is running at [time]: 1, 2 or 3. Null outside
/// qualifying. Race control tags its messages with the part.
int? qualifyingPhaseAt(List<RaceControlMessage> messages, DateTime time) {
  int? phase;
  for (final message in messages) {
    if (message.date.isAfter(time)) break;
    phase = message.qualifyingPhase ?? phase;
  }
  return phase;
}

/// The latest weather reading at [time], or null before the first one.
/// [readings] must be sorted by time, oldest first.
WeatherReading? weatherAt(List<WeatherReading> readings, DateTime time) {
  WeatherReading? latest;
  for (final reading in readings) {
    if (reading.date.isAfter(time)) break;
    latest = reading;
  }
  return latest;
}

// ----------------------------------------------------------------------
// Data saver: cars placed from lap times instead of GPS (Chapter 43)
// ----------------------------------------------------------------------

/// Where a car is at [time], worked out from its lap times alone.
///
/// [outline] is one lap of GPS points from the start line, in the order
/// the car drove them, a few times a second. So a point halfway through the
/// list is where that car was halfway through its lap. If another car is
/// 40% of the way through its own lap time, we put it 40% of the way along
/// the list. Every car slows for the same corners, so this looks right,
/// and it needs only the lap times: no GPS download at all.
///
/// [laps] is one driver's laps in lap order. Null when the car is not on a
/// timed lap: before the start, in the garage, or after the finish.
Offset? positionFromLaps(List<Lap> laps, List<Offset> outline, DateTime time) {
  if (outline.length < 2) return null;

  // Newest lap first: the car is on the last lap it had started.
  for (var i = laps.length - 1; i >= 0; i--) {
    final start = laps[i].start;
    if (start == null || start.isAfter(time)) continue;

    // When does that lap end? Its own time, or else when the next begins.
    final seconds = laps[i].duration;
    final DateTime? end;
    if (seconds != null) {
      end = start.add(Duration(milliseconds: (seconds * 1000).round()));
    } else if (i + 1 < laps.length) {
      end = laps[i + 1].start;
    } else {
      end = null;
    }
    if (end == null || !time.isBefore(end) || !end.isAfter(start)) {
      return null; // Between laps: in the pits, the garage, or finished
    }

    // How far through the lap, from 0.0 to 1.0, and so where in the list.
    final fraction = time.difference(start).inMicroseconds /
        end.difference(start).inMicroseconds;
    final position = fraction * (outline.length - 1);
    final index = position.floor();
    final along = position - index; // How far from this point to the next
    final from = outline[index];
    final to = outline[math.min(index + 1, outline.length - 1)];
    return Offset(
      from.dx + (to.dx - from.dx) * along,
      from.dy + (to.dy - from.dy) * along,
    );
  }
  return null;
}

// ----------------------------------------------------------------------
// Qualifying, tyre age and sector times (Chapter 50)
// ----------------------------------------------------------------------

/// How many laps the tyres [driverNumber] is on have done by [lap]: the
/// laps they had before this stint (from an earlier session) plus the laps
/// since. The TV shows the same number next to the tyre.
int? tyreAgeOn(List<Stint> stints, int driverNumber, int lap) {
  final stint = stintOn(stints, driverNumber, lap);
  if (stint == null) return null;
  return stint.tyreAgeAtStart + (lap - stint.lapStart);
}

/// How many laps one driver had finished by [time].
int lapsCompleted(List<Lap> driverLaps, DateTime time) {
  var count = 0;
  for (final lap in driverLaps) {
    final start = lap.start;
    final seconds = lap.duration;
    if (start == null || seconds == null) continue;
    final end = start.add(Duration(milliseconds: (seconds * 1000).round()));
    if (!end.isAfter(time)) count++;
  }
  return count;
}

/// Who is out of qualifying during part [phase] (1, 2 or 3), and in which
/// part they went out, worked out from the running order.
///
/// Q3 always has 10 cars, and Q1 and Q2 knock out the same number each:
/// 5 each with 20 cars, 6 each with 22. So once Q2 starts, anyone below
/// the Q2 places is out in Q1, and once Q3 starts, anyone from 11th down
/// to there is out in Q2.
Map<int, int> knockedOutAt(List<int> order, int phase, int entrants) {
  if (entrants <= 10) return {};
  final perPart = ((entrants - 10) / 2).ceil();
  final inQ2 = 10 + perPart;
  final out = <int, int>{}; // Driver number -> the part they went out in
  for (var i = 0; i < order.length; i++) {
    final place = i + 1;
    if (phase >= 2 && place > inQ2) {
      out[order[i]] = 1;
    } else if (phase >= 3 && place > 10) {
      out[order[i]] = 2;
    }
  }
  return out;
}

/// The fastest time in each sector, and the fastest lap, among [laps].
class LapBests {
  const LapBests(this.sectors, this.lap);

  final List<double?> sectors; // Best sector 1, 2 and 3
  final double? lap;
}

LapBests bestsOf(Iterable<Lap> laps) {
  final sectors = <double?>[null, null, null];
  double? bestLap;
  for (final lap in laps) {
    for (var i = 0; i < 3; i++) {
      final time = lap.sectors[i];
      final best = sectors[i];
      if (time != null && (best == null || time < best)) sectors[i] = time;
    }
    final seconds = lap.duration;
    if (seconds != null && (bestLap == null || seconds < bestLap)) {
      bestLap = seconds;
    }
  }
  return LapBests(sectors, bestLap);
}

/// For every lap number, the lap that was driven fastest.
Map<int, Lap> fastestEachLap(List<Lap> laps) {
  final fastest = <int, Lap>{};
  for (final lap in laps) {
    final seconds = lap.duration;
    if (seconds == null) continue;
    final best = fastest[lap.lapNumber]?.duration;
    if (best == null || seconds < best) fastest[lap.lapNumber] = lap;
  }
  return fastest;
}
