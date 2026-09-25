import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/openf1_models.dart';

/// Draws the circuit and a coloured dot for every car.
///
/// OpenF1 coordinates are in tenths of a metre, with y pointing UP.
/// The screen is in pixels, with y pointing DOWN. So before drawing
/// anything we work out how to squash the track into the space we have,
/// and we flip it upside down.
class TrackPainter extends CustomPainter {
  TrackPainter({
    required this.outline,
    required this.cars,
    required this.drivers,
    this.outCars = const {},
  });

  final List<Offset> outline; // Track shape, in OpenF1 coordinates
  final Map<int, Offset> cars; // Driver number -> OpenF1 coordinates
  final Map<int, DriverInfo> drivers;
  final Set<int> outCars; // Retired: grey, where they stopped (Chapter 52)

  @override
  void paint(Canvas canvas, Size size) {
    // Use the track to decide the scale. If we have no track, use the cars.
    final reference = outline.isNotEmpty ? outline : cars.values.toList();
    if (reference.isEmpty) return;

    // 1. Find the box that the whole track fits inside.
    var minX = reference.first.dx;
    var maxX = minX;
    var minY = reference.first.dy;
    var maxY = minY;
    for (final point in reference) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }
    final trackWidth = maxX - minX;
    final trackHeight = maxY - minY;
    if (trackWidth == 0 || trackHeight == 0) return;

    // 2. Pick one scale for both directions so the track does not stretch.
    const padding = 24.0;
    final scale = math.min(
      (size.width - padding * 2) / trackWidth,
      (size.height - padding * 2) / trackHeight,
    );
    // Centre it.
    final left = (size.width - trackWidth * scale) / 2;
    final top = (size.height - trackHeight * scale) / 2;

    // Turns an OpenF1 point into a screen point. Note maxY - y: the flip.
    Offset toScreen(Offset point) => Offset(
          left + (point.dx - minX) * scale,
          top + (maxY - point.dy) * scale,
        );

    // 3. Draw the track: a wide faint line with a thin bright line on top.
    if (outline.length > 1) {
      final path = Path();
      final first = toScreen(outline.first);
      path.moveTo(first.dx, first.dy);
      for (final point in outline.skip(1)) {
        final screenPoint = toScreen(point);
        path.lineTo(screenPoint.dx, screenPoint.dy);
      }
      path.close();

      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white24
          ..style = PaintingStyle.stroke
          ..strokeWidth = 12
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white70
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }

    // 4. Draw every car: a dot in the team colour and the driver's code.
    //    A car that is out is grey.
    for (final entry in cars.entries) {
      final position = toScreen(entry.value);
      final driver = drivers[entry.key];
      final out = outCars.contains(entry.key);
      final colour =
          out ? Colors.grey.shade700 : (driver?.colour ?? Colors.grey);

      canvas.drawCircle(position, 7, Paint()..color = colour);
      canvas.drawCircle(
        position,
        7,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      final label = TextPainter(
        text: TextSpan(
          text: driver?.acronym ?? '${entry.key}',
          style: TextStyle(
            color: out ? Colors.white38 : Colors.white,
            fontSize: 10,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      label.paint(canvas, position + Offset(9, -label.height / 2));
      label.dispose();
    }
  }

  // The cars move every tick, so always repaint.
  @override
  bool shouldRepaint(covariant TrackPainter oldDelegate) => true;
}
