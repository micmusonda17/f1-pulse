import 'package:flutter_test/flutter_test.dart';
import 'package:pitbeat/models/openf1_models.dart';
import 'package:pitbeat/tracker/tracker_math.dart';

/// A made-up location point, [seconds] after midday.
CarLocation point(int seconds, double x, double y) => CarLocation(
      driverNumber: 1,
      date: DateTime.utc(2026, 9, 13, 12, 0, seconds),
      x: x,
      y: y,
    );

DateTime at(int seconds, [int milliseconds = 0]) =>
    DateTime.utc(2026, 9, 13, 12, 0, seconds, milliseconds);

void main() {
  final points = [
    point(0, 0, 0),
    point(1, 10, 0),
    point(2, 20, 0),
    point(3, 30, 0),
  ];

  group('firstIndexAfter (binary search)', () {
    test('finds the first point after a time in the middle', () {
      expect(firstIndexAfter(points, at(1, 500)), 2);
    });

    test('a time exactly on a point returns the NEXT one', () {
      expect(firstIndexAfter(points, at(1)), 2);
    });

    test('before everything returns 0, after everything returns length', () {
      expect(firstIndexAfter(points, at(0).subtract(const Duration(seconds: 1))), 0);
      expect(firstIndexAfter(points, at(10)), 4);
    });
  });

  group('positionAt (interpolation)', () {
    test('halfway between two points is halfway along the line', () {
      expect(positionAt(points, at(1, 500)), const Offset(15, 0));
    });

    test('before the first point, the car sits on the first point', () {
      final early = at(0).subtract(const Duration(seconds: 5));
      expect(positionAt(points, early), const Offset(0, 0));
    });

    test('after the last point, the car sits on the last point', () {
      expect(positionAt(points, at(10)), const Offset(30, 0));
    });

    test('no points means no position', () {
      expect(positionAt([], at(0)), isNull);
    });
  });

  group('runningOrderAt', () {
    final updates = [
      PositionUpdate(driverNumber: 1, date: at(0), position: 1),
      PositionUpdate(driverNumber: 44, date: at(0), position: 2),
      // Overtake! Car 44 takes the lead at 10 seconds.
      PositionUpdate(driverNumber: 44, date: at(10), position: 1),
      PositionUpdate(driverNumber: 1, date: at(10), position: 2),
    ];

    test('before the overtake, car 1 leads', () {
      expect(runningOrderAt(updates, at(5)), [1, 44]);
    });

    test('after the overtake, car 44 leads', () {
      expect(runningOrderAt(updates, at(15)), [44, 1]);
    });
  });

  group('lap counter', () {
    Lap lap(int driver, int number, int seconds) => Lap(
          driverNumber: driver,
          lapNumber: number,
          start: at(seconds), // Seconds past 59 roll over into minutes
          duration: null,
        );

    final laps = [
      lap(1, 1, 0),
      lap(2, 1, 1),
      lap(1, 2, 90), // Car 1 leads onto lap 2
      lap(2, 2, 92),
      lap(2, 3, 181), // Car 2 has overtaken and starts lap 3 first
      lap(1, 3, 183),
      // No start time: OpenF1 sometimes leaves it out. It is skipped.
      const Lap(driverNumber: 1, lapNumber: 4, start: null, duration: null),
    ];

    test('keeps one mark per lap, at the first car to start it', () {
      final timeline = buildLapTimeline(laps);
      expect(timeline.map((mark) => mark.lap).toList(), [1, 2, 3]);
      expect(timeline[2].date, at(181));
    });

    test('the order the laps arrive in does not matter', () {
      final timeline = buildLapTimeline(laps.reversed.toList());
      expect(timeline.map((mark) => mark.lap).toList(), [1, 2, 3]);
    });

    test('lapAt finds the lap at any moment', () {
      final timeline = buildLapTimeline(laps);
      final beforeStart = at(0).subtract(const Duration(seconds: 1));
      expect(lapAt(timeline, beforeStart), isNull);
      expect(lapAt(timeline, at(45)), 1);
      expect(lapAt(timeline, at(90)), 2); // Exactly at the start counts
      expect(lapAt(timeline, at(500)), 3);
    });
  });
}
