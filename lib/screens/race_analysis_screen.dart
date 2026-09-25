import 'package:flutter/material.dart';

import '../models/openf1_models.dart';
import '../services/openf1_api.dart';
import '../stats/race_story.dart';
import '../stats/strategy.dart';
import '../theme.dart';
import '../tracker/tracker_math.dart';
import '../utils/formatting.dart';
import '../widgets/common_widgets.dart';
import '../widgets/driver_widgets.dart';
import '../widgets/race_widgets.dart';
import '../widgets/spoiler_gate.dart';
import '../widgets/strategy_chart.dart';

/// Everything the analysis needs from OpenF1, downloaded once.
class AnalysisData {
  const AnalysisData({
    required this.drivers,
    required this.positions,
    required this.laps,
    required this.pitStops,
    required this.stints,
    required this.messages,
  });

  final Map<int, DriverInfo> drivers;
  final List<PositionUpdate> positions;
  final List<Lap> laps;
  final List<PitStop> pitStops;
  final List<Stint> stints;
  final List<RaceControlMessage> messages;
}

/// After a session (Chapter 51): the story of a race, every lap's sector
/// times, and the fastest driver on each lap. For practice and qualifying,
/// everyone's best lap with its sectors.
class RaceAnalysisScreen extends StatefulWidget {
  const RaceAnalysisScreen({super.key, required this.session});

  final OpenF1Session session;

  @override
  State<RaceAnalysisScreen> createState() => _RaceAnalysisScreenState();
}

class _RaceAnalysisScreenState extends State<RaceAnalysisScreen> {
  late Future<AnalysisData> _data = _load();

  bool get _isRace => widget.session.type == 'Race';

  Future<AnalysisData> _load() async {
    final api = OpenF1Api.instance;
    final key = widget.session.sessionKey;
    final drivers = await api.getDrivers(key);
    final positions = await api.getPositions(key);
    positions.sort((a, b) => a.date.compareTo(b.date));
    return AnalysisData(
      drivers: {for (final driver in drivers) driver.number: driver},
      positions: positions,
      laps: await api.getLaps(key),
      pitStops: await api.getPitStops(key),
      stints: await api.getStints(key),
      messages: await api.getRaceControl(key),
    );
  }

  void _retry() => setState(() => _data = _load());

  @override
  Widget build(BuildContext context) {
    final tabs = _isRace
        ? const [
            Tab(text: 'Story'),
            Tab(text: 'Strategy'),
            Tab(text: 'Lap times'),
            Tab(text: 'Fastest laps'),
          ]
        : const [Tab(text: 'Best laps'), Tab(text: 'Tyres')];

    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.session.title),
          // Scrollable: four tabs do not fit across a small phone.
          bottom: TabBar(tabs: tabs, isScrollable: _isRace),
        ),
        body: SpoilerGate(
          topic: 'analysis-${widget.session.sessionKey}',
          what: 'The analysis',
          child: FutureBuilder<AnalysisData>(
            future: _data,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return ErrorView(
                  message: '${snapshot.error}',
                  onRetry: _retry,
                );
              }
              final data = snapshot.data;
              if (data == null) {
                return const LoadingView(message: 'Reading the session');
              }
              return TabBarView(
                children: _isRace
                    ? [
                        StoryTab(data: data),
                        StrategyTab(data: data, isRace: true),
                        LapTimesTab(data: data),
                        FastestLapsTab(data: data),
                      ]
                    : [
                        BestLapsTab(data: data),
                        StrategyTab(data: data, isRace: false),
                      ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Story
// ----------------------------------------------------------------------

/// The headlines, then every key moment with its lap.
class StoryTab extends StatelessWidget {
  const StoryTab({super.key, required this.data});

  final AnalysisData data;

  @override
  Widget build(BuildContext context) {
    final story = raceStory(
      names: {
        for (final driver in data.drivers.values) driver.number: driver.acronym,
      },
      positions: data.positions,
      laps: data.laps,
      pitStops: data.pitStops,
      stints: data.stints,
      messages: data.messages,
    );
    if (story.moments.isEmpty) {
      return const Center(child: Text('No story for this session yet.'));
    }

    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Card(
          margin: const EdgeInsets.all(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in story.headlines)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                      line,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SectionHeader('How it happened'),
        for (final moment in story.moments)
          ListTile(
            dense: true,
            leading: SizedBox(
              width: 64,
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    child: Text(
                      'L${moment.lap}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: F1Colors.muted,
                      ),
                    ),
                  ),
                  Icon(
                    momentIcon(moment.kind),
                    size: 20,
                    color: momentColour(moment.kind),
                  ),
                ],
              ),
            ),
            title: Text(moment.text),
          ),
      ],
    );
  }
}

