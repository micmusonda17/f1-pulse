import '../models/openf1_models.dart';
import '../tracker/tracker_math.dart';
import '../utils/formatting.dart';

// The post-race analysis (Chapter 51): the moments that decided a race,
// in order, worked out from OpenF1's positions, laps, pit stops, tyres and
// race control messages. Plain maths, tested in test/race_story_test.dart.

/// The kinds of moment, each with its own icon on screen.
enum MomentKind {
  start,
  lead,
  pit,
  safetyCar,
  redFlag,
  penalty,
  retirement,
  fastestLap,
  finish,
}

/// One moment in the race.
class StoryMoment {
  const StoryMoment({
    required this.lap,
    required this.at,
    required this.kind,
    required this.text,
  });

  final int lap; // The race's lap when it happened
  final DateTime at; // For putting moments in order
  final MomentKind kind;
  final String text;
}

/// The whole story: a few headline facts, then the moments in order.
class RaceStory {
  const RaceStory({required this.headlines, required this.moments});

  final List<String> headlines;
  final List<StoryMoment> moments;

  static const RaceStory empty = RaceStory(headlines: [], moments: []);
}

/// Writes the story of a race or sprint.
///
/// [names] turns driver numbers into codes like "VER". [positions] must be
/// sorted by time, like the tracker's.
RaceStory raceStory({
  required Map<int, String> names,
  required List<PositionUpdate> positions,
  required List<Lap> laps,
  List<PitStop> pitStops = const [],
  List<Stint> stints = const [],
  List<RaceControlMessage> messages = const [],
}) {
  final timeline = buildLapTimeline(laps);
  if (timeline.isEmpty || positions.isEmpty) return RaceStory.empty;

  String name(int number) => names[number] ?? '#$number';
  int lapOf(DateTime time) => lapAt(timeline, time) ?? 0;
  final totalLaps = timeline.last.lap;
  final lightsOut = timeline.first.date;
  final afterLap1 = timeline.length > 1 ? timeline[1].date : lightsOut;

  final grid = runningOrderAt(positions, lightsOut);
  final lap1 = runningOrderAt(positions, afterLap1);
  final finish = runningOrderAt(positions, positions.last.date);
  final moments = <StoryMoment>[];

  // 1. The start.
  if (grid.isNotEmpty && lap1.isNotEmpty) {
    final leader = lap1.first;
    final from = grid.indexOf(leader) + 1;
    moments.add(
      StoryMoment(
        lap: 1,
        at: lightsOut,
        kind: MomentKind.start,
        text: from == 1
            ? 'Lights out: ${name(leader)} keeps the lead from pole.'
            : 'Lights out: ${name(leader)} takes the lead from P$from.',
      ),
    );
    final changes = placeChanges(grid, lap1);
    final gainer = _biggest(changes, (a, b) => a > b);
    final loser = _biggest(changes, (a, b) => a < b);
    if (gainer != null && changes[gainer]! >= 3) {
      moments.add(
        StoryMoment(
          lap: 1,
          at: afterLap1,
          kind: MomentKind.start,
          text: '${name(gainer)} gains ${changes[gainer]} places on lap 1.',
        ),
      );
    }
    if (loser != null && changes[loser]! <= -3) {
      moments.add(
        StoryMoment(
          lap: 1,
          at: afterLap1,
          kind: MomentKind.start,
          text: '${name(loser)} loses ${-changes[loser]!} places on lap 1.',
        ),
      );
    }
  }

  // 2. Every change of leader after lap 1. Swaps less than 20 seconds
  //    apart are timing flicker, so only the last one counts.
  final leadChanges = <PositionUpdate>[];
  int? leader = lap1.isEmpty ? null : lap1.first;
  for (final update in positions) {
    if (update.position != 1 || update.date.isBefore(afterLap1)) continue;
    if (update.driverNumber == leader) continue;
    if (leadChanges.isNotEmpty &&
        update.date.difference(leadChanges.last.date).inSeconds < 20) {
      leadChanges.removeLast();
    }
    leadChanges.add(update);
    leader = update.driverNumber;
  }
  var previous = lap1.isEmpty ? null : lap1.first;
  for (final change in leadChanges) {
    final old = previous;
    previous = change.driverNumber;
    if (old == null || old == change.driverNumber) continue;
    final pitted = pitStops.any(
      (stop) =>
          stop.driverNumber == old &&
          change.date.difference(stop.date).inSeconds.abs() < 60,
    );
    moments.add(
      StoryMoment(
        lap: lapOf(change.date),
        at: change.date,
        kind: MomentKind.lead,
        text: '${name(change.driverNumber)} takes the lead from ${name(old)}'
            '${pitted ? ' as ${name(old)} pits' : ''}.',
      ),
    );
  }

  // 3. The podium finishers' pit stops, with their new tyres.
  final podium = finish.take(3).toSet();
  for (final stop in pitStops) {
    if (!podium.contains(stop.driverNumber)) continue;
    final lap = stop.lapNumber ?? lapOf(stop.date);
    final next = stintOn(stints, stop.driverNumber, lap + 1);
    final tyres = next == null || next.lapStart <= lap
        ? ''
        : ' onto ${next.compound.toLowerCase()} tyres';
    final standing = stop.stopSeconds;
    final how = standing != null
        ? ', ${standing.toStringAsFixed(1)} s stop'
        : '';
    moments.add(
      StoryMoment(
        lap: lap,
        at: stop.date,
        kind: MomentKind.pit,
        text: '${name(stop.driverNumber)} pits$tyres$how.',
      ),
    );
  }

  // 4. Safety cars, red flags and penalties, from race control.
  for (final message in messages) {
    final text = message.message;
    final lap = message.lapNumber ?? lapOf(message.date);
    MomentKind? kind;
    String? story;
    if (message.category == 'SafetyCar' && text.contains('DEPLOYED')) {
      kind = MomentKind.safetyCar;
      story = text.contains('VIRTUAL')
          ? 'Virtual safety car.'
          : 'Safety car.';
    } else if (message.flag == 'RED') {
      kind = MomentKind.redFlag;
      story = 'Red flag: the race is stopped.';
    } else if (text.contains('PENALTY') &&
        !text.contains('NO FURTHER') &&
        !text.contains('NO PENALTY') &&
        !text.contains('SERVED')) {
      kind = MomentKind.penalty;
      story = sentenceCase(text.replaceFirst('FIA STEWARDS: ', ''));
    }
    if (kind != null && story != null) {
      moments.add(
        StoryMoment(lap: lap, at: message.date, kind: kind, text: story),
      );
    }
  }

  // 5. Retirements: anyone who did not finish 90% of the race distance,
  //    the rule for being classified.
  final byDriver = lapsByDriver(laps);
  for (final entry in byDriver.entries) {
    final last = entry.value.last;
    final start = last.start;
    if (start == null || last.lapNumber >= totalLaps * 0.9) continue;
    moments.add(
      StoryMoment(
        lap: last.lapNumber,
        at: start,
        kind: MomentKind.retirement,
        text: '${name(entry.key)} retires.',
      ),
    );
  }

  // 6. The fastest lap of the race.
  final fastest = fastestLap(laps);
  final fastestStart = fastest?.start;
  final fastestTime = fastest?.duration;
  if (fastest != null && fastestStart != null && fastestTime != null) {
    moments.add(
      StoryMoment(
        lap: fastest.lapNumber,
        at: fastestStart,
        kind: MomentKind.fastestLap,
        text: 'Fastest lap of the race: ${name(fastest.driverNumber)}, '
            '${formatLapTime(fastestTime)}.',
      ),
    );
  }

  // 7. The chequered flag, when the last car finished its last lap.
  var chequered = positions.last.date;
  for (final lap in laps) {
    final start = lap.start;
    if (start == null) continue;
    final seconds = lap.duration ?? 0;
    final end = start.add(Duration(milliseconds: (seconds * 1000).round()));
    if (end.isAfter(chequered)) chequered = end;
  }
  if (finish.length >= 3) {
    moments.add(
      StoryMoment(
        lap: totalLaps,
        at: chequered,
        kind: MomentKind.finish,
        text: 'Chequered flag: ${name(finish[0])} wins, ${name(finish[1])} '
            'is second and ${name(finish[2])} third.',
      ),
    );
  }

  // In time order. Two moments at the same time go in the order of
  // MomentKind, so the list comes out the same every time.
  moments.sort((a, b) {
    final byTime = a.at.compareTo(b.at);
    return byTime != 0 ? byTime : a.kind.index.compareTo(b.kind.index);
  });

  return RaceStory(
    headlines: _headlines(
      name: name,
      grid: grid,
      finish: finish,
      positions: positions,
      timeline: timeline,
      finishers: {
        for (final entry in byDriver.entries)
          if (entry.value.last.lapNumber >= totalLaps * 0.9) entry.key,
      },
    ),
    moments: moments,
  );
}

