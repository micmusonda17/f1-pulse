import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitbeat/models/openf1_models.dart';
import 'package:pitbeat/models/race.dart';
import 'package:pitbeat/stats/strategy.dart';
import 'package:pitbeat/tracker/race_status.dart';
import 'package:pitbeat/tracker/tracker_math.dart';
import 'package:pitbeat/utils/formatting.dart';

/// [seconds] after a made-up lights out.
DateTime t(double seconds) => DateTime.utc(2026, 9, 27, 13)
    .add(Duration(milliseconds: (seconds * 1000).round()));

Lap lap(int driver, int number, double start, [double? seconds = 90]) => Lap(
      driverNumber: driver,
      lapNumber: number,
      start: t(start),
      duration: seconds,
    );

RaceControlMessage message(
  double seconds,
  String text, {
  String category = 'Flag',
  String? flag,
  String? scope,
  int? sector,
  int? driver,
}) =>
    RaceControlMessage(
      date: t(seconds),
      category: category,
      message: text,
      flag: flag,
      scope: scope,
      sector: sector,
      driverNumber: driver,
    );

void main() {
  group('who is out, and why', () {
    // Car 1 does all 10 laps. Car 2 stops on lap 4, in the pits. Car 3 is
    // a lap down, but takes the flag.
    final byDriver = lapsByDriver([
      for (var n = 1; n <= 10; n++) lap(1, n, 90.0 * (n - 1)),
      for (var n = 1; n <= 3; n++) lap(2, n, 90.0 * (n - 1) + 1),
      lap(2, 4, 271, null), // No time: it never finished lap 4
      for (var n = 1; n <= 9; n++) lap(3, n, 100.0 * (n - 1), 100),
    ]);
    final stops = [
      PitStop(driverNumber: 2, date: t(300), laneSeconds: null),
    ];
    Map<int, Retirement> outAt(double seconds) => findRetirements(
          byDriver,
          clock: t(seconds),
          chequered: t(900),
          pitStops: stops,
        );

    test('a car is out once the race has gone a lap without it', () {
      expect(outAt(400), isEmpty); // Could still be coming round
      expect(outAt(545).keys, [2]);
      final retirement = outAt(545)[2]!;
      expect(retirement.lap, 4);
      expect(retirement.inPits, isTrue);
    });

    test('cars that take the chequered flag are not out', () {
      expect(outAt(2000).keys, [2]); // Car 3, a lap down, finished
    });

    test('the note says why, as well as it can', () {
      final retirement = Retirement(lap: 23, at: t(0), inPits: true);
      expect(
        retirementNote(retirement, status: 'Engine'),
        'Retired on lap 23 in the pits: engine',
      );
      final onTrack = Retirement(lap: 23, at: t(0));
      expect(
        retirementNote(
          onTrack,
          status: 'Retired', // Says nothing, so the message is used
          message: message(0, 'CAR 16 (LEC) STOPPED AT TURN 4'),
        ),
        'Retired on lap 23. Car 16 (LEC) stopped at turn 4',
      );
      expect(retirementNote(onTrack), 'Retired on lap 23');
      expect(isGenericStatus('+1 Lap'), isTrue);
      expect(isGenericStatus('Collision'), isFalse);
    });

    test('messages about one car, and the one that explains', () {
      final messages = [
        message(10, 'CAR 16 (LEC) TIME 1:32.100 DELETED - TRACK LIMITS',
            driver: 16),
        message(20, 'BLUE FLAG FOR CAR 16 (LEC)', driver: 16),
        message(30, 'INCIDENT INVOLVING CARS 1 (VER) AND 16 (LEC) NOTED'),
        message(40, 'CAR 1 (VER) TIME 1:31.900 DELETED - TRACK LIMITS'),
        message(50, 'CAR 16 (LEC) STOPPED AT TURN 4', driver: 16),
      ];
      final about = messagesAbout(messages, 16, code: 'LEC', until: t(45));
      expect(about.length, 2); // No blue flag, nothing about car 1 alone
      expect(explainingMessage(about, t(35))?.message, contains('INCIDENT'));
    });
  });

  group('flags', () {
    final messages = [
      message(0, 'GREEN LIGHT - PIT EXIT OPEN', flag: 'GREEN', scope: 'Track'),
      message(100, 'YELLOW IN TRACK SECTOR 7',
          flag: 'YELLOW', scope: 'Sector', sector: 7),
      message(130, 'CLEAR IN TRACK SECTOR 7',
          flag: 'CLEAR', scope: 'Sector', sector: 7),
      message(200, 'SAFETY CAR DEPLOYED', category: 'SafetyCar'),
      message(400, 'SAFETY CAR IN THIS LAP', category: 'SafetyCar'),
      message(450, 'TRACK CLEAR', flag: 'CLEAR', scope: 'Track'),
      message(500, 'VIRTUAL SAFETY CAR DEPLOYED', category: 'SafetyCar'),
      message(560, 'VIRTUAL SAFETY CAR ENDING', category: 'SafetyCar'),
      message(600, 'RED FLAG', flag: 'RED', scope: 'Track'),
      message(900, 'GREEN LIGHT - PIT EXIT OPEN',
          flag: 'GREEN', scope: 'Track'),
      message(1000, 'DOUBLE YELLOW IN TRACK SECTOR 3',
          flag: 'DOUBLE YELLOW', scope: 'Sector', sector: 3),
      message(1500, 'CHEQUERED FLAG', flag: 'CHEQUERED', scope: 'Track'),
    ];
    TrackStatus at(double seconds) =>
        trackStateAt(messages, t(seconds)).status;

    test('every flag in turn', () {
      expect(at(50), TrackStatus.green);
      expect(at(110), TrackStatus.yellow);
      expect(trackStateAt(messages, t(110)).yellowSectors, {7});
      expect(at(150), TrackStatus.green);
      expect(at(300), TrackStatus.safetyCar);
      expect(at(420), TrackStatus.safetyCar); // Still out until the clear
      expect(at(460), TrackStatus.green);
      expect(at(520), TrackStatus.virtualSafetyCar);
      expect(at(570), TrackStatus.green);
      expect(at(700), TrackStatus.red);
      expect(at(950), TrackStatus.green);
      expect(at(1100), TrackStatus.yellow);
      expect(at(1600), TrackStatus.chequered);
    });

    test('a yellow with no clear is dropped after five minutes', () {
      expect(at(1400), TrackStatus.green);
    });
  });

  group('gaps and the fastest lap', () {
    // Car 2 is 3.2 seconds behind car 1. Car 3 has been lapped.
    final byDriver = lapsByDriver([
      lap(1, 1, 0), lap(1, 2, 90), lap(1, 3, 180), lap(1, 4, 270),
      lap(2, 1, 0), lap(2, 2, 91.5), lap(2, 3, 182), lap(2, 4, 273.2),
      lap(3, 1, 0), lap(3, 2, 100), lap(3, 3, 275),
    ]);

    test('measured on the line, in seconds or laps', () {
      final gaps = gapsAt(byDriver, [1, 2, 3], t(280));
      expect(gaps.containsKey(1), isFalse); // The leader has no gap
      expect(gaps[2]!.toAhead!.seconds, 3.2);
      expect(gaps[2]!.toLeader!.seconds, 3.2);
      expect(gaps[3]!.toLeader!.laps, 1);
      expect(gapsAt(byDriver, [1, 2, 3], t(50)), isEmpty); // Lap 1
    });

    test('formatGap', () {
      expect(formatGap(const TimingGap(seconds: 3.2)), '+3.200');
      expect(formatGap(const TimingGap(seconds: 75.5)), '+1:15.500');
      expect(formatGap(const TimingGap(laps: 1)), '+1 LAP');
      expect(formatGap(const TimingGap(laps: 2)), '+2 LAPS');
    });

    test('fastestLapAt only counts laps that are over', () {
      final laps = [lap(1, 2, 0, 91.0), lap(2, 2, 1, 90.5), lap(1, 3, 91, 89)];
      expect(fastestLapAt(laps, t(95))?.driverNumber, 2);
      expect(fastestLapAt(laps, t(200))?.lapNumber, 3);
      expect(fastestLapAt(laps, t(10)), isNull);
    });
  });

  test('carNumbersFor matches Jolpica ids by surname', () {
    DriverInfo info(int number, String name) => DriverInfo(
          number: number,
          acronym: name.substring(0, 3),
          fullName: name,
          team: '',
          colour: Colors.red,
        );
    final drivers = {
      1: info(1, 'Max VERSTAPPEN'),
      12: info(12, 'Andrea Kimi ANTONELLI'),
      44: info(44, 'Lewis HAMILTON'),
    };
    expect(carNumbersFor(['max_verstappen', 'antonelli'], drivers), {1, 12});
  });

  group('strategy', () {
    final laps = lapsByDriver([
      for (var n = 1; n <= 30; n++) lap(1, n, 90.0 * (n - 1)),
    ]);
    const stints = [
      Stint(driverNumber: 1, lapStart: 1, lapEnd: 20, compound: 'MEDIUM'),
      Stint(driverNumber: 1, lapStart: 21, lapEnd: null, compound: 'HARD'),
    ];
    final stops = [
      PitStop(
        driverNumber: 1,
        date: t(1790),
        laneSeconds: 22.1,
        lapNumber: 20,
        stopSeconds: 2.4,
      ),
    ];

    test('stints and stops for the whole race', () {
      final strategy = strategies(
        order: [1],
        stints: stints,
        pitStops: stops,
        lapsByDriver: laps,
      ).single;
      expect(
        strategy.stints.map((s) => '${s.compound} ${s.fromLap}-${s.toLap}'),
        ['MEDIUM 1-20', 'HARD 21-30'],
      );
      expect(strategy.stops.single.lap, 20);
      expect(tyreChange(strategy.stops.single), 'Medium to hard');
    });

    test('only what had happened by the clock', () {
      final strategy = strategies(
        order: [1],
        stints: stints,
        pitStops: stops,
        lapsByDriver: laps,
        until: t(900), // Lap 11
      ).single;
      expect(strategy.stints.single.toLap, 11);
      expect(strategy.stops, isEmpty);
    });
  });

  test('weather and the calendar helpers', () {
    expect(compassPoint(0), 'N');
    expect(compassPoint(90), 'E');
    expect(compassPoint(225), 'SW');
    expect(compassPoint(350), 'N');
    expect(formatWindSpeed(5), '18 km/h');

    Race race(int round, DateTime start) => Race(
          season: 2026,
          round: round,
          name: 'Round $round',
          circuitId: 'x',
          circuitName: 'x',
          locality: 'x',
          country: 'x',
          start: start,
          sessions: const [],
        );
    final races = [
      race(1, DateTime.utc(2026, 9, 13, 13)),
      race(2, DateTime.utc(2026, 9, 27, 12)),
    ];
    // Saturday's qualifying belongs to Sunday's race.
    expect(raceNear(races, DateTime.utc(2026, 9, 26, 14))?.round, 2);
    expect(raceNear(races, DateTime.utc(2026, 9, 20, 12)), isNull);
  });
}
