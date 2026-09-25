import 'package:flutter_test/flutter_test.dart';
import 'package:pitbeat/models/lap_timing.dart';
import 'package:pitbeat/models/openf1_models.dart';
import 'package:pitbeat/models/race.dart';
import 'package:pitbeat/models/race_result.dart';
import 'package:pitbeat/models/standing.dart';
import 'package:pitbeat/services/api_exception.dart';
import 'package:pitbeat/services/replay_archive.dart';
import 'package:pitbeat/stats/timing_replay.dart';
import 'package:pitbeat/tracker/tracker_math.dart';

/// A pretend phone storage: a plain Map, so the tests need no files.
class MemoryReplayStore implements ReplayStore {
  final Map<String, List<int>> files = {};

  @override
  Future<List<int>?> read(String name) async => files[name];

  @override
  Future<void> write(String name, List<int> bytes) async {
    files[name] = bytes;
  }

  @override
  Future<void> deleteAll() async => files.clear();
}

/// One of OpenF1's sessions rows.
Map<String, dynamic> sessionRow(int key, String name, DateTime start) => {
      'session_key': key,
      'meeting_key': 1,
      'session_name': name,
      'session_type': name,
      'location': 'Monza',
      'country_name': 'Italy',
      'date_start': start.toIso8601String(),
      'date_end': start.add(const Duration(hours: 1)).toIso8601String(),
      'is_cancelled': false,
    };

RaceResult result(
  String id,
  String number,
  int position,
  int grid, {
  String status = 'Finished',
}) =>
    RaceResult(
      position: position,
      driver: Driver(
        id: id,
        code: id.substring(0, 3).toUpperCase(),
        number: number,
        firstName: 'Test',
        lastName: id,
        nationality: '',
      ),
      team: 'Team',
      grid: grid,
      laps: 3,
      status: status,
      time: null,
      points: 0,
    );

