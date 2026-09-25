import 'package:flutter/material.dart';

import '../stats/form_guide.dart';
import '../stats/season_data.dart';
import '../theme.dart';
import '../utils/formatting.dart';
import '../widgets/common_widgets.dart';
import '../widgets/driver_widgets.dart';
import '../widgets/spoiler_gate.dart';

/// Betting stats (Chapter 49): how often each driver wins, reaches the
/// podium, scores and retires this season, and how they do against their
/// teammate. Only shown to profiles that said they are 18 or older.
class FormGuideScreen extends StatefulWidget {
  const FormGuideScreen({super.key});

  @override
  State<FormGuideScreen> createState() => _FormGuideScreenState();
}

class _FormGuideScreenState extends State<FormGuideScreen> {
  late final Future<List<DriverForm>> _guide = SeasonService.instance
      .load(DateTime.now().year)
      .then(formGuide);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Form guide')),
      body: SpoilerGate(
        topic: 'form',
        what: 'The form guide',
        child: FutureBuilder<List<DriverForm>>(
          future: _guide,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return ErrorView(message: '${snapshot.error}');
            }
            final guide = snapshot.data;
            if (guide == null) {
              return const LoadingView(message: 'Reading the season');
            }
            return ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                for (final form in guide) _FormRow(form: form),
                const BettingNote(),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({required this.form});

  final DriverForm form;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: F1Colors.muted);
    final average = form.averageFinish;
    final teammate = form.teammate;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          driverName(form.driver),
          Text('${form.team}  ·  ${form.starts} starts', style: muted),
          const SizedBox(height: 6),
          // Wrap: the numbers go onto a second line on a narrow phone.
          Wrap(
            spacing: 16,
            runSpacing: 4,
            children: [
              _Stat('Wins', formatRate(form.rate(form.wins))),
              _Stat('Podiums', formatRate(form.rate(form.podiums))),
              _Stat('Points', formatRate(form.rate(form.pointsFinishes))),
              _Stat('Retired', formatRate(form.rate(form.retirements))),
              if (average != null)
                _Stat('Avg finish', 'P${average.toStringAsFixed(1)}'),
            ],
          ),
          if (teammate != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Against $teammate: races ${form.raceWinsOverTeammate}-'
                '${form.raceLossesToTeammate}, qualifying '
                '${form.qualifyingWinsOverTeammate}-'
                '${form.qualifyingLossesToTeammate}',
                style: muted,
              ),
            ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
        Text(
          label,
          style: const TextStyle(color: F1Colors.muted, fontSize: 11),
        ),
      ],
    );
  }
}

/// What the numbers are, and where to get help. Shown wherever betting
/// stats appear.
class BettingNote extends StatelessWidget {
  const BettingNote({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: F1Colors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        "Fair odds are 1 divided by Pitbeat's chance: its own estimate, not a "
        "bookmaker's price. Pitbeat does not show bookmaker odds, take bets "
        'or link to any betting site. 18+ only. Bet only what you can '
        'afford to lose. Free, confidential help: National Responsible '
        'Gambling Programme, 0800 006 008.',
        style: TextStyle(fontSize: 12, color: F1Colors.muted),
      ),
    );
  }
}
