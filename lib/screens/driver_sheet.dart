import 'package:flutter/material.dart';

import '../stats/race_story.dart' show sentenceCase;
import '../stats/strategy.dart';
import '../theme.dart';
import '../tracker/tracker_controller.dart';
import '../widgets/driver_widgets.dart';
import 'tracker_screen.dart' show TyreDot;

/// Everything about one driver at the replay's clock (Chapters 52 and 54):
/// why they are out, their tyres, every pit stop, and what race control
/// has said about them. Opens when you tap a row in the running order.
class DriverSheet extends StatelessWidget {
  const DriverSheet({
    super.key,
    required this.controller,
    required this.number,
    this.onFollow,
  });

  final TrackerController controller;
  final int number;
  final VoidCallback? onFollow; // Follow this car in the 3D view

  @override
  Widget build(BuildContext context) {
    // It keeps up with the replay while it is open.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final theme = Theme.of(context);
        final driver = controller.drivers[number];
        final colour = driver?.colour ?? Colors.grey;
        final out = controller.outNotes[number];
        final compound = controller.tyres[number];
        final age = controller.tyreAges[number];
        final strategy = controller.strategiesNow([number]).first;
        final messages = controller.messagesFor(number).reversed.take(8);

        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(context).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            children: [
              Row(
                children: [
                  DriverAvatar(
                    photoUrl: driver?.headshotUrl,
                    colour: colour,
                    code: driver?.acronym ?? '$number',
                    size: 48,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          driver?.fullName ?? 'Car $number',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          driver?.team ?? '',
                          style: const TextStyle(color: F1Colors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (out != null)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: F1Colors.surfaceHigh,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.cancel_outlined, color: F1Colors.muted),
                      const SizedBox(width: 8),
                      Expanded(child: Text(out)),
                    ],
                  ),
                ),
              const _Heading('Tyres'),
              if (compound != null)
                Row(
                  children: [
                    TyreDot(compound: compound),
                    const SizedBox(width: 8),
                    Text(
                      age == null
                          ? 'Now on ${compound.toLowerCase()}'
                          : 'Now on ${compound.toLowerCase()}, $age '
                              '${age == 1 ? 'lap' : 'laps'} old',
                    ),
                  ],
                )
              else
                const Text('Not known yet.'),
              const SizedBox(height: 6),
              for (final stint in strategy.stints)
                Text(
                  '${compoundName(stint.compound)}: '
                  'laps ${stint.fromLap} to ${stint.toLap}'
                  '${stint.tyreAgeAtStart > 0 ? ', used' : ''}',
                  style: const TextStyle(fontSize: 12, color: F1Colors.muted),
                ),
              _Heading(
                strategy.stops.length == 1
                    ? '1 pit stop'
                    : '${strategy.stops.length} pit stops',
              ),
              if (strategy.stops.isEmpty) const Text('None yet.'),
              for (final stop in strategy.stops)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    [
                      'Lap ${stop.lap}',
                      if (stop.stopSeconds case final seconds?)
                        '${seconds.toStringAsFixed(1)} s stopped',
                      if (stop.laneSeconds case final seconds?)
                        '${seconds.toStringAsFixed(1)} s in the pit lane',
                      if (tyreChange(stop) case final change
                          when change.isNotEmpty)
                        change,
                    ].join('  ·  '),
                  ),
                ),
              if (messages.isNotEmpty) ...[
                const _Heading('Race control'),
                for (final message in messages)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      [
                        if (message.lapNumber case final lap?) 'Lap $lap',
                        sentenceCase(message.message),
                      ].join(': '),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
              ],
              if (onFollow case final follow?) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: follow,
                  icon: const Icon(Icons.videocam_outlined),
                  label: const Text('Follow in 3D'),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 6),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          color: F1Colors.red,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
        ),
      ),
    );
  }
}