IconData momentIcon(MomentKind kind) {
  return switch (kind) {
    MomentKind.start => Icons.traffic,
    MomentKind.lead => Icons.emoji_events_outlined,
    MomentKind.pit => Icons.build_circle_outlined,
    MomentKind.safetyCar => Icons.directions_car_filled,
    MomentKind.redFlag => Icons.flag,
    MomentKind.penalty => Icons.gavel,
    MomentKind.retirement => Icons.cancel_outlined,
    MomentKind.fastestLap => Icons.timer_outlined,
    MomentKind.finish => Icons.sports_score,
  };
}

Color momentColour(MomentKind kind) {
  return switch (kind) {
    MomentKind.redFlag || MomentKind.retirement => Colors.red,
    MomentKind.safetyCar => Colors.orange,
    MomentKind.fastestLap => fastestPurple,
    MomentKind.lead || MomentKind.finish => Colors.white,
    _ => F1Colors.muted,
  };
}

// ----------------------------------------------------------------------
// Lap times: one lap of the race at a time
// ----------------------------------------------------------------------

/// Everyone's sector times on one lap, fastest first. The fastest time
/// in each column is purple, as on the TV.
class LapTimesTab extends StatefulWidget {
  const LapTimesTab({super.key, required this.data});

  final AnalysisData data;

  @override
  State<LapTimesTab> createState() => _LapTimesTabState();
}

class _LapTimesTabState extends State<LapTimesTab> {
  int _lap = 1;

  int get _totalLaps {
    var highest = 1;
    for (final lap in widget.data.laps) {
      if (lap.lapNumber > highest) highest = lap.lapNumber;
    }
    return highest;
  }

  void _goTo(int lap) {
    setState(() => _lap = lap.clamp(1, _totalLaps).toInt());
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalLaps;
    final onLap = widget.data.laps.where((lap) => lap.lapNumber == _lap);
    final rows = sortedByTime(onLap);
    final bests = bestsOf(rows);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              IconButton(
                onPressed: _lap > 1 ? () => _goTo(_lap - 1) : null,
                icon: const Icon(Icons.chevron_left),
                tooltip: 'Previous lap',
              ),
              Expanded(
                child: Column(
                  children: [
                    Text(
                      'Lap $_lap of $total',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    if (total > 1)
                      Slider(
                        value: _lap.toDouble(),
                        min: 1,
                        max: total.toDouble(),
                        divisions: total - 1, // One stop per lap
                        onChanged: (value) => _goTo(value.round()),
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _lap < total ? () => _goTo(_lap + 1) : null,
                icon: const Icon(Icons.chevron_right),
                tooltip: 'Next lap',
              ),
            ],
          ),
        ),
        const SectorHeader(),
        Expanded(
          child: ListView(
            children: [
              for (final lap in rows)
                SectorRow(
                  lap: lap,
                  info: widget.data.drivers[lap.driverNumber],
                  bests: bests,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Laps with a time first, fastest first; laps without a time last.
List<Lap> sortedByTime(Iterable<Lap> laps) {
  final list = laps.toList();
  list.sort((a, b) {
    final aTime = a.duration;
    final bTime = b.duration;
    if (aTime == null && bTime == null) return 0;
    if (aTime == null) return 1;
    if (bTime == null) return -1;
    return aTime.compareTo(bTime);
  });
  return list;
}

/// The column titles over the sector rows.
class SectorHeader extends StatelessWidget {
  const SectorHeader({super.key});

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: F1Colors.muted,
      fontSize: 11,
      fontWeight: FontWeight.w700,
    );
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text('DRIVER', style: style)),
          Expanded(child: Text('S1', style: style, textAlign: TextAlign.end)),
          Expanded(child: Text('S2', style: style, textAlign: TextAlign.end)),
          Expanded(child: Text('S3', style: style, textAlign: TextAlign.end)),
          SizedBox(
            width: 76,
            child: Text('LAP', style: style, textAlign: TextAlign.end),
          ),
        ],
      ),
    );
  }
}

/// One driver's lap: three sectors and the lap time, purple where they
/// were the fastest.
class SectorRow extends StatelessWidget {
  const SectorRow({
    super.key,
    required this.lap,
    required this.info,
    required this.bests,
  });

  final Lap lap;
  final DriverInfo? info;
  final LapBests bests;