void main() {
  group('Jolpica lap times (Chapter 57)', () {
    test('parseTimeText reads minutes and hours', () {
      expect(parseTimeText('1:39.019'), closeTo(99.019, 1e-9));
      expect(parseTimeText('22.345'), 22.345);
      expect(parseTimeText('1:02:03.5'), 3723.5);
      expect(parseTimeText(''), isNull);
      expect(parseTimeText('fast'), isNull);
    });

    test('lapTimingsFrom flattens Jolpica laps', () {
      final timings = lapTimingsFrom([
        {
          'number': '1',
          'Timings': [
            {'driverId': 'alpha', 'position': '1', 'time': '1:40.000'},
            {'driverId': 'bravo', 'position': '2', 'time': 'broken'},
          ],
        },
      ]);
      expect(timings.single.driverId, 'alpha');
      expect(timings.single.seconds, 100);
    });

    group('timingReplay', () {
      final start = DateTime.utc(2026, 9, 6, 13);
      DateTime at(int seconds) => start.add(Duration(seconds: seconds));
      LapTiming timing(String id, int lap, int position, double seconds) =>
          LapTiming(
            lap: lap,
            driverId: id,
            position: position,
            seconds: seconds,
          );

      final replay = timingReplay(
        start: start,
        results: [
          result('alpha', '1', 1, 2),
          result('bravo', '1', 2, 1), // Number 1 is taken: gets a spare
          result('charlie', '16', 3, 3, status: 'Engine'),
        ],
        timings: [
          timing('alpha', 1, 2, 100),
          timing('alpha', 2, 1, 90),
          timing('alpha', 3, 1, 90),
          timing('bravo', 1, 1, 99),
          timing('bravo', 2, 2, 91),
          timing('bravo', 3, 2, 92),
          timing('charlie', 1, 3, 101),
          timing('charlie', 2, 3, 95),
        ],
        stops: const [JolpicaPitStop(driverId: 'bravo', lap: 2, seconds: 22)],
      );

      test('car numbers, with a spare for a clash', () {
        expect(replay.drivers.keys.toSet(), {1, 900, 16});
        expect(replay.drivers[16]!.acronym, 'CHA');
      });

      test('each lap starts when the last one ended', () {
        final alpha = lapsByDriver(replay.laps)[1]!;
        expect(alpha[1].start, at(100));
        expect(alpha[2].start, at(190));
      });

      test('the grid, then the order at the line', () {
        expect(runningOrderAt(replay.positions, start), [900, 1, 16]);
        expect(runningOrderAt(replay.positions, at(195)), [1, 900, 16]);
      });

      test('pit stops, the flag and the reasons', () {
        final stop = replay.pitStops.single;
        expect(stop.driverNumber, 900);
        expect(stop.lapNumber, 2);
        expect(stop.date, at(179)); // Half of 22 s before the lap ended
        expect(replay.chequered, at(280));
        expect(replay.statusByCode['CHA'], 'Engine');
      });
    });

    test('a made-up session for the tracker', () {
      final race = Race(
        season: 2026,
        round: 16,
        name: 'Italian Grand Prix',
        circuitId: 'monza',
        circuitName: 'Monza',
        locality: 'Monza',
        country: 'Italy',
        start: DateTime.utc(2026, 9, 6, 13),
        sessions: const [],
      );
      final session = timingSessionFor(race);
      expect(session.sessionKey, -202616); // Never a real OpenF1 key
      expect(session.type, 'Race');
      expect(session.title, 'Monza Race');
    });
  });

  group('replays saved on the phone (Chapter 56)', () {
    final now = DateTime.now().toUtc();
    final race = sessionRow(9001, 'Race', now.subtract(const Duration(days: 10)));
    final practice =
        sessionRow(9000, 'Practice', now.subtract(const Duration(days: 11)));
    final future = sessionRow(9002, 'Race', now.add(const Duration(days: 1)));

    late MemoryReplayStore store;
    late List<String> requests;
    var locked = false;
    var onWifi = true;

    // The pretend OpenF1.
    Future<List<dynamic>> fetch(String path) async {
      requests.add(path);
      if (locked) throw const ApiException('OpenF1 said no.');
      if (path.startsWith('sessions')) return [race, practice, future];
      if (path.startsWith('laps')) {
        return [
          {
            'driver_number': 1,
            'lap_number': 1,
            'date_start': now.subtract(const Duration(days: 10)).toIso8601String(),
            'lap_duration': 81.5,
          },
        ];
      }
      if (path.startsWith('drivers')) {
        return [
          {'driver_number': 1, 'name_acronym': 'VER', 'full_name': 'Max V'},
        ];
      }
      if (path.startsWith('location')) {
        return [
          {
            'driver_number': 1,
            'date': now.toIso8601String(),
            'x': 1,
            'y': 2,
            'z': 3,
          },
        ];
      }
      return [];
    }

    ReplayArchive archive() => ReplayArchive(
          store: store,
          fetch: fetch,
          onWifi: () async => onWifi,
          pace: Duration.zero,
        );

    setUp(() {
      store = MemoryReplayStore();
      requests = [];
      locked = false;
      onWifi = true;
    });

    test('a replay survives being squeezed into bytes', () {
      final replay = SavedReplay({
        'laps': [
          {'driver_number': 1, 'lap_number': 2, 'lap_duration': 80.1},
        ],
      });
      final back = decodeReplay(encodeReplay(replay))!;
      expect(back.laps.single.duration, 80.1);
      expect(decodeReplay([1, 2, 3]), isNull); // Damaged bytes
    });

    test('sessionsToSave: finished, not cancelled, not saved, newest first',
        () {
      final sessions = [
        for (final row in [practice, race, future]) OpenF1Session.fromJson(row),
      ];
      final todo = sessionsToSave(sessions, {}, now);
      expect(todo.map((session) => session.sessionKey), [9001, 9000]);
      expect(sessionsToSave(sessions, {9001}, now).single.sessionKey, 9000);
    });

    test('catchUp saves every finished session, once', () async {
      final saving = archive();
      await saving.catchUp();
      expect(saving.savedSessions.map((s) => s.sessionKey), [9001, 9000]);
      expect(requests.where((path) => path.startsWith('location')).length, 2);

      final saved = (await saving.replayFor(9001))!;
      expect(saved.laps.single.duration, 81.5);
      expect(saved.drivers.single.acronym, 'VER');
      expect(saved.outline.single.z, 3);
      final raceStart = OpenF1Session.fromJson(race).start;
      expect(saving.findSaved(raceStart)?.sessionKey, 9001);

      // Again: only the list of sessions is asked for.
      final before = requests.length;
      await saving.catchUp();
      expect(requests.length, before + 1);

      // And a fresh start of the app finds them on the phone.
      final reopened = archive();
      await reopened.load();
      expect(reopened.savedSessions.length, 2);
    });

    test('waits for Wi-Fi, unless you say otherwise', () async {
      onWifi = false;
      final saving = archive();
      await saving.catchUp();
      expect(requests, isEmpty);
      expect(saving.status, 'Waiting for Wi-Fi');
      await saving.catchUp(anyNetwork: true);
      expect(saving.savedSessions.length, 2);
    });

    test('stops quietly while OpenF1 is locked', () async {
      locked = true;
      final saving = archive();
      await saving.catchUp();
      expect(saving.savedSessions, isEmpty);
      expect(saving.status, startsWith('Paused'));
      expect(saving.isSaving, isFalse);
    });

    test('deleteAll empties the phone', () async {
      final saving = archive();
      await saving.catchUp();
      await saving.deleteAll();
      expect(saving.savedSessions, isEmpty);
      expect(store.files, isEmpty);
    });
  });
}
