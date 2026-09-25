import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/openf1_models.dart';
import 'tracker_math.dart';

// The 3D view (Chapter 55). OpenF1's GPS points have a height (z) as well
// as x and y, so the track can be drawn with its real hills. No 3D engine:
// the maths a camera does, then ordinary 2D drawing on a Canvas.

/// A point in 3D: x to the east, y to the north, z up.
class Point3 {
  const Point3(this.x, this.y, this.z);

  final double x;
  final double y;
  final double z;

  /// Part of the way from here to [to]: 0.0 is here, 1.0 is there.
  Point3 lerp(Point3 to, double t) => Point3(
        x + (to.x - x) * t,
        y + (to.y - y) * t,
        z + (to.z - z) * t,
      );
}

Point3 pointOf(CarLocation location) =>
    Point3(location.x, location.y, location.z);

/// Where a car is at [time], with its height: positionAt (Chapter 23) in 3D.
Point3? position3At(List<CarLocation> points, DateTime time) {
  if (points.isEmpty) return null;
  final after = firstIndexAfter(points, time);
  if (after == 0) return pointOf(points.first);
  if (after == points.length) return pointOf(points.last);

  final before = points[after - 1];
  final next = points[after];
  final gap = next.date.difference(before.date).inMicroseconds;
  if (gap == 0) return pointOf(next);
  final fraction = time.difference(before.date).inMicroseconds / gap;
  return pointOf(before).lerp(pointOf(next), fraction);
}

/// Data saver in 3D: the point [fraction] of the way round [outline], the
/// same idea as positionFromLaps (Chapter 43).
Point3? pointAlong3(List<Point3> outline, double fraction) {
  if (outline.length < 2) return null;
  final position = fraction.clamp(0.0, 1.0).toDouble() * (outline.length - 1);
  final index = position.floor();
  final next = math.min(index + 1, outline.length - 1);
  return outline[index].lerp(outline[next], position - index);
}

/// Shrinks OpenF1's coordinates (thousands of units across) into a box
/// about one unit wide around (0, 0), with the lowest point at height 0.
/// Hills are stretched [lift] times: a 40 metre climb on a 5 kilometre lap
/// would hardly show otherwise.
class TrackSpace {
  const TrackSpace({
    required this.centreX,
    required this.centreY,
    required this.lowest,
    required this.scale,
    this.lift = 4,
  });

  factory TrackSpace.fit(Iterable<Point3> points, {double lift = 4}) {
    var minX = double.infinity;
    var maxX = double.negativeInfinity;
    var minY = double.infinity;
    var maxY = double.negativeInfinity;
    var minZ = double.infinity;
    for (final point in points) {
      minX = math.min(minX, point.x);
      maxX = math.max(maxX, point.x);
      minY = math.min(minY, point.y);
      maxY = math.max(maxY, point.y);
      minZ = math.min(minZ, point.z);
    }
    if (minX > maxX) {
      return const TrackSpace(centreX: 0, centreY: 0, lowest: 0, scale: 1);
    }
    final size = math.max(maxX - minX, maxY - minY);
    return TrackSpace(
      centreX: (minX + maxX) / 2,
      centreY: (minY + maxY) / 2,
      lowest: minZ,
      scale: size == 0 ? 1 : 1 / size,
      lift: lift,
    );
  }

  final double centreX;
  final double centreY;
  final double lowest;
  final double scale;
  final double lift;

  Point3 toUnits(Point3 point) => Point3(
        (point.x - centreX) * scale,
        (point.y - centreY) * scale,
        (point.z - lowest) * scale * lift,
      );
}

/// Where the camera is: turned [yaw] radians around the track (0 looks
/// north), tilted [pitch] radians down from the horizon (pi / 2 looks
/// straight down, like the 2D map), and [zoom] times closer.
class Camera3D {
  const Camera3D({this.yaw = 0, this.pitch = 0.75, this.zoom = 1});

  final double yaw;
  final double pitch;
  final double zoom;

  Camera3D copyWith({double? yaw, double? pitch, double? zoom}) => Camera3D(
        yaw: yaw ?? this.yaw,
        pitch: pitch ?? this.pitch,
        zoom: zoom ?? this.zoom,
      );
}

/// A point on the screen, how far away it is, and how big things there
/// look: 1.0 at the target, less further away, more closer.
class Projected {
  const Projected(this.offset, this.depth, this.scale);

  final Offset offset;
  final double depth;
  final double scale;
}

/// How far the camera sits from what it looks at, in track units.
const double cameraDistance = 2.2;

