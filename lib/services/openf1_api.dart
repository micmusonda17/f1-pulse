import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/openf1_models.dart';
import 'api_exception.dart';

/// Talks to OpenF1: sessions, drivers, laps, car locations and positions.
///
/// Historical data (anything that has finished) is free. Live data, during
/// a session, needs a paid sponsor account and a token: see [signIn].
///
/// The free tier allows 3 requests a second and 30 a minute, so every
/// request waits for its turn in a queue: see [_waitForSlot].
class OpenF1Api {
  // The underscore makes the constructor private. Nobody outside this file
  // can make a new OpenF1Api, so the whole app shares [instance].
  OpenF1Api._();

  /// One shared copy, so every screen uses the same queue and the same token.
  static final OpenF1Api instance = OpenF1Api._();

  final http.Client _client = http.Client();
  String? _token;
  DateTime? _tokenExpires;

  // ------------------------------------------------------------------
  // The request queue
  // ------------------------------------------------------------------

  static const Duration _gapBetweenRequests = Duration(milliseconds: 400);
  Future<void> _nextSlot = Future<void>.value();

  /// Gives each caller a turn 0.4 seconds after the caller before it.
  /// That keeps us under 3 requests a second however busy the app gets.
  Future<void> _waitForSlot() {
    final mySlot = _nextSlot;
    _nextSlot = mySlot.then((_) => Future<void>.delayed(_gapBetweenRequests));
    return mySlot;
  }

  // ------------------------------------------------------------------
  // Signing in (only needed for live data)
  // ------------------------------------------------------------------

  bool get hasValidToken {
    final expires = _tokenExpires;
    return _token != null &&
        expires != null &&
        DateTime.now().isBefore(expires);
  }

  /// Swaps an OpenF1 email and password for a token that lasts one hour.
  Future<void> signIn(String username, String password) async {
    final http.Response response;
    try {
      response = await _client
          .post(
            Uri.parse(AppConfig.openF1TokenUrl),
            // A Map body is sent as a form, which is what OpenF1 expects.
            body: {'username': username, 'password': password},
          )
          .timeout(const Duration(seconds: 15));
    } on Exception {
      throw const ApiException('Could not reach OpenF1 to sign in.');
    }
    if (response.statusCode != 200) {
      throw const ApiException(
        'OpenF1 did not accept that email and password.',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    _token = data['access_token'] as String;
    final seconds = int.tryParse('${data['expires_in']}') ?? 3600;
    // Renew a minute early so we never send a token that has just expired.
    _tokenExpires = DateTime.now().add(Duration(seconds: seconds - 60));
  }

  void signOut() {
    _token = null;
    _tokenExpires = null;
  }

  // ------------------------------------------------------------------
  // The one method that actually talks to the internet
  // ------------------------------------------------------------------

  Future<List<dynamic>> _get(String pathAndQuery) async {
    final url = Uri.parse('${AppConfig.openF1BaseUrl}/$pathAndQuery');

    for (var attempt = 1; attempt <= 3; attempt++) {
      await _waitForSlot();

      final http.Response response;
      try {
        response = await _client
            .get(
              url,
              headers: hasValidToken ? {'Authorization': 'Bearer $_token'} : null,
            )
            .timeout(const Duration(seconds: 30));
      } on Exception {
        throw const ApiException(
          'Could not reach OpenF1. Check your internet connection.',
        );
      }

      if (response.statusCode == 200) {
        final decoded = jsonDecode(utf8.decode(response.bodyBytes));
        return decoded is List ? decoded : <dynamic>[];
      }
      if (response.statusCode == 404) {
        return <dynamic>[]; // OpenF1 uses 404 to mean "no results"
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const ApiException(
          'OpenF1 said no. While a session is live, it only answers '
          'sponsors, even for old races. Try again when the session ends, '
          'or add a sponsor login in Settings.',
        );
      }
      if (response.statusCode == 429) {
        // Too many requests: back off a little longer each time, then retry.
        await Future<void>.delayed(Duration(seconds: 2 * attempt));
        continue;
      }
      throw ApiException('OpenF1 answered with error ${response.statusCode}.');
    }
    throw const ApiException('OpenF1 is busy right now. Try again in a minute.');
  }

  /// OpenF1 wants times like 2026-09-13T13:10:00.000Z
  String _time(DateTime time) => time.toUtc().toIso8601String();

  // ------------------------------------------------------------------
  // Sessions
  // ------------------------------------------------------------------

  /// Every race and sprint in a year (2023 onwards).
  Future<List<OpenF1Session>> getRaceSessions(int year) async {
    final rows = await _get('sessions?year=$year&session_type=Race');
    return rows
        .map((row) => OpenF1Session.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// The session happening now, or the one that happened most recently.
  Future<OpenF1Session?> getLatestSession() async {
    final rows = await _get('sessions?session_key=latest');
    if (rows.isEmpty) return null;
    return OpenF1Session.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Every session of one race weekend.
  Future<List<OpenF1Session>> getMeetingSessions(int meetingKey) async {
    final rows = await _get('sessions?meeting_key=$meetingKey');
    return rows
        .map((row) => OpenF1Session.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Finds the OpenF1 race that starts at the same time as a Jolpica race.
  /// This is how the two APIs get joined together.
  Future<OpenF1Session?> findRace(DateTime raceStart) async {
    final year = raceStart.toUtc().year;
    final rows = await _get('sessions?year=$year&session_name=Race');
    for (final row in rows) {
      final session = OpenF1Session.fromJson(row as Map<String, dynamic>);
      final gap = session.start.difference(raceStart).abs();
      if (gap < const Duration(hours: 3)) return session;
    }
    return null;
  }

  // ------------------------------------------------------------------
  // Drivers, laps, positions and locations
  // ------------------------------------------------------------------

  Future<List<DriverInfo>> getDrivers(int sessionKey) async {
    final rows = await _get('drivers?session_key=$sessionKey');
    return rows
        .map((row) => DriverInfo.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// One lap, or null if OpenF1 does not have it.
  Future<Lap?> getLap(int sessionKey, int driverNumber, int lapNumber) async {
    final rows = await _get(
      'laps?session_key=$sessionKey'
      '&driver_number=$driverNumber&lap_number=$lapNumber',
    );
    if (rows.isEmpty) return null;
    return Lap.fromJson(rows.first as Map<String, dynamic>);
  }

  /// Every position change in a session, or only those after [after].
  Future<List<PositionUpdate>> getPositions(
    int sessionKey, {
    DateTime? after,
  }) async {
    var query = 'position?session_key=$sessionKey';
    if (after != null) query += '&date>${_time(after)}';
    final rows = await _get(query);
    return rows
        .map((row) => PositionUpdate.fromJson(row as Map<String, dynamic>))
        .toList();
  }

  /// Where the cars were between [from] and [to].
  /// Leave out [driverNumber] to get every car at once.
  Future<List<CarLocation>> getLocations(
    int sessionKey, {
    required DateTime from,
    DateTime? to,
    int? driverNumber,
  }) async {
    var query = 'location?session_key=$sessionKey&date>${_time(from)}';
    if (to != null) query += '&date<${_time(to)}';
    if (driverNumber != null) query += '&driver_number=$driverNumber';
    final rows = await _get(query);
    return rows
        .map((row) => CarLocation.fromJson(row as Map<String, dynamic>))
        .toList();
  }
}
