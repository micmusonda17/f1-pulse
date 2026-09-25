import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:flutter/foundation.dart';

import '../config.dart';
import '../models/openf1_models.dart';
import '../models/race.dart';
import '../services/api_exception.dart';
import '../services/jolpica_api.dart';
import '../services/openf1_api.dart';
import '../services/settings_store.dart';
import '../stats/strategy.dart';
import 'race_status.dart';
import 'track3d.dart';
import 'tracker_math.dart';

/// Replay plays back a finished session. Live follows one happening now.
enum TrackerMode { replay, live }

/// The brain of the tracker screen.
///
/// It loads the data, keeps a race clock ticking, and works out where every
/// car is. It knows nothing about widgets. The screen listens to it and
/// redraws whenever it calls notifyListeners().
class TrackerController extends ChangeNotifier {
  TrackerController({
    required this.session,
    required this.mode,
    this.saveData = false,
  }) : clock = mode == TrackerMode.live ? _liveClock() : session.start;

  final OpenF1Session session;
  final TrackerMode mode;
  final bool saveData; // Data saver: see placesCarsByLaps
  final OpenF1Api _api = OpenF1Api.instance;

  // ------------------------------------------------------------------
  // What the screen reads
  // ------------------------------------------------------------------

  bool isLoading = true;
  String? error; // A problem that stops the tracker completely
  String? message; // Loading steps, or a small warning while running
  Map<int, DriverInfo> drivers = {};
  List<Offset> trackOutline = [];
  List<Point3> trackOutline3d = []; // The same lap, with heights (Chapter 55)
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
  Map<int, List<Lap>> _lapsByDriver = {}; // The same laps, per driver
  List<Stint> _stints = [];
  List<PitStop> _pitStops = [];
  List<RaceControlMessage> _messages = [];
  List<WeatherReading> _weather = [];
  Map<String, String> _statusByCode = {}; // Jolpica: "LEC" -> "Engine"
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

  /// Data saver in a replay: place the cars from their lap times instead
  /// of downloading their GPS positions (Chapter 43). Live always uses GPS,
  /// because lap times only arrive once a lap is over.
  bool get placesCarsByLaps => saveData && mode == TrackerMode.replay;

