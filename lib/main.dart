import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/calendar_screen.dart';
import 'screens/news_screen.dart';
import 'screens/standings_screen.dart';
import 'screens/tracker_hub_screen.dart';
import 'screens/tracker_screen.dart';
import 'screens/welcome_screen.dart';
import 'services/api_exception.dart';
import 'services/app_preferences.dart';
import 'services/jolpica_api.dart';
import 'services/openf1_api.dart';
import 'services/phone_cache.dart';
import 'services/race_alerts.dart';
import 'services/settings_store.dart';
import 'theme.dart';
import 'tracker/tracker_controller.dart';

/// Where the app starts, just like `if __name__ == "__main__":` in Python.
void main() {
  LicenseRegistry.addLicense(_ourLicences);
  // Keep copies of calendar, standings and results on the phone, so they
  // still show with no signal, and data saver can reuse them (Chapter 43).
  JolpicaApi.cache = PhoneCache();
  runApp(const PitbeatApp());
}

/// Lets code outside any screen open a new screen, like tapping an alert.
/// MaterialApp uses it for its Navigator, so it is always the real one.
final GlobalKey<NavigatorState> appNavigator = GlobalKey<NavigatorState>();

/// Opens the replay a "replay is ready" alert points to. The payload is
/// the session's start time, which is how findSession finds it.
Future<void> openReplayFromAlert(String? payload) async {
  final start = DateTime.tryParse(payload ?? '');
  if (start == null) return; // A reminder: just opening the app is enough
  try {
    final session = await OpenF1Api.instance.findSession(start);
    final navigator = appNavigator.currentState;
    if (session == null || navigator == null) return;
    navigator.push(
      MaterialPageRoute(
        builder: (context) =>
            TrackerScreen(session: session, mode: TrackerMode.replay),
      ),
    );
  } on ApiException {
    // OpenF1 could not be reached. The app simply opens where it was.
  }
}

/// The licences of the free files we ship with the app, for the Licences
/// page in Settings (Flutter adds its own packages' licences by itself).
///
/// async* makes a Stream: a function that can hand back several results,
/// one at a time, with yield. The page only calls it when you open it.
Stream<LicenseEntry> _ourLicences() async* {
  final circuits = await rootBundle.loadString('assets/circuits/LICENSE.txt');
  yield LicenseEntryWithLineBreaks(['f1-circuits (circuit maps)'], circuits);
  final font = await rootBundle.loadString('assets/fonts/OFL.txt');
  yield LicenseEntryWithLineBreaks(['Titillium Web (font)'], font);
}

/// The whole app: its name, its colours and its first screen.
class PitbeatApp extends StatelessWidget {
  const PitbeatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pitbeat',
      navigatorKey: appNavigator,
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
    // The switches from Settings, before any screen needs them.
    await AppPreferences.instance.load();
    await RaceAlerts.instance.init(onTap: openReplayFromAlert);
    if (!mounted) return;
    setState(() => _welcomeDone = done);

    // Opened by tapping a "replay is ready" alert? Go straight to it.
    final payload = await RaceAlerts.instance.launchPayload();
    if (done && payload != null) openReplayFromAlert(payload);
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
