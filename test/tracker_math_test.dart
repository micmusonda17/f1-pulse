import 'package:f1_pulse/models/openf1_models.dart';
import 'package:f1_pulse/tracker/tracker_math.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