  @override
  Widget build(BuildContext context) {
    final colour = info?.colour ?? Colors.grey;
    final seconds = lap.duration;

    // One sector time, purple if it was the fastest.
    Widget time(double? value, double? best) {
      final isBest = value != null && value == best;
      return Expanded(
        child: Text(
          value == null ? '-' : value.toStringAsFixed(3),
          textAlign: TextAlign.end,
          style: TextStyle(
            fontWeight: isBest ? FontWeight.w900 : FontWeight.w400,
            color: isBest ? fastestPurple : null,
            // Every digit the same width, so the columns line up.
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Row(
              children: [
                TeamColourBar(colour: colour, height: 20),
                const SizedBox(width: 6),
                Text(
                  info?.acronym ?? '${lap.driverNumber}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          time(lap.sectors[0], bests.sectors[0]),
          time(lap.sectors[1], bests.sectors[1]),
          time(lap.sectors[2], bests.sectors[2]),
          SizedBox(
            width: 76,
            child: lap.isPitOutLap && seconds == null
                ? const Text(
                    'PIT OUT',
                    textAlign: TextAlign.end,
                    style: TextStyle(color: F1Colors.muted, fontSize: 11),
                  )
                : Text(
                    seconds == null ? '-' : formatLapTime(seconds),
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: seconds != null && seconds == bests.lap
                          ? fastestPurple
                          : null,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Fastest laps: who was quickest on every lap
// ----------------------------------------------------------------------

class FastestLapsTab extends StatelessWidget {
  const FastestLapsTab({super.key, required this.data});

  final AnalysisData data;

  @override
  Widget build(BuildContext context) {
    final byLap = fastestEachLap(data.laps);
    final numbers = byLap.keys.toList()..sort();
    final overall = bestsOf(byLap.values).lap;

    // Who was fastest on the most laps.
    final counts = <int, int>{};
    for (final lap in byLap.values) {
      counts[lap.driverNumber] = (counts[lap.driverNumber] ?? 0) + 1;
    }
    final top = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    String name(int number) =>
        data.drivers[number]?.acronym ?? '#$number';

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (top.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Fastest on the most laps: ${name(top.first.key)}, '
              '${top.first.value} of ${numbers.length}.',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        for (final number in numbers)
          ListTile(
            dense: true,
            leading: SizedBox(
              width: 40,
              child: Text(
                'L$number',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: F1Colors.muted,
                ),
              ),
            ),
            title: Text(name(byLap[number]!.driverNumber)),
            trailing: Text(
              formatLapTime(byLap[number]!.duration!),
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: byLap[number]!.duration == overall
                    ? fastestPurple
                    : null,
              ),
            ),
          ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// Best laps: practice and qualifying
// ----------------------------------------------------------------------

/// Everyone's best lap of the session with its sectors, fastest first.
class BestLapsTab extends StatelessWidget {
  const BestLapsTab({super.key, required this.data});

  final AnalysisData data;

  @override
  Widget build(BuildContext context) {
    final best = <int, Lap>{};
    for (final entry in lapsByDriver(data.laps).entries) {
      final fastest = fastestLap(entry.value);
      if (fastest != null) best[entry.key] = fastest;
    }
    final rows = sortedByTime(best.values);
    // Purple is the best sector of anyone's lap, not only best laps.
    final bests = bestsOf(data.laps);

    if (rows.isEmpty) {
      return const Center(child: Text('No lap times in this session.'));
    }
    return Column(
      children: [
        const SectorHeader(),
        Expanded(
          child: ListView(
            children: [
              for (final lap in rows)
                SectorRow(
                  lap: lap,
                  info: data.drivers[lap.driverNumber],
                  bests: bests,
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------------
// Strategy: everyone's tyres and pit stops (Chapter 54)
// ----------------------------------------------------------------------

/// The whole session's strategy chart, in finishing order.
class StrategyTab extends StatelessWidget {
  const StrategyTab({super.key, required this.data, required this.isRace});

  final AnalysisData data;
  final bool isRace;

  @override
  Widget build(BuildContext context) {
    final positions = data.positions;
    final order = positions.isEmpty
        ? data.drivers.keys.toList()
        : runningOrderAt(positions, positions.last.date);
    var totalLaps = 1;
    for (final lap in data.laps) {
      if (lap.lapNumber > totalLaps) totalLaps = lap.lapNumber;
    }
    return StrategyChart(
      strategies: strategies(
        order: order,
        stints: data.stints,
        pitStops: data.pitStops,
        lapsByDriver: lapsByDriver(data.laps),
      ),
      drivers: data.drivers,
      totalLaps: totalLaps,
      countStops: isRace,
    );
  }
}

