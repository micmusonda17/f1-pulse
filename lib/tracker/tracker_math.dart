import 'dart:ui' show Offset;

import '../models/openf1_models.dart';

// The maths behind the tracker. These are plain functions with no screens
// and no internet, which makes them easy to test (see test/tracker_math_test.dart).

/// Finds the index of the first point whose time is AFTER [time].
///
/// This is the binary search from Chapter 20 of your Study Bible. The list
/// is sorted by time, so we can keep cutting it in half instead of checking
/// every point. With 1,000 points that is about 10 checks instead of 1,000.
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
