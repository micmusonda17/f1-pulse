import 'package:flutter/material.dart';

import '../models/openf1_models.dart';
import '../stats/strategy.dart';
import '../theme.dart';
import 'driver_widgets.dart';

/// The strategy chart (Chapter 54): one bar per driver across the laps,
/// coloured by tyre, with a white tick at every pit stop. Tap a driver to
/// see each stop: the lap, how long, and the tyres off and on.
class StrategyChart extends StatefulWidget {
  const StrategyChart({
    super.key,
    required this.strategies,
    required this.drivers,
    required this.totalLaps,
    this.countStops = true,
  });

  final List<DriverStrategy> strategies; // In running order
  final Map<int, DriverInfo> drivers;
  final int totalLaps; // The width of the chart, in laps
  final bool countStops; // Races count stops; practice counts runs

  @override
  State<StrategyChart> createState() => _StrategyChartState();
}

class _StrategyChartState extends State<StrategyChart> {
  final Set<int> _open = {}; // Drivers whose stops are showing

  @override
  Widget build(BuildContext context) {
    // Lap-by-lap replays (Chapter 57) have stops but no tyres: still worth
    // a chart, in grey with the ticks.
    if (widget.strategies.every(
      (strategy) => strategy.stints.isEmpty && strategy.stops.isEmpty,
    )) {
      return const Center(child: Text('No tyre data for this session yet.'));
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        _Legend(totalLaps: widget.totalLaps),
        for (final strategy in widget.strategies) ..._row(strategy),
      ],
    );
  }

  List<Widget> _row(DriverStrategy strategy) {
    final number = strategy.driverNumber;
    final driver = widget.drivers[number];
    final open = _open.contains(number);
    final count = widget.countStops
        ? strategy.stops.length
        : strategy.stints.length;
    final word = widget.countStops ? 'stop' : 'run';

    return [
      InkWell(
        onTap: () => setState(() {
          if (!_open.remove(number)) _open.add(number);
        }),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          child: Row(
            children: [
              TeamColourBar(colour: driver?.colour ?? Colors.grey, height: 18),
              const SizedBox(width: 6),
              SizedBox(
                width: 36,
                child: Text(
                  driver?.acronym ?? '$number',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 18,
                  child: CustomPaint(
                    painter: StrategyBarPainter(
                      stints: strategy.stints,
                      stopLaps: [for (final stop in strategy.stops) stop.lap],
                      totalLaps: widget.totalLaps,
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: 58,
                child: Text(
                  count == 1 ? '1 $word' : '$count ${word}s',
                  textAlign: TextAlign.end,
                  style: const TextStyle(fontSize: 12, color: F1Colors.muted),
                ),
              ),
            ],
          ),
        ),
      ),
      if (open) ..._details(strategy),
    ];
  }

  /// Every stop, one line each: "Lap 18  ·  2.4 s stopped  ·  22.1 s in
  /// the pit lane  ·  Medium to hard".
  List<Widget> _details(DriverStrategy strategy) {
    if (strategy.stops.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.fromLTRB(58, 0, 12, 8),
          child: Text(
            'No pit stops.',
            style: TextStyle(fontSize: 12, color: F1Colors.muted),
          ),
        ),
      ];
    }
    return [
      for (final stop in strategy.stops)
        Padding(
          padding: const EdgeInsets.fromLTRB(58, 0, 12, 6),
          child: Text(
            [
              'Lap ${stop.lap}',
              if (stop.stopSeconds case final seconds?)
                '${seconds.toStringAsFixed(1)} s stopped',
              if (stop.laneSeconds case final seconds?)
                '${seconds.toStringAsFixed(1)} s in the pit lane',
              if (tyreChange(stop) case final change when change.isNotEmpty)
                change,
            ].join('  ·  '),
            style: const TextStyle(fontSize: 12),
          ),
        ),
    ];
  }
}

/// The lap numbers along the top, and what each colour means.
class _Legend extends StatelessWidget {
  const _Legend({required this.totalLaps});

  final int totalLaps;

  @override
  Widget build(BuildContext context) {
    const small = TextStyle(fontSize: 11, color: F1Colors.muted);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Column(
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 4,
            children: [
              for (final entry in F1Colors.tyres.entries)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: entry.value,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(compoundName(entry.key), style: small),
                  ],
                ),
            ],
          ),
          const SizedBox(height: 6),
          // Lap 1 on the left, the last lap on the right, over the bars.
          Row(
            children: [
              const SizedBox(width: 46), // The colour bar and the code
              const Expanded(child: Text('Lap 1', style: small)),
              Text('Lap $totalLaps', style: small),
              const SizedBox(width: 58),
            ],
          ),
        ],
      ),
    );
  }
}

/// Paints one driver's bar: a block per set of tyres, and a tick for each
/// stop.
class StrategyBarPainter extends CustomPainter {
  StrategyBarPainter({
    required this.stints,
    required this.stopLaps,
    required this.totalLaps,
  });

  final List<StintSpan> stints;
  final List<int> stopLaps;
  final int totalLaps;

  @override
  void paint(Canvas canvas, Size size) {
    if (totalLaps <= 0) return;
    final perLap = size.width / totalLaps;

    // A faint track for the whole race, so the bars have something to sit on.
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(3)),
      Paint()..color = Colors.white.withValues(alpha: 0.05),
    );

    for (final stint in stints) {
      final left = (stint.fromLap - 1) * perLap;
      final width = stint.laps * perLap;
      final colour = F1Colors.tyres[stint.compound] ?? F1Colors.muted;
      final block = Rect.fromLTWH(left, 2, width, size.height - 4);
      canvas.drawRRect(
        RRect.fromRectAndRadius(block.deflate(0.5), const Radius.circular(3)),
        Paint()..color = colour.withValues(alpha: 0.85),
      );
      // The compound's letter, if the block is wide enough for it.
      if (width > 14 && stint.compound.isNotEmpty) {
        final letter = TextPainter(
          text: TextSpan(
            text: stint.compound[0],
            style: const TextStyle(
              color: Colors.black,
              fontSize: 10,
              fontWeight: FontWeight.w900,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        letter.paint(
          canvas,
          Offset(left + 4, (size.height - letter.height) / 2),
        );
        letter.dispose();
      }
    }

    // A white tick at the end of the lap each stop came on.
    final tick = Paint()
      ..color = Colors.white
      ..strokeWidth = 2;
    for (final lap in stopLaps) {
      final x = lap * perLap;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), tick);
    }
  }

  @override
  bool shouldRepaint(covariant StrategyBarPainter oldDelegate) => true;
}
