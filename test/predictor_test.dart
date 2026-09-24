import 'package:flutter_test/flutter_test.dart';
import 'package:pitbeat/models/race_result.dart';
import 'package:pitbeat/models/standing.dart';
import 'package:pitbeat/predictions/predictor.dart';
import 'package:pitbeat/screens/prediction_screen.dart';
import 'package:pitbeat/utils/formatting.dart';

// Made-up drivers called alpha, bravo, charlie, delta and echo, so the
// numbers are easy to follow.

Driver driver(String id) => Driver(
      id: id,
      code: id.substring(0, 3).toUpperCase(),
      number: '',
      firstName: 'Test',
      lastName: id,
      nationality: '',
    );

RaceResult finish(String id, int position) => RaceResult(
      position: position,
      driver: driver(id),
      team: 'Team $id',
      grid: position,
      laps: 50,
      status: 'Finished',
      time: null,
      points: pointsFor(position).toDouble(),
    );

DriverStanding standing(String id, int position, double points) =>
    DriverStanding(
      position: position,
      points: points,
      wins: 0,
      driver: driver(id),
      team: 'Team $id',
    );

QualifyingResult qualified(String id, int position) =>
    QualifyingResult(position: position, driver: driver(id), team: 'Team $id');

// Two races, newest first. Alpha won both.
final latestRace = [
  finish('alpha', 1),
  finish('bravo', 2),
  finish('charlie', 3),
  finish('echo', 11),
];
final raceBefore = [
  finish('alpha', 1),
  finish('charlie', 2),
  finish('bravo', 3),
  finish('echo', 12),
];
// Delta is in the table but was replaced, so is not in the latest race.
final table = [
  standing('alpha', 1, 50),
  standing('bravo', 2, 33),
  standing('charlie', 3, 33),
  standing('delta', 4, 10),
  standing('echo', 5, 0),
];

PredictionData data({
  List<RaceResult> lastYearHere = const [],
  List<QualifyingResult> qualifying = const [],
}) {
  return PredictionData(
    standings: table,
    recentRaces: [latestRace, raceBefore],
    lastYearHere: lastYearHere,
    qualifying: qualifying,
  );
}

List<String> order(RacePrediction prediction) =>
    [for (final row in prediction.ranking) row.driver.id];

void main() {
  group('the building blocks', () {
    test('pointsFor follows the points table', () {
      expect(pointsFor(1), 25);
      expect(pointsFor(10), 1);
      expect(pointsFor(11), 0);
      expect(pointsFor(null), 0);
    });

    test('formScore counts newer races more', () {
      // Won the newest race: 2 x 25 out of a possible 2 x 25 + 1 x 25.
      expect(formScore([1, 11]), closeTo(2 / 3, 1e-9));
      expect(formScore([11, 1]), closeTo(1 / 3, 1e-9));
    });

    test('describeForm picks the best thing to say', () {
      expect(describeForm([1, 3, 1, 5, 2]), 'Won 2 of the last 5 races');
      expect(describeForm([1]), 'Won the last race');
      expect(describeForm([3, 5]), '1 podium in the last 2 races');
      expect(describeForm([6]), '8 points in the last race');
      expect(describeForm([15, 12]), 'No points in the last 2 races');
    });

    test('softmax turns scores into chances that add up to 1', () {
      final chances = softmax([0.9, 0.5, 0.5]);
      expect(chances.reduce((a, b) => a + b), closeTo(1, 1e-9));
      expect(chances[0], greaterThan(chances[1]));
      expect(chances[1], chances[2]); // Equal scores, equal chances
    });

    test('ordinal', () {
      final words = [1, 2, 3, 4, 11, 12, 13, 21, 22, 101].map(ordinal).toList();
      expect(words, [
        '1st', '2nd', '3rd', '4th', '11th',
        '12th', '13th', '21st', '22nd', '101st',
      ]);
    });

    test('formatChance', () {
      expect(formatChance(0.4123), '41%');
      expect(formatChance(0.004), '<1%');
    });
  });

  group('predictWinner', () {
    test('the chances add up to 100%', () {
      final prediction = predictWinner(data());
      var total = 0.0;
      for (final row in prediction.ranking) {
        total += row.chance;
      }
      expect(total, closeTo(1, 1e-9));
    });

    test('the in-form championship leader is the favourite', () {
      final prediction = predictWinner(data());
      expect(order(prediction), ['alpha', 'bravo', 'charlie', 'echo']);
      expect(prediction.ranking.first.reasons, [
        'Won 2 of the last 2 races',
        'Leads the championship',
      ]);
      expect(prediction.racesUsed, 2);
      expect(prediction.usedQualifying, isFalse);
    });

    test('drivers who are not in the race are left out', () {
      final prediction = predictWinner(data());
      expect(order(prediction), isNot(contains('delta')));
    });

    test('pole position can change the favourite', () {
      final prediction = predictWinner(
        data(
          qualifying: [
            qualified('charlie', 1),
            qualified('bravo', 2),
            qualified('alpha', 10),
            qualified('echo', 20),
          ],
        ),
      );
      expect(order(prediction).take(3).toList(), ['charlie', 'bravo', 'alpha']);
      expect(prediction.ranking.first.reasons, [
        'Qualified on pole',
        '2 podiums in the last 2 races',
      ]);
      expect(prediction.usedQualifying, isTrue);
    });

    test('winning here last year counts', () {
      final echoBefore = predictWinner(data()).ranking.last;
      final prediction = predictWinner(
        data(
          lastYearHere: [
            finish('echo', 1),
            finish('alpha', 2),
            finish('bravo', 3),
          ],
        ),
      );
      final echo = prediction.ranking.firstWhere(
        (row) => row.driver.id == 'echo',
      );
      expect(echo.chance, greaterThan(echoBefore.chance));
      expect(echo.reasons, [
        'Won here last year',
        'No points in the last 2 races',
      ]);
      expect(prediction.usedLastYear, isTrue);
    });

    test('before the first race there is nothing to go on', () {
      final prediction = predictWinner(
        const PredictionData(standings: [], recentRaces: []),
      );
      expect(prediction.ranking, isEmpty);
    });
  });

  test('describeEvidence lists what the prediction used', () {
    const prediction = RacePrediction(
      ranking: [],
      racesUsed: 5,
      usedLastYear: true,
      usedQualifying: false,
    );
    expect(
      describeEvidence(prediction),
      "Based on the last 5 races, the championship and last year's race "
      'here. The chances will change after qualifying.',
    );
  });
}
