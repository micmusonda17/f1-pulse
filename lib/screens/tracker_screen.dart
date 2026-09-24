import 'package:flutter/material.dart';

import '../models/openf1_models.dart';
import '../theme.dart';
import '../tracker/track_painter.dart';
import '../tracker/tracker_controller.dart';
import '../utils/formatting.dart';
import '../widgets/common_widgets.dart';
import '../widgets/driver_widgets.dart';

/// The map: the track and cars on top, the controls, then the running order.
class TrackerScreen extends StatefulWidget {
  const TrackerScreen({super.key, required this.session, required this.mode});

  final OpenF1Session session;
  final TrackerMode mode;

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  late final TrackerController _controller;
  double? _dragSeconds; // Where the slider is while your finger is on it

  @override
  void initState() {
    super.initState();
    _controller = TrackerController(session: widget.session, mode: widget.mode);
    _controller.start();
  }

  @override
  void dispose() {
    _controller.dispose(); // Stops the clock and the downloads
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.session.title),
        actions: [
          if (widget.mode == TrackerMode.live)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: LiveBadge(),
            ),
        ],
      ),
      // ListenableBuilder runs builder() again every time the controller
      // calls notifyListeners(). That is ten times a second while playing.
      body: ListenableBuilder(
        listenable: _controller,
        builder: (context, child) {
          final error = _controller.error;
          if (error != null) return ErrorView(message: error);
          if (_controller.isLoading) {
            return LoadingView(message: _controller.message);
          }

          final message = _controller.message;
          final lap = _controller.currentLap;
          final timeLeft = _controller.timeLeft;
          return Column(
            children: [
              Expanded(
                flex: 5,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  // A Stack puts its children on top of each other: the map
                  // first, then the lap counter (races) or the session clock
                  // (practice) in the top left corner.
                  child: Stack(
                    children: [
                      CustomPaint(
                        painter: TrackPainter(
                          outline: _controller.trackOutline,
                          cars: _controller.carPositions,
                          drivers: _controller.drivers,
                        ),
                        child: const SizedBox.expand(),
                      ),
                      if (lap != null)
                        Positioned(
                          top: 0,
                          left: 0,
                          child: MapBadge(
                            label: 'LAP ',
                            value: '$lap',
                            suffix: _controller.totalLaps == null
                                ? null
                                : '/${_controller.totalLaps}',
                          ),
                        ),
                      if (timeLeft != null)
                        Positioned(
                          top: 0,
                          left: 0,
                          child: MapBadge(
                            label: 'TIME LEFT ',
                            value: formatMinutes(timeLeft),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (widget.mode == TrackerMode.replay)
                _buildReplayControls()
              else
                _buildLiveBar(),
              const Divider(height: 1),
              Expanded(
                flex: 4,
                child: Leaderboard(
                  order: _controller.runningOrder,
                  drivers: _controller.drivers,
                  bestLaps: _controller.showsLapTimes
                      ? _controller.bestLaps
                      : null,
                  inGarage: _controller.inGarage,
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReplayControls() {
    final c = _controller;
    final total = c.length.inSeconds.toDouble();
    final current =
        c.elapsed.inSeconds.clamp(0, c.length.inSeconds).toDouble();
    final shown = _dragSeconds ?? current;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Column(
        children: [
          Row(
            children: [
              IconButton.filled(
                onPressed: c.isPlaying ? c.pause : c.play,
                icon: Icon(c.isPlaying ? Icons.pause : Icons.play_arrow),
                tooltip: c.isPlaying ? 'Pause' : 'Play',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatClock(c.clock),
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      '+${formatElapsed(Duration(seconds: shown.round()))} '
                      'into the session',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                onPressed: c.cycleSpeed,
                child: Text('${c.speed}x'),
              ),
            ],
          ),
          Slider(
            value: shown.clamp(0.0, total > 0 ? total : 1.0).toDouble(),
            max: total > 0 ? total : 1.0,
            onChanged: (value) => setState(() => _dragSeconds = value),
            onChangeEnd: (value) {
              setState(() => _dragSeconds = null);
              final target = widget.session.start.add(
                Duration(seconds: value.round()),
              );
              c.seekTo(target);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLiveBar() {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          const LiveBadge(),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Showing ${formatClock(_controller.clock)}, '
              'a few seconds behind real time',
            ),
          ),
        ],
      ),
    );
  }
}

/// A small box in the corner of the map, like the TV graphics:
/// "LAP 23/51" in races, "TIME LEFT 34:12" in practice.
/// Live races show just "LAP 23": nobody knows the last lap in advance.
class MapBadge extends StatelessWidget {
  const MapBadge({
    super.key,
    required this.label,
    required this.value,
    this.suffix,
  });

  final String label; // "LAP ", in red
  final String value; // "23", big and bold
  final String? suffix; // "/51", in grey. Optional.

  @override
  Widget build(BuildContext context) {
    final grey = suffix;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: F1Colors.surface,
        borderRadius: BorderRadius.circular(6),
      ),
      // Text.rich: one line of text with a different style for each part.
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: label,
              style: const TextStyle(
                color: F1Colors.red,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
            ),
            if (grey != null)
              TextSpan(
                text: grey,
                style: const TextStyle(
                  color: F1Colors.muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A small red LIVE label.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.red,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        'LIVE',
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// The running order under the map.
class Leaderboard extends StatelessWidget {
  const Leaderboard({
    super.key,
    required this.order,
    required this.drivers,
    this.bestLaps,
    this.inGarage = const {},
  });

  final List<int> order; // Driver numbers, leader first
  final Map<int, DriverInfo> drivers;
  final Map<int, double>? bestLaps; // Practice and qualifying only
  final Set<int> inGarage;

  @override
  Widget build(BuildContext context) {
    if (order.isEmpty) {
      return const Center(child: Text('Waiting for the running order'));
    }
    final times = bestLaps;
    // The fastest time so far: every gap is measured from it.
    double? fastest;
    if (times != null) {
      for (final seconds in times.values) {
        if (fastest == null || seconds < fastest) fastest = seconds;
      }
    }

    return ListView.builder(
      itemCount: order.length,
      itemBuilder: (context, index) {
        final number = order[index];
        final driver = drivers[number];
        final colour = driver?.colour ?? Colors.grey;
        return ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  'P${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              TeamColourBar(colour: colour, height: 28),
              const SizedBox(width: 8),
              DriverAvatar(
                photoUrl: driver?.headshotUrl,
                colour: colour,
                code: driver?.acronym ?? '$number',
                size: 32,
              ),
            ],
          ),
          title: Text(driver?.fullName ?? 'Car $number'),
          subtitle: Text(
            inGarage.contains(number)
                ? '${driver?.team ?? ''}  ·  In the garage'
                : driver?.team ?? '',
          ),
          trailing: Text(
            times == null
                ? driver?.acronym ?? '$number'
                : lapTimeOrGap(times[number], fastest),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      },
    );
  }
}

/// What the timing screen shows for one driver: the fastest driver's time
/// ("1:32.456"), everyone else's gap to it ("+0.234"), or "No time".
String lapTimeOrGap(double? seconds, double? fastest) {
  if (seconds == null || fastest == null) return 'No time';
  if (seconds == fastest) return formatLapTime(seconds);
  return '+${(seconds - fastest).toStringAsFixed(3)}';
}
