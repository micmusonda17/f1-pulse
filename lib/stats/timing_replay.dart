import 'package:flutter/material.dart';

import '../models/lap_timing.dart';
import '../models/openf1_models.dart';
import '../models/race.dart';
import '../models/race_result.dart';

// A race rebuilt from Jolpica's lap times (Chapter 57), in the shapes the
// tracker already understands: OpenF1's laps, positions and pit stops. So
// the running order, the gaps, who is out, the fastest lap and the pit stop
// chart all work, with no map. Plain maths, tested in
// test/replay_archive_test.dart.

/// Everything the tracker needs for a lap-by-lap replay.
class TimingReplay {
  const TimingReplay({
    required this.drivers,
    required this.laps,
    required this.positions,
    required this.pitStops,
    required this.statusByCode,
    this.chequered,
  });

  final Map<int, DriverInfo> drivers;
  final List<Lap> laps;
  final List<PositionUpdate> positions; // Sorted by time
  final List<PitStop> pitStops;
  final Map<String, String> statusByCode; // "LEC" -> "Engine"
  final DateTime? chequered; // When the winner finished
}

/// Builds the replay. [start] is lights out; each lap starts when the one
/// before it ended. [colours] are team colours by driver code, if known.
TimingReplay timingReplay({
  required DateTime start,
  required List<RaceResult> results,
  required List<LapTiming> timings,
  List<JolpicaPitStop> stops = const [],
  Map<String, Color> colours = const {},
}) {
  // 1. A car number for everyone: their own, or a made-up one for drivers
  //    from before permanent numbers (and for any clash).
  final numbers = <String, int>{}; // Jolpica driverId -> car number
  var spare = 900;
  for (final result in results) {
    final own = int.tryParse(result.driver.number);
    numbers[result.driver.id] =
        own != null && !numbers.containsValue(own) ? own : spare++;
  }
  final drivers = {
    for (final result in results)
      numbers[result.driver.id]!: DriverInfo(
        number: numbers[result.driver.id]!,
        acronym: result.driver.code,
        fullName:
            '${result.driver.firstName} ${result.driver.lastName.toUpperCase()}',
        team: result.team,
        colour: colours[result.driver.code] ?? Colors.grey,
      ),
  };

  // 2. The grid at lights out. Grid 0 is the pit lane: the back.
  int gridSlot(RaceResult result) => result.grid == 0 ? 99 : result.grid;
  final grid = [...results]..sort((a, b) => gridSlot(a).compareTo(gridSlot(b)));
  final positions = [
    for (var i = 0; i < grid.length; i++)
      PositionUpdate(
        driverNumber: numbers[grid[i].driver.id]!,
        date: start,
        position: i + 1,
      ),
  ];

  // 3. Every lap: it starts where the one before ended. And the driver's
  //    place as they cross the line at its end.
  final byDriver = <String, List<LapTiming>>{};
  for (final timing in timings) {
    byDriver.putIfAbsent(timing.driverId, () => []).add(timing);
  }
  final laps = <Lap>[];
  final lapEnds = <String, Map<int, DateTime>>{}; // driverId -> lap -> end
  for (final entry in byDriver.entries) {
    final number = numbers[entry.key];
    if (number == null) continue;
    entry.value.sort((a, b) => a.lap.compareTo(b.lap));
    var clock = start;
    final ends = <int, DateTime>{};
    for (final timing in entry.value) {
      laps.add(
        Lap(
          driverNumber: number,
          lapNumber: timing.lap,
          start: clock,
          duration: timing.seconds,
        ),
      );
      clock = clock.add(Duration(milliseconds: (timing.seconds * 1000).round()));
      ends[timing.lap] = clock;
      positions.add(
        PositionUpdate(
          driverNumber: number,
          date: clock,
          position: timing.position,
        ),
      );
    }
    lapEnds[entry.key] = ends;
  }
  positions.sort((a, b) => a.date.compareTo(b.date));

  // 4. Pit stops. The pit lane runs past the line, so a stop is placed
  //    half its time before the end of the lap it came on.
  final pitStops = [
    for (final stop in stops)
      if (numbers[stop.driverId] case final number?)
        if (lapEnds[stop.driverId]?[stop.lap] case final lapEnd?)
          PitStop(
            driverNumber: number,
            date: lapEnd.subtract(
              Duration(milliseconds: ((stop.seconds ?? 0) * 500).round()),
            ),
            laneSeconds: stop.seconds,
            lapNumber: stop.lap,
          ),
  ]..sort((a, b) => a.date.compareTo(b.date));

  // 5. The chequered flag: when the winner crossed the line for the last
  //    time.
  DateTime? chequered;
  for (final result in results) {
    if (result.position != 1) continue;
    final ends = lapEnds[result.driver.id];
    if (ends != null && ends.isNotEmpty) {
      chequered = ends[ends.keys.reduce((a, b) => a > b ? a : b)];
    }
  }

  return TimingReplay(
    drivers: drivers,
    laps: laps,
    positions: positions,
    pitStops: pitStops,
    statusByCode: {
      for (final result in results) result.driver.code: result.status,
    },
    chequered: chequered,
  );
}

/// The tracker needs an OpenF1 session to show. For a lap-by-lap replay
/// we make one up from the calendar: the race, two hours long. The key is
/// negative so it can never match a real OpenF1 session.
OpenF1Session timingSessionFor(Race race) {
  final start = race.start ?? DateTime.now().toUtc();
  return OpenF1Session(
    sessionKey: -(race.season * 100 + race.round),
    meetingKey: 0,
    name: 'Race',
    type: 'Race',
    location: race.locality,
    country: race.country,
    start: start,
    end: start.add(const Duration(hours: 2)),
    isCancelled: false,
  );
}
