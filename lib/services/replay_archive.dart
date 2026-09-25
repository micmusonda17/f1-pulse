import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/openf1_models.dart';
import '../tracker/tracker_math.dart';
import 'api_exception.dart';
import 'openf1_api.dart';

// Replays saved on the phone (Chapter 56). While any session is live,
// OpenF1 turns away everyone without a sponsor login, even for old races.
// So Pitbeat quietly saves every finished session of the season while
// OpenF1 is open, and plays the saved copy when it is not.

/// One session, saved: OpenF1's own rows for everything the tracker and the
/// analysis need, plus one lap of GPS for the track's outline. There is no
/// GPS for every car (about 50 MB a race), so a saved replay places the
/// cars from their lap times, like data saver (Chapter 43).
class SavedReplay {
  SavedReplay(this.rows);

  /// 'laps' -> OpenF1's laps rows, 'session' -> one sessions row, and so on.
  final Map<String, List<dynamic>> rows;

  OpenF1Session? get session {
    final list = rows['session'];
    if (list == null || list.isEmpty) return null;
    return OpenF1Session.fromJson(list.first as Map<String, dynamic>);
  }

  List<DriverInfo> get drivers => _parse(rows['drivers'], DriverInfo.fromJson);
  List<Lap> get laps => _parse(rows['laps'], Lap.fromJson);
  List<Stint> get stints => _parse(rows['stints'], Stint.fromJson);

  // The ones where order matters come back sorted by time, the same as
  // OpenF1Api hands them over.
  List<PositionUpdate> get positions =>
      _parse(rows['position'], PositionUpdate.fromJson)
        ..sort((a, b) => a.date.compareTo(b.date));
  List<PitStop> get pitStops => _parse(rows['pit'], PitStop.fromJson)
    ..sort((a, b) => a.date.compareTo(b.date));
  List<RaceControlMessage> get messages =>
      _parse(rows['race_control'], RaceControlMessage.fromJson)
        ..sort((a, b) => a.date.compareTo(b.date));
  List<WeatherReading> get weather =>
      _parse(rows['weather'], WeatherReading.fromJson)
        ..sort((a, b) => a.date.compareTo(b.date));
  List<CarLocation> get outline =>
      _parse(rows['outline'], CarLocation.fromJson)
        ..sort((a, b) => a.date.compareTo(b.date));

  /// Rows into objects with a model's fromJson. `<T>` is the model.
  static List<T> _parse<T>(
    List<dynamic>? list,
    T Function(Map<String, dynamic>) fromJson,
  ) =>
      [for (final row in list ?? const []) fromJson(row as Map<String, dynamic>)];
}

/// A saved replay as bytes: JSON, squeezed with gzip to about a sixth.
List<int> encodeReplay(SavedReplay replay) =>
    gzip.encode(utf8.encode(jsonEncode(replay.rows)));

/// The bytes back into a replay. Damaged bytes give null.
SavedReplay? decodeReplay(List<int> bytes) {
  try {
    final json = jsonDecode(utf8.decode(gzip.decode(bytes)));
    return SavedReplay({
      for (final entry in (json as Map<String, dynamic>).entries)
        entry.key: entry.value as List<dynamic>,
    });
  } catch (_) {
    return null;
  }
}

/// The sessions worth saving, newest first: over for at least an hour (so
/// OpenF1 has all of their data), not cancelled, and not saved already.
List<OpenF1Session> sessionsToSave(
  List<OpenF1Session> all,
  Set<int> saved,
  DateTime now,
) {
  return [
    for (final session in all)
      if (!session.isCancelled &&
          !saved.contains(session.sessionKey) &&
          now.isAfter(session.end.add(const Duration(hours: 1))))
        session,
  ]..sort((a, b) => b.start.compareTo(a.start));
}

/// Where saved replays are kept. The phone uses files; the tests a Map.
abstract class ReplayStore {
  Future<List<int>?> read(String name);
  Future<void> write(String name, List<int> bytes);
  Future<void> deleteAll();
}

/// Files in the app's own folder, which the phone keeps until the app is
/// deleted.
class FileReplayStore implements ReplayStore {
  Future<Directory>? _folder;

  // ??= : made the first time it is needed, then reused.
  Future<Directory> get _dir => _folder ??= _open();

  static Future<Directory> _open() async {
    final base = await getApplicationSupportDirectory();
    final folder = Directory('${base.path}/replays');
    await folder.create(recursive: true);
    return folder;
  }

  @override
  Future<List<int>?> read(String name) async {
    final file = File('${(await _dir).path}/$name');
    if (!await file.exists()) return null;
    return file.readAsBytes();
  }

