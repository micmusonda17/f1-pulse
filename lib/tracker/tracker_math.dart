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
