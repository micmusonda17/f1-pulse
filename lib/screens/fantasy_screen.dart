import 'package:flutter/material.dart';

import '../models/openf1_models.dart';
import '../services/driver_directory.dart';
import '../services/settings_store.dart';
import '../stats/fantasy.dart';
import '../stats/season_data.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/driver_widgets.dart';

/// How many drivers and teams a fantasy team has, as in F1 Fantasy.
const int fantasyDriverCount = 5;
const int fantasyTeamCount = 2;

/// The third Standings tab: your fantasy team, then everyone's points.
class FantasyTab extends StatefulWidget {
  const FantasyTab({super.key});

  @override
  State<FantasyTab> createState() => _FantasyTabState();
}

class _FantasyTabState extends State<FantasyTab>
    with AutomaticKeepAliveClientMixin {
  final SettingsStore _settings = SettingsStore();
  late Future<FantasyTable> _table;
  List<String> _myDrivers = [];
  List<String> _myTeams = [];
  Map<String, DriverInfo> _directory = {};

  @override
  bool get wantKeepAlive => true; // Keep it when you switch tabs

  @override
  void initState() {
    super.initState();
    _table = loadFantasyTable();
    _loadMyTeam();
    _loadDirectory();
  }

  Future<void> _loadMyTeam() async {
    final drivers = await _settings.getFantasyDrivers();
    final teams = await _settings.getFantasyTeams();
    if (!mounted) return;
    setState(() {
      _myDrivers = drivers;
      _myTeams = teams;
    });
  }

  Future<void> _loadDirectory() async {
    final directory = await DriverDirectory.instance.load();
    if (mounted) setState(() => _directory = directory);
  }

  Future<void> _editTeam() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const FantasyTeamScreen()),
    );
    _loadMyTeam(); // You may have changed it
  }

  Future<void> _refresh() async {
    setState(() {
      _table = SeasonService.instance
          .load(DateTime.now().year, refresh: true)
          .then(fantasyTable);
    });
    try {
      await _table;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Needed by AutomaticKeepAliveClientMixin
    return FutureBuilder<FantasyTable>(
      future: _table,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return ErrorView(message: '${snapshot.error}', onRetry: _refresh);
        }
        final table = snapshot.data;
        if (table == null) {
          return const LoadingView(message: 'Adding up the season');
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              _MyTeamCard(
                table: table,
                drivers: _myDrivers,
                teams: _myTeams,
                onEdit: _editTeam,
              ),
              const SectionHeader('Drivers'),
              for (var i = 0; i < table.drivers.length; i++)
                _FantasyDriverRow(
                  rank: i + 1,
                  entry: table.drivers[i],
                  info: _directory[table.drivers[i].driver.code],
                  mine: _myDrivers.contains(table.drivers[i].driver.id),
                ),
              const SectionHeader('Teams'),
              for (var i = 0; i < table.teams.length; i++)
                ListTile(
                  dense: true,
                  leading: Text(
                    '${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  title: Text(table.teams[i].team),
                  selected: _myTeams.contains(table.teams[i].team),
                  trailing: _Points(
                    total: table.teams[i].total,
                    last: table.teams[i].lastRound,
                  ),
                ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                child: Text(
                  "Pitbeat's estimate with F1 Fantasy's main scoring rules: "
                  'qualifying, sprint and race places, places gained or '
                  'lost, fastest laps and retirements. It leaves out '
                  'overtakes, Driver of the Day and pit stops, so official '
                  'scores are a little higher.',
                  style: TextStyle(color: F1Colors.muted, fontSize: 12),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Your fantasy team's total, or a button to pick one.
class _MyTeamCard extends StatelessWidget {
  const _MyTeamCard({
    required this.table,
    required this.drivers,
    required this.teams,
    required this.onEdit,
  });

  final FantasyTable table;
  final List<String> drivers;
  final List<String> teams;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final picked = drivers.isNotEmpty || teams.isNotEmpty;
    final total = table.teamPoints(drivers, teams);
    final last = table.teamPoints(drivers, teams, lastRoundOnly: true);

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'MY FANTASY TEAM',
              style: theme.textTheme.labelMedium?.copyWith(
                color: F1Colors.red,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.4,
              ),
            ),
            const SizedBox(height: 8),
            if (picked) ...[
              Text(
                '$total points this season',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (table.lastRaceName case final race?)
                Text('$last at the $race', style: theme.textTheme.bodyMedium),
            ] else
              const Text(
                'Pick 5 drivers and 2 teams, and Pitbeat adds up their '
                'points every race weekend.',
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: onEdit,
              icon: Icon(picked ? Icons.edit : Icons.add),
              label: Text(picked ? 'Change my team' : 'Pick my team'),
            ),
          ],
        ),
      ),
    );
  }
}

class _FantasyDriverRow extends StatelessWidget {
  const _FantasyDriverRow({
    required this.rank,
    required this.entry,
    required this.info,
    required this.mine,
  });

  final int rank;
  final DriverFantasy entry;
  final DriverInfo? info;
  final bool mine; // In your fantasy team

  @override
  Widget build(BuildContext context) {
    final colour = info?.colour ?? Colors.grey;
    return ListTile(
      dense: true,
      selected: mine,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '$rank',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          TeamColourBar(colour: colour, height: 28),
        ],
      ),
      title: driverName(entry.driver),
      subtitle: Text(entry.team),
      trailing: _Points(total: entry.total, last: entry.lastRound),
    );
  }
}

