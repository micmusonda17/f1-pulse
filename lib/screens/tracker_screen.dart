import 'package:flutter/material.dart';

import '../models/openf1_models.dart';
import '../models/race.dart';
import '../services/app_preferences.dart';
import '../services/replay_archive.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import '../tracker/race_status.dart';
import '../tracker/track_painter.dart';
import '../tracker/tracker_controller.dart';
import '../utils/formatting.dart';
import '../widgets/common_widgets.dart';
import '../widgets/driver_widgets.dart';
import '../widgets/race_widgets.dart';
import '../widgets/strategy_chart.dart';
import '../widgets/track_3d_view.dart';
import 'driver_sheet.dart';
import 'race_analysis_screen.dart';

/// The map: the track and cars on top, the controls, then the running order.
class TrackerScreen extends StatefulWidget {
  const TrackerScreen({
    super.key,
    required this.session,
    required this.mode,
    this.timingRace,
  });

  final OpenF1Session session;
  final TrackerMode mode;
  final Race? timingRace; // A lap-by-lap replay from Jolpica (Chapter 57)

  @override
  State<TrackerScreen> createState() => _TrackerScreenState();
}

class _TrackerScreenState extends State<TrackerScreen> {
  late final TrackerController _controller;
  double? _dragSeconds; // Where the slider is while your finger is on it
  bool _show3d = false; // The 3D view instead of the flat map (Chapter 55)
  int? _follow; // The car the 3D camera follows
  bool _showStrategy = false; // Pit stops under the map instead of the order
  String? _favouriteId; // Your drivers, as Jolpica ids, for the 3D view
  List<String> _fantasyIds = [];

  @override
  void initState() {
    super.initState();
    _controller = TrackerController(
      session: widget.session,
      mode: widget.mode,
      saveData: AppPreferences.instance.dataSaver,
      timingRace: widget.timingRace,
    );
    _controller.start();
    _loadMyDrivers();
    // Saving replays in the background waits while this one plays, so its
    // downloads get OpenF1's queue to themselves (Chapter 56).
    ReplayArchive.instance.holdOff();
  }

  /// Your favourite and fantasy drivers get a ring in the 3D view.
  Future<void> _loadMyDrivers() async {
    final settings = SettingsStore();
    final favourite = await settings.getFavouriteDriver();
    final fantasy = await settings.getFantasyDrivers();
    if (!mounted) return;
    setState(() {
      _favouriteId = favourite;
      _fantasyIds = fantasy;
    });
  }

  /// Gold for your favourite driver, white for your fantasy team.
  Map<int, Color> get _rings {
    final drivers = _controller.drivers;
    return {
      for (final number in carNumbersFor(_fantasyIds, drivers))
        number: Colors.white,
      for (final number in carNumbersFor([?_favouriteId], drivers))
        number: const Color(0xFFFFD700),
    };
  }

