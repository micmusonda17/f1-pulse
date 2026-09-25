import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pitbeat/models/race_result.dart';
import 'package:pitbeat/models/standing.dart';
import 'package:pitbeat/services/jolpica_api.dart';
import 'package:pitbeat/stats/fantasy.dart';
import 'package:pitbeat/stats/form_guide.dart';
import 'package:pitbeat/stats/season_data.dart';
import 'package:pitbeat/utils/formatting.dart';

// Made-up drivers again (see predictor_test.dart): alpha and bravo drive
// for Team A, charlie and delta for Team C.

Driver driver(String id) => Driver(
      id: id,
      code: id.substring(0, 3).toUpperCase(),
      number: '',
      firstName: 'Test',
      lastName: id,
      nationality: '',
    );

String teamOf(String id) =>
    id == 'alpha' || id == 'bravo' ? 'Team A' : 'Team C';

RaceResult result(
  String id,
  int position, {
  int? grid,
  bool classified = true,
  int? fastestLapRank,
}) =>
    RaceResult(
      position: position,
      driver: driver(id),
      team: teamOf(id),
      grid: grid ?? position,
      laps: 50,
      status: classified ? 'Finished' : 'Retired',
      time: null,
      points: 0,
      classified: classified,
      fastestLapRank: fastestLapRank,
    );

QualifyingResult qualifying(
  String id,
  int position, {
  bool q2 = false,
  bool q3 = false,
}) =>
    QualifyingResult(
      position: position,
      driver: driver(id),
      team: teamOf(id),
      reachedQ2: q2,
      reachedQ3: q3,
    );