  @override
  Future<void> write(String name, List<int> bytes) async {
    final file = File('${(await _dir).path}/$name');
    await file.writeAsBytes(bytes, flush: true);
  }

  @override
  Future<void> deleteAll() async {
    final folder = await _dir;
    if (await folder.exists()) await folder.delete(recursive: true);
    _folder = null; // Made again, empty, next time
  }
}

/// One saved session in the list of what is on the phone.
class _Saved {
  const _Saved(this.session, this.row, this.bytes);

  final OpenF1Session session;
  final Map<String, dynamic> row; // OpenF1's sessions row, to save again
  final int bytes;
}

/// Every replay saved on the phone, and the saving itself.
class ReplayArchive extends ChangeNotifier {
  ReplayArchive({
    this.store,
    Future<List<dynamic>> Function(String)? fetch,
    Future<bool> Function()? onWifi,
    this.pace = const Duration(milliseconds: 2100),
  })  : _fetch = fetch ?? OpenF1Api.instance.getRows,
        _onWifi = onWifi ?? _wifiNow;

  /// The app's copy. No store on the web, where there are no files.
  static final ReplayArchive instance =
      ReplayArchive(store: kIsWeb ? null : FileReplayStore());

  final ReplayStore? store;
  final Future<List<dynamic>> Function(String) _fetch;
  final Future<bool> Function() _onWifi;

  /// The wait between requests. OpenF1's free tier allows 30 a minute.
  final Duration pace;

  static const String _indexName = 'index.json';
  final Map<int, _Saved> _saved = {}; // Session key -> saved session
  bool _loaded = false;
  int _holds = 0; // Screens that need OpenF1's queue to themselves

  bool isSaving = false;
  String? status; // What it is doing, for Settings

  bool get isSupported => store != null;
  bool isSaved(int sessionKey) => _saved.containsKey(sessionKey);

  /// Every saved session, newest first.
  List<OpenF1Session> get savedSessions => [
        for (final saved in _saved.values) saved.session,
      ]..sort((a, b) => b.start.compareTo(a.start));

  int get savedBytes {
    var total = 0;
    for (final saved in _saved.values) {
      total += saved.bytes;
    }
    return total;
  }

  /// Reads the list of saved sessions. Safe to call again: it only reads
  /// once.
  Future<void> load() async {
    final store = this.store;
    if (store == null || _loaded) return;
    _loaded = true;
    try {
      final bytes = await store.read(_indexName);
      if (bytes != null) {
        final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
        final items = (json['sessions'] as List<dynamic>)
            .cast<Map<String, dynamic>>();
        for (final item in items) {
          final row = item['row'] as Map<String, dynamic>;
          final session = OpenF1Session.fromJson(row);
          _saved[session.sessionKey] =
              _Saved(session, row, (item['bytes'] as int?) ?? 0);
        }
      }
    } catch (_) {
      _saved.clear(); // A damaged list: start again
    }
    notifyListeners();
  }

  /// The saved copy of one session, or null.
  Future<SavedReplay?> replayFor(int sessionKey) async {
    final store = this.store;
    if (store == null) return null;
    await load();
    if (!isSaved(sessionKey)) return null;
    final bytes = await store.read(_fileName(sessionKey));
    return bytes == null ? null : decodeReplay(bytes);
  }

  /// The saved session that starts at [start], like findSession.
  OpenF1Session? findSaved(DateTime start) =>
      closestSession(savedSessions, start);

  /// A replay or the analysis is open: let its downloads go first.
  void holdOff() => _holds++;

  void release() {
    if (_holds > 0) _holds--;
  }

