import 'package:flutter/material.dart';

import '../models/race.dart';
import '../services/jolpica_api.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import '../utils/formatting.dart';
import '../widgets/circuit_outline.dart';
import '../widgets/common_widgets.dart';
import '../widgets/countdown.dart';
import 'prediction_screen.dart';
import 'race_detail_screen.dart';
import 'settings_screen.dart';

/// The first tab: the next race with a countdown, then the whole season.
class CalendarScreen extends StatefulWidget {
  const CalendarScreen({super.key});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  final JolpicaApi _api = JolpicaApi();
  late Future<List<Race>> _races;
  String? _name; // From the welcome page, for the greeting

  @override
  void initState() {
    super.initState();
    _races = _api.getSchedule(); // Start downloading straight away
    _loadName();
  }

  Future<void> _loadName() async {
    final name = await SettingsStore().getName();
    if (mounted) setState(() => _name = name);
  }

  Future<void> _refresh() async {
    setState(() {
      _races = _api.getSchedule();
    });
    try {
      await _races;
    } catch (_) {
      // Nothing to do here: the FutureBuilder below shows the error.
    }
  }

  Future<void> _openSettings() async {
    // await waits here until you come back from Settings.
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
    _loadName(); // You may have changed your name there
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pitbeat'),
        actions: [
          IconButton(
            onPressed: _openSettings,
            icon: const Icon(Icons.settings),
            tooltip: 'Settings',
          ),
        ],
      ),
      body: FutureBuilder<List<Race>>(
        future: _races,
        builder: (context, snapshot) {
          // Still waiting and nothing to show yet: spinner.
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const LoadingView(message: 'Loading the calendar');
          }
          // It went wrong: say why, and offer to try again.
          if (snapshot.hasError) {
            return ErrorView(message: '${snapshot.error}', onRetry: _refresh);
          }
          // It worked: build the list.
          final races = snapshot.data ?? [];
          final nextRace = findNextRace(races);
          final title = races.isEmpty
              ? 'No races found'
              : '${races.first.season} calendar';

          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(
                    greetingFor(_name),
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (nextRace != null) ...[
                  NextRaceCard(race: nextRace),
                  PredictionTeaser(race: nextRace),
                ],
                SectionHeader(title),
                for (final race in races)
                  RaceTile(race: race, isNext: race == nextRace),
                const SizedBox(height: 24),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Opens the details page for one race.
void openRace(BuildContext context, Race race) {
  Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => RaceDetailScreen(race: race)),
  );
}

/// The big card at the top: next race, next session, countdown.
class NextRaceCard extends StatelessWidget {
  const NextRaceCard({super.key, required this.race});

  final Race race;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final next = race.nextSession;

    return Card(
      margin: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => openRace(context, race),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The red stripe across the top, like an F1 TV graphic.
            Container(height: 5, color: F1Colors.red),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // The words on the left, the circuit drawing on the right.
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ROUND ${race.round}  ·  UP NEXT',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: F1Colors.red,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.4,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              race.name.toUpperCase(),
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${race.circuitName}\n'
                              '${race.locality}, ${race.country}',
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: F1Colors.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      CircuitOutline(
                        circuitId: race.circuitId,
                        size: 96,
                        colour: Colors.white,
                        strokeWidth: 3,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (next != null) ...[
                    Text(
                      '${next.name}  ·  ${formatDayTime(next.start)}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Countdown(target: next.start),
                  ] else
                    Text('Race under way', style: theme.textTheme.titleMedium),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row in the season list.
class RaceTile extends StatelessWidget {
  const RaceTile({super.key, required this.race, required this.isNext});

  final Race race;
  final bool isNext;

  @override
  Widget build(BuildContext context) {
    final start = race.start;
    var subtitle = '${race.locality}, ${race.country}';
    if (start != null) subtitle += '  ·  ${formatDate(start)}';

    // The circuit's shape: red for the next race, faded once it is over.
    final Color outlineColour;
    if (isNext) {
      outlineColour = F1Colors.red;
    } else if (race.isFinished) {
      outlineColour = Colors.white38;
    } else {
      outlineColour = Colors.white70;
    }
    Widget? icon;
    if (race.isFinished) {
      icon = const Icon(Icons.check_circle_outline, color: F1Colors.muted);
    } else if (isNext) {
      icon = const Icon(Icons.arrow_forward);
    }

    return ListTile(
      // The round number in a rounded square: red for the next race.
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isNext ? F1Colors.red : F1Colors.surfaceHigh,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          '${race.round}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      title: Text(race.name),
      subtitle: Text(subtitle),
      // mainAxisSize.min: the Row is only as wide as what is inside it.
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircuitOutline(circuitId: race.circuitId, colour: outlineColour),
          if (icon != null) ...[const SizedBox(width: 8), icon],
        ],
      ),
      selected: isNext,
      onTap: () => openRace(context, race),
    );
  }
}
