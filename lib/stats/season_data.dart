import '../models/race_result.dart';
import '../services/jolpica_api.dart';

/// Everything that happened at one finished race weekend.
class SeasonRound {
  const SeasonRound({
    required this.round,
    required this.raceName,
    required this.race,
    this.qualifying = const [],
    this.sprint = const [],
  });

  final int round;
  final String raceName;
  final List<RaceResult> race;
  final List<QualifyingResult> qualifying;
  final List<RaceResult> sprint; // Empty on a weekend without a sprint
}

/// Downloads a whole season, for fantasy points and the form guide.
///
/// That is about a dozen requests, so the answer is kept for 15 minutes
/// and shared, like PredictionService (Chapter 39).
class SeasonService {
  SeasonService._();

  static final SeasonService instance = SeasonService._();

  static const Duration keepFor = Duration(minutes: 15);

  final Map<int, _Saved> _saved = {};

  /// Every finished round of [season], in order.
  Future<List<SeasonRound>> load(int season, {bool refresh = false}) async {
    final saved = _saved[season];
    if (!refresh &&
        saved != null &&
        DateTime.now().difference(saved.time) < keepFor) {
      return saved.rounds;
    }

    final api = JolpicaApi();
    final schedule = await api.getSchedule(season: '$season');
    final results = await api.getSeasonResults(season);
    final qualifying = await api.getSeasonQualifying(season);
    final sprints = await api.getSeasonSprints(season);

    final rounds = [
      for (final race in schedule)
        if (results[race.round] case final raceResults?)
          SeasonRound(
            round: race.round,
            raceName: race.name,
            race: raceResults,
            qualifying: qualifying[race.round] ?? const [],
            sprint: sprints[race.round] ?? const [],
          ),
    ];
    _saved[season] = _Saved(DateTime.now(), rounds);
    return rounds;
  }
}

class _Saved {
  const _Saved(this.time, this.rounds);

  final DateTime time;
  final List<SeasonRound> rounds;
}
