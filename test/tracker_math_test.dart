import 'package:flutter_test/flutter_test.dart';
import 'package:pitbeat/models/openf1_models.dart';
import 'package:pitbeat/screens/tracker_screen.dart';
import 'package:pitbeat/tracker/tracker_math.dart';
import 'package:pitbeat/utils/formatting.dart';

/// A made-up location point, [seconds] after midday.
CarLocation point(int seconds, double x, double y) => CarLocation(
      driverNumber: 1,
      date: DateTime.utc(2026, 9, 13, 12, 0, seconds),
      x: x,
      y: y,
    );

DateTime at(int seconds, [int milliseconds = 0]) =>
    DateTime.utc(2026, 9, 13, 12, 0, seconds, milliseconds);

void main() {
  final points = [
    point(0, 0, 0),
    point(1, 10, 0),
    point(2, 20, 0),
    point(3, 30, 0),
  ];

  group('firstIndexAfter (binary search)', () {
    test('finds the first point after a time in the middle', () {
      expect(firstIndexAfter(points, at(1, 500)), 2);
    });

    test('a time exactly on a point returns the NEXT one', () {
      expect(firstIndexAfter(points, at(1)), 2);
    });

    test('before everything returns 0, after everything returns length', () {
      expect(firstIndexAfter(points, at(0).subtract(const Duration(seconds: 1))), 0);
      expect(firstIndexAfter(points, at(10)), 4);
    });
  });

  group('positionAt (interpolation)', () {
    test('halfway between two points is halfway along the line', () {
      expect(positionAt(points, at(1, 500)), const Offset(15, 0));
    });

    test('before the first point, the car sits on the first point', () {
      final early = at(0).subtract(const Duration(seconds: 5));
      expect(positionAt(points, early), const Offset(0, 0));
    });

    test('after the last point, the car sits on the last point', () {
      expect(positionAt(points, at(10)), const Offset(30, 0));
    });

    test('no points means no position', () {
      expect(positionAt([], at(0)), isNull);
    });
  });

  group('runningOrderAt', () {
    final updates = [
      PositionUpdate(driverNumber: 1, date: at(0), position: 1),
      PositionUpdate(driverNumber: 44, date: at(0), position: 2),
      // Overtake! Car 44 takes the lead at 10 seconds.
      PositionUpdate(driverNumber: 44, date: at(10), position: 1),
      PositionUpdate(driverNumber: 1, date: at(10), position: 2),
    ];

    test('before the overtake, car 1 leads', () {
      expect(runningOrderAt(updates, at(5)), [1, 44]);
    });

    test('after the overtake, car 44 leads', () {
      expect(runningOrderAt(updates, at(15)), [44, 1]);
    });
  });

  group('lap counter', () {
    Lap lap(int driver, int number, int seconds) => Lap(
          driverNumber: driver,
          lapNumber: number,
          start: at(seconds), // Seconds past 59 roll over into minutes
          duration: null,
        );

    final laps = [
      lap(1, 1, 0),
      lap(2, 1, 1),
      lap(1, 2, 90), // Car 1 leads onto lap 2
      lap(2, 2, 92),
      lap(2, 3, 181), // Car 2 has overtaken and starts lap 3 first
      lap(1, 3, 183),
      // No start time: OpenF1 sometimes leaves it out. It is skipped.
      const Lap(driverNumber: 1, lapNumber: 4, start: null, duration: null),
    ];

    test('keeps one mark per lap, at the first car to start it', () {
      final timeline = buildLapTimeline(laps);
      expect(timeline.map((mark) => mark.lap).toList(), [1, 2, 3]);
      expect(timeline[2].date, at(181));
    });

    test('the order the laps arrive in does not matter', () {
      final timeline = buildLapTimeline(laps.reversed.toList());
      expect(timeline.map((mark) => mark.lap).toList(), [1, 2, 3]);
    });

    test('lapAt finds the lap at any moment', () {
      final timeline = buildLapTimeline(laps);
      final beforeStart = at(0).subtract(const Duration(seconds: 1));
      expect(lapAt(timeline, beforeStart), isNull);
      expect(lapAt(timeline, at(45)), 1);
      expect(lapAt(timeline, at(90)), 2); // Exactly at the start counts
      expect(lapAt(timeline, at(500)), 3);
    });
  });

  group('practice and qualifying', () {
    Lap timed(int driver, int number, int startSeconds, double? seconds) =>
        Lap(
          driverNumber: driver,
          lapNumber: number,
          start: at(startSeconds),
          duration: seconds,
        );

    final laps = [
      timed(1, 1, 0, 95.5), // Ends at 95.5 seconds
      timed(1, 2, 96, 91.2), // Ends at 187.2 seconds: car 1's best
      timed(44, 1, 10, 92.0), // Ends at 102 seconds
      timed(44, 2, 103, null), // Went into the pits: no time
    ];

    test('bestLapsAt only counts laps that have finished', () {
      expect(bestLapsAt(laps, at(100)), {1: 95.5});
      expect(bestLapsAt(laps, at(150)), {1: 95.5, 44: 92.0});
      expect(bestLapsAt(laps, at(200)), {1: 91.2, 44: 92.0});
    });

    test('fastestLap picks the quickest lap that has a time', () {
      final fastest = fastestLap(laps);
      expect(fastest?.driverNumber, 1);
      expect(fastest?.lapNumber, 2);
      expect(fastestLap([timed(1, 1, 0, null)]), isNull);
    });

    test('a car at (0, 0) is in its garage', () {
      final track = [
        point(0, 0, 0), // In the garage
        point(1, 0, 0), // Still in the garage
        point(2, 50, 20), // Out on track
        point(3, 60, 20),
      ];
      expect(isInGarageAt(track, at(0, 500)), isTrue);
      expect(isInGarageAt(track, at(1, 500)), isTrue); // Just leaving
      expect(isInGarageAt(track, at(2, 500)), isFalse);
    });
  });

  group('the timing screen', () {
    test('lap times look like the TV', () {
      expect(formatLapTime(92.456), '1:32.456');
      expect(formatLapTime(59.9996), '1:00.000'); // Never "0:60.000"
      expect(formatMinutes(const Duration(minutes: 34, seconds: 12)), '34:12');
    });

    test('the fastest driver shows a time, everyone else a gap', () {
      expect(lapTimeOrGap(92.456, 92.456), '1:32.456');
      expect(lapTimeOrGap(92.69, 92.456), '+0.234');
      expect(lapTimeOrGap(null, 92.456), 'No time');
    });
  });

  group('tyres, pit stops, flags and weather', () {
    final laps = [
      Lap(driverNumber: 1, lapNumber: 2, start: at(90), duration: 90.0),
      Lap(driverNumber: 1, lapNumber: 1, start: at(0), duration: 90.0),
      Lap(driverNumber: 44, lapNumber: 1, start: at(2), duration: 91.0),
    ];

    test('lapsByDriver and driverLapAt', () {
      final byDriver = lapsByDriver(laps);
      expect(byDriver[1]!.map((lap) => lap.lapNumber).toList(), [1, 2]);
      expect(driverLapAt(byDriver[1]!, at(30)), 1);
      expect(driverLapAt(byDriver[1]!, at(100)), 2);
      expect(driverLapAt(byDriver[44]!, at(1)), isNull); // Not started
    });

    test('compoundOn finds the tyre for a lap', () {
      const stints = [
        Stint(driverNumber: 1, lapStart: 1, lapEnd: 20, compound: 'MEDIUM'),
        Stint(driverNumber: 1, lapStart: 21, lapEnd: null, compound: 'HARD'),
        Stint(driverNumber: 44, lapStart: 1, lapEnd: 30, compound: 'SOFT'),
      ];
      expect(compoundOn(stints, 1, 5), 'MEDIUM');
      expect(compoundOn(stints, 1, 40), 'HARD');
      expect(compoundOn(stints, 44, 5), 'SOFT');
      expect(compoundOn(stints, 16, 5), isNull); // No stints for car 16
    });

    test('pit stops: in the lane, and how many so far', () {
      final stops = [
        PitStop(driverNumber: 1, date: at(100), laneSeconds: 22.0),
        PitStop(driverNumber: 1, date: at(500), laneSeconds: 21.0),
      ];
      expect(isInPitLane(stops, 1, at(110)), isTrue);
      expect(isInPitLane(stops, 1, at(130)), isFalse); // Out after 22 s
      expect(pitStopsBefore(stops, 1, at(130)), 1);
      expect(pitStopsBefore(stops, 1, at(600)), 2);
    });

    test('race control: the latest message, only while it is fresh', () {
      final messages = [
        RaceControlMessage(
          date: at(10),
          category: 'Other',
          message: 'Q1 STARTED',
          qualifyingPhase: 1,
        ),
        RaceControlMessage(
          date: at(100),
          category: 'SafetyCar',
          message: 'SAFETY CAR DEPLOYED',
        ),
      ];
      expect(latestMessageAt(messages, at(120))?.message,
          'SAFETY CAR DEPLOYED');
      expect(latestMessageAt(messages, at(500)), isNull); // Too old now
      expect(qualifyingPhaseAt(messages, at(120)), 1);
      expect(qualifyingPhaseAt(messages, at(5)), isNull);
    });

    test('weatherAt picks the latest reading', () {
      final readings = [
        WeatherReading(
          date: at(0),
          airTemperature: 28.0,
          trackTemperature: 41.0,
          isRaining: false,
        ),
        WeatherReading(
          date: at(60),
          airTemperature: 27.0,
          trackTemperature: 38.0,
          isRaining: true,
        ),
      ];
      expect(weatherAt(readings, at(30))?.trackTemperature, 41);
      expect(weatherAt(readings, at(90))?.isRaining, isTrue);
    });
  });

  group('data saver: cars placed from lap times', () {
    // A straight "track" from (0, 0) to (20, 0), drawn with three points.
    const outline = [Offset(0, 0), Offset(10, 0), Offset(20, 0)];
    final laps = [
      Lap(driverNumber: 1, lapNumber: 1, start: at(0), duration: 10.0),
      Lap(driverNumber: 1, lapNumber: 2, start: at(10), duration: 10.0),
    ];

    test('halfway through a lap is halfway along the outline', () {
      expect(positionFromLaps(laps, outline, at(5)), const Offset(10, 0));
      expect(
        positionFromLaps(laps, outline, at(2, 500)),
        const Offset(5, 0),
      );
      expect(positionFromLaps(laps, outline, at(15)), const Offset(10, 0));
    });

    test('no position before the start or after the last lap', () {
      final early = at(0).subtract(const Duration(seconds: 1));
      expect(positionFromLaps(laps, outline, early), isNull);
      expect(positionFromLaps(laps, outline, at(25)), isNull);
    });

    test('a lap without a time ends when the next one starts', () {
      final noTime = [
        Lap(driverNumber: 1, lapNumber: 1, start: at(0), duration: null),
        Lap(driverNumber: 1, lapNumber: 2, start: at(10), duration: 10.0),
      ];
      expect(positionFromLaps(noTime, outline, at(5)), const Offset(10, 0));
    });
  });

  group('qualifying, tyre age and sector times', () {
    test('tyreAgeOn counts the laps from before the stint too', () {
      const stints = [
        Stint(
          driverNumber: 1,
          lapStart: 1,
          lapEnd: 8,
          compound: 'SOFT',
          tyreAgeAtStart: 3, // A used set: 3 laps already
        ),
        Stint(driverNumber: 1, lapStart: 9, lapEnd: null, compound: 'SOFT'),
      ];
      expect(tyreAgeOn(stints, 1, 1), 3);
      expect(tyreAgeOn(stints, 1, 5), 7);
      expect(tyreAgeOn(stints, 1, 9), 0); // A new set
      expect(tyreAgeOn(stints, 44, 5), isNull); // No stints for car 44
    });

    test('lapsCompleted counts laps with a time that had ended', () {
      final driverLaps = [
        Lap(driverNumber: 1, lapNumber: 1, start: at(0), duration: 90.0),
        Lap(driverNumber: 1, lapNumber: 2, start: at(90), duration: 90.0),
        // Into the pits: no time, so it does not count.
        Lap(driverNumber: 1, lapNumber: 3, start: at(180), duration: null),
      ];
      expect(lapsCompleted(driverLaps, at(60)), 0);
      expect(lapsCompleted(driverLaps, at(90)), 1); // Ended exactly now
      expect(lapsCompleted(driverLaps, at(500)), 2);
    });

    test('knockedOutAt works out who is out from the running order', () {
      final order22 = [for (var car = 1; car <= 22; car++) car]; // Car 1 P1
      expect(knockedOutAt(order22, 1, 22), isEmpty); // Q1: nobody out yet

      // Q2 with 22 cars: P17 to P22 went out in Q1.
      final duringQ2 = knockedOutAt(order22, 2, 22);
      expect(duringQ2.keys.toList(), [17, 18, 19, 20, 21, 22]);
      expect(duringQ2.values.toSet(), {1});

      // Q3: P11 to P16 went out in Q2.
      final duringQ3 = knockedOutAt(order22, 3, 22);
      expect(duringQ3[11], 2);
      expect(duringQ3[16], 2);
      expect(duringQ3[17], 1);
      expect(duringQ3.containsKey(10), isFalse);

      // 20 cars: 5 out in each part.
      final order20 = [for (var car = 1; car <= 20; car++) car];
      expect(knockedOutAt(order20, 2, 20).keys.toList(), [16, 17, 18, 19, 20]);
    });

    test('bestsOf finds the fastest sectors and the fastest lap', () {
      final laps = [
        Lap(
          driverNumber: 1,
          lapNumber: 1,
          start: at(0),
          duration: 90.0,
          sectors: [30.0, 31.0, 29.0],
        ),
        Lap(
          driverNumber: 44,
          lapNumber: 1,
          start: at(1),
          duration: 89.9,
          sectors: [30.2, 30.5, 29.2],
        ),
        // No lap time, but its first sector still counts.
        Lap(
          driverNumber: 16,
          lapNumber: 1,
          start: at(2),
          duration: null,
          sectors: [29.8, null, null],
        ),
      ];
      final bests = bestsOf(laps);
      expect(bests.sectors, [29.8, 30.5, 29.0]);
      expect(bests.lap, 89.9);
      expect(bestsOf(const <Lap>[]).lap, isNull);
    });

    test('fastestEachLap: who was quickest on every lap', () {
      final laps = [
        Lap(driverNumber: 1, lapNumber: 1, start: at(0), duration: 91.0),
        Lap(driverNumber: 44, lapNumber: 1, start: at(1), duration: 90.5),
        Lap(driverNumber: 1, lapNumber: 2, start: at(91), duration: 89.0),
        Lap(driverNumber: 44, lapNumber: 2, start: at(92), duration: null),
      ];
      final fastest = fastestEachLap(laps);
      expect(fastest[1]?.driverNumber, 44);
      expect(fastest[2]?.driverNumber, 1);
    });
  });
}
