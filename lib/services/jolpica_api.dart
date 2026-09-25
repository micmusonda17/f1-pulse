import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/lap_timing.dart';
import '../models/race.dart';
import '../models/race_result.dart';
import '../models/standing.dart';
import 'api_exception.dart';

/// Somewhere to keep copies of Jolpica's answers on the phone.
///
/// An abstract class only lists what something can do, like a Python
/// base class full of `raise NotImplementedError`. PhoneCache (in
/// lib/services/phone_cache.dart) does the actual saving. Keeping this file
/// free of Flutter means `dart run bin/try_api.dart` still works.
abstract class ResponseCache {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
}

/// Talks to the Jolpica F1 API: the calendar, standings and results.
///
/// Free, no key needed. Limits: 4 requests a second and 500 an hour,
/// which is plenty for one person using the app.
class JolpicaApi {
  // Tests can pass in a fake client. The app just uses the real one.
  JolpicaApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Where answers are saved. main() plugs in PhoneCache. In tests and in
  /// bin/try_api.dart it stays null, and nothing is saved.
  static ResponseCache? cache;

  /// Data saver: reuse a saved answer younger than this instead of
  /// downloading it again. Zero (always download) unless data saver is on.
  static Duration reuseCopiesFor = Duration.zero;

  // One queue for every JolpicaApi in the app (static means shared by all
  // of them), so together they stay under 4 requests a second. The same
  // idea as the queue in OpenF1Api.
  static const Duration _gapBetweenRequests = Duration(milliseconds: 260);
  static Future<void> _nextSlot = Future<void>.value();

  static Future<void> _waitForSlot() {
    final mySlot = _nextSlot;
    _nextSlot = mySlot.then((_) => Future<void>.delayed(_gapBetweenRequests));
    return mySlot;
  }

  /// Gets one answer: a recent saved copy in data saver mode, otherwise a
  /// fresh download, and the saved copy if the download fails (no signal,
  /// or the server is down). A week-old calendar beats an error screen.
  /// [keepCopy] false skips the copies, for big answers like lap times.
  Future<Map<String, dynamic>> _get(
    String path, {
    bool keepCopy = true,
  }) async {
    if (!keepCopy) return _fetch(path);
    final saved = await _readCopy(path);
    if (saved != null &&
        DateTime.now().difference(saved.savedAt) < reuseCopiesFor) {
      return saved.data;
    }
    try {
      final data = await _fetch(path);
      await _writeCopy(path, data);
      return data;
    } on ApiException {
      if (saved != null) return saved.data;
      rethrow;
    }
  }

  Future<_Copy?> _readCopy(String path) async {
    final store = cache;
    if (store == null) return null;
    try {
      final text = await store.read('jolpica:$path');
      if (text == null) return null;
      final json = jsonDecode(text) as Map<String, dynamic>;
      return _Copy(
        DateTime.parse(json['savedAt'] as String),
        json['data'] as Map<String, dynamic>,
      );
    } catch (_) {
      return null; // A damaged copy is no copy
    }
  }

  Future<void> _writeCopy(String path, Map<String, dynamic> data) async {
    final store = cache;
    if (store == null) return;
    try {
      final saved = {'savedAt': DateTime.now().toIso8601String(), 'data': data};
      await store.write('jolpica:$path', jsonEncode(saved));
    } catch (_) {
      // Could not save a copy. The app still has the fresh answer.
    }
  }

  /// Every Jolpica answer is wrapped in {"MRData": {...}}.
  /// This makes the request, checks it worked, and unwraps it.
  Future<Map<String, dynamic>> _fetch(String path) async {
    final url = Uri.parse('${AppConfig.jolpicaBaseUrl}/$path');
    await _waitForSlot(); // Wait for our turn

    final http.Response response;
    try {
      response = await _client.get(url).timeout(const Duration(seconds: 15));
    } on Exception {
      throw const ApiException(
        'Could not reach the F1 data server. Check your internet connection.',
      );
    }

    if (response.statusCode == 429) {
      throw const ApiException(
        'Too many requests. Wait a minute, then pull down to refresh.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        'The F1 data server answered with error ${response.statusCode}.',
      );
    }

    // utf8.decode makes names like "Pérez" come out right.
    final body = jsonDecode(utf8.decode(response.bodyBytes));
    return (body as Map<String, dynamic>)['MRData'] as Map<String, dynamic>;
  }

  /// Every race in a season. 'current' means this year.
  Future<List<Race>> getSchedule({String season = 'current'}) async {
    final data = await _get('$season.json?limit=100');
    final races = data['RaceTable']['Races'] as List<dynamic>;
    return races
        .map((race) => Race.fromJson(race as Map<String, dynamic>))
        .toList();
  }

