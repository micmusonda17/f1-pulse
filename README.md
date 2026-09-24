# F1 Pulse

A Formula 1 companion app built with Flutter, as a learning project.

## What it does

- **Races:** the season calendar, a live countdown to the next session in your own time zone, weekend schedules and race results.
- **Standings:** drivers' and constructors' championships, with a favourite driver pinned to the top.
- **Tracker:** a map of the circuit with every car moving round it. Replay any race from 2023 onwards for free, or follow a session live with an OpenF1 sponsor login.
- **News:** headlines from RaceFans, Formula1.com and Autosport.

It uses an F1-style dark theme (Titillium Web font, red accents), driver photos and team colours from OpenF1, and its own app icon. The driver photos belong to Formula 1, so they are for personal use only: do not publish the app with them.

## Running it

First time on a new Mac? `bash tool/setup_and_check.sh` installs Flutter if needed, sets up the project, runs every check and serves the web version on http://localhost:8765.

On the iPhone simulator: `bash tool/run_iphone.sh` checks Xcode, downloads the iOS platform if it is missing, builds the app and runs it on an iPhone.

On the web: `bash tool/publish_web.sh` puts the project on GitHub and switches on GitHub Pages. After that, every `git push` rebuilds the website automatically (`.github/workflows/deploy-web.yml`). The public website is built with `--dart-define=SHOW_PHOTOS=false`, so it shows driver codes instead of photos.

```bash
flutter pub get
flutter run            # pick a device from the list
flutter test           # run the unit and widget tests
flutter analyze        # check the code for problems
dart run bin/try_api.dart   # print the calendar and standings in the terminal
```

## How the code is organised

```
lib/
  main.dart              app start, theme, bottom navigation
  config.dart            every URL and setting in one place
  models/                classes that turn JSON and XML into Dart objects
  services/              one class per data source (Jolpica, OpenF1, RSS, settings)
  tracker/               the race map: controller, maths and painter
  screens/               one file per screen
  widgets/               small reusable pieces (countdown, loading, errors)
  utils/formatting.dart  dates, times and points
test/                    tests for the models, news parsing, tracker maths and widgets
bin/try_api.dart         a terminal playground for the data layer
tool/setup_and_check.sh  one-command setup and checks
```

## Data sources

- [Jolpica F1 API](https://github.com/jolpica/jolpica-f1): calendar, standings, results. Free, no key.
- [OpenF1](https://openf1.org): car locations and positions. Historical data is free; live data needs a paid sponsor account.
- RSS feeds from each news site.

F1 Pulse is a personal learning project and is not connected to Formula 1 or any team.

## The study guide

`F1_Pulse_Build_Bible.pdf` in this folder walks through building the whole app step by step.
