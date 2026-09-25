import 'package:flutter/material.dart';

import '../services/api_exception.dart';
import '../services/app_preferences.dart';
import '../services/openf1_api.dart';
import '../services/profile_store.dart';
import '../services/race_alerts.dart';
import '../services/settings_store.dart';
import 'profiles_screen.dart';

/// Where you enter an OpenF1 login for live data, plus the credits.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final SettingsStore _settings = SettingsStore();
  // A TextEditingController holds what is typed in a TextField.
  final TextEditingController _name = TextEditingController();
  final TextEditingController _username = TextEditingController();
  final TextEditingController _password = TextEditingController();
  bool _saving = false;
  bool _hasLogin = false;
  bool _bettingStats = false; // This profile's choice (Chapter 49)

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final username = await _settings.getOpenF1Username();
    final password = await _settings.getOpenF1Password();
    final betting = await _settings.getBettingStats();
    if (!mounted) return;
    setState(() {
      _name.text = ProfileStore.instance.current?.name ?? '';
      _username.text = username ?? '';
      _password.text = password ?? '';
      _hasLogin = (username ?? '').isNotEmpty;
      _bettingStats = betting;
    });
  }

  /// Renames the signed-in profile.
  Future<void> _saveName() async {
    final name = _name.text.trim();
    final profile = ProfileStore.instance.current;
    if (name.isEmpty || profile == null) {
      _show('Type a name first.');
      return;
    }
    await ProfileStore.instance.rename(profile.id, name);
    if (!mounted) return;
    FocusScope.of(context).unfocus(); // Hides the keyboard
    _show('Saved. Hi $name!');
  }

  /// Back to "Who's watching?". Settings closes first, so the picker
  /// is what you see.
  Future<void> _signOut() async {
    Navigator.pop(context);
    await ProfileStore.instance.signOut();
  }

  /// Deletes the signed-in profile, after asking.
  Future<void> _deleteProfile() async {
    final profile = ProfileStore.instance.current;
    if (profile == null) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${profile.name}?'),
        content: const Text(
          'Their name, favourites and fantasy team are removed from this '
          'phone. Everyone else is kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (sure != true || !mounted) return;
    Navigator.pop(context);
    await ProfileStore.instance.delete(profile.id);
  }

  /// Betting stats are for adults only, so switching them on asks first.
  Future<void> _setBettingStats(bool on) async {
    if (on) {
      final adult = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Are you 18 or older?'),
          content: const Text(
            'Betting stats show fair odds and form for each driver. '
            'Gambling is for adults only. Pitbeat never takes bets and is '
            'not linked to any bookmaker.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('No'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Yes, I am 18+'),
            ),
          ],
        ),
      );
      if (adult != true) return;
    }
    await _settings.setBettingStats(on);
    if (mounted) setState(() => _bettingStats = on);
  }

  Future<void> _save() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      _show('Enter both your OpenF1 email and password.');
      return;
    }

    setState(() => _saving = true);
    try {
      // Check the login works before we save it.
      await OpenF1Api.instance.signIn(username, password);
      await _settings.saveOpenF1Login(username, password);
      if (!mounted) return;
      setState(() => _hasLogin = true);
      _show('Signed in. Live data is unlocked.');
    } on ApiException catch (e) {
      if (mounted) _show(e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _clear() async {
    await _settings.clearOpenF1Login();
    OpenF1Api.instance.signOut();
    if (!mounted) return;
    setState(() {
      _username.clear();
      _password.clear();
      _hasLogin = false;
    });
    _show('Login removed.');
  }

  /// Switches reminders or replay alerts on or off. Switching one on asks
  /// iOS for permission first, and stays off if you said no.
  Future<void> _setAlert(bool on, Future<void> Function(bool) save) async {
    if (on && !await RaceAlerts.instance.askPermission()) {
      if (!mounted) return;
      _show('Allow notifications for Pitbeat in the iPhone Settings app.');
      return;
    }
    await save(on);
    await RaceAlerts.instance.refresh();
  }

  void _show(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Your profile', style: theme.textTheme.titleMedium),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            onSubmitted: (_) => _saveName(),
            decoration: InputDecoration(
              labelText: 'Your name',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                onPressed: _saveName,
                icon: const Icon(Icons.check),
                tooltip: 'Save name',
              ),
            ),
          ),
          const SizedBox(height: 4),
          // Wrap: the buttons go onto a second line if the phone is narrow.
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: () => showProfileSwitcher(context),
                icon: const Icon(Icons.switch_account),
                label: const Text('Switch profile'),
              ),
              TextButton.icon(
                onPressed: _signOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
              ),
              TextButton.icon(
                onPressed: _deleteProfile,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete profile'),
              ),
            ],
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Betting stats (18+)'),
            subtitle: const Text(
              "Fair odds from Pitbeat's predictions, and each driver's form. "
              'Only for this profile.',
            ),
            value: _bettingStats,
            onChanged: _setBettingStats,
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Text('Race weekends', style: theme.textTheme.titleMedium),
          // ListenableBuilder redraws the switches whenever one changes.
          ListenableBuilder(
            listenable: AppPreferences.instance,
            builder: (context, _) => _buildSwitches(),
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),
          Text('Live data (optional)', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Everything else in the app is free, including replays. '
            'Watching the cars live during a session needs an OpenF1 '
            'sponsor account (about 9.90 euros a month, from openf1.org). '
            'Enter that login here.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _username,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'OpenF1 email',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _password,
            obscureText: true, // Shows dots instead of letters
            decoration: const InputDecoration(
              labelText: 'Password',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Checking...' : 'Save and sign in'),
              ),
              const SizedBox(width: 12),
              if (_hasLogin)
                TextButton(
                  onPressed: _clear,
                  child: const Text('Remove login'),
                ),
            ],
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text('About', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          const Text(
            'Pitbeat is a personal learning project. It is not connected '
            'to Formula 1 or any team.\n\n'
            'Calendar, standings and results: Jolpica F1 API.\n'
            'Car positions, laps, tyres, pit stops, race control and '
            'weather: OpenF1.\n'
            'Circuit maps: the f1-circuits project by Tomislav Bacinger.\n'
            'News: the RSS feeds of each website.',
          ),
          const SizedBox(height: 8),
          // The Licences page button
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              // A ready-made Flutter page listing every licence.
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'Pitbeat',
              ),
              child: const Text('Open-source licences'),
            ),
          ),
        ],
      ),
    );
  }

  /// The four switches: two alerts, data saver and spoiler-free mode.
  Widget _buildSwitches() {
    final preferences = AppPreferences.instance;
    return Column(
      children: [
        if (RaceAlerts.supported) ...[
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Session reminders'),
            subtitle: const Text(
              '15 minutes before every practice, qualifying and race.',
            ),
            value: preferences.sessionReminders,
            onChanged: (on) =>
                _setAlert(on, preferences.setSessionReminders),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Replay alerts'),
            subtitle: const Text(
              'When a session can be watched on the tracker, about 30 '
              'minutes after it ends. Tap the alert to open the replay.',
            ),
            value: preferences.replayAlerts,
            onChanged: (on) => _setAlert(on, preferences.setReplayAlerts),
          ),
        ] else
          const ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.notifications_off_outlined),
            title: Text('Reminders and replay alerts are in the iPhone app.'),
          ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Data saver'),
          subtitle: const Text(
            'No driver or news photos, saved results reused for 30 minutes, '
            'and replays drawn from lap times instead of GPS, which needs '
            'only a small fraction of the data.',
          ),
          value: preferences.dataSaver,
          onChanged: preferences.setDataSaver,
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Spoiler-free mode'),
          subtitle: const Text(
            'Hides results, standings, news and predictions until you tap '
            'Show. Handy if you watch the race later.',
          ),
          value: preferences.spoilerFree,
          onChanged: preferences.setSpoilerFree,
        ),
      ],
    );
  }
}
