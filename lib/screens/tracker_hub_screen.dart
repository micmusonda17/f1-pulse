import 'package:flutter/material.dart';

import '../models/openf1_models.dart';
import '../models/race.dart';
import '../services/api_exception.dart';
import '../services/jolpica_api.dart';
import '../services/openf1_api.dart';
import '../services/settings_store.dart';
import '../tracker/tracker_controller.dart';
import '../utils/formatting.dart';
import '../widgets/common_widgets.dart';
import 'settings_screen.dart';
import 'tracker_screen.dart';

/// The third tab: go live, or pick a race to replay.
class TrackerHubScreen extends StatefulWidget {
  const TrackerHubScreen({super.key});

  @override
  State<TrackerHubScreen> createState() => _TrackerHubScreenState();
}

class _TrackerHubScreenState extends State<TrackerHubScreen> {
  final OpenF1Api _api = OpenF1Api.instance;
  int _year = DateTime.now().year;
  late Future<List<OpenF1Session>> _races;
  bool _checkingLive = false;

  @override
  void initState() {
    super.initState();
    _races = _loadRaces();
  }

  /// Races and sprints from [_year] that have finished, newest first.
  Future<List<OpenF1Session>> _loadRaces() async {
    try {
      final sessions = await _api.getRaceSessions(_year);
      final finished =
          sessions.where((s) => s.hasFinished && !s.isCancelled).toList();
      finished.sort((a, b) => b.start.compareTo(a.start));
      return finished;
    } on ApiException {
      // While any session is live, OpenF1 shuts out everyone without a
      // sponsor login, even for old races. In a browser that looks like
      // "no internet", so we check the calendar and say what is going on.
      final live = await _liveSession();
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
      _races = _loadRaces();
    });
  }

  void _open(OpenF1Session session, TrackerMode mode) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TrackerScreen(session: session, mode: mode),
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
                Text('Race replays', style: theme.textTheme.titleMedium),
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
          Expanded(
            child: FutureBuilder<List<OpenF1Session>>(
              future: _races,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingView(message: 'Loading races');
                }
                if (snapshot.hasError) {
                  return ErrorView(
                    message: '${snapshot.error}',
                    onRetry: () => _pickYear(_year),
                  );
                }
                final races = snapshot.data ?? [];
                if (races.isEmpty) {
                  return Center(child: Text('No finished races in $_year yet.'));
                }
                return ListView.builder(
                  itemCount: races.length,
                  itemBuilder: (context, index) {
                    final race = races[index];
                    return ListTile(
                      leading: Icon(
                        race.name == 'Sprint' ? Icons.bolt : Icons.flag,
                      ),
                      title: Text(race.title),
                      subtitle: Text(
                        '${race.country}  ·  ${formatDate(race.start)}',
                      ),
                      trailing: const Icon(Icons.play_circle_outline),
                      onTap: () => _open(race, TrackerMode.replay),
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
