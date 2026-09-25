import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import '../tracker/track3d.dart';
import '../tracker/tracker_controller.dart';

/// The 3D map (Chapter 55). Drag to turn it, pinch to zoom, double tap to
/// reset. It draws every frame, so the cars and the camera glide between
/// the controller's ten ticks a second.
class Track3DView extends StatefulWidget {
  const Track3DView({
    super.key,
    required this.controller,
    this.follow,
    this.rings = const {},
    this.outCars = const {},
  });

  final TrackerController controller;
  final int? follow; // The car to follow with a chase camera
  final Map<int, Color> rings; // Your drivers, ringed in a colour
  final Set<int> outCars; // Drawn in grey

  @override
  State<Track3DView> createState() => _Track3DViewState();
}

class _Track3DViewState extends State<Track3DView>
    with SingleTickerProviderStateMixin {
  static const Camera3D _startCamera = Camera3D();

  // An AnimationController that repeats forever is a simple way to be
  // called once per frame: its listener runs every time the screen redraws.
  late final AnimationController _frames;
  final Stopwatch _watch = Stopwatch()..start();
  Duration _lastFrame = Duration.zero;

  Camera3D _camera = _startCamera;
  double _zoomAtStart = 1; // The zoom when a pinch began
  bool _spin = false; // Slowly turn around the track on its own

  @override
  void initState() {
    super.initState();
    _frames = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 1),
    )
      ..addListener(_onFrame)
      ..repeat();
  }

  @override
  void dispose() {
    _frames.dispose();
    super.dispose();
  }

  /// Once per frame: turn the camera if it is spinning or chasing a car,
  /// and redraw if anything moves.
  void _onFrame() {
    final now = _watch.elapsed;
    final seconds = (now - _lastFrame).inMicroseconds / 1e6;
    _lastFrame = now;

    final controller = widget.controller;
    final follow = widget.follow;
    final moving =
        controller.isPlaying || controller.mode == TrackerMode.live;
    if (!moving && !_spin && follow == null) return; // Nothing to redraw

    var camera = _camera;
    if (_spin) {
      camera = camera.copyWith(yaw: camera.yaw + seconds * 0.25);
    } else if (follow != null) {
      // Chase camera: turn, a little each frame, to look where the car is
      // going. Where it was 0.6 seconds ago to where it is now is its
      // direction.
      final clock = controller.smoothClock();
      final before = controller.carPosition3dAt(
        follow,
        clock.subtract(const Duration(milliseconds: 600)),
      );
      final after = controller.carPosition3dAt(follow, clock);
      final heading =
          before == null || after == null ? null : chaseYaw(before, after);
      if (heading != null) {
        camera = camera.copyWith(
          yaw: turnToward(camera.yaw, heading, math.min(1.0, seconds * 2)),
        );
      }
    }
    setState(() => _camera = camera);
  }

  void _zoomBy(double factor) {
    setState(() {
      _camera = _camera.copyWith(
        zoom: (_camera.zoom * factor).clamp(0.6, 6.0).toDouble(),
      );
    });
  }

  void _reset() {
    setState(() {
      _camera = _startCamera;
      _spin = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final follow = widget.follow;
    // Following a car: much closer, so you can see who is around it.
    final camera =
        follow == null ? _camera : _camera.copyWith(zoom: _camera.zoom * 3);

    return Stack(
      children: [
        GestureDetector(
          onScaleStart: (details) => _zoomAtStart = _camera.zoom,
          onScaleUpdate: (details) {
            setState(() {
              if (details.pointerCount >= 2) {
                // Two fingers: pinch to zoom.
                final zoom = _zoomAtStart * details.scale;
                _camera = _camera.copyWith(
                  zoom: zoom.clamp(0.6, 6.0).toDouble(),
                );
              } else {
                // One finger: sideways turns the track, up and down tilts.
                _spin = false;
                _camera = _camera.copyWith(
                  yaw: _camera.yaw - details.focalPointDelta.dx * 0.008,
                  pitch: (_camera.pitch + details.focalPointDelta.dy * 0.006)
                      .clamp(0.2, 1.5)
                      .toDouble(),
                );
              }
            });
          },
          onDoubleTap: _reset,
          child: CustomPaint(
            painter: Track3DPainter(
              outline: controller.trackOutline3d,
              cars: controller.carPositions3dAt(controller.smoothClock()),
              drivers: controller.drivers,
              camera: camera,
              follow: follow,
              rings: widget.rings,
              outCars: widget.outCars,
            ),
            child: const SizedBox.expand(),
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _MapButton(
                icon: Icons.add,
                tooltip: 'Zoom in',
                onPressed: () => _zoomBy(1.25),
              ),
              _MapButton(
                icon: Icons.remove,
                tooltip: 'Zoom out',
                onPressed: () => _zoomBy(0.8),
              ),
              _MapButton(
                icon: Icons.threesixty,
                tooltip: _spin ? 'Stop turning' : 'Turn slowly',
                selected: _spin,
                onPressed: () => setState(() => _spin = !_spin),
              ),
              _MapButton(
                icon: Icons.center_focus_strong,
                tooltip: 'Reset the view',
                onPressed: _reset,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// A small round button on the map.
class _MapButton extends StatelessWidget {
  const _MapButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: IconButton.filledTonal(
        onPressed: onPressed,
        isSelected: selected,
        tooltip: tooltip,
        visualDensity: VisualDensity.compact,
        iconSize: 18,
        style: IconButton.styleFrom(
          backgroundColor: selected ? F1Colors.red : F1Colors.surfaceHigh,
        ),
        icon: Icon(icon),
      ),
    );
  }
}
