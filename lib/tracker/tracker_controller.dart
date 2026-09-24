import 'dart:async';
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../models/openf1_models.dart';
import '../services/api_exception.dart';
import '../services/openf1_api.dart';
import '../services/settings_store.dart';
import 'tracker_math.dart';

/// Replay plays back a finished session. Live follows one happening now.
enum TrackerMode { replay, live }

/// The brain of the tracker screen.
///
/// It loads the data, keeps a race clock ticking, and works out where every
/// car is. It knows nothing about widgets. The screen listens to it and
/// redraws whenever it calls notifyListeners().
class TrackerController extends ChangeNotifier {
  TrackerController({required this.session, required this.mode})
      : clock = mode == TrackerMode.live ? _liveClock() : session.start;

  final OpenF1Session session;
  final TrackerMode mode;
  final OpenF1Api _api = OpenF1Api.instance;

  // ------------------------------------------------------------------
  // What the screen reads
  // ------------------------------------------------------------------

  bool isLoading = true;
  String? error; // A problem that stops the tracker completely
  String? message; // Loading steps, or a small warning while running
  Map<int, DriverInfo> drivers = {};
  List<Offset> trackOutline = [];
  DateTime clock; // The moment of the race we are showing
  bool isPlaying = false;
  int speed = 1;
  int? totalLaps; // Replays only: how many laps the race had

  static const List<int> speeds = [1, 5, 10, 20];

  // ------------------------------------------------------------------
  // What we keep behind the scenes
  // ------------------------------------------------------------------

  final Map<int, List<CarLocation>> _locations = {}; // driver -> points
  final List<PositionUpdate> _positions = [];
  final List<Lap> _laps = []; // For the lap counter
  List<LapMark> _lapTimeline = [];
  DateTime _lastLapPoll = DateTime(2000);
  DateTime? _loadedUntil; // Replay: we have car data up to here
  DateTime? _liveCursor; // Live: the newest car data we have
  DateTime? _positionCursor; // Live: the newest position data we have
  bool _fetching = false;
  int _generation = 0; // Goes up every time the user jumps with the slider
  DateTime _retryAfter = DateTime(2000);
  Timer? _ticker;
  DateTime _lastTick = DateTime.now();
  DateTime _lastPoll = DateTime(2000);
  bool _disposed = false;

  static DateTime _liveClock() =>
      DateTime.now().toUtc().subtract(AppConfig.liveDelay);

  /// How far into the session we are.
  Duration get elapsed => clock.difference(session.start);

  /// How long the session is scheduled to last.
  Duration get length => session.end.difference(session.start);

  /// Where every car is at [clock].
  Map<int, Offset> get carPositions {
    final result = <int, Offset>{};
    for (final entry in _locations.entries) {
      if (isInGarageAt(entry.value, clock)) continue; // Not on track
      final point = positionAt(entry.value, clock);
      if (point != null) result[entry.key] = point;
    }
    return result;
  }

  /// Driver numbers of the cars sitting in their garage at [clock].
  Set<int> get inGarage => {
        for (final entry in _locations.entries)
          if (isInGarageAt(entry.value, clock)) entry.key,
      };

  /// Driver numbers in race order at [clock], leader first.
  List<int> get runningOrder => runningOrderAt(_positions, clock);

  /// The race's lap at [clock], or null before the start (and in practice
  /// or qualifying, where a lap count means nothing).
  int? get currentLap => lapAt(_lapTimeline, clock);

  /// Races and sprints count laps. OpenF1 calls both of them type "Race".
  bool get countsLaps => session.type == 'Race';

  /// Practice and qualifying are about one fast lap, so the running order
  /// shows each driver's best lap time instead.
  bool get showsLapTimes => !countsLaps;

  /// Each driver's best lap so far at [clock], in seconds. Empty in races.
  Map<int, double> get bestLaps =>
      showsLapTimes ? bestLapsAt(_laps, clock) : const {};

