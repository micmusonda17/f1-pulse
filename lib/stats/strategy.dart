import 'dart:math' as math;

import '../models/openf1_models.dart';
import '../tracker/tracker_math.dart';

// Every driver's tyres and pit stops (Chapter 54): the strategy chart in
// the tracker and after the race. Plain maths, tested in
// test/race_status_test.dart.

/// One set of tyres, from one lap to another.
class StintSpan {
  const StintSpan({
    required this.compound,
    required this.fromLap,
    required this.toLap,
    this.tyreAgeAtStart = 0,
  });

  final String compound; // "SOFT", "MEDIUM"...
  final int fromLap;
  final int toLap;
  final int tyreAgeAtStart; // Laps the set had done before (Chapter 50)

  int get laps => toLap - fromLap + 1;
}

/// One trip through the pit lane: when, how long, and the tyres off and on.
class PitVisit {
  const PitVisit({
    required this.lap,
    this.laneSeconds,
    this.stopSeconds,
    this.from,
    this.to,
  });

  final int lap; // The lap they came in on
  final double? laneSeconds; // Pit entry to pit exit
  final double? stopSeconds; // Standing still (recent seasons only)
  final String? from; // The compound that came off
  final String? to; // The compound that went on. Null if it did not change.
}

/// One driver's whole strategy.
class DriverStrategy {
  const DriverStrategy({
    required this.driverNumber,
    required this.stints,
    required this.stops,
  });

  final int driverNumber;
  final List<StintSpan> stints;
  final List<PitVisit> stops;
}

/// Every driver's tyres and pit stops, in [order]. With [until], only what
/// had happened by then: the replay's clock.
List<DriverStrategy> strategies({
  required List<int> order,
  required List<Stint> stints,
  required List<PitStop> pitStops,
  required Map<int, List<Lap>> lapsByDriver,
  DateTime? until,
}) {
  return [
    for (final number in order)
      _strategyOf(
        number,
        stints,
        pitStops,
        lapsByDriver[number] ?? const [],
        until,
      ),
  ];
}

DriverStrategy _strategyOf(
  int number,
  List<Stint> allStints,
  List<PitStop> allStops,
  List<Lap> laps,
  DateTime? until,
) {
  // The last lap this driver had started: the whole race, or up to the clock.
  final lastLap = until == null
      ? (laps.isEmpty ? 0 : laps.last.lapNumber)
      : (driverLapAt(laps, until) ?? 0);
  final shownUpTo = math.max(lastLap, 1);

  final mine = [
    for (final stint in allStints)
      if (stint.driverNumber == number && stint.lapStart <= shownUpTo) stint,
  ]..sort((a, b) => a.lapStart.compareTo(b.lapStart));

  final spans = <StintSpan>[];
  for (var i = 0; i < mine.length; i++) {
    final stint = mine[i];
    final beforeNext = i + 1 < mine.length ? mine[i + 1].lapStart - 1 : null;
    var toLap = stint.lapEnd ?? beforeNext ?? shownUpTo;
    toLap = math.max(math.min(toLap, shownUpTo), stint.lapStart);
    spans.add(
      StintSpan(
        compound: stint.compound,
        fromLap: stint.lapStart,
        toLap: toLap,
        tyreAgeAtStart: stint.tyreAgeAtStart,
      ),
    );
  }

  final stops = [
    for (final stop in allStops)
      if (stop.driverNumber == number &&
          (until == null || !stop.date.isAfter(until)))
        _visit(stop, laps, allStints),
  ];
  return DriverStrategy(driverNumber: number, stints: spans, stops: stops);
}

PitVisit _visit(PitStop stop, List<Lap> laps, List<Stint> stints) {
  final lap = stop.lapNumber ?? driverLapAt(laps, stop.date) ?? 0;
  final before = stintOn(stints, stop.driverNumber, lap);
  final after = stintOn(stints, stop.driverNumber, lap + 1);
  return PitVisit(
    lap: lap,
    laneSeconds: stop.laneSeconds,
    stopSeconds: stop.stopSeconds,
    from: before?.compound,
    // The same stint after the stop: a penalty or a repair, no new tyres.
    to: after == null || after.lapStart <= lap ? null : after.compound,
  );
}

/// "MEDIUM" as people write it: "Medium".
String compoundName(String compound) => compound.isEmpty
    ? compound
    : compound[0] + compound.substring(1).toLowerCase();

/// "Medium to hard", "Soft", or "" when the tyres are unknown.
String tyreChange(PitVisit visit) {
  final from = visit.from;
  final to = visit.to;
  if (from != null && to != null) {
    return '${compoundName(from)} to ${to.toLowerCase()}';
  }
  if (to != null) return compoundName(to);
  return '';
}