  Future<List<DriverStanding>> getDriverStandings({
    String season = 'current',
  }) async {
    final data = await _get('$season/driverStandings.json?limit=100');
    final lists = data['StandingsTable']['StandingsLists'] as List<dynamic>;
    if (lists.isEmpty) return []; // Before the first race of the season
    final rows = lists.first['DriverStandings'] as List<dynamic>;
    return rows
        .map((row) => DriverStanding.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  Future<List<ConstructorStanding>> getConstructorStandings({
    String season = 'current',
  }) async {
    final data = await _get('$season/constructorStandings.json?limit=100');
    final lists = data['StandingsTable']['StandingsLists'] as List<dynamic>;
    if (lists.isEmpty) return [];
    final rows = lists.first['ConstructorStandings'] as List<dynamic>;
    return rows
        .map((row) => ConstructorStanding.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// The finishing order of one race.
  Future<List<RaceResult>> getResults(int season, int round) async {
    final data = await _get('$season/$round/results.json?limit=100');
    final races = data['RaceTable']['Races'] as List<dynamic>;
    if (races.isEmpty) return []; // Results not published yet
    final rows = races.first['Results'] as List<dynamic>;
    return rows
        .map((row) => RaceResult.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// The finishing order of one sprint. Empty for a weekend without one.
  Future<List<RaceResult>> getSprintResults(int season, int round) async {
    final data = await _get('$season/$round/sprint.json?limit=100');
    final races = data['RaceTable']['Races'] as List<dynamic>;
    if (races.isEmpty) return [];
    final rows = races.first['SprintResults'] as List<dynamic>;
    return rows
        .map((row) => RaceResult.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// The round number of the latest race with results, or null before the
  /// first race of the season. "last" is a Jolpica shortcut.
  Future<int?> getLastRound(int season) async {
    final data = await _get('$season/last/results.json?limit=1');
    final races = data['RaceTable']['Races'] as List<dynamic>;
    if (races.isEmpty) return null;
    return int.tryParse('${races.first['round']}');
  }

  /// The finishing order of the race at one circuit in one season.
  /// Empty if there was no race there that year.
  Future<List<RaceResult>> getResultsAtCircuit(
    int season,
    String circuitId,
  ) async {
    final data = await _get(
      '$season/circuits/$circuitId/results.json?limit=100',
    );
    final races = data['RaceTable']['Races'] as List<dynamic>;
    if (races.isEmpty) return [];
    final rows = races.first['Results'] as List<dynamic>;
    return rows
        .map((row) => RaceResult.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Every race result of a season, by round (Chapters 48 and 49).
  Future<Map<int, List<RaceResult>>> getSeasonResults(int season) async {
    final rows = await _seasonRows(season, 'results', 'Results');
    return rows.map(
      (round, list) => MapEntry(round, list.map(RaceResult.fromJson).toList()),
    );
  }

  /// Every sprint result of a season, by round. Sprints have the same
  /// layout as races, under "SprintResults".
  Future<Map<int, List<RaceResult>>> getSeasonSprints(int season) async {
    final rows = await _seasonRows(season, 'sprint', 'SprintResults');
    return rows.map(
      (round, list) => MapEntry(round, list.map(RaceResult.fromJson).toList()),
    );
  }

  /// Every qualifying result of a season, by round.
  Future<Map<int, List<QualifyingResult>>> getSeasonQualifying(
    int season,
  ) async {
    final rows = await _seasonRows(season, 'qualifying', 'QualifyingResults');
    return rows.map(
      (round, list) =>
          MapEntry(round, list.map(QualifyingResult.fromJson).toList()),
    );
  }

  /// A whole season's rows under [key], grouped by round.
  ///
  /// Jolpica sends at most 100 rows at a time, and a season has over 400,
  /// so we ask page by page: offset 0, 100, 200... until we have them all.
  /// One race can be split across two pages, so rows are added to their
  /// round rather than replacing it.
  Future<Map<int, List<Map<String, dynamic>>>> _seasonRows(
    int season,
    String path,
    String key,
  ) async {
    final byRound = <int, List<Map<String, dynamic>>>{};
    var offset = 0;
    while (true) {
      final data = await _get('$season/$path.json?limit=100&offset=$offset');
      final races = data['RaceTable']['Races'] as List<dynamic>;
      var rowsOnPage = 0;
      for (final race in races.cast<Map<String, dynamic>>()) {
        final round = int.parse(race['round'] as String);
        final rows = ((race[key] as List<dynamic>?) ?? const [])
            .cast<Map<String, dynamic>>();
        byRound.putIfAbsent(round, () => []).addAll(rows);
        rowsOnPage += rows.length;
      }
      final total = int.tryParse('${data['total']}') ?? 0;
      offset += 100;
      if (rowsOnPage == 0 || offset >= total) break;
    }
    return byRound;
  }

  /// Every driver's time on every lap of one race (Chapter 57). Jolpica
  /// sends 100 timings at a time, and a race has over 1,000, so we page
  /// through like _seasonRows. No saved copies: they would be big.
  Future<List<LapTiming>> getLapTimings(int season, int round) async {
    final timings = <LapTiming>[];
    var offset = 0;
    while (true) {
      final data = await _get(
        '$season/$round/laps.json?limit=100&offset=$offset',
        keepCopy: false,
      );
      final races = data['RaceTable']['Races'] as List<dynamic>;
      final page = races.isEmpty
          ? <LapTiming>[]
          : lapTimingsFrom(races.first['Laps'] as List<dynamic>);
      timings.addAll(page);
      final total = int.tryParse('${data['total']}') ?? 0;
      offset += 100;
      if (page.isEmpty || offset >= total) break;
    }
    return timings;
  }

  /// Every pit stop of one race: the lap and the time in the pit lane.
  Future<List<JolpicaPitStop>> getPitStopTimes(int season, int round) async {
    final data = await _get('$season/$round/pitstops.json?limit=100');
    final races = data['RaceTable']['Races'] as List<dynamic>;
    if (races.isEmpty) return [];
    final rows = (races.first['PitStops'] as List<dynamic>?) ?? const [];
    return rows
        .map((row) => JolpicaPitStop.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// The qualifying order for one race. Empty until qualifying is over.
  Future<List<QualifyingResult>> getQualifying(int season, int round) async {
    final data = await _get('$season/$round/qualifying.json?limit=100');
    final races = data['RaceTable']['Races'] as List<dynamic>;
    if (races.isEmpty) return [];
    final rows = races.first['QualifyingResults'] as List<dynamic>;
    return rows
        .map((row) => QualifyingResult.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}

/// A saved answer and when it was saved.
class _Copy {
  const _Copy(this.savedAt, this.data);

  final DateTime savedAt;
  final Map<String, dynamic> data;
}
