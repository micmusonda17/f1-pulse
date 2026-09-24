import 'package:flutter/material.dart';

import 'screens/calendar_screen.dart';
import 'screens/news_screen.dart';
import 'screens/standings_screen.dart';
import 'screens/tracker_hub_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/settings_store.dart';
import 'theme.dart';

/// Where the app starts, just like `if __name__ == "__main__":` in Python.
void main() {
  runApp(const F1PulseApp());
}

/// The whole app: its name, its colours and its first screen.
class F1PulseApp extends StatelessWidget {
  const F1PulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'F1 Pulse',
      debugShowCheckedModeBanner: false,
      theme: buildF1Theme(), // Colours and font, from lib/theme.dart
      home: const StartGate(),
    );
  }
}

/// Decides the first screen: the welcome pages the very first time you
/// open the app, and straight to the tabs every time after that.
class StartGate extends StatefulWidget {
  const StartGate({super.key});

  @override
  State<StartGate> createState() => _StartGateState();
}

class _StartGateState extends State<StartGate> {
  final SettingsStore _settings = SettingsStore();
  bool? _welcomeDone; // null while we are still checking

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    var done = false;
    try {
      done = await _settings.isWelcomeDone();
    } catch (_) {
      // Could not read the settings: show the welcome pages to be safe.
    }
    if (mounted) setState(() => _welcomeDone = done);
  }

  @override
  Widget build(BuildContext context) {
    final done = _welcomeDone;
    final Widget screen;
    if (done == null) {
      screen = const Scaffold(); // A blink of plain background while we check
    } else if (!done) {
      screen = WelcomeScreen(
        onFinished: () => setState(() => _welcomeDone = true),
      );
    } else {
      screen = const HomeShell();
    }
    // Fades from one screen to the next instead of jumping.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 400),
      child: screen,
    );
  }
}

/// The frame around the four tabs, with the bar along the bottom.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _tab = 0;

  // The four tabs, in the same order as the buttons below.
  static const List<Widget> _screens = [
    CalendarScreen(),
    StandingsScreen(),
    TrackerHubScreen(),
    NewsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // IndexedStack keeps all four screens alive and only shows one.
      // Switching tabs does not reload anything.
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (index) => setState(() => _tab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month),
            label: 'Races',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'Standings',
          ),
          NavigationDestination(
            icon: Icon(Icons.map_outlined),
            selectedIcon: Icon(Icons.map),
            label: 'Tracker',
          ),
          NavigationDestination(
            icon: Icon(Icons.article_outlined),
            selectedIcon: Icon(Icons.article),
            label: 'News',
          ),
        ],
      ),
    );
  }
}
