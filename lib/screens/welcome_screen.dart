import 'package:flutter/material.dart';

import '../models/openf1_models.dart';
import '../models/standing.dart';
import '../services/driver_directory.dart';
import '../services/jolpica_api.dart';
import '../services/settings_store.dart';
import '../theme.dart';
import '../widgets/common_widgets.dart';
import '../widgets/driver_widgets.dart';

/// The pages you see the very first time you open the app:
/// your name, your driver, your team. Then the main app.
class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key, required this.onFinished});

  /// Called after the last page, so main.dart can show the tabs instead.
  final VoidCallback onFinished;

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  final SettingsStore _settings = SettingsStore();
  final JolpicaApi _api = JolpicaApi();
  final PageController _pages = PageController();
  final TextEditingController _name = TextEditingController();

  // The choices, filled in when the standings arrive.
  List<DriverStanding>? _drivers;
  List<ConstructorStanding>? _teams;
  String? _loadError;
  Map<String, DriverInfo> _directory = {}; // Photos and colours, by code

  int _page = 0; // 0 = name, 1 = driver, 2 = team
  String? _driverId; // The driver you tapped, like "hamilton"
  String? _team; // The team you tapped, like "Ferrari"
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Start downloading now, while you are still typing your name.
    _loadChoices();
    _loadPhotos();
  }

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  /// Downloads this season's drivers and teams to choose from.
  Future<void> _loadChoices() async {
    try {
      final drivers = await _api.getDriverStandings();
      final teams = await _api.getConstructorStandings();
      if (!mounted) return;
      setState(() {
        _drivers = drivers;
        _teams = teams;
        _loadError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _loadError = '$error');
    }
  }

  void _retry() {
    setState(() => _loadError = null); // Back to the spinner
    _loadChoices();
  }

  Future<void> _loadPhotos() async {
    final directory = await DriverDirectory.instance.load();
    if (mounted) setState(() => _directory = directory);
  }

  /// Slides to another page. Only the buttons can do this.
  void _goTo(int page) {
    FocusScope.of(context).unfocus(); // Hides the keyboard
    setState(() => _page = page);
    _pages.animateToPage(
      page,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  /// Saves everything, then hands over to the main app.
  Future<void> _finish() async {
    setState(() => _saving = true);
    try {
      await _settings.setName(_name.text.trim());
      await _settings.setFavouriteDriver(_driverId);
      await _settings.setFavouriteTeam(_team);
      await _settings.setWelcomeDone(true);
    } catch (_) {
      // Saving failed. Carry on anyway: the worst that happens is that
      // you see these pages again next time.
    }
    widget.onFinished();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(21, 12, 21, 0),
              child: StepBars(current: _page),
            ),
            Expanded(
              child: PageView(
                controller: _pages,
                // No swiping: you could swipe past the name without typing it.
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  NamePage(controller: _name, onNext: () => _goTo(1)),
                  _driverPage(),
                  _teamPage(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------------
  // Page 2: your driver
  // ------------------------------------------------------------------

  Widget _driverPage() {
    return WelcomeStep(
      step: 2,
      title: 'Hi ${_name.text.trim()}. Who is your driver?',
      subtitle: 'They get pinned to the top of the standings.',
      buttons: [
        TextButton(onPressed: () => _goTo(0), child: const Text('Back')),
        const Spacer(),
        TextButton(
          onPressed: () {
            setState(() => _driverId = null);
            _goTo(2);
          },
          child: const Text('Skip'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _driverId == null ? null : () => _goTo(2),
          child: const Text('Next'),
        ),
      ],
      child: _whenLoaded(_driverGrid),
    );
  }

  Widget _driverGrid() {
    final drivers = _drivers!;
    if (drivers.isEmpty) {
      return const _NothingToPick(
        'The season has not started yet. '
        'Pick your driver later with the star in Standings.',
      );
    }
    final teamColours = teamColoursFrom(drivers, _directory);
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3, // Three drivers across
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 140, // Each card is 140 pixels tall
      ),
      itemCount: drivers.length,
      itemBuilder: (context, index) {
        final standing = drivers[index];
        final info = _directory[standing.driver.code];
        return DriverChoice(
          driver: standing.driver,
          team: standing.team,
          photoUrl: info?.headshotUrl,
          colour: info?.colour ?? teamColours[standing.team] ?? Colors.grey,
          selected: standing.driver.id == _driverId,
          onTap: () => setState(() {
            _driverId = standing.driver.id;
            // Suggest their team on the next page. You can still change it.
            _team = standing.team;
          }),
        );
      },
    );
  }

  // ------------------------------------------------------------------
  // Page 3: your team
  // ------------------------------------------------------------------

  Widget _teamPage() {
    return WelcomeStep(
      step: 3,
      title: 'And your team?',
      subtitle: 'Your team gets a star in the team standings.',
      buttons: [
        TextButton(onPressed: () => _goTo(1), child: const Text('Back')),
        const Spacer(),
        TextButton(
          onPressed: _saving
              ? null
              : () {
                  setState(() => _team = null);
                  _finish();
                },
          child: const Text('Skip'),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _saving || _team == null ? null : _finish,
          child: const Text("Let's go"),
        ),
      ],
      child: _whenLoaded(_teamList),
    );
  }

  Widget _teamList() {
    final teams = _teams!;
    if (teams.isEmpty) {
      return const _NothingToPick(
        'The season has not started yet. '
        'Pick your team later with the star in Standings.',
      );
    }
    final teamColours = teamColoursFrom(_drivers!, _directory);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final team in teams)
          TeamChoice(
            name: team.name,
            colour: teamColours[team.name] ?? Colors.grey,
            selected: team.name == _team,
            onTap: () => setState(() => _team = team.name),
          ),
      ],
    );
  }

  /// A spinner or an error until the standings arrive, then [builder].
  Widget _whenLoaded(Widget Function() builder) {
    final error = _loadError;
    if (error != null) return ErrorView(message: error, onRetry: _retry);
    if (_drivers == null || _teams == null) {
      return const LoadingView(message: "Loading this season's grid");
    }
    return builder();
  }
}

// ----------------------------------------------------------------------
// The pieces the pages are made of
// ----------------------------------------------------------------------

/// Page 1: the welcome and your name.
class NamePage extends StatelessWidget {
  const NamePage({super.key, required this.controller, required this.onNext});

  final TextEditingController controller;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return WelcomeStep(
      step: 1,
      title: 'Welcome to Pitbeat',
      subtitle: 'Races, standings, replays and news in one place. '
          'First, what should we call you?',
      buttons: [
        const Spacer(),
        // Rebuilds the button every time the text changes, so it only
        // becomes pressable once there is a name.
        ListenableBuilder(
          listenable: controller,
          builder: (context, child) => FilledButton(
            onPressed: controller.text.trim().isEmpty ? null : onNext,
            child: const Text('Next'),
          ),
        ),
      ],
      // A ListView, so the field can scroll when the keyboard takes space.
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        children: [
          TextField(
            controller: controller,
            // Starts each word with a capital: "michael" becomes "Michael".
            textCapitalization: TextCapitalization.words,
            textInputAction: TextInputAction.next,
            onSubmitted: (_) {
              if (controller.text.trim().isNotEmpty) onNext();
            },
            decoration: const InputDecoration(
              labelText: 'Your name',
              prefixIcon: Icon(Icons.person_outline),
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

/// The layout every welcome page shares: a heading at the top, the
/// content in the middle and the buttons along the bottom.
class WelcomeStep extends StatelessWidget {
  const WelcomeStep({
    super.key,
    required this.step,
    required this.title,
    required this.subtitle,
    required this.child,
    required this.buttons,
  });

  final int step; // 1, 2 or 3
  final String title;
  final String subtitle;
  final Widget child;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'STEP $step OF 3',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: F1Colors.red,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: F1Colors.muted,
                ),
              ),
            ],
          ),
        ),
        Expanded(child: child),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 24, 16),
          child: Row(children: buttons),
        ),
      ],
    );
  }
}