/// The short facts at the top: who won from where, who led most, and who
/// climbed the most places.
List<String> _headlines({
  required String Function(int) name,
  required List<int> grid,
  required List<int> finish,
  required List<PositionUpdate> positions,
  required List<LapMark> timeline,
  required Set<int> finishers,
}) {
  final lines = <String>[];
  if (finish.isEmpty) return lines;

  final winner = finish.first;
  final from = grid.indexOf(winner) + 1;
  lines.add(
    from == 1
        ? '${name(winner)} won from pole.'
        : from > 1
            ? '${name(winner)} won from P$from on the grid.'
            : '${name(winner)} won.',
  );

  // Who led at the start of each lap.
  final ledLaps = <int, int>{};
  for (final mark in timeline) {
    final order = runningOrderAt(positions, mark.date);
    if (order.isEmpty) continue;
    ledLaps[order.first] = (ledLaps[order.first] ?? 0) + 1;
  }
  final mostLed = _biggest(ledLaps, (a, b) => a > b);
  if (mostLed != null) {
    lines.add(
      '${name(mostLed)} led ${ledLaps[mostLed]} of ${timeline.length} laps.',
    );
  }

  // Grid to flag, for drivers who finished.
  final changes = placeChanges(grid, finish)
    ..removeWhere((driver, _) => !finishers.contains(driver));
  final climber = _biggest(changes, (a, b) => a > b);
  if (climber != null && changes[climber]! > 0) {
    final start = grid.indexOf(climber) + 1;
    final end = finish.indexOf(climber) + 1;
    lines.add(
      '${name(climber)} climbed ${changes[climber]} places, '
      'P$start to P$end.',
    );
  }
  return lines;
}

/// Places gained (positive) or lost (negative) between two running orders,
/// for every driver in both.
Map<int, int> placeChanges(List<int> before, List<int> after) {
  final changes = <int, int>{};
  for (var i = 0; i < after.length; i++) {
    final was = before.indexOf(after[i]);
    if (was >= 0) changes[after[i]] = was - i;
  }
  return changes;
}

/// The key whose value wins [better] against every other, or null.
int? _biggest(Map<int, int> values, bool Function(int, int) better) {
  int? best;
  for (final entry in values.entries) {
    final current = best == null ? null : values[best];
    if (current == null || better(entry.value, current)) best = entry.key;
  }
  return best;
}

/// "5 SECOND TIME PENALTY FOR CAR 44 (HAM)" becomes
/// "5 second time penalty for car 44 (HAM)": easier to read, and driver
/// codes in brackets stay in capitals.
String sentenceCase(String text) {
  final lower = text.toLowerCase();
  final fixed = lower.replaceAllMapped(
    RegExp(r'\(([a-z]{3})\)'),
    (match) => '(${match.group(1)!.toUpperCase()})',
  );
  if (fixed.isEmpty) return fixed;
  return fixed[0].toUpperCase() + fixed.substring(1);
}
