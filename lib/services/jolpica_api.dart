import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/race.dart';
import '../models/race_result.dart';
import '../models/standing.dart';
import 'api_exception.dart';

/// Talks to the Jolpica F1 API: the calendar, standings and results.
///
/// Free, no key needed. Limits: 4 requests a second and 500 an hour,
/// which is plenty for one person using the app.
class JolpicaApi {
  // Tests can pass in a fake client. The app just uses the real one.
  JolpicaApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// Every Jolpica answer is wrapped in {"MRData": {...}}.
  /// This makes the request, checks it worked, and unwraps it.
  Future<Map<String, dynamic>> _get(String path) async {
    final url = Uri.parse('${AppConfig.jolpicaBaseUrl}/$path');

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
}
