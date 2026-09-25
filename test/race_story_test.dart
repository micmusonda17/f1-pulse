import 'package:flutter_test/flutter_test.dart';
import 'package:pitbeat/models/openf1_models.dart';
import 'package:pitbeat/stats/race_story.dart';

// A made-up 10 lap race, 90 seconds a lap, with five cars. Small enough to
// work out the right story by hand.

DateTime at(int seconds) =>
    DateTime.utc(2026, 9, 13, 13).add(Duration(seconds: seconds));

PositionUpdate place(int seconds, int driver, int position) =>
    PositionUpdate(driverNumber: driver, date: at(seconds), position: position);

void main() {
  const names = {1: 'VER', 4: 'NOR', 16: 'LEC', 44: 'HAM', 81: 'PIA'};

  // How many seconds behind the leader each car crosses the line.
  const gaps = {1: 0, 4: 1, 44: 2, 81: 3, 16: 4};
  final laps = [
    for (final driver in gaps.keys)
      // LEC stops after 3 laps.
      for (var lap = 1; lap <= (driver == 16 ? 3 : 10); lap++)
        Lap(
          driverNumber: driver,
          lapNumber: lap,
          start: at(90 * (lap - 1) + gaps[driver]!),
          // VER's lap 9 is the fastest of the race.
          duration: driver == 1 && lap == 9 ? 88.5 : 90.0,
        ),
  ];

  final positions = [
    // The grid.
    place(0, 1, 1), place(0, 44, 2), place(0, 16, 3),
    place(0, 81, 4), place(0, 4, 5),
    // Lap 1: NOR passes three cars.
    place(80, 4, 2), place(80, 44, 3), place(80, 16, 4), place(80, 81, 5),
    // LEC drops back with a problem.
    place(250, 81, 4), place(250, 16, 5),
    // VER pits and NOR takes the lead. The swaps back and forth are timing
    // flicker, so only the last one counts.
    place(400, 4, 1), place(400, 1, 2),
    place(410, 1, 1), place(410, 4, 2),
    place(415, 4, 1), place(415, 1, 2),
    // VER passes NOR on track.
    place(700, 1, 1), place(700, 4, 2),
  ];

  final pitStops = [
    PitStop(
      driverNumber: 1,
      date: at(395),
      laneSeconds: 22.0,
      lapNumber: 5,
      stopSeconds: 2.4,
    ),
    // PIA is not on the podium, so this stop is left out.
    PitStop(driverNumber: 81, date: at(500), laneSeconds: 23.0, lapNumber: 6),
  ];

  const stints = [
    Stint(driverNumber: 1, lapStart: 1, lapEnd: 5, compound: 'MEDIUM'),
    Stint(driverNumber: 1, lapStart: 6, lapEnd: null, compound: 'HARD'),
  ];

  final messages = [
    RaceControlMessage(
      date: at(300),
      category: 'SafetyCar',
      message: 'SAFETY CAR DEPLOYED',
      lapNumber: 4,
    ),
    RaceControlMessage(
      date: at(320),
      category: 'Other',
      message: 'FIA STEWARDS: 5 SECOND TIME PENALTY FOR CAR 81 (PIA) - '
          'CAUSING A COLLISION',
      lapNumber: 4,
    ),
    // These two are not moments.
    RaceControlMessage(
      date: at(330),
      category: 'SafetyCar',
      message: 'SAFETY CAR IN THIS LAP',
      lapNumber: 4,
    ),
    RaceControlMessage(
      date: at(600),
      category: 'Other',
      message: 'FIA STEWARDS: 5 SECOND TIME PENALTY FOR CAR 81 (PIA) SERVED',
      lapNumber: 7,
    ),
  ];

  RaceStory story() => raceStory(
        names: names,
        positions: positions,
        laps: laps,
        pitStops: pitStops,
        stints: stints,
        messages: messages,
      );

  test('the moments, in order', () {
    expect(story().moments.map((moment) => moment.text).toList(), [
      'Lights out: VER keeps the lead from pole.',
      'NOR gains 3 places on lap 1.',
      'LEC retires.',
      'Safety car.',
      '5 second time penalty for car 81 (PIA) - causing a collision',
      'VER pits onto hard tyres, 2.4 s stop.',
      'NOR takes the lead from VER as VER pits.',
      'VER takes the lead from NOR.',
      'Fastest lap of the race: VER, 1:28.500.',
      'Chequered flag: VER wins, NOR is second and HAM third.',
    ]);
  });

  test('each moment knows its lap', () {
    final lapByKind = {
      for (final moment in story().moments) moment.kind: moment.lap,
    };
    expect(lapByKind[MomentKind.retirement], 3);
    expect(lapByKind[MomentKind.safetyCar], 4);
    expect(lapByKind[MomentKind.pit], 5);
    expect(lapByKind[MomentKind.fastestLap], 9);
    expect(lapByKind[MomentKind.finish], 10);
  });

  test('the headlines', () {
    expect(story().headlines, [
      'VER won from pole.',
      'VER led 7 of 10 laps.',
      'NOR climbed 3 places, P5 to P2.',
    ]);
  });

  test('no laps or positions means no story', () {
    final empty = raceStory(names: names, positions: const [], laps: const []);
    expect(empty.moments, isEmpty);
    expect(empty.headlines, isEmpty);
  });

  test('placeChanges counts places gained and lost', () {
    expect(placeChanges([1, 2, 3], [3, 1, 2]), {3: 2, 1: -1, 2: -1});
    expect(placeChanges([1, 2], [2, 9]), {2: 1}); // 9 was not on the grid
  });

  test('sentenceCase keeps driver codes in capitals', () {
    expect(
      sentenceCase('CAR 44 (HAM) TIME 1:32.456 DELETED'),
      'Car 44 (HAM) time 1:32.456 deleted',
    );
    expect(sentenceCase(''), '');
  });
}
