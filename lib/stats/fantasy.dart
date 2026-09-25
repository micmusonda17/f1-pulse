import '../models/race_result.dart';
import '../models/standing.dart';
import 'season_data.dart';

// Fantasy points, worked out by Pitbeat with the main F1 Fantasy scoring
// rules. Plain maths on results, so it is easy to test
// (test/fantasy_test.dart).
//
// Not included, because no free data source has them: overtakes, Driver of
// the Day and pit stop times. So these are estimates, a little below the
// official scores. The numbers live here, in one place, if the rules change.

/// Race points by finishing position, winner first.
const List<int> fantasyRacePoints = [25, 18, 15, 12, 10, 8, 6, 4, 2, 1];

/// Qualifying: 10 for pole down to 1 for P10. No time set: minus 5.
int qualifyingFantasyPoints(QualifyingResult? result) {
  if (result == null) return 0; // Not in qualifying at all
  if (!result.setTime) return -5;
  return result.position <= 10 ? 11 - result.position : 0;
}

/// Sprint: 8 for the winner down to 1 for P8, plus or minus 1 for every
/// place gained or lost, and 5 for the fastest lap. Not classified: -10.
int sprintFantasyPoints(RaceResult? result, {required int starters}) {
  if (result == null) return 0; // No sprint this weekend
  if (!result.classified) return -10;
  var points = result.position <= 8 ? 9 - result.position : 0;
  points += placesGained(result, starters: starters);
  if (result.fastestLapRank == 1) points += 5;
  return points;
}

/// Race: 25 for the winner down to 1 for P10, plus or minus 1 for every
/// place gained or lost, and 10 for the fastest lap. Not classified: -20.
int raceFantasyPoints(RaceResult result, {required int starters}) {
  if (!result.classified) return -20;
  var points = result.position <= fantasyRacePoints.length
      ? fantasyRacePoints[result.position - 1]
      : 0;
  points += placesGained(result, starters: starters);
  if (result.fastestLapRank == 1) points += 10;
  return points;
}

/// Places gained from the grid (negative when places were lost). Jolpica
/// writes a pit lane start as grid 0, which counts as starting last.
int placesGained(RaceResult result, {required int starters}) {
  final grid = result.grid == 0 ? starters : result.grid;
  return grid - result.position;
}

/// A team's qualifying bonus, from how far its two drivers got.
int teamQualifyingBonus(List<QualifyingResult> teamRows) {
  if (teamRows.isEmpty) return 0; // No qualifying results to go on
  final inQ3 = teamRows.where((row) => row.reachedQ3).length;
  final inQ2 = teamRows.where((row) => row.reachedQ2).length;
  if (inQ3 >= 2) return 10;
  if (inQ3 == 1) return 5;
  if (inQ2 >= 2) return 3;
  if (inQ2 == 1) return 1;
  return -1; // Both out in Q1
}

/// One driver's fantasy season.
class DriverFantasy {
  DriverFantasy(this.driver, this.team);

  final Driver driver;
  String team; // Their latest team
  int total = 0;
  int lastRound = 0; // Points at the latest race weekend
}

/// One team's fantasy season.
class TeamFantasy {
  TeamFantasy(this.team);

  final String team;
  int total = 0;
  int lastRound = 0;
}

/// The whole season's fantasy points, best first.
class FantasyTable {
  const FantasyTable({
    required this.drivers,
    required this.teams,
    this.lastRaceName,
  });

  final List<DriverFantasy> drivers;
  final List<TeamFantasy> teams;
  final String? lastRaceName; // The race "lastRound" points are from

  /// A fantasy team's points: the season so far, or the latest weekend.
  int teamPoints(
    List<String> driverIds,
    List<String> teamNames, {
    bool lastRoundOnly = false,
  }) {
    var sum = 0;
    for (final driver in drivers) {
      if (driverIds.contains(driver.driver.id)) {
        sum += lastRoundOnly ? driver.lastRound : driver.total;
      }
    }
    for (final team in teams) {
      if (teamNames.contains(team.team)) {
        sum += lastRoundOnly ? team.lastRound : team.total;
      }
    }
    return sum;
  }
}

/// This season's fantasy table. Shared by the Fantasy tab, the team picker
/// and the welcome card; SeasonService keeps the downloads for 15 minutes.
Future<FantasyTable> loadFantasyTable() async {
  final rounds = await SeasonService.instance.load(DateTime.now().year);
  return fantasyTable(rounds);
}

/// Adds up every round of the season into a fantasy table.
FantasyTable fantasyTable(List<SeasonRound> rounds) {
  final drivers = <String, DriverFantasy>{}; // Driver id -> season
  final teams = <String, TeamFantasy>{}; // Team name -> season

  for (var i = 0; i < rounds.length; i++) {
    final round = rounds[i];
    final isLast = i == rounds.length - 1;
    final starters = round.race.length;
    final qualifyingById = {
      for (final row in round.qualifying) row.driver.id: row,
    };
    final sprintById = {for (final row in round.sprint) row.driver.id: row};
    final teamPoints = <String, int>{};

    for (final result in round.race) {
      final id = result.driver.id;
      final points = qualifyingFantasyPoints(qualifyingById[id]) +
          sprintFantasyPoints(sprintById[id], starters: round.sprint.length) +
          raceFantasyPoints(result, starters: starters);

      final season = drivers.putIfAbsent(
        id,
        () => DriverFantasy(result.driver, result.team),
      );
      season.team = result.team;
      season.total += points;
      if (isLast) season.lastRound = points;
      teamPoints[result.team] = (teamPoints[result.team] ?? 0) + points;
    }

    // Teams score their drivers' points plus the qualifying bonus.
    for (final entry in teamPoints.entries) {
      final teamRows =
          round.qualifying.where((row) => row.team == entry.key).toList();
      final points = entry.value + teamQualifyingBonus(teamRows);
      final season = teams.putIfAbsent(entry.key, () => TeamFantasy(entry.key));
      season.total += points;
      if (isLast) season.lastRound = points;
    }
  }

  final driverList = drivers.values.toList()
    ..sort((a, b) => b.total.compareTo(a.total));
  final teamList = teams.values.toList()
    ..sort((a, b) => b.total.compareTo(a.total));
  return FantasyTable(
    drivers: driverList,
    teams: teamList,
    lastRaceName: rounds.isEmpty ? null : rounds.last.raceName,
  );
}
