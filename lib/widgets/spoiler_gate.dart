import 'package:flutter/material.dart';

import '../services/app_preferences.dart';
import '../theme.dart';

/// Hides [child] while spoiler-free mode is on, with a button to show it.
///
/// Wrap anything that could give away a result: standings, news, results,
/// predictions. Once you tap Show, that [topic] stays visible until the app
/// closes. With spoiler-free mode off, this just shows [child].
class SpoilerGate extends StatelessWidget {
  const SpoilerGate({
    super.key,
    required this.topic,
    required this.what,
    required this.child,
  });

  final String topic; // A name for what is hidden, like 'standings'
  final String what; // For the message: "The standings"
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final preferences = AppPreferences.instance;
    // Redraws when spoiler-free mode is switched, or something is revealed.
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) {
        if (!preferences.isHidden(topic)) return child;

        final theme = Theme.of(context);
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.visibility_off_outlined,
                  size: 40,
                  color: F1Colors.muted,
                ),
                const SizedBox(height: 12),
                Text(
                  '$what may contain spoilers.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  'Spoiler-free mode is on.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: F1Colors.muted,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.tonal(
                  onPressed: () => preferences.reveal(topic),
                  child: const Text('Show'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
