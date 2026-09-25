import 'package:flutter/material.dart';

import '../models/openf1_models.dart';
import '../models/race.dart';
import '../services/api_exception.dart';
import '../services/jolpica_api.dart';
import '../services/openf1_api.dart';
import '../services/replay_archive.dart';
import '../services/settings_store.dart';
import '../stats/timing_replay.dart';
import '../tracker/tracker_controller.dart';
import '../utils/formatting.dart';
import '../widgets/common_widgets.dart';
import 'settings_screen.dart';
import 'tracker_screen.dart';

/// The third tab: go live, or pick a session to replay.
class TrackerHubScreen extends StatefulWidget {
  const TrackerHubScreen({super.key});

  @override
  State<TrackerHubScreen> createState() => _TrackerHubScreenState();
}

class _TrackerHubScreenState extends State<TrackerHubScreen> {
  final OpenF1Api _api = OpenF1Api.instance;
  int _year = DateTime.now().year;
  late Future<List<OpenF1Session>> _sessions;
  String _kind = 'Race'; // Which chip is picked: an OpenF1 session type
  bool _checkingLive = false;
  String? _offlineNote; // Why the list is not from OpenF1, when it is not
  final Map<int, Race> _timingRaces = {}; // Made-up session key -> race

  /// The chips above the list: OpenF1's session type -> the chip's label.
  static const Map<String, String> _kinds = {
    'Race': 'Races',
    'Qualifying': 'Qualifying',
    'Practice': 'Practice',
  };

  @override
  void initState() {
    super.initState();
    _sessions = _loadSessions();
  }

  /// Every session from [_year] that has finished, newest first. The chips
  /// only filter this list, so switching chips needs no new download.
  Future<List<OpenF1Session>> _loadSessions() async {
    _offlineNote = null;
    _timingRaces.clear();
    try {
      final sessions = await _api.getSessions(_year);
      final finished =
          sessions.where((s) => s.hasFinished && !s.isCancelled).toList();
      finished.sort((a, b) => b.start.compareTo(a.start));
      return finished;
    } on ApiException {
      // While any session is live, OpenF1 shuts out everyone without a
      // sponsor login, even for old races. In a browser that looks like
      // "no internet", so we check the calendar and say what is going on.
      final live = await _liveSession();

      // The replays saved on the phone, and every race lap by lap from
      // Jolpica, still work (Chapters 56 and 57).
      final fallback = await _sessionsWithoutOpenF1();
      if (fallback.isNotEmpty) {
        final why = live == null
            ? 'OpenF1 cannot be reached right now'
            : '${live.name} is on, and OpenF1 only answers sponsors while '
                'a session is live';
        _offlineNote = '$why. Showing the replays saved on your phone, and '
            'every race lap by lap from Jolpica.';
        return fallback;
      }
      if (live != null) {
        throw ApiException(
          '${live.name} is on right now. While a session is live, OpenF1 '
          'only answers sponsors, even for old races. The replays come '
          'back when it ends.',
        );
      }
      rethrow; // Not a live session: keep the original message
    }
  }

  /// Without OpenF1: the sessions of [_year] saved on the phone, plus
  /// every finished race that is not saved, as a lap-by-lap replay.
  Future<List<OpenF1Session>> _sessionsWithoutOpenF1() async {
    final archive = ReplayArchive.instance;
    await archive.load();
    final sessions = [
      for (final session in archive.savedSessions)
        if (session.start.year == _year) session,
    ];
    try {
      final races = await JolpicaApi().getSchedule(season: '$_year');
      for (final race in races) {
        final start = race.start;
        if (!race.isFinished || start == null) continue;
        if (archive.findSaved(start) != null) continue; // Saved is better
        final session = timingSessionFor(race);
        _timingRaces[session.sessionKey] = race;
        sessions.add(session);
      }
    } catch (_) {
      // No calendar either: just what is saved.
    }
    sessions.sort((a, b) => b.start.compareTo(a.start));
    return sessions;
  }

  /// The session on right now, from the Jolpica calendar (which never
  /// locks anyone out). Null if nothing is on or the calendar fails too.
  Future<WeekendSession?> _liveSession() async {
    try {
      return findLiveSession(await JolpicaApi().getSchedule());
    } catch (_) {
      return null;
    }
  }

  void _pickYear(int year) {
    setState(() {
      _year = year;
      _sessions = _loadSessions();
    });
  }

