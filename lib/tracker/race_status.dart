import 'dart:math' as math;

import '../models/openf1_models.dart';
import '../stats/race_story.dart' show sentenceCase;

// The state of a session at the replay's clock (Chapters 52 and 53): who is
// out and why, the flags, the gaps and the fastest lap. Plain functions, so
// they are easy to test (test/race_status_test.dart).

Duration _seconds(double seconds) =>
    Duration(milliseconds: (seconds * 1000).round());

// ----------------------------------------------------------------------
// Who is out, and why (Chapter 52)
// ----------------------------------------------------------------------

/// A driver whose race ended early.
class Retirement {
  const Retirement({required this.lap, required this.at, this.inPits = false});

  final int lap; // The lap they stopped on
  final DateTime at; // Roughly when they stopped
  final bool inPits; // Stopped in the pit lane rather than out on track
}

/// A driver's usual lap time: the middle one of their timed laps, so pit
/// stops and safety car laps do not drag it up. 100 seconds if unknown.
double typicalLapSeconds(List<Lap> laps) {
  final times = [for (final lap in laps) ?lap.duration]..sort();
  if (times.isEmpty) return 100;
  return times[times.length ~/ 2];
}

/// Everyone who had stopped for good by [clock].
///
/// A car is out once it has gone a whole lap longer than usual without
/// starting a new one, and other cars have started laps since. A car whose
/// last lap ended after the chequered flag took the flag, so it finished.
/// [byDriver] is every lap, per driver, in lap order.
Map<int, Retirement> findRetirements(
  Map<int, List<Lap>> byDriver, {
  required DateTime clock,
  DateTime? chequered,
  List<PitStop> pitStops = const [],
}) {
  // The newest lap anyone had started by the clock: proof the race went on.
  DateTime? newest;
  for (final laps in byDriver.values) {
    for (final lap in laps) {
      final start = lap.start;
      if (start == null || start.isAfter(clock)) continue;
      if (newest == null || start.isAfter(newest)) newest = start;
    }
  }
  final raceWentOn = newest;
  if (raceWentOn == null) return {};

  final out = <int, Retirement>{};
  for (final entry in byDriver.entries) {
    final started = [
      for (final lap in entry.value)
        if (lap.start != null) lap,
    ];
    if (started.isEmpty) continue;
    final last = started.last;
    final lastStart = last.start!;
    final typical = typicalLapSeconds(started);
    final stopped = lastStart.add(_seconds(last.duration ?? typical));

    // Finished at, or just after, the flag: not a retirement.
    final flag = chequered;
    if (flag != null &&
        !stopped.isBefore(flag.subtract(const Duration(seconds: 60)))) {
      continue;
    }
    // Only sure once a full lap more has gone by with the race still on.
    final sure = stopped.add(_seconds(typical));
    if (clock.isBefore(sure) || !raceWentOn.isAfter(sure)) continue;

    final inPits = pitStops.any(
      (stop) =>
          stop.driverNumber == entry.key &&
          !stop.date.isBefore(lastStart.subtract(const Duration(seconds: 5))),
    );
    out[entry.key] =
        Retirement(lap: last.lapNumber, at: stopped, inPits: inPits);
  }
  return out;
}

/// Statuses that do not say why a car stopped: "Finished", "Retired",
/// "+1 Lap" and the like.
bool isGenericStatus(String status) {
  const generic = {
    'finished',
    'retired',
    'lapped',
    'not classified',
    'did not finish',
  };
  final lower = status.trim().toLowerCase();
  return lower.isEmpty || lower.startsWith('+') || generic.contains(lower);
}

/// Why a retired driver is out, in a few words: "Retired on lap 23 in the
/// pits: engine". [status] is Jolpica's reason, once the results are in;
/// [message] a race control message about the car, when there is no
/// better reason.
String retirementNote(
  Retirement retirement, {
  String? status,
  RaceControlMessage? message,
}) {
  final where = retirement.inPits ? ' in the pits' : '';
  final base = 'Retired on lap ${retirement.lap}$where';
  if (status != null && !isGenericStatus(status)) {
    return '$base: ${status.toLowerCase()}';
  }
  if (message != null) return '$base. ${sentenceCase(message.message)}';
  return base;
}

