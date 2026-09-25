import 'package:flutter/material.dart';

import '../models/profile.dart';
import '../services/profile_store.dart';
import '../theme.dart';
import 'welcome_screen.dart';

/// One colour per profile, in the order they were added.
const List<Color> profileColours = [
  F1Colors.red,
  Color(0xFF3671C6), // Blue
  Color(0xFF27F4D2), // Teal
  Color(0xFFFF8000), // Orange
  Color(0xFF229971), // Green
  Color(0xFFB6BABD), // Silver
];

Color profileColour(Profile profile) =>
    profileColours[profile.colourIndex % profileColours.length];

/// "Who's watching?": shown when nobody is signed in. Tap a profile to
/// sign in, or add a new one.
class ProfilePickerScreen extends StatelessWidget {
  const ProfilePickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = ProfileStore.instance;
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Text(
                  "Who's watching?",
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 32),
                // Wrap puts the profiles in rows, as many as fit across.
                ListenableBuilder(
                  listenable: store,
                  builder: (context, _) => Wrap(
                    spacing: 24,
                    runSpacing: 24,
                    alignment: WrapAlignment.center,
                    children: [
                      for (final profile in store.profiles)
                        _ProfileTile(
                          label: profile.name,
                          onTap: () => store.signIn(profile.id),
                          child: ProfileBadge(profile: profile, size: 80),
                        ),
                      _ProfileTile(
                        label: 'Add profile',
                        onTap: () => openAddProfile(context),
                        child: Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: F1Colors.muted, width: 2),
                          ),
                          child: const Icon(Icons.add, size: 36),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ProfileTile extends StatelessWidget {
  const _ProfileTile({
    required this.label,
    required this.onTap,
    required this.child,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        width: 96,
        child: Column(
          children: [
            child,
            const SizedBox(height: 8),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// A profile's initials in a circle of its colour.
class ProfileBadge extends StatelessWidget {
  const ProfileBadge({super.key, required this.profile, this.size = 36});

  final Profile profile;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colour = profileColour(profile);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: colour.withValues(alpha: 0.25),
        border: Border.all(color: colour, width: 2),
      ),
      child: Text(
        profile.initials,
        style: TextStyle(
          fontSize: size * 0.36,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Opens the welcome pages to make another profile. They close themselves
/// when the new profile is signed in, or when you tap the X.
Future<void> openAddProfile(BuildContext context) {
  return Navigator.push(
    context,
    MaterialPageRoute(
      builder: (routeContext) => WelcomeScreen(
        onFinished: () => Navigator.pop(routeContext),
        onCancel: () => Navigator.pop(routeContext),
      ),
    ),
  );
}

/// The sheet behind the profile badge on the Races tab: switch to someone
/// else, add a profile, or sign out.
Future<void> showProfileSwitcher(BuildContext context) {
  final store = ProfileStore.instance;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true, // Only as tall as the rows in it
        children: [
          for (final profile in store.profiles)
            ListTile(
              leading: ProfileBadge(profile: profile),
              title: Text(profile.name),
              trailing: profile.id == store.currentId
                  ? const Icon(Icons.check, color: F1Colors.red)
                  : null,
              onTap: () {
                Navigator.pop(sheetContext);
                store.signIn(profile.id);
              },
            ),
          ListTile(
            leading: const Icon(Icons.person_add_alt),
            title: const Text('Add profile'),
            onTap: () {
              Navigator.pop(sheetContext);
              openAddProfile(context);
            },
          ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Sign out'),
            onTap: () {
              Navigator.pop(sheetContext);
              store.signOut();
            },
          ),
        ],
      ),
    ),
  );
}