  void _open(OpenF1Session session, TrackerMode mode, {Race? timingRace}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TrackerScreen(
          session: session,
          mode: mode,
          timingRace: timingRace,
        ),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  /// Checks whether anything is live, and opens it if we are allowed.
  Future<void> _goLive() async {
    setState(() => _checkingLive = true);
    try {
      await signInWithSavedLogin();
      final latest = await _api.getLatestSession();
      if (!mounted) return;

      if (latest == null || !latest.isLiveNow) {
        final text = latest == null
            ? 'OpenF1 has no sessions yet.'
            : 'The last session was ${latest.title} on '
                '${formatDayTime(latest.start)}. Come back during a race '
                'weekend, or watch a replay below.';
        _showInfo('Nothing is live right now', text);
        return;
      }
      if (!_api.hasValidToken) {
        _showInfo(
          'Live data needs a login',
          'OpenF1 charges for live data (their sponsor tier). Add your '
              'OpenF1 email and password in Settings, then try again.',
        );
        return;
      }
      _open(latest, TrackerMode.live);
    } on ApiException catch (e) {
      if (mounted) _showInfo('Could not go live', e.message);
    } finally {
      if (mounted) setState(() => _checkingLive = false);
    }
  }

  void _showInfo(String title, String text) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(text),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thisYear = DateTime.now().year;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Race tracker'),
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: Column(
        children: [
          Card(
            margin: const EdgeInsets.all(16),
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: Icon(Icons.sensors, color: theme.colorScheme.primary),
              title: const Text('Live map'),
              subtitle: const Text(
                'Follow every car during a session. '
                'Needs an OpenF1 sponsor login.',
              ),
              trailing: _checkingLive
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _checkingLive ? null : _goLive,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Replays', style: theme.textTheme.titleMedium),
                const Spacer(),
                DropdownButton<int>(
                  value: _year,
                  items: [
                    for (var year = thisYear; year >= 2023; year--)
                      DropdownMenuItem(value: year, child: Text('$year')),
                  ],
                  onChanged: (year) {
                    if (year != null) _pickYear(year);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(
              spacing: 8,
              children: [
                for (final kind in _kinds.entries)
                  ChoiceChip(
                    label: Text(kind.value),
                    selected: _kind == kind.key,
                    onSelected: (_) => setState(() => _kind = kind.key),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<OpenF1Session>>(
              future: _sessions,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingView(message: 'Loading sessions');
                }
                if (snapshot.hasError) {
                  return ErrorView(
                    message: '${snapshot.error}',
                    onRetry: () => _pickYear(_year),
                  );
                }
                final shown = (snapshot.data ?? [])
                    .where((session) => session.type == _kind)
                    .toList();
                final note = _offlineNote;
                if (shown.isEmpty) {
                  final label = _kinds[_kind]!.toLowerCase();
                  return Center(
                    child: Text(
                      note == null
                          ? 'No $label to replay in $_year yet.'
                          : 'No $label saved on your phone for $_year.',
                      textAlign: TextAlign.center,
                    ),
                  );
                }
                return ListView.builder(
                  // One more row at the top for the note, when there is one.
                  itemCount: shown.length + (note == null ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (note != null && index == 0) {
                      return Card(
                        margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: ListTile(
                          leading: const Icon(Icons.lock_clock_outlined),
                          title: Text(note),
                        ),
                      );
                    }
                    final session = shown[index - (note == null ? 0 : 1)];
                    final race = _timingRaces[session.sessionKey];
                    final saved =
                        ReplayArchive.instance.isSaved(session.sessionKey);
                    return ListTile(
                      leading: Icon(sessionIcon(session)),
                      title: Text(session.title),
                      subtitle: Text(
                        [
                          session.country,
                          formatDate(session.start),
                          if (race != null)
                            'Lap by lap'
                          else if (saved)
                            'Saved',
                        ].join('  ·  '),
                      ),
                      trailing: Icon(
                        race != null
                            ? Icons.format_list_numbered
                            : saved
                                ? Icons.download_done
                                : Icons.play_circle_outline,
                      ),
                      onTap: () => _open(
                        session,
                        TrackerMode.replay,
                        timingRace: race,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// An icon for each kind of session: a flag for a race, a bolt for a
/// sprint, a stopwatch for qualifying, a speedometer for practice.
IconData sessionIcon(OpenF1Session session) {
  return switch (session.type) {
    'Race' => session.name == 'Sprint' ? Icons.bolt : Icons.flag,
    'Qualifying' => Icons.timer_outlined,
    _ => Icons.speed,
  };
}
