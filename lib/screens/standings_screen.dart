import 'package:flutter/material.dart';

import '../models/openf1_models.dart';
import '../models/standing.dart';
import '../services/api_exception.dart';
import '../services/driver_directory.dart';
import '../services/jolpica_api.dart';
import '../services/settings_store.dart';
import '../utils/formatting.dart';
import '../widgets/common_widgets.dart';
import '../widgets/driver_widgets.dart';
import '../widgets/spoiler_gate.dart';

/// The second tab: drivers' and constructors' championships.
class StandingsScreen extends StatelessWidget {
  const StandingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // DefaultTabController links the TabBar at the top with the
    // TabBarView underneath, so tapping a tab shows the right page.
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Standings'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Drivers'), Tab(text: 'Teams')],
          ),
        ),
        body: const SpoilerGate(
          topic: 'standings',
          what: 'The standings',
          child: TabBarView(
            children: [DriverStandingsTab(), TeamStandingsTab()],
          ),
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Drivers
// ----------------------------------------------------------------------

class DriverStandingsTab extends StatefulWidget {
  const DriverStandingsTab({super.key});

  @override
  State<DriverStandingsTab> createState() => _DriverStandingsTabState();
}

// AutomaticKeepAliveClientMixin stops Flutter throwing this tab away when
// you switch to Teams, so it does not download everything again.
class _DriverStandingsTabState extends State<DriverStandingsTab>
    with AutomaticKeepAliveClientMixin {
  final JolpicaApi _api = JolpicaApi();
  final SettingsStore _settings = SettingsStore();
  late Future<List<DriverStanding>> _standings;
  String? _favouriteId;
  Map<String, DriverInfo> _directory = {}; // Photos and colours, by code

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _standings = _api.getDriverStandings();
    _loadFavourite();
    _loadDirectory();
  }

  Future<void> _loadFavourite() async {
    final id = await _settings.getFavouriteDriver();
    if (mounted) setState(() => _favouriteId = id);
  }

  /// Photos arrive a moment after the table. Until then, rows show codes.
  Future<void> _loadDirectory() async {
    final directory = await DriverDirectory.instance.load();
    if (mounted) setState(() => _directory = directory);
  }

  Future<void> _toggleFavourite(String driverId) async {
    // Tapping your current favourite again removes it.
    final newId = _favouriteId == driverId ? null : driverId;
    setState(() => _favouriteId = newId);
    await _settings.setFavouriteDriver(newId);
  }

  Future<void> _refresh() async {
    setState(() {
      _standings = _api.getDriverStandings();
    });
    try {
      await _standings;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // Needed by AutomaticKeepAliveClientMixin
    return FutureBuilder<List<DriverStanding>>(
      future: _standings,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(message: 'Loading the standings');
        }
        if (snapshot.hasError) {
          return ErrorView(message: '${snapshot.error}', onRetry: _refresh);
        }
        final standings = snapshot.data ?? [];
        if (standings.isEmpty) {
          return const Center(child: Text('No standings yet this season.'));
        }

        // Find your favourite in the list (if you have picked one).
        DriverStanding? favourite;
        for (final standing in standings) {
          if (standing.driver.id == _favouriteId) favourite = standing;
        }

        // Each team's colour, for drivers missing from OpenF1's recent races.
        final teamColours = teamColoursFrom(standings, _directory);

        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            children: [
              if (favourite != null)
                FavouriteDriverCard(
                  standing: favourite,
                  leaderPoints: standings.first.points,
                  info: _directory[favourite.driver.code],
                ),
              for (final standing in standings)
                DriverStandingTile(
                  standing: standing,
                  info: _directory[standing.driver.code],
                  teamColour: teamColours[standing.team],
                  isFavourite: standing.driver.id == _favouriteId,
                  onFavourite: () => _toggleFavourite(standing.driver.id),
                ),
            ],
          ),
        );
      },
    );
  }
}

class DriverStandingTile extends StatelessWidget {
  const DriverStandingTile({
    super.key,
    required this.standing,
    required this.info,
    this.teamColour,
    required this.isFavourite,
    required this.onFavourite,
  });

  final DriverStanding standing;
  final DriverInfo? info; // Null until the photos have loaded
  final Color? teamColour; // Backup colour when info is null
  final bool isFavourite;
  final VoidCallback onFavourite;

