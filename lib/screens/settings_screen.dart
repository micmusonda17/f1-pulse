import 'package:flutter/material.dart';

import '../services/api_exception.dart';
import '../services/openf1_api.dart';
import '../services/settings_store.dart';

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
    final name = await _settings.getName();
    final username = await _settings.getOpenF1Username();
    final password = await _settings.getOpenF1Password();
    if (!mounted) return;
    setState(() {
      _name.text = name ?? '';
      _username.text = username ?? '';
      _password.text = password ?? '';
      _hasLogin = (username ?? '').isNotEmpty;
    });
  }

  Future<void> _saveName() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _show('Type a name first.');
      return;
    }
    await _settings.setName(name);
    if (!mounted) return;
    FocusScope.of(context).unfocus(); // Hides the keyboard
    _show('Saved. Hi $name!');
  }

  Future<void> _showWelcomeAgain() async {
    await _settings.setWelcomeDone(false);
    if (!mounted) return;
    _show('The welcome pages will show next time Pitbeat starts.');
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
          Text('You', style: theme.textTheme.titleMedium),
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
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: _showWelcomeAgain,
              icon: const Icon(Icons.replay),
              label: const Text('Show the welcome pages again'),
            ),
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
            'Car positions: OpenF1.\n'
            'News: the RSS feeds of each website.',
          ),
        ],
      ),
    );
  }
}
