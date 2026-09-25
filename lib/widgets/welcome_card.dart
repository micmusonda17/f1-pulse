import 'package:flutter/material.dart';

import '../models/race.dart';
import '../models/standing.dart';
import '../services/app_preferences.dart';
import '../services/jolpica_api.dart';
import '../services/profile_store.dart';
import '../services/settings_store.dart';
import '../stats/fantasy.dart';
import '../stats/welcome_message.dart';
import '../theme.dart';

/// The personal message at the top of the Races tab: hello, what is next,
/// and how your driver, team and fantasy team are doing (Chapter 47).
class WelcomeCard extends StatefulWidget {
  const WelcomeCard({super.key, this.nextRace});

  final Race? nextRace;

  @override
  State<WelcomeCard> createState() => _WelcomeCardState();
}

class _WelcomeCardState extends State<WelcomeCard> {
  DriverStanding? _driver;
  ConstructorStanding? _team;
  int? _fantasyPoints;
  String? _fantasyRace;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Everything the message can mention. Each part is optional: if one
  /// download fails, the message just leaves that line out.
  Future<void> _load() async {
    final settings = SettingsStore();
    try {
      final api = JolpicaApi();
      final driverId = await settings.getFavouriteDriver();
      final teamName = await settings.getFavouriteTeam();
      final drivers = await api.getDriverStandings();
      final teams = await api.getConstructorStandings();
      if (!mounted) return;
      setState(() {
        _driver = _firstWhereOrNull(drivers, (d) => d.driver.id == driverId);
        _team = _firstWhereOrNull(teams, (t) => t.name == teamName);
      });
    } catch (_) {
      // No standings: no driver or team line.
    }
    try {
      final myDrivers = await settings.getFantasyDrivers();
      final myTeams = await settings.getFantasyTeams();
      if (myDrivers.isEmpty && myTeams.isEmpty) return; // No fantasy team
      final table = await loadFantasyTable();
      if (!mounted) return;
      setState(() {
        _fantasyPoints =
            table.teamPoints(myDrivers, myTeams, lastRoundOnly: true);
        _fantasyRace = table.lastRaceName;
      });
    } catch (_) {
      // No fantasy line.
    }
  }

  static T? _firstWhereOrNull<T>(List<T> items, bool Function(T) test) {
    for (final item in items) {
      if (test(item)) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Redraw when the profile's name or spoiler-free mode changes.
    return ListenableBuilder(
      listenable: Listenable.merge([
        ProfileStore.instance,
        AppPreferences.instance,
      ]),
      builder: (context, _) {
        final profile = ProfileStore.instance.current;
        if (profile == null) return const SizedBox.shrink();
        final session = widget.nextRace?.nextSession;
        final lines = welcomeLines(
          name: profile.name,
          now: DateTime.now(),
          nextSession: session?.name,
          nextSessionStart: session?.start,
          raceName: widget.nextRace?.name,
          favouriteDriver: _driver,
          favouriteTeam: _team,
          fantasyPoints: _fantasyPoints,
          fantasyRace: _fantasyRace,
          spoilerFree: AppPreferences.instance.spoilerFree,
        );
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                lines.first,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              for (final line in lines.skip(1))
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    line,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: F1Colors.muted,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
