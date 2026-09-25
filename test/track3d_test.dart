import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitbeat/models/openf1_models.dart';
import 'package:pitbeat/tracker/track3d.dart';

DateTime at(int seconds) => DateTime.utc(2026, 9, 27, 13, 0, seconds);

void main() {
  const size = Size(200, 200);
  const origin = Point3(0, 0, 0);

  group('the camera', () {
    const topDown = Camera3D(pitch: math.pi / 2);

    test('looking straight down, north is up and east is right', () {
      Offset screen(Point3 point) =>
          project(point, camera: topDown, target: origin, size: size).offset;
      expect(screen(origin), const Offset(100, 100));
      final north = screen(const Point3(0, 0.1, 0));
      expect(north.dx, closeTo(100, 0.001));
      expect(north.dy, lessThan(100));
      expect(screen(const Point3(0.1, 0, 0)).dx, greaterThan(100));
    });

    test('closer things look bigger', () {
      // Looking down, a higher point is nearer the camera.
      final high = project(
        const Point3(0, 0, 0.2),
        camera: topDown,
        target: origin,
        size: size,
      );
      expect(high.scale, greaterThan(1));
    });

    test('from the side, higher points are higher on the screen', () {
      const side = Camera3D(pitch: 0.2);
      final ground =
          project(origin, camera: side, target: origin, size: size).offset;
      final hill = project(
        const Point3(0, 0, 0.1),
        camera: side,
        target: origin,
        size: size,
      ).offset;
      expect(hill.dy, lessThan(ground.dy));
    });

    test('the chase camera looks the way the car is going', () {
      expect(chaseYaw(origin, const Point3(0, 1, 0)), 0); // North
      expect(chaseYaw(origin, const Point3(1, 0, 0)), closeTo(math.pi / 2, 1e-9));
      expect(chaseYaw(origin, origin), isNull); // Not moving
    });

    test('turnToward goes the short way round', () {
      double degrees(double d) => d * math.pi / 180;
      final halfway = turnToward(degrees(350), degrees(10), 0.5);
      // Halfway from 350 to 10 is 360, which is the same as 0.
      expect(math.cos(halfway), closeTo(1, 1e-9));
      expect(math.sin(halfway), closeTo(0, 1e-9));
    });
  });

  group('track space and positions', () {
    test('fit centres the track, and stretches the hills', () {
      final space = TrackSpace.fit(const [
        Point3(0, 0, 10),
        Point3(1000, 500, 30),
      ]);
      final corner = space.toUnits(const Point3(1000, 500, 30));
      expect(corner.x, closeTo(0.5, 1e-9));
      expect(corner.y, closeTo(0.25, 1e-9));
      expect(corner.z, closeTo(20 / 1000 * 4, 1e-9)); // Lifted 4 times
    });

    test('position3At slides the height too', () {
      final points = [
        CarLocation(driverNumber: 1, date: at(0), x: 0, y: 0, z: 10),
        CarLocation(driverNumber: 1, date: at(2), x: 20, y: 0, z: 30),
      ];
      final halfway = position3At(points, at(1))!;
      expect(halfway.x, 10);
      expect(halfway.z, 20);
    });

    test('pointAlong3 for the data saver', () {
      const outline = [Point3(0, 0, 0), Point3(10, 0, 5), Point3(20, 0, 10)];
      expect(pointAlong3(outline, 0.5)!.x, 10);
      expect(pointAlong3(outline, 0.75)!.z, 7.5);
      expect(pointAlong3(const [Point3(0, 0, 0)], 0.5), isNull);
    });

    test('OpenF1 locations carry a height', () {
      final location = CarLocation.fromJson(
        jsonDecode(
          '{"driver_number": 1, "date": "2024-09-01T13:00:00+00:00", '
          '"x": 1200, "y": -300, "z": 115}',
        ) as Map<String, dynamic>,
      );
      expect(location.z, 115);
    });
  });
}
