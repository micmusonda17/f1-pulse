import '../models/race_result.dart';
import '../models/standing.dart';
import 'season_data.dart';

// The form guide behind betting stats (Chapter 49): how often each driver
// wins, reaches the podium, scores or retires, and how they do against
// their teammate. Plain maths on results, tested in test/fantasy_test.dart.

/// One driver's season in numbers.
class DriverForm {
  DriverForm(this.driver, this.team);

  final Driver driver;
  String team; // Their latest team
  String? teammate; // Their latest teammate's surname
  int starts = 0;
  int wins = 0;
  int podiums = 0;
  int pointsFinishes = 0; // Top 10
  int retirements = 0; // Not classified
  int _finishTotal = 0; // For the average finish
  int _classified = 0;
  int raceWinsOverTeammate = 0;
  int raceLossesToTeammate = 0;
  int qualifyingWinsOverTeammate = 0;
  int qualifyingLossesToTeammate = 0;

  /// Average finishing position when they were classified, or null.
  double? get averageFinish =>
      _classified == 0 ? null : _finishTotal / _classified;

  /// [count] as a share of their starts: 3 wins in 12 starts is 0.25.
  double rate(int count) => starts == 0 ? 0 : count / starts;
}

/// The form guide for a season, best first (most wins, then podiums,
/// then the best average finish).
List<DriverForm> formGuide(List<SeasonRound> rounds) {
  final forms = <String, DriverForm>{}; // Driver id -> form

  for (final round in rounds) {
    for (final result in round.race) {
      final form = forms.putIfAbsent(
        result.driver.id,
        () => DriverForm(result.driver, result.team),
      );
      form.team = result.team;
      form.starts++;
      if (!result.classified) {
        form.retirements++;
        continue;
      }
      form._classified++;
      form._finishTotal += result.position;
      if (result.position == 1) form.wins++;
      if (result.position <= 3) form.podiums++;
      if (result.position <= 10) form.pointsFinishes++;
    }
    _raceHeadToHead(round.race, forms);
    _qualifyingHeadToHead(round.qualifying, forms);
  }

  final list = forms.values.toList();
  list.sort((a, b) {
    final byWins = b.wins.compareTo(a.wins);
    if (byWins != 0) return byWins;
    final byPodiums = b.podiums.compareTo(a.podiums);
    if (byPodiums != 0) return byPodiums;
    return (a.averageFinish ?? 99).compareTo(b.averageFinish ?? 99);
  });
  return list;
}

/// Teammates in the race: whoever finished ahead wins. Finishing beats
/// retiring. If both retired, nobody wins.
void _raceHeadToHead(List<RaceResult> race, Map<String, DriverForm> forms) {
  final byTeam = <String, List<RaceResult>>{};
  for (final result in race) {
    byTeam.putIfAbsent(result.team, () => []).add(result);
  }
  for (final pair in byTeam.values.where((rows) => rows.length == 2)) {
    final a = pair[0];
    final b = pair[1];
    forms[a.driver.id]?.teammate = b.driver.lastName;
    forms[b.driver.id]?.teammate = a.driver.lastName;
    if (!a.classified && !b.classified) continue;
    final aAhead =
        a.classified && (!b.classified || a.position < b.position);
    _score(forms[a.driver.id], forms[b.driver.id], aAhead, race: true);
  }
}

/// Teammates in qualifying: the higher grid slot wins.
void _qualifyingHeadToHead(
  List<QualifyingResult> qualifying,
  Map<String, DriverForm> forms,
) {
  final byTeam = <String, List<QualifyingResult>>{};
  for (final row in qualifying) {
    byTeam.putIfAbsent(row.team, () => []).add(row);
  }
  for (final pair in byTeam.values.where((rows) => rows.length == 2)) {
    final aAhead = pair[0].position < pair[1].position;
    _score(
      forms[pair[0].driver.id],
      forms[pair[1].driver.id],
      aAhead,
      race: false,
    );
  }
}

void _score(DriverForm? a, DriverForm? b, bool aAhead, {required bool race}) {
  if (a == null || b == null) return;
  final winner = aAhead ? a : b;
  final loser = aAhead ? b : a;
  if (race) {
    winner.raceWinsOverTeammate++;
    loser.raceLossesToTeammate++;
  } else {
    winner.qualifyingWinsOverTeammate++;
    loser.qualifyingLossesToTeammate++;
  }
}
