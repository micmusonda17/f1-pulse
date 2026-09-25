import 'package:flutter/material.dart';

import '../models/openf1_models.dart';
import '../models/race.dart';
import '../predictions/prediction_service.dart';
import '../predictions/predictor.dart';
import '../services/driver_directory.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import '../utils/formatting.dart';
import '../widgets/common_widgets.dart';
import '../widgets/driver_widgets.dart';
import '../widgets/spoiler_gate.dart';
import 'form_guide_screen.dart';

/// Opens the full prediction for one race. The Future finishes when you
/// come back.
Future<void> openPrediction(BuildContext context, Race race) {
  return Navigator.push(
    context,
    MaterialPageRoute(builder: (context) => PredictionScreen(race: race)),
  );
}

/// Pitbeat's top 10 for a race: each driver's chance of winning, and why.
class PredictionScreen extends StatefulWidget {
  const PredictionScreen({super.key, required this.race});

  final Race race;

  @override
  State<PredictionScreen> createState() => _PredictionScreenState();
}

class _PredictionScreenState extends State<PredictionScreen> {
  late Future<RacePrediction> _prediction;
  Map<String, DriverInfo> _directory = {}; // Photos and colours, by code
  bool _bettingStats = false; // This profile switched them on (18+)

  @override
  void initState() {
    super.initState();
    _prediction = PredictionService.instance.predict(widget.race);
    _loadDirectory();
    _loadBettingStats();
  }

  Future<void> _loadBettingStats() async {
    final on = await SettingsStore().getBettingStats();
    if (mounted) setState(() => _bettingStats = on);
  }

  Future<void> _loadDirectory() async {
    final directory = await DriverDirectory.instance.load();
    if (mounted) setState(() => _directory = directory);
  }

  void _retry() {
    setState(() {
      _prediction = PredictionService.instance.predict(
        widget.race,
        refresh: true,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Who will win?'),
        actions: [
          if (_bettingStats)
            TextButton.icon(
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const FormGuideScreen(),
                ),
              ),
              icon: const Icon(Icons.query_stats),
              label: const Text('Form guide'),
            ),
        ],
      ),
      body: FutureBuilder<RacePrediction>(
        future: _prediction,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorView(message: '${snapshot.error}', onRetry: _retry);
          }
          final prediction = snapshot.data;
          if (prediction == null) {
            return const LoadingView(message: 'Crunching the numbers');
          }
          if (prediction.ranking.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'Predictions start after the first race of the season.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          // The reasons mention recent results, so they could spoil one.
          return SpoilerGate(
            topic: 'predictions',
            what: 'The predictions',
            child: _buildList(prediction),
          );
        },
      ),
    );
  }

  Widget _buildList(RacePrediction prediction) {
    final theme = Theme.of(context);
    final topTen = prediction.ranking.take(10).toList();

    return ListView(
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            widget.race.name.toUpperCase(),
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            describeEvidence(prediction),
            style: theme.textTheme.bodyMedium?.copyWith(color: F1Colors.muted),
          ),
        ),
        const SectionHeader('Chance of winning'),
        for (var i = 0; i < topTen.length; i++)
          ChanceRow(
            rank: i + 1,
            prediction: topTen[i],
            info: _directory[topTen[i].driver.code],
            showOdds: _bettingStats,
          ),
        if (_bettingStats) const BettingNote(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Text(
            'Just for fun. This is Pitbeat\'s own estimate from public '
            'results. It knows nothing about upgrades, weather or luck.',
            style: theme.textTheme.bodySmall?.copyWith(color: F1Colors.muted),
          ),
        ),
      ],
    );
  }
}

/// What the prediction is based on, as one sentence.
String describeEvidence(RacePrediction prediction) {
  final races = prediction.racesUsed == 1
      ? 'the last race'
      : 'the last ${prediction.racesUsed} races';
  final parts = [
    if (prediction.racesUsed > 0) races,
    'the championship',
    if (prediction.usedLastYear) 'last year\'s race here',
    if (prediction.usedQualifying) 'qualifying',
  ];
  // "a, b and c": commas between all but the last two.
  final list = parts.length == 1
      ? parts.first
      : '${parts.sublist(0, parts.length - 1).join(', ')} '
          'and ${parts.last}';
  final sentence = 'Based on $list.';
  if (prediction.usedQualifying) return sentence;
  return '$sentence The chances will change after qualifying.';
}