  /// Where every car is at [clock].
  Map<int, Offset> get carPositions {
    final result = <int, Offset>{};
    if (placesCarsByLaps) {
      for (final entry in _lapsByDriver.entries) {
        final point = positionFromLaps(entry.value, trackOutline, clock);
        if (point != null) result[entry.key] = point;
      }
      return result;
    }
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
  int? get currentLap => countsLaps ? lapAt(_lapTimeline, clock) : null;

  /// Races and sprints count laps. OpenF1 calls both of them type "Race".
  bool get countsLaps => session.type == 'Race';

  /// Practice and qualifying are about one fast lap, so the running order
  /// shows each driver's best lap time instead.
  bool get showsLapTimes => !countsLaps;

  /// Each driver's best lap so far at [clock], in seconds. Empty in races.
  Map<int, double> get bestLaps =>
      showsLapTimes ? bestLapsAt(_laps, clock) : const {};

  /// The tyre each car is on at [clock]: "SOFT", "MEDIUM", "HARD"...
  Map<int, String> get tyres {
    final result = <int, String>{};
    for (final number in drivers.keys) {
      final lap = driverLapAt(_lapsByDriver[number] ?? const [], clock);
      final compound = compoundOn(_stints, number, lap ?? 1);
      if (compound != null) result[number] = compound;
    }
    return result;
  }

  /// How many laps the tyres each car is on have done at [clock].
  Map<int, int> get tyreAges {
    final result = <int, int>{};
    for (final number in drivers.keys) {
      final lap = driverLapAt(_lapsByDriver[number] ?? const [], clock);
      final age = tyreAgeOn(_stints, number, lap ?? 1);
      if (age != null) result[number] = age;
    }
    return result;
  }

  /// A short note for each car that has one, like "In the garage  ·  6
  /// laps" or "In the pit lane  ·  1 stop". Cars that are out get a note
  /// of their own, from outNotes.
  Map<int, String> get carNotes {
    final garage = inGarage;
    final result = <int, String>{};
    for (final number in drivers.keys) {
      final notes = <String>[];
      if (garage.contains(number)) {
        notes.add('In the garage');
      } else if (isInPitLane(_pitStops, number, clock)) {
        notes.add('In the pit lane');
      }
      if (countsLaps) {
        final stops = pitStopsBefore(_pitStops, number, clock);
        if (stops > 0) notes.add(stops == 1 ? '1 stop' : '$stops stops');
      } else {
        // Practice and qualifying: how many laps they have done so far.
        final done = lapsCompleted(_lapsByDriver[number] ?? const [], clock);
        if (done > 0) notes.add(done == 1 ? '1 lap' : '$done laps');
      }
      if (notes.isNotEmpty) result[number] = notes.join('  ·  ');
    }
    return result;
  }

  /// The latest race control message, if it came in the last minute.
  RaceControlMessage? get latestMessage => latestMessageAt(_messages, clock);

  /// Qualifying only: which part is running, Q1, Q2 or Q3.
  int? get qualifyingPhase =>
      session.type == 'Qualifying' ? qualifyingPhaseAt(_messages, clock) : null;

  /// The weather at the track at [clock].
  WeatherReading? get weather => weatherAt(_weather, clock);

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
  // Who is out, flags, gaps and the fastest lap (Chapters 52 and 53)
  // ------------------------------------------------------------------

  /// Everyone who is out at [clock], and why: knocked out of qualifying,
  /// retired from a race, or never started.
  Map<int, String> get outNotes {
    final result = <int, String>{};
    final phase = qualifyingPhase;
    if (phase != null) {
      final order = runningOrder;
      final out = knockedOutAt(order, phase, drivers.length);
      for (final entry in out.entries) {
        final place = order.indexOf(entry.key) + 1;
        result[entry.key] = 'Knocked out in Q${entry.value}, P$place';
      }
      return result;
    }
    if (!countsLaps) return result; // Nobody is out of practice

    final retired = findRetirements(
      _lapsByDriver,
      clock: clock,
      chequered: _chequeredFlag,
      pitStops: _pitStops,
    );
    for (final entry in retired.entries) {
      final code = drivers[entry.key]?.acronym;
      final about =
          messagesAbout(_messages, entry.key, code: code, until: clock);
      result[entry.key] = retirementNote(
        entry.value,
        status: code == null ? null : _statusByCode[code],
        message: explainingMessage(about, entry.value.at),
      );
    }
    // A car with no laps at all, once the race is under way, never started.
    final lightsOut = _lapTimeline.isEmpty ? null : _lapTimeline.first.date;
    if (lightsOut != null &&
        clock.isAfter(lightsOut.add(const Duration(minutes: 2)))) {
      for (final number in drivers.keys) {
        if ((_lapsByDriver[number] ?? const []).isEmpty) {
          result[number] = 'Did not start';
        }
      }
    }
    return result;
  }

  /// When the chequered flag came out, if it has (races only).
  DateTime? get _chequeredFlag {
    for (final message in _messages) {
      if (message.flag == 'CHEQUERED') return message.date;
    }
    return null;
  }

  /// The race gaps at [clock] for the cars still racing, in [running]
  /// order: to the car ahead and to the leader. Empty outside races.
  Map<int, CarGaps> gapsFor(List<int> running) =>
      countsLaps ? gapsAt(_lapsByDriver, running, clock) : const {};

  /// Green, yellow, safety car, red or chequered, at [clock].
  TrackState get trackState => trackStateAt(_messages, clock);

  /// The fastest lap of the session so far.
  Lap? get fastestLapSoFar => fastestLapAt(_laps, clock);

  /// Races with a known length: how many laps are left after this one.
  int? get lapsToGo {
    final total = totalLaps;
    final lap = currentLap;
    if (total == null || lap == null) return null;
    return math.max(0, total - lap);
  }

  /// The highest lap number anyone has started: the length of the
  /// strategy chart in practice and qualifying.
  int get highestLap {
    var highest = 1;
    for (final lap in _laps) {
      highest = math.max(highest, lap.lapNumber);
    }
    return highest;
  }

  /// Tyres and pit stops so far, for the drivers in [order] (Chapter 54).
  List<DriverStrategy> strategiesNow(List<int> order) => strategies(
        order: order,
        stints: _stints,
        pitStops: _pitStops,
        lapsByDriver: _lapsByDriver,
        until: clock,
      );

  /// Race control's messages about one car, up to [clock].
  List<RaceControlMessage> messagesFor(int number) => messagesAbout(
        _messages,
        number,
        code: drivers[number]?.acronym,
        until: clock,
      );

  // ------------------------------------------------------------------
  // The 3D view (Chapter 55)
  // ------------------------------------------------------------------

  /// The clock between ticks. The 3D view draws every frame, about 60
  /// times a second, so it adds the time since the last tick (at the
  /// playing speed) to move the cars smoothly.
  DateTime smoothClock() {
    if (mode == TrackerMode.live) return _liveClock();
    if (!isPlaying) return clock;
    var since = DateTime.now().difference(_lastTick);
    if (since > const Duration(milliseconds: 250)) {
      since = const Duration(milliseconds: 250);
    }
    return clock.add(since * speed);
  }

  /// Every car's position in 3D at [time].
  Map<int, Point3> carPositions3dAt(DateTime time) {
    final numbers = placesCarsByLaps ? _lapsByDriver.keys : _locations.keys;
    final result = <int, Point3>{};
    for (final number in numbers) {
      final point = carPosition3dAt(number, time);
      if (point != null) result[number] = point;
    }
    return result;
  }

  /// One car's position in 3D at [time], or null if it is not on track.
  Point3? carPosition3dAt(int number, DateTime time) {
    if (placesCarsByLaps) {
      final fraction = lapProgressAt(_lapsByDriver[number] ?? const [], time);
      return fraction == null ? null : pointAlong3(trackOutline3d, fraction);
    }
    final points = _locations[number];
    if (points == null || isInGarageAt(points, time)) return null;
    return position3At(points, time);
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

      _setMessage('Loading tyres, pit stops and flags');
      await _loadExtras();
      await _loadStatuses();

      _setMessage('Drawing the track');
      final outline = await _loadOutline();
      trackOutline = [for (final point in outline) Offset(point.x, point.y)];
      trackOutline3d = [for (final point in outline) pointOf(point)];

      if (placesCarsByLaps) {
        // Data saver: the lap times are all we need. No GPS downloads.
        if (trackOutline.isEmpty) {
          throw const ApiException(
            'Data saver draws the cars along the track outline, and OpenF1 '
            'has no outline for this session. Switch data saver off in '
            'Settings to watch it with GPS.',
          );
        }
      } else if (mode == TrackerMode.replay) {
        _setMessage('Finding the cars');
        await _loadWindow(clock);
      } else {
        _setMessage('Finding the cars');
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

  /// Draws the circuit by following one car around one full lap. The
  /// points keep their heights, for the 3D view.
  Future<List<CarLocation>> _loadOutline() async {
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
  Future<List<CarLocation>> _outlineFromLap(int sessionKey, Lap lap) async {
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
    return points.length <= 50 ? [] : points;
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
    if (placesCarsByLaps) {
      _notify(); // Nothing to download: the lap times cover every moment
      return;
    }
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
    if (placesCarsByLaps) return; // Data saver never downloads GPS
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
      if (lapsDue) {
        await _updateLaps();
        await _loadExtras();
      }
      message = null;
    } on ApiException catch (e) {
      message = e.message;
    } finally {
      _fetching = false;
    }
  }

  /// Downloads the laps: for the lap counter in races, and the lap times
  /// in practice and qualifying. The first time, that is every lap so far.
  /// After that (live only) it is every lap started in the last five
  /// minutes: a lap only gets its time when it ends, so those fresh copies
  /// replace the ones we have. Every car's latest laps, not just the
  /// leader's, keep the tyres, gaps and retirements right (Chapter 52).
  Future<void> _updateLaps() async {
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
      _lapsByDriver = lapsByDriver(_laps);
      if (countsLaps) {
        _lapTimeline = buildLapTimeline(_laps);
        if (mode == TrackerMode.replay && _lapTimeline.isNotEmpty) {
          totalLaps = _lapTimeline.last.lap; // The last lap anyone started
        }
      }
    } on ApiException {
      // The tracker works without laps: no counter and no times.
    }
  }

  /// Tyres, pit stops, race control and weather. Small downloads, and the
  /// tracker works without any of them, so each one fails quietly.
  Future<void> _loadExtras() async {
    final key = session.sessionKey;
    _stints = await _quietly(() => _api.getStints(key), _stints);
    _pitStops = await _quietly(() => _api.getPitStops(key), _pitStops);
    _messages = await _quietly(() => _api.getRaceControl(key), _messages);
    _weather = await _quietly(() => _api.getWeather(key), _weather);
  }

  /// Race and sprint replays: Jolpica's reason for each retirement, like
  /// "Engine" or "Collision", by driver code (Chapter 52). It stays empty
  /// when Jolpica has no results yet, and the notes just give the lap.
  Future<void> _loadStatuses() async {
    if (!countsLaps || mode == TrackerMode.live) return;
    try {
      final api = JolpicaApi();
      final season = session.start.year;
      final race = raceNear(
        await api.getSchedule(season: '$season'),
        session.start,
      );
      if (race == null) return;
      final results = session.name == 'Sprint'
          ? await api.getSprintResults(season, race.round)
          : await api.getResults(season, race.round);
      _statusByCode = {
        for (final result in results) result.driver.code: result.status,
      };
    } catch (_) {
      // No reasons from Jolpica. Race control may still explain.
    }
  }

  /// Runs [download]. If it fails, keeps [fallback], what we had before.
  /// `<T>` makes it work for a list of anything: stints, stops, messages.
  Future<List<T>> _quietly<T>(
    Future<List<T>> Function() download,
    List<T> fallback,
  ) async {
    try {
      return await download();
    } on ApiException {
      return fallback;
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
