import 'dart:math' as math;

import '../models/race_result.dart';
import '../models/standing.dart';

// Pitbeat's race predictions. Everything in this file is plain maths on
// data we already have: no screens and no internet, so it is easy to test
// (see test/predictor_test.dart). lib/predictions/prediction_service.dart
// downloads the data and calls predictWinner().

/// The kinds of evidence the predictor weighs up, and how much each counts.
///
/// An enum can carry values: each kind has its own weight. When a kind is
/// missing (no qualifying yet, or no race here last year), the others share
/// its weight, because predictWinner scales the weights to add up to 1.
enum Factor {
  qualifying(0.4),
  form(0.4),
  championship(0.25),
  lastYear(0.15);

  const Factor(this.weight);

  final double weight;
}

/// How sure of itself the predictor is. A higher number turns the same
/// scores into a bigger chance for the favourite. 6 gives a clear favourite
/// about a 40% chance, which is roughly how often F1 favourites win.
const double winConfidence = 6.0;

/// Race points for each finishing position, winner first.
const List<int> racePoints = [25, 18, 15, 12, 10, 8, 6, 4, 2, 1];

/// Everything the predictor looks at for one race.
class PredictionData {
  const PredictionData({
    required this.standings,
    required this.recentRaces,
    this.lastYearHere = const [],
    this.qualifying = const [],
  });

  final List<DriverStanding> standings; // The championship table
  final List<List<RaceResult>> recentRaces; // Newest race first
  final List<RaceResult> lastYearHere; // Empty if there was no race here
  final List<QualifyingResult> qualifying; // Empty until qualifying is done
}

/// One driver's chance of winning, and the biggest reasons for it.
class WinPrediction {
  const WinPrediction({
    required this.driver,
    required this.team,
    required this.chance,
    required this.reasons,
  });

  final Driver driver;
  final String team;
  final double chance; // 0.0 to 1.0. Everyone's chances add up to 1.
  final List<String> reasons; // Like "Won 2 of the last 5 races"
}

/// The prediction for a whole race.
class RacePrediction {
  const RacePrediction({
    required this.ranking,
    required this.racesUsed,
    required this.usedLastYear,
    required this.usedQualifying,
  });

  final List<WinPrediction> ranking; // Most likely winner first
  final int racesUsed; // How many recent races it looked at
  final bool usedLastYear;
  final bool usedQualifying;

  /// Nothing to go on yet, for example before the first race of the year.
  static const RacePrediction empty = RacePrediction(
    ranking: [],
    racesUsed: 0,
    usedLastYear: false,
    usedQualifying: false,
  );
}

/// Works out every driver's chance of winning.
///
/// Each driver gets a score from 0 to 1 for each kind of evidence. The
/// weighted scores are added up, then [softmax] turns the totals into
/// chances that add up to 100%.
RacePrediction predictWinner(PredictionData data) {
  // 1. Who is racing? Qualifying tells us exactly. Before qualifying we use
  //    the latest race. (The championship table still lists drivers who
  //    have been replaced, so it cannot tell us.)
  final drivers = <String, Driver>{}; // Driver id -> driver
  final teams = <String, String>{}; // Driver id -> team
  if (data.qualifying.isNotEmpty) {
    for (final row in data.qualifying) {
      drivers[row.driver.id] = row.driver;
      teams[row.driver.id] = row.team;
    }
  } else if (data.recentRaces.isNotEmpty) {
    for (final row in data.recentRaces.first) {
      drivers[row.driver.id] = row.driver;
      teams[row.driver.id] = row.team;
    }
  }
  if (drivers.isEmpty) return RacePrediction.empty;

  // 2. Put everything else in maps keyed by driver id, so each lookup is
  //    instant instead of a search through a list.
  final gridById = {
    for (final row in data.qualifying) row.driver.id: row.position,
  };
  final lastYearById = {
    for (final row in data.lastYearHere) row.driver.id: row.position,
  };
  final standingById = {
    for (final row in data.standings) row.driver.id: row,
  };
  final recentById = [
    for (final race in data.recentRaces)
      {for (final row in race) row.driver.id: row.position},
  ];
  final leaderPoints =
      data.standings.isEmpty ? 0.0 : data.standings.first.points;

  // 3. Which kinds of evidence do we have? Their weights are scaled so
  //    they add up to 1.
  final available = [
    if (data.qualifying.isNotEmpty) Factor.qualifying,
    if (data.recentRaces.isNotEmpty) Factor.form,
    if (leaderPoints > 0) Factor.championship,
    if (data.lastYearHere.isNotEmpty) Factor.lastYear,
  ];
  var totalWeight = 0.0;
  for (final factor in available) {
    totalWeight += factor.weight;
  }

  // 4. Score every driver, and note the reason behind each part.
  final ids = drivers.keys.toList();
  final scores = <double>[];
  final reasonLists = <List<String>>[];
  for (final id in ids) {
    final parts = <_Part>[];

    for (final factor in available) {
      var value = 0.0; // 0 to 1: how good this driver looks on this factor
      String? reason; // Stays null if there is nothing worth saying
      switch (factor) {
        case Factor.qualifying:
          final grid = gridById[id];
          value = pointsFor(grid) / 25;
          if (grid != null) {
            reason = grid == 1 ? 'Qualified on pole' : 'Qualified P$grid';
          }
        case Factor.form:
          final finishes = [for (final race in recentById) race[id]];
          value = formScore(finishes);
          reason = describeForm(finishes);
        case Factor.championship:
          final standing = standingById[id];
          value = standing == null ? 0.0 : standing.points / leaderPoints;
          if (standing != null && standing.position > 0) {
            reason = standing.position == 1
                ? 'Leads the championship'
                : '${ordinal(standing.position)} in the championship';
          }
        case Factor.lastYear:
          final place = lastYearById[id];
          value = pointsFor(place) / 25;
          if (place != null && place <= 10) {
            reason =
                place == 1 ? 'Won here last year' : 'P$place here last year';
          }
      }
      parts.add(_Part(factor, factor.weight / totalWeight * value, reason));
    }

    var score = 0.0;
    for (final part in parts) {
      score += part.share;
    }
    scores.add(score);
    reasonLists.add(_topReasons(parts));
  }

  // 5. Scores to chances.
  final chances = softmax(scores);
  final ranking = [
    for (var i = 0; i < ids.length; i++)
      WinPrediction(
        driver: drivers[ids[i]]!,
        team: teams[ids[i]] ?? '',
        chance: chances[i],
        reasons: reasonLists[i],
      ),
  ];

  // 6. Most likely first. If two chances are equal, the driver higher in
  //    the championship goes first.
  int championshipPlace(WinPrediction prediction) {
    final position = standingById[prediction.driver.id]?.position ?? 0;
    return position > 0 ? position : 999;
  }

  ranking.sort((a, b) {
    final byChance = b.chance.compareTo(a.chance);
    if (byChance != 0) return byChance;
    return championshipPlace(a).compareTo(championshipPlace(b));
  });

  return RacePrediction(
    ranking: ranking,
    racesUsed: data.recentRaces.length,
    usedLastYear: available.contains(Factor.lastYear),
    usedQualifying: available.contains(Factor.qualifying),
  );
}