/// The small card under the next race: the top three and a link to the rest.
class PredictionTeaser extends StatefulWidget {
  const PredictionTeaser({super.key, required this.race});

  final Race race;

  @override
  State<PredictionTeaser> createState() => _PredictionTeaserState();
}

class _PredictionTeaserState extends State<PredictionTeaser> {
  late Future<RacePrediction> _prediction;
  Map<String, DriverInfo> _directory = {};

  @override
  void initState() {
    super.initState();
    _prediction = PredictionService.instance.predict(widget.race);
    _loadDirectory();
  }

  // A pull to refresh builds a new Race object for the same race. Only a
  // different race (once this one is over) needs a new prediction.
  @override
  void didUpdateWidget(PredictionTeaser oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sameRace = oldWidget.race.season == widget.race.season &&
        oldWidget.race.round == widget.race.round;
    if (!sameRace) {
      _prediction = PredictionService.instance.predict(widget.race);
    }
  }

  Future<void> _loadDirectory() async {
    final directory = await DriverDirectory.instance.load();
    if (mounted) setState(() => _directory = directory);
  }

  Future<void> _open() async {
    await openPrediction(context, widget.race);
    // Back from the full page. If it worked the prediction out again (after
    // an error, or after qualifying), the service has kept the new answer,
    // so asking again here is instant.
    if (mounted) {
      setState(() {
        _prediction = PredictionService.instance.predict(widget.race);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _open,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.insights, color: F1Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'PITBEAT PREDICTS',
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: F1Colors.red,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                        ),
                      ),
                    ),
                    Text('Top 10', style: theme.textTheme.labelMedium),
                    const Icon(Icons.chevron_right, size: 18),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SpoilerGate(
                topic: 'predictions',
                what: 'The predictions',
                child: _buildTopThree(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTopThree() {
    return FutureBuilder<RacePrediction>(
      future: _prediction,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const _TeaserNote(
            'Predictions are not available right now. Tap to try again.',
          );
        }
        final prediction = snapshot.data;
        if (prediction == null) {
          return const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: LinearProgressIndicator(),
          );
        }
        if (prediction.ranking.isEmpty) {
          return const _TeaserNote(
            'Predictions start after the first race of the season.',
          );
        }
        final topThree = prediction.ranking.take(3).toList();
        return Column(
          children: [
            for (var i = 0; i < topThree.length; i++)
              ChanceRow(
                rank: i + 1,
                prediction: topThree[i],
                info: _directory[topThree[i].driver.code],
                showReasons: false,
              ),
          ],
        );
      },
    );
  }
}

class _TeaserNote extends StatelessWidget {
  const _TeaserNote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(text, style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

/// One driver in a prediction: place, photo, name, why, and the chance.
class ChanceRow extends StatelessWidget {
  const ChanceRow({
    super.key,
    required this.rank,
    required this.prediction,
    required this.info,
    this.showReasons = true,
    this.showOdds = false,
  });

  final int rank;
  final WinPrediction prediction;
  final DriverInfo? info; // Photo and team colour, once they have loaded
  final bool showReasons;
  final bool showOdds; // Betting stats: fair odds under the chance

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = info?.colour ?? Colors.grey;
    final reasons = prediction.reasons.join('  ·  ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 24,
            child: Text(
              '$rank',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          TeamColourBar(colour: colour, height: 32),
          const SizedBox(width: 10),
          DriverAvatar(
            photoUrl: info?.headshotUrl,
            colour: colour,
            code: prediction.driver.code,
            size: 32,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                driverName(prediction.driver),
                if (showReasons && reasons.isNotEmpty)
                  Text(
                    reasons,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: F1Colors.muted,
                    ),
                  )
                else
                  Text(
                    prediction.team,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: F1Colors.muted,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 56,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatChance(prediction.chance),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                ChanceBar(value: prediction.chance, colour: colour),
                if (showOdds)
                  Text(
                    formatOdds(prediction.chance),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: F1Colors.muted,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A thin bar filled from the left: 0.4 fills 40% of it.
class ChanceBar extends StatelessWidget {
  const ChanceBar({super.key, required this.value, required this.colour});

  final double value; // 0 to 1
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 4,
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: F1Colors.surfaceHigh,
        borderRadius: BorderRadius.circular(2),
      ),
      // FractionallySizedBox makes its child a fraction of the space it has.
      child: FractionallySizedBox(
        widthFactor: value.clamp(0.0, 1.0).toDouble(),
        child: Container(
          decoration: BoxDecoration(
            color: colour,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }
}
