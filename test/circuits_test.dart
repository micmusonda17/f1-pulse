import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitbeat/models/circuit_shape.dart';
import 'package:pitbeat/services/circuit_shapes.dart';
import 'package:pitbeat/widgets/circuit_outline.dart';

// A tiny GeoJSON file: one made-up track, and one point that is not a track.
const tinyGeoJson = '''
{
  "type": "FeatureCollection",
  "features": [
    {"type": "Feature",
     "properties": {"id": "xx-2000", "Name": "Test Ring",
                    "length": 4200, "firstgp": 2001},
     "geometry": {"type": "LineString",
                  "coordinates": [[10.0, 60.0], [11.0, 60.0],
                                  [11.0, 61.0], [10.0, 60.0]]}},
    {"type": "Feature",
     "properties": {"id": "a-point"},
     "geometry": {"type": "Point", "coordinates": [10.0, 60.0]}}
  ]
}
''';

void main() {
  group('parseCircuitShapes', () {
    test('reads each track and skips anything that is not a line', () {
      final shapes = parseCircuitShapes(tinyGeoJson);
      expect(shapes.keys.toList(), ['xx-2000']);
      final ring = shapes['xx-2000']!;
      expect(ring.name, 'Test Ring');
      expect(ring.lengthText, '4.200 km');
      expect(ring.firstGrandPrix, 2001);
      expect(ring.points.length, 4);
    });

    test('shrinks longitude by cos(latitude) so tracks keep their shape', () {
      final ring = parseCircuitShapes(tinyGeoJson)['xx-2000']!;
      // The average latitude is (60 + 60 + 61 + 60) / 4 = 60.25 degrees.
      final squeeze = math.cos(60.25 * math.pi / 180);
      expect(ring.points[1].dx, closeTo(11 * squeeze, 1e-9));
      expect(ring.points[1].dy, 60); // Latitude stays as it is
    });
  });

  group('fitToBox', () {
    const square = [Offset(0, 0), Offset(10, 0), Offset(10, 10), Offset(0, 10)];

    test('keeps the proportions, centres the shape and puts north up', () {
      // The box is 100 x 50, so the 10 x 10 square becomes 50 x 50 in the
      // middle. North (y = 10) ends up at the top of the screen (y = 0).
      expect(fitToBox(square, const Size(100, 50)), const [
        Offset(25, 50),
        Offset(75, 50),
        Offset(75, 0),
        Offset(25, 0),
      ]);
    });

    test('a straight line has no shape to draw', () {
      const line = [Offset(0, 0), Offset(5, 0)];
      expect(fitToBox(line, const Size(10, 10)), isEmpty);
    });
  });

  group('the real circuits file', () {
    // Tests run from the project folder, so we can read the asset directly.
    final shapes = parseCircuitShapes(
      File('assets/circuits/f1-circuits.geojson').readAsStringSync(),
    );

    test('every circuit id in the table has a shape in the file', () {
      for (final entry in circuitShapeIds.entries) {
        expect(
          shapes.containsKey(entry.value),
          isTrue,
          reason: '${entry.key} should match ${entry.value}',
        );
      }
    });

    test('every shape has enough points to draw', () {
      for (final shape in shapes.values) {
        expect(shape.points.length, greaterThan(50), reason: shape.name);
      }
    });
  });
}
