import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pitbeat/models/openf1_models.dart';
import 'package:pitbeat/models/race.dart';
import 'package:pitbeat/models/race_result.dart';
import 'package:pitbeat/models/standing.dart';
import 'package:pitbeat/services/driver_directory.dart';

// These JSON samples are copied from real Jolpica and OpenF1 answers.
// We run jsonDecode on them so the test sees exactly what the app sees.

const raceJson = '''
{
  "season": "2026",
  "round": "1",
  "raceName": "Australian Grand Prix",
  "Circuit": {
    "circuitId": "albert_park",
    "circuitName": "Albert Park Grand Prix Circuit",
    "Location": {"lat": "-37.8497", "long": "144.968",
                 "locality": "Melbourne", "country": "Australia"}
  },
  "date": "2026-03-08",
  "time": "04:00:00Z",
  "FirstPractice": {"date": "2026-03-06", "time": "01:30:00Z"},
  "SecondPractice": {"date": "2026-03-06", "time": "05:00:00Z"},
  "ThirdPractice": {"date": "2026-03-07", "time": "01:30:00Z"},
  "Qualifying": {"date": "2026-03-07", "time": "05:00:00Z"}
}
''';

const standingJson = '''
{
  "position": "1", "positionText": "1", "points": "267", "wins": "7",
  "Driver": {"driverId": "antonelli", "permanentNumber": "12", "code": "ANT",
             "givenName": "Andrea Kimi", "familyName": "Antonelli",
             "dateOfBirth": "2006-08-25", "nationality": "Italian"},
  "Constructors": [{"constructorId": "mercedes", "name": "Mercedes",
                    "nationality": "German"}]
}
''';

const winnerJson = '''
{
  "number": "12", "position": "1", "positionText": "1", "points": "25",
  "Driver": {"driverId": "antonelli", "code": "ANT", "givenName": "Andrea Kimi",
             "familyName": "Antonelli", "nationality": "Italian"},
  "Constructor": {"constructorId": "mercedes", "name": "Mercedes"},
  "grid": "2", "laps": "57", "status": "Finished",
  "Time": {"millis": "5663754", "time": "1:34:23.754"}
}
''';

const retiredJson = '''
{
  "number": "44", "position": "22", "positionText": "R", "points": "0",
  "Driver": {"driverId": "hamilton", "code": "HAM", "givenName": "Lewis",
             "familyName": "Hamilton", "nationality": "British"},
  "Constructor": {"constructorId": "ferrari", "name": "Ferrari"},
  "grid": "4", "laps": "6", "status": "Retired"
}
''';

const qualifyingJson = '''
{
  "number": "63", "position": "1",
  "Driver": {"driverId": "russell", "code": "RUS", "givenName": "George",
             "familyName": "Russell", "nationality": "British"},
  "Constructor": {"constructorId": "mercedes", "name": "Mercedes"},
  "Q1": "1:41.221", "Q2": "1:40.902", "Q3": "1:40.513"
}
''';

const openF1DriverJson = '''
{
  "driver_number": 44, "name_acronym": "HAM", "full_name": "Lewis HAMILTON",
  "team_name": "Ferrari", "team_colour": "ED1131",
  "headshot_url": "https://media.formula1.com/example/lewham01.png"
}
''';

Map<String, dynamic> decode(String text) =>
    jsonDecode(text) as Map<String, dynamic>;

