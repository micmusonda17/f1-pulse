// A playground for the data layer, with no screens at all.
// Run it from the project folder with:
//
//   dart run bin/try_api.dart
//
// It prints the season, the top five drivers and the last race's podium.

// print() is fine in a terminal script, so we switch that lint off here.
// ignore_for_file: avoid_print

import 'package:pitbeat/services/jolpica_api.dart';
import 'package:pitbeat/utils/formatting.dart';

Future<void> main() async {
  final api = JolpicaApi();

  print('THE CALENDAR');
  final races = await api.getSchedule();
  for (final race in races) {
    final start = race.start;
    final when = start == null ? 'date to be confirmed' : formatDayTime(start);
    final done = race.isFinished ? 'done' : '';
    print('${race.round.toString().padLeft(2)}. ${race.name} ($when) $done');
  }

  print('\nTOP FIVE DRIVERS');
  final standings = await api.getDriverStandings();
  for (final standing in standings.take(5)) {
    print('P${standing.position} ${standing.driver.fullName} '
        '${formatPoints(standing.points)} pts');
  }

  final finished = races.where((race) => race.isFinished).toList();
  if (finished.isNotEmpty) {
    final last = finished.last;
    print('\nPODIUM AT THE ${last.name.toUpperCase()}');
    final results = await api.getResults(last.season, last.round);
    for (final result in results.take(3)) {
      print('P${result.position} ${result.driver.fullName} '
          '(${result.team}) ${result.timeOrStatus}');
    }
  }
}
