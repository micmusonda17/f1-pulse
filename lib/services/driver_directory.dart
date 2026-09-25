import 'package:flutter/material.dart';

import '../models/openf1_models.dart';
import '../models/standing.dart';
import 'openf1_api.dart';
import 'replay_archive.dart';

/// Photos and team colours for this season's drivers.
///
/// Jolpica (standings and results) has no pictures or colours, but OpenF1
/// does. Both APIs use the same three-letter driver codes ("ANT", "HAM"),
/// so we download OpenF1's driver lists once and look drivers up by code.
class DriverDirectory {
  DriverDirectory._();

  /// One shared copy, so the lists are only downloaded once per app run.
  static final DriverDirectory instance = DriverDirectory._();

  Future<Map<String, DriverInfo>>? _loading;

  /// Every driver, keyed by code. Several screens can call this at the
  /// same time: they all share the same download.
  Future<Map<String, DriverInfo>> load() {
    return _loading ??= _download();
  }

  Future<Map<String, DriverInfo>> _download() async {
    final api = OpenF1Api.instance;
    final thisYear = DateTime.now().year;
    try {
      // The drivers from the last three finished races. Early in the year
      // there may not be any yet, so we also try last year.
      for (final year in [thisYear, thisYear - 1]) {
        final races = await api.getRaceSessions(year);
        final finished = races
            .where((race) => race.hasFinished && !race.isCancelled)
            .toList();
        if (finished.isEmpty) continue;
        finished.sort((a, b) => a.start.compareTo(b.start)); // Oldest first
        final lastThree = finished.length > 3
            ? finished.sublist(finished.length - 3)
            : finished;
        final lists = <List<DriverInfo>>[];
        for (final race in lastThree) {
          lists.add(await api.getDrivers(race.sessionKey));
        }
        return mergeDriverLists(lists);
      }
      return {};
    } catch (_) {
      _loading = null; // Forget the failure so the next screen tries again
      // While OpenF1 is locked, the newest replay saved on the phone still
      // knows everyone's team colour and photo (Chapter 56).
      return _fromSavedReplay();
    }
  }

  Future<Map<String, DriverInfo>> _fromSavedReplay() async {
    try {
      final archive = ReplayArchive.instance;
      await archive.load();
      for (final session in archive.savedSessions) {
        final saved = await archive.replayFor(session.sessionKey);
        if (saved != null && saved.drivers.isNotEmpty) {
          return mergeDriverLists([saved.drivers]);
        }
      }
    } catch (_) {
      // Nothing saved either: codes and grey, which still works.
    }
    return {};
  }
}

/// Joins the driver lists from several races, oldest race first.
///
/// The newest race wins, because drivers change teams during a season.
/// But OpenF1 sometimes has no photo for a driver in one race, so we keep
/// the photo from an older race when the newer one is missing.
Map<String, DriverInfo> mergeDriverLists(List<List<DriverInfo>> races) {
  final directory = <String, DriverInfo>{};
  for (final drivers in races) {
    for (final driver in drivers) {
      final older = directory[driver.acronym];
      directory[driver.acronym] = DriverInfo(
        number: driver.number,
        acronym: driver.acronym,
        fullName: driver.fullName,
        team: driver.team,
        colour: driver.colour,
        headshotUrl: driver.headshotUrl ?? older?.headshotUrl,
      );
    }
  }
  return directory;
}

/// Jolpica and OpenF1 spell team names differently ("RB F1 Team" and
/// "Racing Bulls"), so we find each team's colour through its drivers.
Map<String, Color> teamColoursFrom(
  List<DriverStanding> standings,
  Map<String, DriverInfo> directory,
) {
  final colours = <String, Color>{};
  for (final standing in standings) {
    final info = directory[standing.driver.code];
    if (info != null) colours[standing.team] = info.colour;
  }
  return colours;
}