void main() {
  group('Race.fromJson', () {
    test('reads the basic details', () {
      final race = Race.fromJson(decode(raceJson));
      expect(race.season, 2026);
      expect(race.round, 1);
      expect(race.name, 'Australian Grand Prix');
      expect(race.circuitId, 'albert_park');
      expect(race.locality, 'Melbourne');
      expect(race.country, 'Australia');
    });

    test('joins the date and time into one UTC DateTime', () {
      final race = Race.fromJson(decode(raceJson));
      expect(race.start, DateTime.utc(2026, 3, 8, 4));
    });

    test('puts the weekend sessions in time order, race last', () {
      final race = Race.fromJson(decode(raceJson));
      final names = race.sessions.map((s) => s.name).toList();
      expect(names, [
        'Practice 1',
        'Practice 2',
        'Practice 3',
        'Qualifying',
        'Race',
      ]);
    });
  });

  group('findLiveSession', () {
    final races = [Race.fromJson(decode(raceJson))];

    test('finds the session that is on', () {
      // Practice 1 started at 01:30 UTC; this is half an hour in.
      final live = findLiveSession(races, now: DateTime.utc(2026, 3, 6, 2));
      expect(live?.name, 'Practice 1');
    });

    test('finds nothing between sessions', () {
      // Practice 1 is over and Practice 2 starts at 05:00.
      final live = findLiveSession(races, now: DateTime.utc(2026, 3, 6, 4));
      expect(live, isNull);
    });
  });

  group('DriverStanding.fromJson', () {
    test('reads position, points, wins, driver and team', () {
      final standing = DriverStanding.fromJson(decode(standingJson));
      expect(standing.position, 1);
      expect(standing.points, 267);
      expect(standing.wins, 7);
      expect(standing.driver.fullName, 'Andrea Kimi Antonelli');
      expect(standing.driver.code, 'ANT');
      expect(standing.team, 'Mercedes');
    });
  });

  group('RaceResult.fromJson', () {
    test('a finisher has a race time', () {
      final result = RaceResult.fromJson(decode(winnerJson));
      expect(result.position, 1);
      expect(result.timeOrStatus, '1:34:23.754');
      expect(result.points, 25);
      expect(result.placesGained, 1); // Started P2, finished P1
    });

    test('a driver who retired has no Time, so we show the status', () {
      final result = RaceResult.fromJson(decode(retiredJson));
      expect(result.time, isNull);
      expect(result.timeOrStatus, 'Retired');
    });
  });

  group('QualifyingResult.fromJson', () {
    test('reads the position, driver and team', () {
      final result = QualifyingResult.fromJson(decode(qualifyingJson));
      expect(result.position, 1);
      expect(result.driver.code, 'RUS');
      expect(result.team, 'Mercedes');
    });
  });

  group('DriverInfo.fromJson', () {
    test('reads the code, team colour and photo', () {
      final driver = DriverInfo.fromJson(decode(openF1DriverJson));
      expect(driver.number, 44);
      expect(driver.acronym, 'HAM');
      expect(driver.colour, const Color(0xFFED1131));
      expect(driver.headshotUrl, contains('lewham01.png'));
    });
  });

  group('teamColoursFrom', () {
    test('finds each team colour through its drivers', () {
      final standing = DriverStanding.fromJson(decode(standingJson));
      final directory = {
        'ANT': const DriverInfo(
          number: 12,
          acronym: 'ANT',
          fullName: 'Kimi ANTONELLI',
          team: 'Mercedes',
          colour: Color(0xFF00D7B6),
        ),
      };
      final colours = teamColoursFrom([standing], directory);
      expect(colours['Mercedes'], const Color(0xFF00D7B6));
    });
  });

  group('mergeDriverLists', () {
    DriverInfo lawson(String team, String? photo) => DriverInfo(
          number: 30,
          acronym: 'LAW',
          fullName: 'Liam LAWSON',
          team: team,
          colour: Colors.blue,
          headshotUrl: photo,
        );

    test('the newest race wins when a driver changes team', () {
      final merged = mergeDriverLists([
        [lawson('Racing Bulls', 'old.png')], // Older race first
        [lawson('Red Bull Racing', 'new.png')],
      ]);
      expect(merged['LAW']!.team, 'Red Bull Racing');
      expect(merged['LAW']!.headshotUrl, 'new.png');
    });

    test('keeps an older photo when the newest race has none', () {
      final merged = mergeDriverLists([
        [lawson('Racing Bulls', 'old.png')],
        [lawson('Racing Bulls', null)],
      ]);
      expect(merged['LAW']!.headshotUrl, 'old.png');
    });
  });

  group('closestSession', () {
    OpenF1Session practice(int key, String name, DateTime start) =>
        OpenF1Session(
          sessionKey: key,
          meetingKey: 1,
          name: name,
          type: 'Practice',
          location: 'Baku',
          country: 'Azerbaijan',
          start: start,
          end: start.add(const Duration(hours: 1)),
          isCancelled: false,
        );

    final weekend = [
      practice(1, 'Practice 1', DateTime.utc(2026, 9, 25, 8, 30)),
      practice(2, 'Practice 2', DateTime.utc(2026, 9, 25, 12)),
    ];

    test('matches the session that starts at the same time', () {
      final found = closestSession(weekend, DateTime.utc(2026, 9, 25, 12));
      expect(found?.name, 'Practice 2');
    });

    test('nothing within 90 minutes means no match', () {
      expect(closestSession(weekend, DateTime.utc(2026, 9, 26, 12)), isNull);
    });
  });

  group('tyres, pit stops, race control and weather', () {
    test('read OpenF1 JSON', () {
      final stint = Stint.fromJson(decode(
        '{"driver_number": 16, "lap_start": 1, "lap_end": 20, '
        '"compound": "SOFT"}',
      ));
      expect(stint.compound, 'SOFT');
      expect(stint.lapEnd, 20);

      final stop = PitStop.fromJson(decode(
        '{"driver_number": 16, "date": "2025-10-26T20:46:37.358000+00:00", '
        '"lane_duration": 22.215}',
      ));
      expect(stop.laneSeconds, 22.215);

      final message = RaceControlMessage.fromJson(decode(
        '{"date": "2023-06-04T14:21:01+00:00", "category": "Flag", '
        '"flag": "YELLOW", "message": "YELLOW IN TRACK SECTOR 7", '
        '"qualifying_phase": null}',
      ));
      expect(message.flag, 'YELLOW');
      expect(message.qualifyingPhase, isNull);

      final weather = WeatherReading.fromJson(decode(
        '{"date": "2023-05-07T18:42:25.233000+00:00", '
        '"air_temperature": 27.8, "track_temperature": 52.5, "rainfall": 0}',
      ));
      expect(weather.trackTemperature, 52.5);
      expect(weather.isRaining, isFalse);
    });

    test('older pit stops only have pit_duration', () {
      final stop = PitStop.fromJson(decode(
        '{"driver_number": 1, "date": "2023-03-05T16:00:00+00:00", '
        '"pit_duration": 23.4}',
      ));
      expect(stop.laneSeconds, 23.4);
    });
  });

  group('colourFromHex', () {
    test('turns a team colour into a Flutter Color', () {
      expect(colourFromHex('F58020'), const Color(0xFFF58020));
    });

    test('falls back to grey for missing or broken colours', () {
      expect(colourFromHex(null), Colors.grey);
      expect(colourFromHex('nope'), Colors.grey);
    });
  });
}
