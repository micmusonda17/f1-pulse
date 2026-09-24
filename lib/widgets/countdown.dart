import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/formatting.dart';

/// Counts down to [target]: DAYS HRS MIN SEC, updating every second.
class Countdown extends StatefulWidget {
  const Countdown({super.key, required this.target});

  final DateTime target;

  @override
  State<Countdown> createState() => _CountdownState();
}

class _CountdownState extends State<Countdown> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Every second, call setState. That makes Flutter run build() again,
    // and build() works out the new time left.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {});
    });
  }

  @override
  void dispose() {
    // Always stop timers when the widget goes away, or they keep running.
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.target.difference(DateTime.now());
    if (left.isNegative) {
      return Text(
        'Happening now',
        style: Theme.of(context).textTheme.titleLarge,
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _CountdownUnit(value: left.inDays, label: 'DAYS'),
        _CountdownUnit(value: left.inHours % 24, label: 'HRS'),
        _CountdownUnit(value: left.inMinutes % 60, label: 'MIN'),
        _CountdownUnit(value: left.inSeconds % 60, label: 'SEC'),
      ],
    );
  }
}

/// One number with its label underneath.
class _CountdownUnit extends StatelessWidget {
  const _CountdownUnit({required this.value, required this.label});

  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          twoDigits(value),
          style: theme.textTheme.headlineLarge?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}