  /// Saves every finished session of [year] (this year) that is not saved
  /// yet, newest first, one at a time. Only on Wi-Fi, unless [anyNetwork].
  /// Stops quietly as soon as OpenF1 says no, and carries on next time.
  Future<void> catchUp({bool anyNetwork = false, int? year}) async {
    final store = this.store;
    if (store == null || isSaving) return;
    isSaving = true;
    try {
      await load();
      if (!anyNetwork && !await _onWifi()) {
        _setStatus('Waiting for Wi-Fi');
        return;
      }
      _setStatus('Checking for new sessions');
      final rows = await _get('sessions?year=${year ?? DateTime.now().year}');
      final rowByKey = <int, Map<String, dynamic>>{};
      for (final row in rows.cast<Map<String, dynamic>>()) {
        rowByKey[OpenF1Session.fromJson(row).sessionKey] = row;
      }
      final todo = sessionsToSave(
        [for (final row in rowByKey.values) OpenF1Session.fromJson(row)],
        _saved.keys.toSet(),
        DateTime.now(),
      );
      for (var i = 0; i < todo.length; i++) {
        if (!anyNetwork && !await _onWifi()) {
          _setStatus('Waiting for Wi-Fi');
          return;
        }
        _setStatus('Saving ${todo[i].title} (${i + 1} of ${todo.length})');
        await saveSession(rowByKey[todo[i].sessionKey]!);
      }
      _setStatus('Every finished session is saved');
    } on ApiException {
      _setStatus(
        'Paused: OpenF1 is not answering, usually because a session is '
        'live. It carries on next time.',
      );
    } catch (_) {
      _setStatus('Could not save replays this time. It tries again later.');
    } finally {
      isSaving = false;
      notifyListeners();
    }
  }

  /// Downloads one session and saves it: eight requests.
  Future<void> saveSession(Map<String, dynamic> sessionRow) async {
    final store = this.store;
    if (store == null) return;
    final session = OpenF1Session.fromJson(sessionRow);
    final key = session.sessionKey;
    final laps = await _get('laps?session_key=$key');
    final replay = SavedReplay({
      'session': [sessionRow],
      'drivers': await _get('drivers?session_key=$key'),
      'position': await _get('position?session_key=$key'),
      'laps': laps,
      'stints': await _get('stints?session_key=$key'),
      'pit': await _get('pit?session_key=$key'),
      'race_control': await _get('race_control?session_key=$key'),
      'weather': await _get('weather?session_key=$key'),
      'outline': await _outlineRows(key, laps),
    });
    final bytes = encodeReplay(replay);
    await store.write(_fileName(key), bytes);
    _saved[key] = _Saved(session, sessionRow, bytes.length);
    await _saveList(store);
    notifyListeners();
  }

  /// Deletes every saved replay.
  Future<void> deleteAll() async {
    final store = this.store;
    if (store == null) return;
    await store.deleteAll();
    _saved.clear();
    _setStatus(null);
  }

  /// One request, after waiting its turn: while a replay or the analysis
  /// is open, and then [pace], so we stay under OpenF1's limit.
  Future<List<dynamic>> _get(String pathAndQuery) async {
    while (_holds > 0) {
      await Future<void>.delayed(const Duration(seconds: 3));
    }
    if (pace > Duration.zero) await Future<void>.delayed(pace);
    return _fetch(pathAndQuery);
  }

  /// One lap of GPS for the outline: the session's fastest lap, which is
  /// flat out all the way round (Chapter 41).
  Future<List<dynamic>> _outlineRows(int key, List<dynamic> lapRows) async {
    final fastest = fastestLap([
      for (final row in lapRows) Lap.fromJson(row as Map<String, dynamic>),
    ]);
    final start = fastest?.start;
    final seconds = fastest?.duration;
    if (fastest == null || start == null || seconds == null) return [];
    final end = start.add(Duration(milliseconds: (seconds * 1000).round()));
    return _get(
      'location?session_key=$key&driver_number=${fastest.driverNumber}'
      '&date>${start.toUtc().toIso8601String()}'
      '&date<${end.toUtc().toIso8601String()}',
    );
  }

  Future<void> _saveList(ReplayStore store) async {
    final json = {
      'sessions': [
        for (final saved in _saved.values)
          {'row': saved.row, 'bytes': saved.bytes},
      ],
    };
    await store.write(_indexName, utf8.encode(jsonEncode(json)));
  }

  String _fileName(int sessionKey) => 'session_$sessionKey.json.gz';

  void _setStatus(String? text) {
    status = text;
    notifyListeners();
  }

  /// True on Wi-Fi (or a cable). Mobile data costs money.
  static Future<bool> _wifiNow() async {
    try {
      final kinds = await Connectivity().checkConnectivity();
      return kinds.contains(ConnectivityResult.wifi) ||
          kinds.contains(ConnectivityResult.ethernet);
    } catch (_) {
      return false;
    }
  }
}

/// Finds the OpenF1 session that starts at [start], like
/// OpenF1Api.findSession, but falls back to the replays saved on the phone
/// when OpenF1 cannot answer.
Future<OpenF1Session?> findReplaySession(DateTime start) async {
  try {
    return await OpenF1Api.instance.findSession(start);
  } on ApiException {
    final archive = ReplayArchive.instance;
    await archive.load();
    final saved = archive.findSaved(start);
    if (saved != null) return saved;
    rethrow;
  }
}