/// The camera's maths. Turn the world around the up axis by the yaw, tilt
/// it by the pitch, then divide by the distance so that far things look
/// smaller: perspective. [target] is the point the camera looks at, which
/// ends up in the middle of the screen.
Projected project(
  Point3 point, {
  required Camera3D camera,
  required Point3 target,
  required Size size,
}) {
  final x = point.x - target.x;
  final y = point.y - target.y;
  final z = point.z - target.z;

  // 1. Turn around the vertical axis.
  final cosYaw = math.cos(camera.yaw);
  final sinYaw = math.sin(camera.yaw);
  final right = x * cosYaw - y * sinYaw;
  final forward = x * sinYaw + y * cosYaw; // Away from the camera

  // 2. Tilt. Looking straight down, "up the screen" is forward; looking
  //    along the ground, it is height.
  final sinPitch = math.sin(camera.pitch);
  final cosPitch = math.cos(camera.pitch);
  final up = forward * sinPitch + z * cosPitch;
  final depth = forward * cosPitch - z * sinPitch;

  // 3. Perspective: further away, smaller.
  final scale = cameraDistance / math.max(cameraDistance + depth, 0.05);
  final pixels = math.min(size.width, size.height) * 0.85 * camera.zoom;
  return Projected(
    Offset(
      size.width / 2 + right * scale * pixels,
      size.height / 2 - up * scale * pixels,
    ),
    depth,
    scale,
  );
}

/// The yaw that puts the camera behind a car moving from [before] to
/// [now], looking the way it is going. Null if it has not moved.
double? chaseYaw(Point3 before, Point3 now) {
  final dx = now.x - before.x;
  final dy = now.y - before.y;
  if (dx * dx + dy * dy < 1e-9) return null;
  return math.atan2(dx, dy);
}

/// Turns the angle [from] part of the way towards [to], the short way
/// round: from 350 degrees to 10 goes up through 360, not down through 180.
double turnToward(double from, double to, double amount) {
  final difference = math.atan2(math.sin(to - from), math.cos(to - from));
  return from + difference * amount;
}

double _within(double value, double low, double high) =>
    math.min(math.max(value, low), high);

/// Draws the 3D view: a faint grid on the ground, the track's shadow, the
/// track itself shaded by height, then the cars, far ones first.
class Track3DPainter extends CustomPainter {
  Track3DPainter({
    required this.outline,
    required this.cars,
    required this.drivers,
    required this.camera,
    this.follow,
    this.rings = const {},
    this.outCars = const {},
  });

  final List<Point3> outline; // One lap of GPS points, with heights
  final Map<int, Point3> cars; // Driver number -> OpenF1 coordinates
  final Map<int, DriverInfo> drivers;
  final Camera3D camera;
  final int? follow; // The car the camera follows, if any
  final Map<int, Color> rings; // Your drivers: a ring in this colour
  final Set<int> outCars; // Retired or knocked out: drawn in grey

  @override
  void paint(Canvas canvas, Size size) {
    final Iterable<Point3> reference =
        outline.isNotEmpty ? outline : cars.values;
    if (reference.isEmpty) return;
    final space = TrackSpace.fit(reference);
    final followed = follow == null ? null : cars[follow];
    final target =
        followed == null ? const Point3(0, 0, 0) : space.toUnits(followed);

    Projected at(Point3 units) =>
        project(units, camera: camera, target: target, size: size);

    _drawGrid(canvas, at);
    final track = [for (final point in outline) space.toUnits(point)];
    if (track.length > 1) _drawTrack(canvas, track, at);
    _drawCars(canvas, space, at);
  }

