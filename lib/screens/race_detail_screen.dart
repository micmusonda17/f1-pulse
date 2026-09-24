import 'package:flutter/material.dart';

import '../models/openf1_models.dart';
import '../models/race.dart';
import '../models/race_result.dart';
import '../services/api_exception.dart';
import '../services/driver_directory.dart';
import '../services/jolpica_api.dart';
import '../services/openf1_api.dart';
import '../tracker/tracker_controller.dart';
import '../utils/formatting.dart';
import '../widgets/circuit_outline.dart';
import '../widgets/common_widgets.dart';
import '../widgets/driver_widgets.dart';
import 'prediction_screen.dart';
import 'tracker_screen.dart';

/// One race weekend: the session times, and the results once it is over.
class RaceDetailScreen extends StatefulWidget {
  const RaceDetailScreen({super.key, required this.race});

  final Race race;

  @override
  State<RaceDetailScreen> createState() => _RaceDetailScreenState();
}

class _RaceDetailScreenState extends State<RaceDetailScreen> {
  final JolpicaApi _api = JolpicaApi();
  Future<List<RaceResult>>? _results; // Stays null until the race is done
  bool _findingReplay = false;
  Map<String, DriverInfo> _directory = {}; // Photos and colours, by code

  @override
  void initState() {
    super.initState();
    if (widget.race.isFinished) {
      _results = _api.getResults(widget.race.season, widget.race.round);
      _loadDirectory();
    }
  }

  Future<void> _loadDirectory() async {
    final directory = await DriverDirectory.instance.load();
    if (mounted) setState(() => _directory = directory);
  }

  /// Finds this race in OpenF1 and opens the replay.
  Future<void> _openReplay() async {
    final start = widget.race.start;
    if (start == null) return;

    setState(() => _findingReplay = true);
    try {
      final session = await OpenF1Api.instance.findRace(start);
      // We waited, so the user might have left this screen. Check first.
      if (!mounted) return;
      if (session == null) {
        _showMessage('No replay for this race. OpenF1 covers 2023 onwards.');
        return;
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              TrackerScreen(session: session, mode: TrackerMode.replay),
        ),
      );
    } on ApiException catch (e) {
      if (mounted) _showMessage(e.message);
    } finally {
      if (mounted) setState(() => _findingReplay = false);
    }
  }

  void _showMessage(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final race = widget.race;
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(title: Text(race.name)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          ListTile(
            leading: const Icon(Icons.place_outlined),
            title: Text(race.circuitName),
            subtitle: Text(
              '${race.locality}, ${race.country}  ·  Round ${race.round}',
            ),
          ),
          Center(
            child: CircuitOutline(
              circuitId: race.circuitId,
              size: 200,
              colour: Colors.white,
              strokeWidth: 4,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: CircuitFacts(circuitId: race.circuitId),
          ),
          if (!race.isFinished)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: OutlinedButton.icon(
                onPressed: () => openPrediction(context, race),
                icon: const Icon(Icons.insights),
                label: const Text('Who will win?'),
              ),
            ),
          const SectionHeader('Weekend schedule (your time)'),
          for (final session in race.sessions)
            ListTile(
              dense: true,
              leading: Icon(
                session.start.isBefore(now) ? Icons.check : Icons.schedule,
                size: 20,
              ),
              title: Text(session.name),
              trailing: Text(formatDayTime(session.start)),
            ),
          if (race.isFinished) ...[
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _findingReplay ? null : _openReplay,
                icon: const Icon(Icons.play_arrow),
                label: Text(
                  _findingReplay ? 'Finding the replay...' : 'Watch the replay',
                ),
              ),
            ),
            const SectionHeader('Results'),
            _buildResults(),
          ],
        ],
      ),
    );
  }

  Widget _buildResults() {
    return FutureBuilder<List<RaceResult>>(
      future: _results,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorView(message: '${snapshot.error}');
        }
        if (!snapshot.hasData) {
          return const LoadingView();
        }
        final results = snapshot.data!;
        if (results.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Results are not out yet. Check back in a few hours.'),
          );
        }
        return Column(
          children: [
            for (final result in results)
              ResultRow(
                result: result,
                info: _directory[result.driver.code],
              ),
          ],
        );
      },
    );
  }
}

/// One line of the results: position, driver, team, time and points.
class ResultRow extends StatelessWidget {
  const ResultRow({super.key, required this.result, required this.info});

  final RaceResult result;
  final DriverInfo? info; // Photo and team colour, once they have loaded

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final gained = result.placesGained;
    final grid = result.grid == 0 ? 'pit lane' : 'P${result.grid}';
    var subtitle = '${result.team}  ·  started $grid';
    if (gained > 0) subtitle += ' (+$gained)';

    final colour = info?.colour ?? Colors.grey;

    return ListTile(
      dense: true,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 36,
            child: Text(
              'P${result.position}',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          TeamColourBar(colour: colour),
          const SizedBox(width: 10),
          DriverAvatar(
            photoUrl: info?.headshotUrl,
            colour: colour,
            code: result.driver.code,
            size: 36,
          ),
        ],
      ),
      title: driverName(result.driver),
      subtitle: Text(subtitle),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(result.timeOrStatus),
          if (result.points > 0)
            Text(
              '${formatPoints(result.points)} pts',
              style: theme.textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}
