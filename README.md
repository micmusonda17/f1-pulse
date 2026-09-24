# F1 Pulse

[![Deploy web version](https://github.com/micmusonda17/f1-pulse/actions/workflows/deploy-web.yml/badge.svg)](https://github.com/micmusonda17/f1-pulse/actions/workflows/deploy-web.yml)

A Formula 1 companion app for iPhone and the web, built with Flutter. It brings the season calendar, championship standings, animated race replays and the latest news together in one place.

**Live demo:** [micmusonda17.github.io/f1-pulse](https://micmusonda17.github.io/f1-pulse/)

## Features

- **Races:** the full season calendar with a live countdown to the next session in your own time zone, weekend schedules and race results with places gained or lost.
- **Standings:** drivers' and constructors' championships in team colours, with your favourite driver pinned to the top and your favourite team highlighted.
- **Race tracker:** replay any race or sprint since 2023 on an animated circuit map. Every car moves smoothly around the track, with a live running order, playback from 1x to 20x and a timeline you can scrub. Live sessions can be followed with an OpenF1 sponsor account.
- **News:** headlines from RaceFans, Formula1.com and Autosport, on the phone and on the web.
- **Personal setup:** a short onboarding flow for your name, driver and team, and a greeting on the home screen.
- **F1-inspired design:** a dark theme in racing red and carbon black, the Titillium Web typeface, driver photos, team colours and a custom app icon.

## Technical highlights

- **Two APIs, one app.** Calendar, standings and results come from the Jolpica F1 API; car positions, driver photos and team colours come from OpenF1. The two are joined on each driver's three-letter code.
- **Smooth replays from sparse data.** OpenF1 reports each car's position about four times a second. The tracker finds the samples either side of the current moment with a binary search and interpolates between them, so cars glide at full frame rate. The track is drawn with a `CustomPainter`, and playback runs on a `ChangeNotifier` controller that discards responses from outdated requests.
- **Respecting rate limits.** All OpenF1 traffic goes through a single request queue that stays within the free tier's limits and backs off on HTTP 429.
- **News that works in the browser.** Browsers block web pages from reading RSS feeds on other sites (CORS). A scheduled GitHub Actions job copies the feeds next to the website every 30 minutes, so the web version reads them from its own origin. The mobile app reads the feeds directly and falls back to the same copies if a source is down.
- **Graceful failure.** When OpenF1 locks out non-sponsors during a live session, the app detects the session from the race calendar and explains what is happening instead of showing a generic network error.
- **Continuous deployment.** Every push to `main` runs the test suite and, if it passes, builds and publishes the web version to GitHub Pages.
- **Build-time configuration.** The public web build uses `--dart-define=SHOW_PHOTOS=false` to leave out driver photos, which are licensed by Formula 1.

## Tech stack

| Area | Tools |
|---|---|
| App | Flutter, Dart |
| Packages | `http`, `xml`, `shared_preferences`, `url_launcher` |
| Data | [Jolpica F1 API](https://github.com/jolpica/jolpica-f1), [OpenF1](https://openf1.org), RSS |
| CI/CD | GitHub Actions, GitHub Pages |
| Platforms | iOS and web (Android and macOS projects are included but not yet tested) |

## Getting started

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) and, for iOS, Xcode.

```bash
git clone https://github.com/micmusonda17/f1-pulse.git
cd f1-pulse
flutter pub get
flutter run -d chrome        # or pick an iPhone simulator or device
```

On a Mac, `bash tool/run_iphone.sh` checks Xcode, installs the iOS platform if it is missing, and launches the app on an iPhone simulator.

## Testing

```bash
flutter analyze
flutter test
```

Unit and widget tests cover the JSON and XML parsing, the tracker maths, the news fallback, the live-session check, the onboarding name step and the shared widgets. The same tests run on every push before the website is deployed.

## Project structure

```
lib/
  main.dart            App entry point, start-up routing and bottom navigation
  config.dart          API endpoints, news sources and build-time settings
  theme.dart           Colours, typography and component themes
  models/              Data classes built from JSON and XML
  services/            One class per data source, plus local settings
  tracker/             Replay controller, interpolation maths and track painter
  screens/             One file per screen, including onboarding
  widgets/             Shared UI components
  utils/               Date, time and number formatting
test/                  Unit and widget tests
bin/
  fetch_news.dart      Copies the news feeds for the web version
  try_api.dart         Command-line check of the data layer
tool/
  deploy-web.yml       GitHub Actions workflow (installed to .github/workflows)
  publish_web.sh       One-time GitHub and GitHub Pages setup
  run_iphone.sh        Builds and runs the app on an iPhone simulator
  setup_and_check.sh   Environment setup and full check on a new Mac
  make_icon.py         Generates every app icon size
```

## Configuration

| Setting | Where | Default |
|---|---|---|
| Driver photos | `--dart-define=SHOW_PHOTOS=false` at build time | On |
| Live tracking | OpenF1 sponsor login, entered in the app's Settings | Off |
| News sources | `newsSources` in `lib/config.dart` | RaceFans, Formula1.com, Autosport |

## Acknowledgements

- [Jolpica F1 API](https://github.com/jolpica/jolpica-f1) for calendar, standings and results.
- [OpenF1](https://openf1.org) for car positions, driver photos and team colours.
- RaceFans, Formula1.com and Autosport for their RSS feeds. The app shows headlines and summaries only, and every story links back to the original article.
- [Titillium Web](https://fonts.google.com/specimen/Titillium+Web), used under the SIL Open Font License.

## Disclaimer

F1 Pulse is an unofficial, non-commercial personal project. It is not associated in any way with the Formula 1 companies. F1, FORMULA ONE, FORMULA 1, FIA FORMULA ONE WORLD CHAMPIONSHIP, GRAND PRIX and related marks are trade marks of Formula One Licensing B.V.

## Author

Built by Michael Musonda ([@micmusonda17](https://github.com/micmusonda17)).