  /// Lines on the ground every tenth of the track's width, so the eye can
  /// tell which way is flat.
  void _drawGrid(Canvas canvas, Projected Function(Point3) at) {
    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var i = -6; i <= 6; i++) {
      final v = i / 10;
      canvas.drawLine(
        at(Point3(v, -0.6, 0)).offset,
        at(Point3(v, 0.6, 0)).offset,
        paint,
      );
      canvas.drawLine(
        at(Point3(-0.6, v, 0)).offset,
        at(Point3(0.6, v, 0)).offset,
        paint,
      );
    }
  }

  void _drawTrack(
    Canvas canvas,
    List<Point3> track,
    Projected Function(Point3) at,
  ) {
    final top = [for (final point in track) at(point)];
    final ground = [
      for (final point in track) at(Point3(point.x, point.y, 0)),
    ];

    // 1. The shadow on the ground, and a thin post every so often from the
    //    ground up to the track. The gap between them is the height.
    final shadow = Path()
      ..moveTo(ground.first.offset.dx, ground.first.offset.dy);
    for (final point in ground.skip(1)) {
      shadow.lineTo(point.offset.dx, point.offset.dy);
    }
    shadow.close();
    canvas.drawPath(
      shadow,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 6 * camera.zoom
        ..strokeJoin = StrokeJoin.round,
    );
    final post = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    final every = math.max(1, track.length ~/ 48);
    for (var i = 0; i < track.length; i += every) {
      canvas.drawLine(ground[i].offset, top[i].offset, post);
    }

    // 2. The track, one short piece at a time. Far pieces first, so near
    //    ones are drawn over them. Higher ground is lighter.
    var highest = 0.0;
    for (final point in track) {
      highest = math.max(highest, point.z);
    }
    final pieces = List<int>.generate(track.length, (i) => i)
      ..sort((a, b) => top[b].depth.compareTo(top[a].depth));
    for (final i in pieces) {
      final j = (i + 1) % track.length; // The last piece joins the first
      final near = (top[i].scale + top[j].scale) / 2;
      final height =
          highest == 0 ? 0.0 : (track[i].z + track[j].z) / 2 / highest;
      canvas.drawLine(
        top[i].offset,
        top[j].offset,
        Paint()
          ..color = Color.lerp(const Color(0xFF59606E), Colors.white, height)!
          ..strokeWidth = _within(9 * near * camera.zoom, 2, 30)
          ..strokeCap = StrokeCap.round,
      );
    }

    // 3. The start line: a red dot where the outline begins.
    canvas.drawCircle(
      top.first.offset,
      _within(5 * top.first.scale * camera.zoom, 3, 12),
      Paint()..color = const Color(0xFFE10600),
    );
  }

  void _drawCars(
    Canvas canvas,
    TrackSpace space,
    Projected Function(Point3) at,
  ) {
    final dots = [
      for (final entry in cars.entries)
        _CarDot(entry.key, space.toUnits(entry.value), at),
    ]..sort((a, b) => b.where.depth.compareTo(a.where.depth)); // Far first

    for (final dot in dots) {
      final out = outCars.contains(dot.number);
      final driver = drivers[dot.number];
      final colour =
          out ? Colors.grey.shade700 : (driver?.colour ?? Colors.grey);
      final ring = out ? null : rings[dot.number];
      final big = ring != null || dot.number == follow;
      final radius = _within(
        (big ? 8 : 6) * dot.where.scale * math.sqrt(camera.zoom),
        3,
        20,
      );
      final centre = dot.where.offset;

      // Its shadow on the ground, and a thin line down to it.
      final ground = at(Point3(dot.units.x, dot.units.y, 0)).offset;
      canvas.drawLine(
        ground,
        centre,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.15)
          ..strokeWidth = 1,
      );
      canvas.drawOval(
        Rect.fromCenter(center: ground, width: radius * 2, height: radius),
        Paint()..color = Colors.black.withValues(alpha: 0.4),
      );

      // The car: a ball in the team colour, lit from the top left.
      final ball = Rect.fromCircle(center: centre, radius: radius);
      canvas.drawCircle(
        centre,
        radius,
        Paint()
          ..shader = RadialGradient(
            center: const Alignment(-0.4, -0.5),
            colors: [Color.lerp(colour, Colors.white, 0.55)!, colour],
          ).createShader(ball),
      );
      if (ring != null) {
        canvas.drawCircle(
          centre,
          radius + 3,
          Paint()
            ..color = ring
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.5,
        );
      }
      _label(
        canvas,
        driver?.acronym ?? '${dot.number}',
        centre + Offset(0, -radius - 4),
        bold: big,
        faded: out,
      );
    }
  }

  /// A driver code above a car. Your drivers get a dark box behind theirs.
  void _label(
    Canvas canvas,
    String text,
    Offset bottomCentre, {
    required bool bold,
    required bool faded,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: faded ? Colors.white38 : Colors.white,
          fontSize: bold ? 12 : 9,
          fontWeight: bold ? FontWeight.w900 : FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final topLeft = bottomCentre - Offset(painter.width / 2, painter.height);
    if (bold) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          (topLeft & painter.size).inflate(3),
          const Radius.circular(4),
        ),
        Paint()..color = Colors.black.withValues(alpha: 0.6),
      );
    }
    painter.paint(canvas, topLeft);
    painter.dispose();
  }

  // The cars and the camera move every frame, so always repaint.
  @override
  bool shouldRepaint(covariant Track3DPainter oldDelegate) => true;
}

/// One car on its way to the screen: where it is in track units, and
/// where that lands on the screen.
class _CarDot {
  _CarDot(this.number, this.units, Projected Function(Point3) at)
      : where = at(units);

  final int number;
  final Point3 units;
  final Projected where;
}