  /// Practice only: how long the session has left at [clock], like the
  /// clock on the TV. Null before the start and after the end.
  Duration? get timeLeft {
    if (session.type != 'Practice') return null;
    if (clock.isBefore(session.start) || clock.isAfter(session.end)) {
      return null;
    }
    return session.end.difference(clock);
  }

  // ------------------------------------------------------------------
  // Starting up
  // ------------------------------------------------------------------

  Future<void> start() async {
    try {
      if (mode == TrackerMode.live) {
        _setMessage('Signing in to OpenF1');
        final signedIn = await signInWithSavedLogin();
        if (!signedIn) {
          throw const ApiException(
            'Live data needs an OpenF1 sponsor login. Add it in Settings.',
          );
        }
      }

      _setMessage('Loading drivers');
      final driverList = await _api.getDrivers(session.sessionKey);
      drivers = {for (final driver in driverList) driver.number: driver};

      _setMessage('Loading the running order');
      _positions.addAll(await _api.getPositions(session.sessionKey));
      _positions.sort((a, b) => a.date.compareTo(b.date));
      if (_positions.isNotEmpty) _positionCursor = _positions.last.date;

      _setMessage(countsLaps ? 'Counting the laps' : 'Loading lap times');
      await _updateLaps();

      _setMessage('Drawing the track');
      trackOutline = await _loadOutline();

      _setMessage('Finding the cars');
      if (mode == TrackerMode.replay) {
        await _loadWindow(clock);
      } else {
        await _pollLive();
      }

      isLoading = false;
      message = null;
      _notify();
      if (mode == TrackerMode.live) play(); // Live never pauses
    } on ApiException catch (e) {
      error = e.message;
      isLoading = false;
      _notify();
    } catch (e) {
      // Anything we did not expect, like OpenF1 changing its data format.
      error = 'Something went wrong loading this session: $e';
      isLoading = false;
      _notify();
    }
  }

  /// Draws the circuit by following one car around one full lap.
  Future<List<Offset>> _loadOutline() async {
    final sessionsToTry = <OpenF1Session>[session];
    if (mode == TrackerMode.live) {
      // Early in a live session nobody has done three laps yet, so we also
      // try the sessions that already finished this weekend, newest first.
      final weekend = await _api.getMeetingSessions(session.meetingKey);
      final finished = weekend
          .where((s) => s.sessionKey != session.sessionKey && s.hasFinished)
          .toList();
      finished.sort((a, b) => b.start.compareTo(a.start));
      sessionsToTry.addAll(finished);
    }

    // Practice and qualifying: the fastest lap of the session is flat out
    // all the way round, so it draws the cleanest outline. (Lap 3 is often
    // a slow lap into the pits there.)
    final fastest = showsLapTimes ? fastestLap(_laps) : null;
    if (fastest != null) {
      final outline = await _outlineFromLap(session.sessionKey, fastest);
      if (outline.isNotEmpty) return outline;
    }

    final order = runningOrder;
    final driverNumbers = order.isNotEmpty ? order : drivers.keys.toList();

    for (final trySession in sessionsToTry) {
      for (final number in driverNumbers.take(3)) {
        // Lap 3: the car is up to speed and not leaving the pits.
        final lap = await _api.getLap(trySession.sessionKey, number, 3);
        if (lap == null) continue;
        final outline = await _outlineFromLap(trySession.sessionKey, lap);
        if (outline.isNotEmpty) return outline;
      }
    }
    return []; // No outline. The painter will still draw the cars.
  }