void main() {
  group('fantasy scoring', () {
    test('qualifying: 10 for pole down to 1 for P10', () {
      expect(qualifyingFantasyPoints(qualifying('alpha', 1)), 10);
      expect(qualifyingFantasyPoints(qualifying('alpha', 10)), 1);
      expect(qualifyingFantasyPoints(qualifying('alpha', 11)), 0);
      const noTime = QualifyingResult(
        position: 20,
        driver: Driver(
          id: 'x',
          code: 'XXX',
          number: '',
          firstName: 'X',
          lastName: 'X',
          nationality: '',
        ),
        team: 'Team X',
        setTime: false,
      );
      expect(qualifyingFantasyPoints(noTime), -5);
    });

    test('race: places, places gained, fastest lap and retirements', () {
      // Won from P3: 25 for the win, plus 2 places gained.
      expect(raceFantasyPoints(result('alpha', 1, grid: 3), starters: 20), 27);
      // Lost 4 places: P6 is 8 points, minus 4.
      expect(raceFantasyPoints(result('alpha', 6, grid: 2), starters: 20), 4);
      // The fastest lap is worth 10.
      expect(
        raceFantasyPoints(
          result('alpha', 2, fastestLapRank: 1),
          starters: 20,
        ),
        28,
      );
      // Retired: minus 20, whatever else happened.
      expect(
        raceFantasyPoints(result('alpha', 18, classified: false), starters: 20),
        -20,
      );
      // A pit lane start (grid 0) counts as starting last: P20 of 20.
      expect(raceFantasyPoints(result('alpha', 12, grid: 0), starters: 20), 8);
    });

    test('sprint: 8 for the win, fastest lap 5, retirement -10', () {
      expect(sprintFantasyPoints(result('alpha', 1), starters: 20), 8);
      expect(
        sprintFantasyPoints(
          result('alpha', 8, grid: 10, fastestLapRank: 1),
          starters: 20,
        ),
        1 + 2 + 5,
      );
      expect(
        sprintFantasyPoints(result('alpha', 20, classified: false),
            starters: 20),
        -10,
      );
      expect(sprintFantasyPoints(null, starters: 0), 0); // No sprint
    });

    test('team qualifying bonus', () {
      expect(
        teamQualifyingBonus([
          qualifying('alpha', 1, q2: true, q3: true),
          qualifying('bravo', 2, q2: true, q3: true),
        ]),
        10,
      );
      expect(
        teamQualifyingBonus([
          qualifying('alpha', 5, q2: true, q3: true),
          qualifying('bravo', 14, q2: true),
        ]),
        5,
      );
      expect(
        teamQualifyingBonus([qualifying('alpha', 18), qualifying('bravo', 19)]),
        -1,
      );
      expect(teamQualifyingBonus([]), 0); // No results yet
    });

    test('the season table adds up drivers, teams and your team', () {
      final rounds = [
        SeasonRound(
          round: 1,
          raceName: 'First Grand Prix',
          race: [result('alpha', 1), result('charlie', 2)],
          qualifying: [
            qualifying('alpha', 1, q2: true, q3: true),
            qualifying('charlie', 2, q2: true, q3: true),
          ],
        ),
        SeasonRound(
          round: 2,
          raceName: 'Second Grand Prix',
          race: [result('charlie', 1), result('alpha', 2)],
          qualifying: [
            qualifying('charlie', 1, q2: true, q3: true),
            qualifying('alpha', 16), // Out in Q1: no points
          ],
        ),
      ];
      final table = fantasyTable(rounds);
      // alpha: round 1 = 10 + 25; round 2 = 0 + 18.
      final alpha = table.drivers.firstWhere((d) => d.driver.id == 'alpha');
      expect(alpha.total, 10 + 25 + 18);
      expect(alpha.lastRound, 18);
      expect(table.lastRaceName, 'Second Grand Prix');
      // Team A in round 1: alpha's 35 plus 5 (one driver in Q3).
      final teamA = table.teams.firstWhere((t) => t.team == 'Team A');
      expect(teamA.total, 35 + 5 + 18 - 1); // Round 2: out in Q1
      // Your team: alpha and Team A.
      expect(
        table.teamPoints(['alpha'], ['Team A']),
        alpha.total + teamA.total,
      );
    });
  });

  group('form guide', () {
    final rounds = [
      SeasonRound(
        round: 1,
        raceName: 'First',
        race: [result('alpha', 1), result('bravo', 3)],
        qualifying: [qualifying('bravo', 1), qualifying('alpha', 2)],
      ),
      SeasonRound(
        round: 2,
        raceName: 'Second',
        race: [result('bravo', 2), result('alpha', 19, classified: false)],
        qualifying: [qualifying('alpha', 1), qualifying('bravo', 2)],
      ),
    ];

    test('rates per start', () {
      final guide = formGuide(rounds);
      final alpha = guide.firstWhere((form) => form.driver.id == 'alpha');
      expect(alpha.starts, 2);
      expect(alpha.rate(alpha.wins), 0.5);
      expect(alpha.rate(alpha.retirements), 0.5);
      expect(alpha.averageFinish, 1); // Only classified finishes count
    });

    test('head to head against the teammate', () {
      final guide = formGuide(rounds);
      final alpha = guide.firstWhere((form) => form.driver.id == 'alpha');
      expect(alpha.teammate, 'bravo');
      expect(alpha.raceWinsOverTeammate, 1); // Round 1
      expect(alpha.raceLossesToTeammate, 1); // Round 2: alpha retired
      expect(alpha.qualifyingWinsOverTeammate, 1);
      expect(alpha.qualifyingLossesToTeammate, 1);
    });
  });

  test('fair odds and rates', () {
    expect(formatOdds(0.4), '2.50'); // Bet 1, get 2.50 back
    expect(formatOdds(0.25), '4.00');
    expect(formatOdds(0.005), '100+'); // A very long shot
    expect(formatRate(0.25), '25%');
  });

  group('a whole season from Jolpica', () {
    // One result row, the way Jolpica sends it.
    Map<String, dynamic> row(String id, int position) => {
          'position': '$position',
          'positionText': '$position',
          'points': '0',
          'grid': '$position',
          'laps': '50',
          'status': 'Finished',
          'Driver': {'driverId': id, 'givenName': 'Test', 'familyName': id},
          'Constructor': {'name': teamOf(id)},
        };

    test('comes page by page, and a race can be split across two', () async {
      final offsets = <String?>[];
      // The pretend server: 150 rows in total, so two pages of 100.
      final client = MockClient((request) async {
        final offset = request.url.queryParameters['offset'];
        offsets.add(offset);
        final races = offset == '0'
            ? [
                {
                  'round': '1',
                  'Results': [row('alpha', 1), row('bravo', 2)],
                },
                {
                  'round': '2',
                  'Results': [row('bravo', 1)],
                },
              ]
            : [
                {
                  'round': '2', // The rest of round 2
                  'Results': [row('alpha', 2)],
                },
              ];
        final body = {
          'MRData': {
            'total': '150',
            'RaceTable': {'Races': races},
          },
        };
        return http.Response(jsonEncode(body), 200);
      });

      final results = await JolpicaApi(client: client).getSeasonResults(2026);
      expect(offsets, ['0', '100']);
      expect(results[1]!.length, 2);
      expect(
        results[2]!.map((result) => result.driver.id).toList(),
        ['bravo', 'alpha'],
      );
    });
  });
}