  /// Everything about one driver, in a sheet from the bottom.
  void _openDriver(int number) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => DriverSheet(
        controller: _controller,
        number: number,
        // No map, nothing to follow: lap-by-lap replays (Chapter 57).
        onFollow: !_controller.hasMap
            ? null
            : () {
                Navigator.pop(sheetContext);
                setState(() {
                  _follow = number;
                  _show3d = true;
                });
              },
      ),
    );
  }

  void _toggle3d() {
    setState(() {
      _show3d = !_show3d;
      if (!_show3d) _follow = null;
    });
    if (_show3d) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Drag to turn, pinch to zoom, double tap to reset. '
            'Tap a driver below to follow them.',
          ),
        ),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose(); // Stops the clock and the downloads
    ReplayArchive.instance.release();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.session.title),
        actions: [
          // Sector times, and the story of a race (Chapters 50 and 51).
          // Not for lap-by-lap replays, which are not OpenF1 sessions.
          if (widget.timingRace == null)
            IconButton(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      RaceAnalysisScreen(session: widget.session),
                ),
              ),
              icon: const Icon(Icons.analytics_outlined),
              tooltip: 'Lap times and analysis',
            ),
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

          final c = _controller;
          final message = c.message;
          final lap = c.currentLap;
          final timeLeft = c.timeLeft;
          final phase = c.qualifyingPhase;
          final raceControl = c.latestMessage;
          final fastest = c.fastestLapSoFar;

          // Who is out, and the order to show: in races, cars still racing
          // first and cars that are out at the bottom, greyed (Chapter 52).
          final out = c.outNotes;
          final order = c.runningOrder;
          final running = [
            for (final number in order)
              if (!out.containsKey(number)) number,
          ];
          final board = c.countsLaps
              ? [
                  ...running,
                  for (final number in order)
                    if (out.containsKey(number)) number,
                  for (final number in out.keys)
                    if (!order.contains(number)) number,
                ]
              : order;

          return Column(
            children: [
              // No map to draw (a lap-by-lap replay): just the lap.
              if (!c.hasMap)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                  child: Row(
                    children: [
                      if (lap != null)
                        MapBadge(
                          label: 'LAP ',
                          value: '$lap',
                          suffix: c.totalLaps == null
                              ? null
                              : '/${c.totalLaps}',
                        ),
                    ],
                  ),
                )
              else
                Expanded(
                  flex: 5,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    // A Stack puts its children on top of each other: the map
                    // first, then the badges in its corners.
                    child: Stack(
                      children: [
                        if (_show3d)
                          Track3DView(
                            controller: c,
                            follow: _follow,
                            rings: _rings,
                            outCars: out.keys.toSet(),
                          )
                        else
                          CustomPaint(
                            painter: TrackPainter(
                              outline: c.trackOutline,
                              cars: c.carPositions,
                              drivers: c.drivers,
                              outCars: out.keys.toSet(),
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
                              suffix: c.totalLaps == null
                                  ? null
                                  : '/${c.totalLaps}',
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
                        if (phase != null)
                          Positioned(
                            top: 0,
                            left: 0,
                            child: MapBadge(label: 'Q', value: '$phase'),
                          ),
                        // The flags, top right (Chapter 53).
                        if (c.hasFlags)
                          Positioned(
                            top: 0,
                            right: 0,
                            child: TrackStatusBadge(state: c.trackState),
                          ),
                        // 2D or 3D, bottom left (Chapter 55).
                        Positioned(
                          left: 0,
                          bottom: 0,
                          child: OutlinedButton.icon(
                            onPressed: _toggle3d,
                            icon: Icon(
                              _show3d ? Icons.map_outlined : Icons.view_in_ar,
                              size: 18,
                            ),
                            label: Text(_show3d ? '2D' : '3D'),
                          ),
                        ),
                        if (_show3d && _follow != null)
                          Positioned(
                            top: 40,
                            left: 0,
                            right: 0,
                            child: Center(
                              child: InputChip(
                                avatar: const Icon(Icons.videocam, size: 16),
                                label: Text(
                                  'Following '
                                  '${c.drivers[_follow]?.acronym ?? '#$_follow'}',
                                ),
                                onDeleted: () => setState(() => _follow = null),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              SessionInfoStrip(
                weather: c.weather,
                fastestLap: fastest,
                fastestCode: fastest == null
                    ? null
                    : c.drivers[fastest.driverNumber]?.acronym,
                lapsToGo: c.lapsToGo,
              ),
              if (raceControl != null) RaceControlBanner(message: raceControl),
              if (message != null)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    message,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              if (c.placesCarsByLaps)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text(
                    c.lapByLap
                        ? 'Lap-by-lap timing from Jolpica: no map, tyres '
                            'or flags'
                        : c.offline
                            ? 'Saved on this phone: cars placed from lap '
                                'times, not GPS'
                            : 'Data saver: cars placed from lap times, not GPS',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: F1Colors.muted,
                    ),
                  ),
                ),
              if (widget.mode == TrackerMode.replay)
                _buildReplayControls()
              else
                _buildLiveBar(),
              const Divider(height: 1),
              // The running order, or everyone's tyres and pit stops
              // (Chapter 54).
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 2),
                child: SegmentedButton<bool>(
                  segments: [
                    const ButtonSegment(
                      value: false,
                      label: Text('Running order'),
                    ),
                    ButtonSegment(
                      value: true,
                      label: Text(c.countsLaps ? 'Pit stops' : 'Tyres'),
                    ),
                  ],
                  selected: {_showStrategy},
                  showSelectedIcon: false,
                  style: const ButtonStyle(
                    visualDensity: VisualDensity.compact,
                  ),
                  onSelectionChanged: (choice) =>
                      setState(() => _showStrategy = choice.first),
                ),
              ),
              Expanded(
                flex: 4,
                child: _showStrategy
                    ? StrategyChart(
                        strategies: c.strategiesNow(board),
                        drivers: c.drivers,
                        totalLaps: c.countsLaps
                            ? (c.totalLaps ?? lap ?? 1)
                            : c.highestLap,
                        countStops: c.countsLaps,
                      )
                    : Leaderboard(
                        order: board,
                        drivers: c.drivers,
                        bestLaps: c.showsLapTimes ? c.bestLaps : null,
                        notes: c.carNotes,
                        tyres: c.tyres,
                        tyreAges: c.tyreAges,
                        out: out,
                        outIsRetired: c.countsLaps,
                        gaps: c.gapsFor(running),
                        fastestLapDriver: fastest?.driverNumber,
                        onTap: _openDriver,
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
    this.notes = const {},
    this.tyres = const {},
    this.tyreAges = const {},
    this.out = const {},
    this.outIsRetired = false,
    this.gaps = const {},
    this.fastestLapDriver,
    this.onTap,
  });

  final List<int> order; // Driver numbers, leader first
  final Map<int, DriverInfo> drivers;
  final Map<int, double>? bestLaps; // Practice and qualifying only
  final Map<int, String> notes; // "In the pit lane", "2 stops"...
  final Map<int, String> tyres; // "SOFT", "MEDIUM"...
  final Map<int, int> tyreAges; // Laps on those tyres
  final Map<int, String> out; // Who is out, and why (Chapter 52)
  final bool outIsRetired; // Races: show OUT instead of a place
  final Map<int, CarGaps> gaps; // Races: interval and gap (Chapter 53)
  final int? fastestLapDriver; // Gets a purple stopwatch
  final void Function(int number)? onTap; // Opens the driver's sheet

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
        final reason = out[number];
        final retired = reason != null && outIsRetired;

        final row = ListTile(
          dense: true,
          visualDensity: VisualDensity.compact,
          onTap: onTap == null ? null : () => onTap!(number),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 32,
                child: Text(
                  retired ? 'OUT' : 'P${index + 1}',
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
          // A driver who is out shows why, instead of the usual notes.
          subtitle: Text(
            reason ?? [driver?.team ?? '', ?notes[number]].join('  ·  '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: retired
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (number == fastestLapDriver) ...[
                      const Icon(
                        Icons.timer_outlined,
                        size: 16,
                        color: fastestPurple,
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (tyres[number] case final compound?) ...[
                      TyreDot(compound: compound, age: tyreAges[number]),
                      const SizedBox(width: 8),
                    ],
                    if (times != null)
                      Text(
                        lapTimeOrGap(times[number], fastest),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      )
                    else
                      _RaceGap(
                        isLeader: index == 0,
                        gaps: gaps[number],
                        code: driver?.acronym ?? '$number',
                      ),
                  ],
                ),
        );
        // Out: the whole row fades to grey.
        return reason == null ? row : Opacity(opacity: 0.45, child: row);
      },
    );
  }
}

/// A race row's timing: the interval to the car ahead in bold, and the
/// gap to the leader under it, like the TV.
class _RaceGap extends StatelessWidget {
  const _RaceGap({
    required this.isLeader,
    required this.gaps,
    required this.code,
  });

  final bool isLeader;
  final CarGaps? gaps;
  final String code;

  @override
  Widget build(BuildContext context) {
    final ahead = gaps?.toAhead;
    final leader = gaps?.toLeader;
    final String top;
    if (isLeader) {
      top = 'Leader';
    } else if (ahead != null) {
      top = formatGap(ahead);
    } else {
      top = code; // Lap 1: no gaps yet
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(top, style: const TextStyle(fontWeight: FontWeight.bold)),
        if (leader != null)
          Text(
            formatGap(leader),
            style: const TextStyle(fontSize: 11, color: F1Colors.muted),
          ),
      ],
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

/// A tyre in its compound's colour with its first letter, like the TV:
/// red S for soft, yellow M, white H, green I for intermediate, blue W.
class TyreDot extends StatelessWidget {
  const TyreDot({super.key, required this.compound, this.age});

  final String compound; // "SOFT", "MEDIUM", "HARD", "INTERMEDIATE", "WET"
  final int? age; // Laps on these tyres, shown beside the dot

  @override
  Widget build(BuildContext context) {
    // The colours live in theme.dart, shared with the strategy chart.
    final colour = F1Colors.tyres[compound] ?? F1Colors.muted;
    final dot = Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: colour, width: 2.5),
      ),
      child: Text(
        compound.isEmpty ? '?' : compound[0], // The first letter
        style: TextStyle(
          color: colour,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    final laps = age;
    if (laps == null) return dot;
    // The tyre's age beside it: "M 12" means mediums that have done 12 laps.
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        dot,
        const SizedBox(width: 4),
        Text(
          '$laps',
          style: const TextStyle(fontSize: 11, color: F1Colors.muted),
        ),
      ],
    );
  }
}

/// The latest message from race control, like the ticker on TV:
/// "SAFETY CAR DEPLOYED", with a stripe in the flag's colour.
class RaceControlBanner extends StatelessWidget {
  const RaceControlBanner({super.key, required this.message});

  final RaceControlMessage message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: F1Colors.surface,
        border: Border(
          left: BorderSide(color: flagColour(message), width: 4),
        ),
      ),
      child: Text(
        message.message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

/// The colour of a race control message: the flag's own colour, orange
/// for the safety car, grey for everything else.
Color flagColour(RaceControlMessage message) {
  final flag = message.flag ?? '';
  if (message.category == 'SafetyCar') return Colors.orange;
  if (flag.contains('RED')) return Colors.red;
  if (flag.contains('YELLOW')) return Colors.amber;
  if (flag.contains('BLUE')) return Colors.blue;
  if (flag.contains('GREEN') || flag == 'CLEAR') return Colors.green;
  if (flag.contains('CHEQUERED')) return Colors.white;
  return F1Colors.muted;
}