  @override
  Widget build(BuildContext context) {
    final colour = info?.colour ?? teamColour ?? Colors.grey;
    final wins = standing.wins == 1 ? '1 win' : '${standing.wins} wins';
    return ListTile(
      selected: isFavourite,
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 26,
            child: Text(
              '${standing.position}',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          TeamColourBar(colour: colour),
          const SizedBox(width: 10),
          DriverAvatar(
            photoUrl: info?.headshotUrl,
            colour: colour,
            code: standing.driver.code,
          ),
        ],
      ),
      title: driverName(standing.driver),
      subtitle: Text('${standing.team}  ·  $wins'),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${formatPoints(standing.points)} pts',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          IconButton(
            onPressed: onFavourite,
            tooltip: 'Make favourite',
            icon: Icon(
              isFavourite ? Icons.star : Icons.star_border,
              color: isFavourite ? Colors.amber : null,
            ),
          ),
        ],
      ),
    );
  }
}

/// The card pinned to the top for your favourite driver.
class FavouriteDriverCard extends StatelessWidget {
  const FavouriteDriverCard({
    super.key,
    required this.standing,
    required this.leaderPoints,
    required this.info,
  });

  final DriverStanding standing;
  final double leaderPoints;
  final DriverInfo? info;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colour = info?.colour ?? Colors.amber;
    final gap = leaderPoints - standing.points;
    final gapText = gap == 0
        ? 'Leading the championship'
        : '${formatPoints(gap)} points behind the leader';

    return Card(
      margin: const EdgeInsets.all(16),
      clipBehavior: Clip.antiAlias,
      child: Container(
        // A thick stripe down the left in the team colour.
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: colour, width: 6)),
        ),
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'YOUR DRIVER',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.amber,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  driverName(
                    standing.driver,
                    style: theme.textTheme.titleLarge,
                  ),
                  Text(standing.team, style: theme.textTheme.bodyMedium),
                  const SizedBox(height: 12),
                  Text(
                    'P${standing.position}  ·  '
                    '${formatPoints(standing.points)} pts  ·  '
                    '${standing.wins} wins',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(gapText, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            const SizedBox(width: 12),
            DriverAvatar(
              photoUrl: info?.headshotUrl,
              colour: colour,
              code: standing.driver.code,
              size: 84,
            ),
          ],
        ),
      ),
    );
  }
}

// ----------------------------------------------------------------------
// Teams
// ----------------------------------------------------------------------

class TeamStandingsTab extends StatefulWidget {
  const TeamStandingsTab({super.key});

  @override
  State<TeamStandingsTab> createState() => _TeamStandingsTabState();
}

class _TeamStandingsTabState extends State<TeamStandingsTab>
    with AutomaticKeepAliveClientMixin {
  final JolpicaApi _api = JolpicaApi();
  final SettingsStore _settings = SettingsStore();
  late Future<List<ConstructorStanding>> _standings;
  Map<String, Color> _teamColours = {};
  String? _favouriteTeam; // A Jolpica team name, like "Ferrari"

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _standings = _api.getConstructorStandings();
    _loadColours();
    _loadFavourite();
  }

  Future<void> _loadFavourite() async {
    final team = await _settings.getFavouriteTeam();
    if (mounted) setState(() => _favouriteTeam = team);
  }

  /// The same idea as the drivers tab: tap the star again to remove it.
  Future<void> _toggleFavourite(String team) async {
    final newTeam = _favouriteTeam == team ? null : team;
    setState(() => _favouriteTeam = newTeam);
    await _settings.setFavouriteTeam(newTeam);
  }

  /// Team colours come from the drivers: see teamColoursFrom.
  Future<void> _loadColours() async {
    try {
      final drivers = await _api.getDriverStandings();
      final directory = await DriverDirectory.instance.load();
      if (!mounted) return;
      setState(() => _teamColours = teamColoursFrom(drivers, directory));
    } on ApiException {
      // No colours is fine: the bars just stay grey.
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _standings = _api.getConstructorStandings();
    });
    try {
      await _standings;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return FutureBuilder<List<ConstructorStanding>>(
      future: _standings,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const LoadingView(message: 'Loading the standings');
        }
        if (snapshot.hasError) {
          return ErrorView(message: '${snapshot.error}', onRetry: _refresh);
        }
        final standings = snapshot.data ?? [];
        if (standings.isEmpty) {
          return const Center(child: Text('No standings yet this season.'));
        }
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            children: [
              for (final team in standings)
                ListTile(
                  selected: team.name == _favouriteTeam,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text(
                          '${team.position}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      TeamColourBar(
                        colour: _teamColours[team.name] ?? Colors.grey,
                      ),
                    ],
                  ),
                  title: Text(
                    team.name,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    team.wins == 1 ? '1 win' : '${team.wins} wins',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${formatPoints(team.points)} pts',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      IconButton(
                        onPressed: () => _toggleFavourite(team.name),
                        tooltip: 'Make favourite',
                        icon: Icon(
                          team.name == _favouriteTeam
                              ? Icons.star
                              : Icons.star_border,
                          color: team.name == _favouriteTeam
                              ? Colors.amber
                              : null,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
