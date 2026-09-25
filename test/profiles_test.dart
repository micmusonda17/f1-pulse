import 'package:flutter_test/flutter_test.dart';
import 'package:pitbeat/models/profile.dart';
import 'package:pitbeat/models/standing.dart';
import 'package:pitbeat/stats/welcome_message.dart';

void main() {
  group('profiles', () {
    test('initials from the first two names', () {
      Profile named(String name) =>
          Profile(id: 'p1', name: name, colourIndex: 0);
      expect(named('Michael Musonda').initials, 'MM');
      expect(named('  thandi ').initials, 'T');
      expect(named('Anna Maria Lopez').initials, 'AM');
      expect(named('').initials, '?');
    });

    test('copyWith changes the name and keeps the rest', () {
      const profile = Profile(id: 'p7', name: 'Mike', colourIndex: 2);
      final renamed = profile.copyWith(name: 'Michael');
      expect(renamed.name, 'Michael');
      expect(renamed.id, 'p7');
      expect(renamed.colourIndex, 2);
    });

    test('saved as text and loaded again', () {
      const profiles = [
        Profile(id: 'p1', name: 'Michael', colourIndex: 0),
        Profile(id: 'p2', name: 'Thandi', colourIndex: 3),
      ];
      final loaded = decodeProfiles(encodeProfiles(profiles));
      expect(loaded.map((profile) => profile.name).toList(),
          ['Michael', 'Thandi']);
      expect(loaded.last.id, 'p2');
      expect(loaded.last.colourIndex, 3);
    });

    test('missing or damaged text gives no profiles', () {
      expect(decodeProfiles(null), isEmpty);
      expect(decodeProfiles(''), isEmpty);
      expect(decodeProfiles('not json'), isEmpty);
      expect(decodeProfiles('{"id": "p1"}'), isEmpty); // Not a list
    });
  });

  group('the welcome message', () {
    final now = DateTime(2026, 9, 25, 9); // A Friday morning

    const leader = DriverStanding(
      position: 1,
      points: 267,
      wins: 7,
      driver: Driver(
        id: 'antonelli',
        code: 'ANT',
        number: '12',
        firstName: 'Andrea Kimi',
        lastName: 'Antonelli',
        nationality: 'Italian',
      ),
      team: 'Mercedes',
    );
    const ferrari = ConstructorStanding(
      position: 3,
      points: 300,
      wins: 2,
      name: 'Ferrari',
      nationality: 'Italian',
    );

    test('inWords', () {
      expect(inWords(const Duration(seconds: 30)), 'now');
      expect(inWords(const Duration(minutes: 1)), 'in 1 minute');
      expect(inWords(const Duration(minutes: 45)), 'in 45 minutes');
      expect(inWords(const Duration(hours: 5, minutes: 50)), 'in 5 hours');
      expect(inWords(const Duration(days: 2, hours: 3)), 'in 2 days');
    });

    test('hello by first name, and the next session', () {
      final lines = welcomeLines(
        name: 'Michael Musonda',
        now: now,
        nextSession: 'Qualifying',
        nextSessionStart: now.add(const Duration(hours: 3)),
        raceName: 'Azerbaijan Grand Prix',
      );
      expect(lines, [
        'Good morning, Michael. Welcome back.',
        'Qualifying at the Azerbaijan Grand Prix starts in 3 hours.',
      ]);
    });

    test('a session that has started is on now', () {
      final lines = welcomeLines(
        name: 'Thandi',
        now: now,
        nextSession: 'Race',
        nextSessionStart: now.subtract(const Duration(minutes: 10)),
      );
      expect(lines[1], 'Race is on now.');
    });

    test('favourites and fantasy points', () {
      final lines = welcomeLines(
        name: 'Thandi',
        now: now,
        favouriteDriver: leader,
        favouriteTeam: ferrari,
        fantasyPoints: 42,
        fantasyRace: 'Italian Grand Prix',
      );
      expect(lines, [
        'Good morning, Thandi. Welcome back.',
        'Antonelli leads the championship with 267 points.',
        'Ferrari are 3rd in the constructors.',
        'Your fantasy team scored 42 points at the Italian Grand Prix.',
      ]);
    });

    test('spoiler-free mode leaves the results out', () {
      final lines = welcomeLines(
        name: 'Thandi',
        now: now,
        favouriteDriver: leader,
        favouriteTeam: ferrari,
        fantasyPoints: 42,
        fantasyRace: 'Italian Grand Prix',
        spoilerFree: true,
      );
      expect(lines, [
        'Good morning, Thandi. Welcome back.',
        'Spoiler-free mode is on, so no results here.',
      ]);
    });
  });
}