/// One factor's share of a driver's score, and the reason in words.
class _Part {
  const _Part(this.factor, this.share, this.reason);

  final Factor factor;
  final double share; // Weight x value: how much this adds to the score
  final String? reason;
}

/// The two parts that added the most to a driver's score, in words.
List<String> _topReasons(List<_Part> parts) {
  final withReasons = parts.where((part) => part.reason != null).toList();
  withReasons.sort((a, b) {
    final byShare = b.share.compareTo(a.share); // Biggest first
    if (byShare != 0) return byShare;
    // Equal: keep the enum's order, so the result never changes at random.
    return a.factor.index.compareTo(b.factor.index);
  });
  return [for (final part in withReasons.take(2)) part.reason!];
}

/// The points a finishing position earns. Nothing outside the top 10,
/// and nothing for null (did not start, or not in the race at all).
int pointsFor(int? position) {
  if (position == null || position < 1 || position > racePoints.length) {
    return 0;
  }
  return racePoints[position - 1];
}

/// Recent finishes (newest first) as one number from 0 to 1.
///
/// Newer races count more. With five races the newest counts five times
/// and the oldest once. 1 means they won every race.
double formScore(List<int?> finishes) {
  var earned = 0.0;
  var best = 0.0; // What they would have earned by winning every race
  for (var i = 0; i < finishes.length; i++) {
    final weight = (finishes.length - i).toDouble();
    earned += weight * pointsFor(finishes[i]);
    best += weight * 25;
  }
  return best == 0 ? 0 : earned / best;
}

/// Recent finishes (newest first) in a few words.
String describeForm(List<int?> finishes) {
  final races = finishes.length;
  final lately = races == 1 ? 'the last race' : 'the last $races races';
  final wins = finishes.where((place) => place == 1).length;
  final podiums =
      finishes.where((place) => place != null && place <= 3).length;
  var points = 0;
  for (final place in finishes) {
    points += pointsFor(place);
  }

  if (wins > 0) {
    return races == 1 ? 'Won the last race' : 'Won $wins of $lately';
  }
  if (podiums > 0) {
    return '$podiums ${podiums == 1 ? 'podium' : 'podiums'} in $lately';
  }
  if (points > 0) return '$points points in $lately';
  return 'No points in $lately';
}

/// Turns scores into chances that add up to 1. This is called "softmax".
///
/// e (2.718...) to the power of anything is positive, and it grows fast.
/// So a small lead in score becomes a clear lead in chance. [confidence]
/// sets how fast: see [winConfidence].
List<double> softmax(
  List<double> scores, {
  double confidence = winConfidence,
}) {
  final powers = [for (final score in scores) math.exp(score * confidence)];
  var total = 0.0;
  for (final power in powers) {
    total += power;
  }
  return [for (final power in powers) power / total];
}

/// 1 becomes "1st", 2 "2nd", 3 "3rd", 11 "11th", 22 "22nd".
String ordinal(int number) {
  final lastTwo = number % 100;
  if (lastTwo >= 11 && lastTwo <= 13) return '${number}th'; // 11th, 12th, 13th
  final suffix = switch (number % 10) {
    1 => 'st',
    2 => 'nd',
    3 => 'rd',
    _ => 'th', // _ means "anything else"
  };
  return '$number$suffix';
}
