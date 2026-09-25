import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/openf1_models.dart';
import '../theme.dart';
import '../tracker/race_status.dart';
import '../utils/formatting.dart';

// The tracker's extra widgets (Chapter 53): the flag in the corner of the
// map, and a strip of cards under it for the weather, the fastest lap and
// the laps to go.

/// The colour F1 uses for the fastest time: purple.
const Color fastestPurple = Color(0xFFB138DD);

/// The track's status in the corner of the map: GREEN, YELLOW S7,
/// VSC, SAFETY CAR, RED FLAG or CHEQUERED.
class TrackStatusBadge extends StatelessWidget {
  const TrackStatusBadge({super.key, required this.state});

  final TrackState state;

  @override
  Widget build(BuildContext context) {
    final sectors = state.yellowSectors.toList()..sort();
    // A switch expression can hand back two things at once, as a record.
    final (label, colour) = switch (state.status) {
      TrackStatus.green => ('GREEN', Colors.green),
      TrackStatus.yellow => (
          ['YELLOW', for (final sector in sectors) 'S$sector'].join(' '),
          Colors.amber,
        ),
      TrackStatus.virtualSafetyCar => ('VSC', Colors.orange),
      TrackStatus.safetyCar => ('SAFETY CAR', Colors.orange),
      TrackStatus.red => ('RED FLAG', Colors.red),
      TrackStatus.chequered => ('CHEQUERED', Colors.white),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: F1Colors.surface,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colour.withValues(alpha: 0.7)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (state.status == TrackStatus.chequered)
            const Icon(Icons.sports_score, size: 14)
          else
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
            ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: colour,
              fontSize: 12,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
        ],
      ),
    );
  }
}

/// The cards under the map, in a row you can swipe sideways.
class SessionInfoStrip extends StatelessWidget {
  const SessionInfoStrip({
    super.key,
    this.weather,
    this.fastestLap,
    this.fastestCode,
    this.lapsToGo,
  });

  final WeatherReading? weather;
  final Lap? fastestLap;
  final String? fastestCode; // "VER"
  final int? lapsToGo;

  @override
  Widget build(BuildContext context) {
    final fastest = fastestLap;
    final seconds = fastest?.duration;
    final toGo = lapsToGo;
    final cards = <Widget>[
      if (weather case final reading?) WeatherCard(reading: reading),
      if (fastest != null && seconds != null)
        InfoCard(
          label: 'FASTEST LAP',
          value: '${fastestCode ?? '#${fastest.driverNumber}'}  '
              '${formatLapTime(seconds)}',
          detail: 'Lap ${fastest.lapNumber}',
          colour: fastestPurple,
        ),
      if (toGo != null)
        InfoCard(
          label: 'TO GO',
          value: toGo == 1 ? '1 lap' : '$toGo laps',
          detail: toGo == 0 ? 'Last lap' : null,
        ),
    ];
    if (cards.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        itemCount: cards.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) => cards[index],
      ),
    );
  }
}

/// One small card: a label in colour, a value, and a line under it.
class InfoCard extends StatelessWidget {
  const InfoCard({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.colour = F1Colors.red,
    this.extra,
  });

  final String label; // "FASTEST LAP"
  final String value; // "VER  1:32.456"
  final String? detail; // "Lap 41"
  final Color colour;
  final Widget? extra; // Anything else on the detail line, like an arrow

  @override
  Widget build(BuildContext context) {
    final line = detail;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: F1Colors.surface,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: colour,
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.2,
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w900),
          ),
          if (line != null || extra != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (line != null)
                  Text(
                    line,
                    style: const TextStyle(fontSize: 10, color: F1Colors.muted),
                  ),
                ?extra,
              ],
            ),
        ],
      ),
    );
  }
}

/// The weather at the clock: air and track temperature, humidity, the
/// wind with an arrow showing where it blows, and rain.
class WeatherCard extends StatelessWidget {
  const WeatherCard({super.key, required this.reading});

  final WeatherReading reading;

  @override
  Widget build(BuildContext context) {
    final humidity = reading.humidity;
    final wind = reading.windSpeed;
    final from = reading.windDirection;
    final parts = [
      if (humidity != null) 'Humidity ${humidity.round()}%',
      if (wind != null)
        'Wind ${formatWindSpeed(wind)}'
            '${from == null ? '' : ' ${compassPoint(from)}'}',
      reading.isRaining ? 'Rain' : 'Dry',
    ];
    return InfoCard(
      label: 'WEATHER',
      colour: reading.isRaining ? Colors.lightBlueAccent : F1Colors.red,
      value: 'Air ${reading.airTemperature.round()}°  '
          'Track ${reading.trackTemperature.round()}°',
      detail: parts.join('  ·  '),
      // Wind direction is where it comes FROM, so the arrow points the
      // other way: where it is going. 0 degrees is north, up the screen.
      extra: from == null
          ? null
          : Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Transform.rotate(
                angle: (from + 180) * math.pi / 180,
                child: const Icon(
                  Icons.navigation,
                  size: 11,
                  color: F1Colors.muted,
                ),
              ),
            ),
    );
  }
}