/// Race control's messages about one car, up to [until], oldest first.
/// Blue flags are left out: they only say a faster car is coming.
List<RaceControlMessage> messagesAbout(
  List<RaceControlMessage> messages,
  int number, {
  String? code,
  DateTime? until,
}) {
  bool isAbout(RaceControlMessage message) =>
      message.driverNumber == number ||
      message.message.contains('CAR $number ') ||
      (code != null && message.message.contains('($code)'));

  return [
    for (final message in messages)
      if ((until == null || !message.date.isAfter(until)) &&
          !message.message.contains('BLUE FLAG') &&
          isAbout(message))
        message,
  ];
}

/// The message most likely to explain why a car stopped: one about it from
/// the five minutes before to three minutes after, that mentions a crash,
/// a stop or damage. The latest one wins.
RaceControlMessage? explainingMessage(
  List<RaceControlMessage> aboutCar,
  DateTime stopped,
) {
  const clues = [
    'STOPPED',
    'RETIRED',
    'INCIDENT',
    'COLLISION',
    'CRASH',
    'SPUN',
    'DAMAGE',
    'FIRE',
    'RECOVERY',
  ];
  RaceControlMessage? best;
  for (final message in aboutCar) {
    final seconds = message.date.difference(stopped).inSeconds;
    if (seconds < -300 || seconds > 180) continue;
    if (clues.any((clue) => message.message.contains(clue))) best = message;
  }
  return best;
}

// ----------------------------------------------------------------------
// Flags (Chapter 53)
// ----------------------------------------------------------------------

/// The state of the whole track, worst first in how it is worked out.
enum TrackStatus { green, yellow, virtualSafetyCar, safetyCar, red, chequered }

/// The flags at one moment: the track's status, and which marshal sectors
/// are showing a yellow.
class TrackState {
  const TrackState(this.status, [this.yellowSectors = const {}]);

  final TrackStatus status;
  final Set<int> yellowSectors;
}

/// Replays race control's messages up to [time] to find the flags.
/// [messages] must be sorted by time, oldest first.
TrackState trackStateAt(List<RaceControlMessage> messages, DateTime time) {
  var safetyCar = false;
  var virtualSafetyCar = false;
  var red = false;
  var chequered = false;
  final yellows = <int, DateTime>{}; // Sector -> when the yellow came out

  for (final message in messages) {
    if (message.date.isAfter(time)) break;
    final text = message.message;
    final flag = message.flag ?? '';

    if (message.category == 'SafetyCar') {
      if (text.contains('VIRTUAL SAFETY CAR DEPLOYED')) {
        virtualSafetyCar = true;
      } else if (text.contains('VIRTUAL SAFETY CAR ENDING')) {
        virtualSafetyCar = false;
      } else if (text.contains('SAFETY CAR DEPLOYED')) {
        safetyCar = true;
      }
    }
    if (flag == 'RED') red = true;
    if (flag == 'CHEQUERED') chequered = true;

    final sector = message.sector;
    if (message.scope == 'Sector' && sector != null) {
      if (flag.contains('YELLOW')) yellows[sector] = message.date;
      if (flag == 'CLEAR' || flag == 'GREEN') yellows.remove(sector);
    } else if ((flag == 'CLEAR' || flag == 'GREEN') &&
        message.scope != 'Driver') {
      // Green for the whole track: every flag and safety car is over.
      safetyCar = false;
      virtualSafetyCar = false;
      red = false;
      chequered = false;
      yellows.clear();
    }
  }

  // A yellow with no "clear" after five minutes was cleared by a message
  // we did not recognise. Better to drop it than show it all race.
  yellows.removeWhere(
    (_, since) => time.difference(since) > const Duration(minutes: 5),
  );

  final TrackStatus status;
  if (chequered) {
    status = TrackStatus.chequered;
  } else if (red) {
    status = TrackStatus.red;
  } else if (safetyCar) {
    status = TrackStatus.safetyCar;
  } else if (virtualSafetyCar) {
    status = TrackStatus.virtualSafetyCar;
  } else if (yellows.isNotEmpty) {
    status = TrackStatus.yellow;
  } else {
    status = TrackStatus.green;
  }
  return TrackState(status, yellows.keys.toSet());
}

// ----------------------------------------------------------------------
// Gaps and the fastest lap (Chapter 53)
// ----------------------------------------------------------------------

/// A gap on the timing screen: seconds, or whole laps when lapped.
class TimingGap {
  const TimingGap({this.seconds, this.laps = 0});

