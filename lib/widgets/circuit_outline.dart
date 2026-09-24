import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/circuit_shape.dart';
import '../services/circuit_shapes.dart';
import '../theme.dart';

/// A drawing of a circuit's shape, [size] pixels square.
///
/// Draws nothing if we have no shape for the circuit, so it is always safe
/// to put one next to any race.
class CircuitOutline extends StatefulWidget {
  const CircuitOutline({
    super.key,
    required this.circuitId,
    this.size = 40,
    this.colour = Colors.white70,
    this.strokeWidth = 2,
  });

  final String circuitId; // Jolpica's id, from Race.circuitId
  final double size;
  final Color colour;
  final double strokeWidth;

  @override
  State<CircuitOutline> createState() => _CircuitOutlineState();
}

class _CircuitOutlineState extends State<CircuitOutline> {
  // Made once in initState, not in build. build() can run many times a
  // second, and a new Future every time would start the lookup again.
  late Future<CircuitShape?> _shape;

  @override
  void initState() {
    super.initState();
    _shape = CircuitShapes.instance.shapeFor(widget.circuitId);
  }

  // Flutter keeps this State when the parent rebuilds, even if the new
  // widget is for another circuit. So we check, and look it up again.
  @override
  void didUpdateWidget(CircuitOutline oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.circuitId != widget.circuitId) {
      _shape = CircuitShapes.instance.shapeFor(widget.circuitId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: widget.size,
      child: FutureBuilder<CircuitShape?>(
        future: _shape,
        builder: (context, snapshot) {
          final shape = snapshot.data;
          if (shape == null) return const SizedBox.shrink();
          return CustomPaint(
            painter: CircuitOutlinePainter(
              points: shape.points,
              colour: widget.colour,
              strokeWidth: widget.strokeWidth,
            ),
          );
        },
      ),
    );
  }
}

/// One line of facts under a big circuit drawing:
/// "6.003 km lap  ·  First Grand Prix in 2016".
class CircuitFacts extends StatefulWidget {
  const CircuitFacts({super.key, required this.circuitId});

  final String circuitId;

  @override
  State<CircuitFacts> createState() => _CircuitFactsState();
}

class _CircuitFactsState extends State<CircuitFacts> {
  late final Future<CircuitShape?> _shape =
      CircuitShapes.instance.shapeFor(widget.circuitId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CircuitShape?>(
      future: _shape,
      builder: (context, snapshot) {
        final shape = snapshot.data;
        if (shape == null) return const SizedBox.shrink();
        final facts = [
          if (shape.lengthText != null) '${shape.lengthText} lap',
          if (shape.firstGrandPrix != null)
            'First Grand Prix in ${shape.firstGrandPrix}',
        ];
        return Text(
          facts.join('  ·  '),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: F1Colors.muted,
          ),
        );
      },
    );
  }
}

/// Draws a circuit as one closed line.
class CircuitOutlinePainter extends CustomPainter {
  const CircuitOutlinePainter({
    required this.points,
    required this.colour,
    required this.strokeWidth,
  });

  final List<Offset> points; // From CircuitShape: x east, y north
  final Color colour;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    // Leave room for the line's own thickness at the edges.
    final onScreen = fitToBox(points, size, padding: strokeWidth);
    if (onScreen.length < 2) return;

    final path = Path()..addPolygon(onScreen, true); // true: join the ends
    canvas.drawPath(
      path,
      Paint()
        ..color = colour
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );
  }

  // Unlike the tracker, nothing moves here. Only repaint if something changed.
  @override
  bool shouldRepaint(covariant CircuitOutlinePainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.colour != colour ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}

/// Scales [points] to fit inside [size], keeping the shape's proportions,
/// centres them, and flips them so north is at the top.
///
/// The same three steps as TrackPainter: find the box around the points,
/// pick one scale for both directions, then turn every point into pixels.
/// Screen y grows downwards, so we use maxY - y to flip the drawing.
List<Offset> fitToBox(List<Offset> points, Size size, {double padding = 0}) {
  if (points.isEmpty) return [];

  var minX = points.first.dx;
  var maxX = minX;
  var minY = points.first.dy;
  var maxY = minY;
  for (final point in points) {
    minX = math.min(minX, point.dx);
    maxX = math.max(maxX, point.dx);
    minY = math.min(minY, point.dy);
    maxY = math.max(maxY, point.dy);
  }
  final width = maxX - minX;
  final height = maxY - minY;
  if (width == 0 || height == 0) return []; // A dot or a straight line

  final scale = math.min(
    (size.width - padding * 2) / width,
    (size.height - padding * 2) / height,
  );
  final left = (size.width - width * scale) / 2;
  final top = (size.height - height * scale) / 2;

  return [
    for (final point in points)
      Offset(left + (point.dx - minX) * scale, top + (maxY - point.dy) * scale),
  ];
}