/// "312 pts" with the latest weekend's points underneath.
class _Points extends StatelessWidget {
  const _Points({required this.total, required this.last});

  final int total;
  final int last;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$total pts',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        Text(
          last >= 0 ? '+$last last race' : '$last last race',
          style: const TextStyle(color: F1Colors.muted, fontSize: 11),
        ),
      ],
    );
  }
}

/// Pick your fantasy team: 5 drivers and 2 teams, saved to your profile.
class FantasyTeamScreen extends StatefulWidget {
  const FantasyTeamScreen({super.key});

  @override
  State<FantasyTeamScreen> createState() => _FantasyTeamScreenState();
}

class _FantasyTeamScreenState extends State<FantasyTeamScreen> {
  final SettingsStore _settings = SettingsStore();
  late final Future<FantasyTable> _table = loadFantasyTable();
  final Set<String> _drivers = {}; // Driver ids
  final Set<String> _teams = {}; // Team names

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final drivers = await _settings.getFantasyDrivers();
    final teams = await _settings.getFantasyTeams();
    if (!mounted) return;
    setState(() {
      _drivers.addAll(drivers);
      _teams.addAll(teams);
    });
  }

  /// Adds or removes a pick, but never more than the limit.
  void _toggle(Set<String> picks, String id, int limit) {
    setState(() {
      if (picks.contains(id)) {
        picks.remove(id);
      } else if (picks.length < limit) {
        picks.add(id);
      }
    });
  }

  Future<void> _save() async {
    await _settings.setFantasyTeam(_drivers.toList(), _teams.toList());
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My fantasy team'),
        actions: [TextButton(onPressed: _save, child: const Text('Save'))],
      ),
      body: FutureBuilder<FantasyTable>(
        future: _table,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return ErrorView(message: '${snapshot.error}');
          }
          final table = snapshot.data;
          if (table == null) return const LoadingView();
          return ListView(
            children: [
              SectionHeader(
                'Drivers: ${_drivers.length} of $fantasyDriverCount',
              ),
              for (final entry in table.drivers)
                CheckboxListTile(
                  value: _drivers.contains(entry.driver.id),
                  onChanged: (_) =>
                      _toggle(_drivers, entry.driver.id, fantasyDriverCount),
                  title: Text(entry.driver.fullName),
                  subtitle: Text('${entry.team}  ·  ${entry.total} pts'),
                ),
              SectionHeader('Teams: ${_teams.length} of $fantasyTeamCount'),
              for (final entry in table.teams)
                CheckboxListTile(
                  value: _teams.contains(entry.team),
                  onChanged: (_) =>
                      _toggle(_teams, entry.team, fantasyTeamCount),
                  title: Text(entry.team),
                  subtitle: Text('${entry.total} pts'),
                ),
            ],
          );
        },
      ),
    );
  }
}