  final double? seconds;
  final int laps;
}

/// One car's gaps: to the car ahead (the "interval") and to the leader.
class CarGaps {
  const CarGaps({this.toAhead, this.toLeader});

  final TimingGap? toAhead;
  final TimingGap? toLeader;
}

/// When a car crossed the line to start each lap, up to [clock].
Map<int, DateTime> lineCrossings(List<Lap> laps, DateTime clock) {
  final crossings = <int, DateTime>{};
  for (final lap in laps) {
    final start = lap.start;
    if (start != null && !start.isAfter(clock)) {
      crossings[lap.lapNumber] = start;
    }
  }
  return crossings;
}

/// How far behind [other] a car was when it crossed the line to start
/// [lap], at [crossed]. If [other] had crossed the line again before
/// that, the gap is in laps. Null if it cannot be worked out.
TimingGap? gapBehind(Map<int, DateTime> other, int lap, DateTime crossed) {
  final theirs = other[lap];
  if (theirs == null) return null;
  var laps = 0;
  while (true) {
    final next = other[lap + laps + 1];
    if (next == null || next.isAfter(crossed)) break;
    laps++;
  }
  if (laps > 0) return TimingGap(laps: laps);
  final seconds = crossed.difference(theirs).inMilliseconds / 1000;
  return seconds < 0 ? null : TimingGap(seconds: seconds);
}

/// The gaps at [clock] for the cars in [order] (still racing, leader
/// first), measured where the timing loops measure them: on the line.
/// So they change once a lap, like the TV's. None on lap 1.
Map<int, CarGaps> gapsAt(
  Map<int, List<Lap>> byDriver,
  List<int> order,
  DateTime clock,
) {
  final result = <int, CarGaps>{};
  if (order.isEmpty) return result;
  final crossings = {
    for (final number in order)
      number: lineCrossings(byDriver[number] ?? const [], clock),
  };
  final leader = crossings[order.first]!;

  for (var i = 1; i < order.length; i++) {
    final mine = crossings[order[i]]!;
    if (mine.isEmpty) continue;
    final lap = mine.keys.reduce(math.max);
    if (lap < 2) continue; // Lap 1 starts from the grid: no gaps yet
    final crossed = mine[lap]!;
    result[order[i]] = CarGaps(
      toAhead: gapBehind(crossings[order[i - 1]]!, lap, crossed),
      toLeader: gapBehind(leader, lap, crossed),
    );
  }
  return result;
}

/// "+1.234", "+1:02.345", "+1 LAP" or "+2 LAPS".
String formatGap(TimingGap gap) {
  final seconds = gap.seconds;
  if (seconds == null) return gap.laps == 1 ? '+1 LAP' : '+${gap.laps} LAPS';
  if (seconds < 60) return '+${seconds.toStringAsFixed(3)}';
  final minutes = seconds ~/ 60;
  final rest = (seconds - minutes * 60).toStringAsFixed(3).padLeft(6, '0');
  return '+$minutes:$rest';
}

/// The fastest complete lap that had ended by [time], or null.
Lap? fastestLapAt(List<Lap> laps, DateTime time) {
  Lap? fastest;
  for (final lap in laps) {
    final start = lap.start;
    final seconds = lap.duration;
    if (start == null || seconds == null) continue;
    if (start.add(_seconds(seconds)).isAfter(time)) continue; // Not over yet
    final best = fastest?.duration;
    if (best == null || seconds < best) fastest = lap;
  }
  return fastest;
}

// ----------------------------------------------------------------------
// Your drivers (Chapter 55)
// ----------------------------------------------------------------------

/// Turns Jolpica driver ids ("max_verstappen", "antonelli") into this
/// session's car numbers, by surname. Used to pick out your favourite and
/// fantasy drivers in the 3D view.
Set<int> carNumbersFor(
  Iterable<String> driverIds,
  Map<int, DriverInfo> drivers,
) {
  final result = <int>{};
  for (final entry in drivers.entries) {
    final words = entry.value.fullName.trim().split(RegExp(r'\s+'));
    final surname = words.last.toLowerCase();
    if (surname.isEmpty) continue;
    for (final id in driverIds) {
      if (id == surname || id.endsWith('_$surname')) result.add(entry.key);
    }
  }
  return result;
}
