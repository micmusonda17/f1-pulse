import 'dart:math' as math;

import '../models/race.dart';
import '../models/race_result.dart';
import '../services/jolpica_api.dart';
import 'predictor.dart';

/// Downloads what the predictor needs from Jolpica, then runs it.
///
/// That is about eight small requests, one after another, so the answer is
/// kept for 15 minutes. The Races tab and the prediction page share it.
class PredictionService {
  PredictionService._();

  static final PredictionService instance = PredictionService._();

  /// How long a prediction is kept before it is worked out again. Short
  /// enough to pick up qualifying soon after it finishes.
  static const Duration keepFor = Duration(minutes: 15);

  /// How many recent races count towards a driver's form.
  static const int formRaces = 5;

  final JolpicaApi _api = JolpicaApi();
  final Map<String, _Saved> _saved = {}; // "2026-15" -> prediction

  Future<RacePrediction> predict(Race race, {bool refresh = false}) async {
    final key = '${race.season}-${race.round}';
    final saved = _saved[key];
    if (!refresh &&
        saved != null &&
        DateTime.now().difference(saved.time) < keepFor) {
      return saved.prediction;
    }

    final prediction = await _download(race);
    _saved[key] = _Saved(DateTime.now(), prediction);
    return prediction;
  }

  Future<RacePrediction> _download(Race race) async {
    final season = race.season;

    // 1. The championship table.
    final standings = await _api.getDriverStandings(season: '$season');

    // 2. The latest races with results, newest first. For a race further
    //    ahead than the next one, we still start from the latest result.
    final recentRaces = <List<RaceResult>>[];
    final lastRound = await _api.getLastRound(season);
    if (lastRound != null) {
      var round = math.min(lastRound, race.round - 1);
      while (round >= 1 && recentRaces.length < formRaces) {
        final results = await _api.getResults(season, round);
        if (results.isNotEmpty) recentRaces.add(results);
        round--;
      }
    }

    // 3. Last year's race at this circuit. Empty for a new circuit.
    final lastYearHere =
        await _api.getResultsAtCircuit(season - 1, race.circuitId);

    // 4. Qualifying. Empty until it is over.
    final qualifying = await _api.getQualifying(season, race.round);

    return predictWinner(
      PredictionData(
        standings: standings,
        recentRaces: recentRaces,
        lastYearHere: lastYearHere,
        qualifying: qualifying,
      ),
    );
  }
}

/// A prediction and when we worked it out.
class _Saved {
  const _Saved(this.time, this.prediction);

  final DateTime time;
  final RacePrediction prediction;
}