  /// The points one car drove during one lap, joined up into an outline.
  /// Empty if the lap has no time or OpenF1 has too few points for it.
  Future<List<Offset>> _outlineFromLap(int sessionKey, Lap lap) async {
    final lapStart = lap.start;
    final lapSeconds = lap.duration;
    if (lapStart == null || lapSeconds == null) return [];

    final lapEnd =
        lapStart.add(Duration(milliseconds: (lapSeconds * 1000).round()));
    final points = await _api.getLocations(
      sessionKey,
      from: lapStart,
      to: lapEnd,
      driverNumber: lap.driverNumber,
    );
    if (points.length <= 50) return [];
    return [for (final point in points) Offset(point.x, point.y)];
  }

  // ------------------------------------------------------------------
  // Play, pause, speed and jumping around
  // ------------------------------------------------------------------

  void play() {
    if (isPlaying) return;
    isPlaying = true;
    _lastTick = DateTime.now();
    // Ten ticks a second is smooth enough for dots on a map.
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) => _tick());
    _notify();
  }

  void pause() {
    isPlaying = false;
    _ticker?.cancel();
    _ticker = null;
    _notify();
  }

  /// 1x, 5x, 10x, 20x, then back to 1x.
  void cycleSpeed() {
    final index = speeds.indexOf(speed);
    speed = speeds[(index + 1) % speeds.length];
    _notify();
  }

  /// Jump to a moment in the replay (used by the slider).
  Future<void> seekTo(DateTime time) async {
    _generation++; // Any download still running is now out of date
    _fetching = false;
    _locations.clear();
    _loadedUntil = null;
    clock = time;
    message = 'Finding the cars';
    _notify();
    await _loadWindow(time);
    _notify();
  }

  // ------------------------------------------------------------------
  // The clock
  // ------------------------------------------------------------------

  void _tick() {
    final now = DateTime.now();
    final realTimePassed = now.difference(_lastTick);
    _lastTick = now;

    if (mode == TrackerMode.live) {
      clock = _liveClock();
      if (now.difference(_lastPoll) >= AppConfig.livePollEvery) {
        unawaited(_pollLive());
      }
    } else {
      clock = clock.add(realTimePassed * speed);
      if (!clock.isBefore(session.end)) {
        clock = session.end;
        pause();
      }
      _loadMoreIfNeeded();
    }

    _dropOldPoints();
    _notify();
  }

  /// Replay: download the next minute of data before we run out.
  void _loadMoreIfNeeded() {
    if (_fetching || DateTime.now().isBefore(_retryAfter)) return;

    final loadedUntil = _loadedUntil;
    if (loadedUntil == null) {
      unawaited(_loadWindow(clock));
      return;
    }
    final timeLeft = loadedUntil.difference(clock);
    if (loadedUntil.isBefore(session.end) &&
        timeLeft < const Duration(seconds: 20)) {
      // If we fell behind (slow internet), skip ahead to where the clock is.
      final from = loadedUntil.isBefore(clock) ? clock : loadedUntil;
      unawaited(_loadWindow(from));
    }
  }

  // ------------------------------------------------------------------
  // Downloading car data
  // ------------------------------------------------------------------

  /// Replay: download one window (a minute) of every car's location.
  Future<void> _loadWindow(DateTime from) async {
    final myGeneration = _generation;
    _fetching = true;
    try {
      final to = from.add(AppConfig.replayWindow);
      final points = await _api.getLocations(
        session.sessionKey,
        from: from,
        to: to,
      );
      // If the user moved the slider while we waited, this data is stale.
      if (myGeneration != _generation) return;
      _addLocations(points);
      _loadedUntil = to;
      message = null;
    } on ApiException catch (e) {
      if (myGeneration == _generation) {
        message = e.message;
        _retryAfter = DateTime.now().add(const Duration(seconds: 5));
      }
    } finally {
      if (myGeneration == _generation) _fetching = false;
    }
  }

  /// Live: ask for everything newer than what we already have.
  Future<void> _pollLive() async {
    if (_fetching) return;
    _fetching = true;
    _lastPoll = DateTime.now();
    try {
      await signInWithSavedLogin(); // Renews the token when it runs out

      final from = _liveCursor ??
          DateTime.now().toUtc().subtract(const Duration(seconds: 30));
      final points = await _api.getLocations(session.sessionKey, from: from);
      _addLocations(points);
      for (final point in points) {
        final cursor = _liveCursor;
        if (cursor == null || point.date.isAfter(cursor)) {
          _liveCursor = point.date;
        }
      }

      final updates = await _api.getPositions(
        session.sessionKey,
        after: _positionCursor,
      );
      if (updates.isNotEmpty) {
        _positions.addAll(updates);
        _positions.sort((a, b) => a.date.compareTo(b.date));
        _positionCursor = _positions.last.date;
      }

      final lapsDue =
          DateTime.now().difference(_lastLapPoll) >= AppConfig.lapPollEvery;
      if (lapsDue) await _updateLaps();
      message = null;
    } on ApiException catch (e) {
      message = e.message;
    } finally {
      _fetching = false;
    }
  }

  /// Races download laps for the lap counter; practice and qualifying
  /// download them for the lap times.
  Future<void> _updateLaps() => countsLaps ? _loadLaps() : _loadLapTimes();

  /// Downloads laps for the lap counter. The first time that is every lap
  /// so far. After that (live only) it is just the laps numbered higher
  /// than the race's current lap, which is all the counter needs.
  Future<void> _loadLaps() async {
    _lastLapPoll = DateTime.now();
    final highest = _lapTimeline.isEmpty ? 0 : _lapTimeline.last.lap;
    try {
      final newLaps = await _api.getLaps(session.sessionKey, above: highest);
      if (newLaps.isEmpty) return;
      _laps.addAll(newLaps);
      _lapTimeline = buildLapTimeline(_laps);
      if (mode == TrackerMode.replay && _lapTimeline.isNotEmpty) {
        totalLaps = _lapTimeline.last.lap; // The last lap anyone started
      }
    } on ApiException {
      // The tracker works fine without the counter, so we just leave it out.
    }
  }

  /// Downloads laps for the lap times in practice and qualifying.
  ///
  /// A lap only gets its time when it ends, so a live session cannot just
  /// ask for laps it has not seen. Instead it asks for every lap started in
  /// the last five minutes, and those replace the copies we already have.
  Future<void> _loadLapTimes() async {
    _lastLapPoll = DateTime.now();
    final since = mode == TrackerMode.live && _laps.isNotEmpty
        ? DateTime.now().toUtc().subtract(const Duration(minutes: 5))
        : null;
    try {
      final laps = await _api.getLaps(session.sessionKey, startedAfter: since);
      String keyOf(Lap lap) => '${lap.driverNumber}-${lap.lapNumber}';
      final fresh = {for (final lap in laps) keyOf(lap)};
      _laps.removeWhere((lap) => fresh.contains(keyOf(lap)));
      _laps.addAll(laps);
    } on ApiException {
      // No lap times this time. The map and the order still work.
    }
  }

  void _addLocations(List<CarLocation> points) {
    for (final point in points) {
      _locations.putIfAbsent(point.driverNumber, () => []).add(point);
    }
    for (final list in _locations.values) {
      list.sort((a, b) => a.date.compareTo(b.date));
    }
  }

  /// Throw away points more than 10 seconds behind the clock, so memory
  /// does not fill up during a two hour race.
  void _dropOldPoints() {
    final cutoff = clock.subtract(const Duration(seconds: 10));
    for (final list in _locations.values) {
      final index = firstIndexAfter(list, cutoff);
      if (index > 1) list.removeRange(0, index - 1);
    }
  }

  // ------------------------------------------------------------------
  // Tidying up
  // ------------------------------------------------------------------

  void _setMessage(String text) {
    message = text;
    _notify();
  }

  /// notifyListeners() crashes after dispose(), and downloads can finish
  /// after the user has left the screen. So we always go through here.
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    super.dispose();
  }
}