/// Three short bars across the top, one per page, red once you reach it.
class StepBars extends StatelessWidget {
  const StepBars({super.key, required this.current, this.count = 3});

  final int current; // Which page you are on, counting from 0
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < count; i++)
          Expanded(
            // AnimatedContainer fades to the new colour instead of jumping.
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 4,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              decoration: BoxDecoration(
                color: i <= current ? F1Colors.red : F1Colors.surfaceHigh,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
      ],
    );
  }
}

/// One driver on the "who is your driver" page: photo, name and team.
class DriverChoice extends StatelessWidget {
  const DriverChoice({
    super.key,
    required this.driver,
    required this.team,
    required this.photoUrl,
    required this.colour,
    required this.selected,
    required this.onTap,
  });

  final Driver driver;
  final String team;
  final String? photoUrl;
  final Color colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? colour.withValues(alpha: 0.25) : F1Colors.surface,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias, // Keeps the tap ripple inside the corners
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? colour : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              DriverAvatar(
                photoUrl: photoUrl,
                colour: colour,
                code: driver.code,
                size: 56,
              ),
              const SizedBox(height: 8),
              Text(
                driver.lastName.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                team,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: F1Colors.muted),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One team on the "and your team" page.
class TeamChoice extends StatelessWidget {
  const TeamChoice({
    super.key,
    required this.name,
    required this.colour,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final Color colour;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      clipBehavior: Clip.antiAlias,
      color: selected ? colour.withValues(alpha: 0.25) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? colour : Colors.transparent,
          width: 2,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        leading: TeamColourBar(colour: colour),
        title: Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
        trailing: selected ? Icon(Icons.check_circle, color: colour) : null,
      ),
    );
  }
}

/// Shown instead of the choices before the first race of a season.
class _NothingToPick extends StatelessWidget {
  const _NothingToPick(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
