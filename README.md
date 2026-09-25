# Pitbeat

[![Deploy web version](https://github.com/micmusonda17/pitbeat/actions/workflows/deploy-web.yml/badge.svg)](https://github.com/micmusonda17/pitbeat/actions/workflows/deploy-web.yml)

A Formula 1 companion app for iPhone and the web, built with Flutter. It brings the season calendar, circuit maps, race predictions, championship standings, animated race replays and the latest news together in one place.

**Live demo:** [micmusonda17.github.io/pitbeat](https://micmusonda17.github.io/pitbeat/)

## Features

- **Races:** the full season calendar with a live countdown to the next session in your own time zone, a map of every circuit, weekend schedules and race results with places gained or lost.
- **Predictions:** each driver's chance of winning the next race, worked out from recent form, the championship, last year's result at the same track and qualifying. The top 10 is shown with a percentage and the main reasons for each driver.
- **Standings:** drivers' and constructors' championships in team colours, with your favourite driver pinned to the top and your favourite team highlighted.
- **Fantasy points:** every driver's and team's fantasy score for the season and the latest race weekend, estimated with the official fantasy game's main scoring rules (qualifying, sprint and race places, places gained or lost, fastest laps, retirements and the team qualifying bonus). Pick five drivers and two teams to follow your own total.
- **Race tracker:** replay any session since 2023 (practice, qualifying, sprints and races) on an animated circuit map. Every car moves smoothly around the track, with playback from 1x to 20x and a timeline you can scrub. Races show a lap counter, the running order, each driver's tyre and its age in laps, and pit stops; practice and qualifying show best lap times, gaps, the session clock (or Q1, Q2, Q3), how many laps each driver has done, and who is in the garage or the pit lane. Drivers who are out are greyed out with the reason: knocked out in Q1 or Q2, or retired on a given lap with the cause from the official results or race control. Races show the interval to the car ahead and the gap to the leader. The track status (green, yellow by sector, safety car, virtual safety car, red flag, chequered), the fastest lap so far, laps to go, and the full weather (air and track temperature, humidity, wind speed and direction, rain) sit around the map. Tap any driver for their tyres, every pit stop and what race control said about them. Race control messages (flags, safety cars, penalties) and the track weather appear as they happened. Any finished session can also be opened from its race weekend page. Live sessions can be followed with an OpenF1 sponsor account.
- **3D tracker:** the same replay in 3D, with each circuit's real elevation from the GPS data. Drag to turn, pinch to zoom, let it spin, or follow one driver with a chase camera. Your favourite driver and fantasy picks are ringed.
- **Works during race weekends:** OpenF1's free tier closes to everyone (even for old races) while any session is live. Pitbeat saves every finished session of the season on the phone in the background (on Wi-Fi, about 1 MB each) and plays the saved copy during a lock, with tyres, flags, weather, the story and the strategy. Any race that is not saved, back to 1996, can still be replayed lap by lap from Jolpica's lap times: the running order, gaps, retirements and pit stops.
- **Pit stop strategy:** a chart of every driver's tyres and stops, lap by lap, in the tracker (up to the replay's clock) and after the race, with the stop times and tyre changes for each stop.
- **Race analysis:** after a race, the story of how it was won: the start, lead changes, the podium finishers' pit stops, safety cars, penalties, retirements and the fastest lap, each with its lap. Every lap's sector times with the fastest in purple, and who was quickest on each lap. Practice and qualifying show everyone's best lap with its sectors.
- **News:** headlines from RaceFans, Formula1.com and Autosport, on the phone and on the web.
- **Race weekend alerts:** a reminder 15 minutes before every session, and an alert when each session's replay is ready, about 30 minutes after it ends. Tap the alert to open the replay. Scheduled on the phone itself, with no server.
- **Data saver:** no photos, saved results reused for 30 minutes, and replays drawn from lap times instead of GPS, for a small fraction of the mobile data.
- **Works offline:** the calendar, standings and results are kept on the phone and shown when there is no signal.
- **Spoiler-free mode:** results, standings, news and predictions stay hidden until you tap Show, for fans who watch later.
- **Profiles:** everyone who shares a phone gets their own profile, with a name, favourite driver and team, fantasy team and settings. Switch or sign out from the profile badge. Each person gets a personal welcome: the next session, how their driver and team are doing, and their fantasy score.
- **Betting stats (18+):** an opt-in, per profile, behind an age check. Fair odds from the prediction model and a form guide for every driver (win, podium, points and retirement rates, average finish, teammate head-to-heads). No bookmaker odds, no bets and no links to betting sites, with a responsible gambling note.
- **F1-inspired design:** a dark theme in racing red and carbon black, the Titillium Web typeface, driver photos, team colours and a custom app icon.

## Technical highlights

- **Two APIs, one app.** Calendar, standings and results come from the Jolpica F1 API; car positions, driver photos and team colours come from OpenF1. The two are joined on each driver's three-letter code.
- **Smooth replays from sparse data.** OpenF1 reports each car's position about four times a second. The tracker finds the samples either side of the current moment with a binary search and interpolates between them, so cars glide at full frame rate. The track is drawn with a `CustomPainter`, and playback runs on a `ChangeNotifier` controller that discards responses from outdated requests.
- **Respecting rate limits.** Jolpica and OpenF1 each have one request queue, shared across the whole app, that keeps traffic within their limits. The OpenF1 queue also backs off on HTTP 429.
- **An explainable prediction model.** Each driver is scored from 0 to 1 on four kinds of evidence. The weights rescale when evidence is missing (before qualifying, or at a new circuit), and a softmax turns the scores into chances that add up to 100%. The two factors that contributed most to each score become the "why" shown next to the driver. The model is plain Dart with no network or UI code, so it is unit tested directly.
- **Circuit maps from open data.** Track outlines come from a GeoJSON file of GPS coordinates bundled with the app. Longitudes are scaled by the cosine of the latitude so tracks far from the equator keep their true shape, and a custom painter fits each outline to any size, from a list icon to a full-width map.
- **Lap counter from sparse data.** OpenF1 reports when each driver starts each lap. Sorting every lap start by time and keeping only those that set a new highest lap number gives the race's own lap timeline, so the counter stays right through overtakes and pit stops. In practice and qualifying the same lap data gives each driver's best time so far, and the session's fastest lap draws the track outline.
- **News that works in the browser.** Browsers block web pages from reading RSS feeds on other sites (CORS). A scheduled GitHub Actions job copies the feeds next to the website every 30 minutes, so the web version reads them from its own origin. The mobile app reads the feeds directly and falls back to the same copies if a source is down.
- **Graceful failure.** When OpenF1 locks out non-sponsors during a live session, the app detects the session from the race calendar and explains what is happening instead of showing a generic network error.
- **Replays on a data budget.** With data saver on, a replay downloads one lap of GPS points for the track outline and every driver's lap times, instead of about four positions a second for every car. Each car is placed along the outline by how far through its lap it is: the reference lap's points were recorded at a steady rate, so the fraction of lap time maps to the right point, corners included.
- **Profiles without a server.** Profiles live on the phone behind a `ChangeNotifier`. Personal settings are saved under keys that end in the profile's id, and the home screen is keyed by profile, so switching rebuilds every tab with that person's data. Settings from before profiles existed are moved into the first profile on upgrade.
- **Season statistics from paged data.** Fantasy points and the form guide need every result of the season, which Jolpica serves 100 rows at a time. The client pages through by offset, merges races split across pages, and keeps the season for 15 minutes so both features share one download.
- **3D without a 3D engine.** OpenF1's location data includes height. The 3D view projects every point through a small camera model (yaw, pitch, perspective divide) and draws with a normal `CustomPainter`: the track in depth order, shaded by height, over its ground shadow. It repaints every frame from an interpolated clock, so cars and camera move smoothly between the controller's ten updates a second.
- **Replays that survive a lockout.** A small archive service downloads each finished session's OpenF1 rows (laps, positions, stints, pit stops, race control, weather, drivers and one GPS lap for the outline), gzips them and keeps them in app storage, pacing requests under the free tier's limit and pausing while a replay is open. The tracker and analysis fall back to these copies whenever OpenF1 fails. For races without a copy, Jolpica's per-lap timings are rebuilt into OpenF1-shaped laps and position updates (each lap starting when the previous one ended), so the existing timing, gap, retirement and strategy code runs unchanged.
- **Race state from the message feed.** Track status is worked out by replaying race control messages up to the clock (sector yellows, safety car, virtual safety car, red flag, green). Retirements are detected from lap data (no new lap for a lap longer than the driver's median, while others keep lapping, ignoring cars that took the flag) and explained with Jolpica's result status or the race control message about the car. Gaps are measured at the timing line from lap start times.
- **A race story from raw timing data.** The post-race analysis is built entirely from OpenF1 positions, laps, stints, pit stops and race control messages: lead changes are filtered for timing flicker, pit stops are matched to the tyres fitted, and retirements are found with the 90% classification rule. Each moment is tagged with its lap.
- **Offline-first data.** Every Jolpica answer is saved on the phone behind a small `ResponseCache` interface, so the API layer stays free of Flutter and still runs as a plain Dart script. A failed download falls back to the saved copy.
- **Local notifications.** Session reminders and replay alerts are planned from the calendar with `flutter_local_notifications`, as absolute UTC times, and refreshed every time the app opens (iOS keeps at most 64 pending).
- **Continuous deployment.** Every push to `main` runs the test suite and, if it passes, builds and publishes the web version to GitHub Pages.
- **Build-time configuration.** The public web build uses `--dart-define=SHOW_PHOTOS=false` to leave out driver photos, which are licensed by Formula 1.

## Tech stack

| Area | Tools |
|---|---|
| App | Flutter, Dart |
| Packages | `http`, `xml`, `shared_preferences`, `url_launcher`, `flutter_local_notifications`, `timezone`, `path_provider`, `connectivity_plus` |
| Data | [Jolpica F1 API](https://github.com/jolpica/jolpica-f1), [OpenF1](https://openf1.org), RSS |
| CI/CD | GitHub Actions, GitHub Pages |
| Platforms | iOS and web (Android and macOS projects are included but not yet tested) |

## Getting started

You need the [Flutter SDK](https://docs.flutter.dev/get-started/install) and, for iOS, Xcode.

```bash
git clone https://github.com/micmusonda17/pitbeat.git
cd pitbeat
flutter pub get
flutter run -d chrome        # or pick an iPhone simulator or device
```

On a Mac, `bash tool/run_iphone.sh` checks Xcode, installs the iOS platform if it is missing, and launches the app on an iPhone simulator.

## Testing

```bash
flutter analyze
flutter test
```

Unit and widget tests cover the JSON, XML and GeoJSON parsing, the prediction model, the tracker, lap-counter and data-saver maths, tyres, pit stops, race control and weather, qualifying knockouts, tyre age and sector times, retirements, track status, gaps, strategy, the 3D camera maths, saved replays and lap-by-lap timing from Jolpica, fantasy scoring, the form guide, season paging, the race story, profiles and the welcome message, alert planning, saved copies when offline, spoiler-free mode, the news fallback, the live-session check, the onboarding name step and the shared widgets. A test also checks that every circuit in the calendar has a map. The same tests run on every push before the website is deployed.

## Project structure

```
lib/
  main.dart            App entry point, start-up routing and bottom navigation
  config.dart          API endpoints, news sources and build-time settings
  theme.dart           Colours, typography and component themes
  models/              Data classes built from JSON, XML and GeoJSON
  services/            One class per data source, plus local settings
  predictions/         The prediction model and the data it needs
  stats/               Fantasy points, form guide, race story and welcome message
  tracker/             Replay controller, interpolation maths and track painter
  screens/             One file per screen, including onboarding and profiles
  widgets/             Shared UI components
  utils/               Date, time and number formatting
assets/
  circuits/            Circuit outlines (GeoJSON) and their licence
  fonts/               Titillium Web
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
| Session reminders, replay alerts | Settings (iPhone app) | Off |
| Data saver, spoiler-free mode | Settings | Off |
| Betting stats | Settings, per profile, 18+ only | Off |
| Save past sessions (offline replays, Wi-Fi only) | Settings (iPhone app) | On |
| News sources | `newsSources` in `lib/config.dart` | RaceFans, Formula1.com, Autosport |

## Acknowledgements

- [Jolpica F1 API](https://github.com/jolpica/jolpica-f1) for calendar, standings and results.
- [OpenF1](https://openf1.org) for car positions, laps, tyres, pit stops, race control, weather, driver photos and team colours.
- [f1-circuits](https://github.com/bacinger/f1-circuits) by Tomislav Bacinger for the circuit outlines, used under the MIT License.
- RaceFans, Formula1.com and Autosport for their RSS feeds. The app shows headlines and summaries only, and every story links back to the original article.
- [Titillium Web](https://fonts.google.com/specimen/Titillium+Web), used under the SIL Open Font License.

## Disclaimer

Pitbeat is an unofficial, non-commercial personal project. It is not associated in any way with the Formula 1 companies. F1, FORMULA ONE, FORMULA 1, FIA FORMULA ONE WORLD CHAMPIONSHIP, GRAND PRIX and related marks are trade marks of Formula One Licensing B.V.

## Author

Built by Michael Musonda ([@micmusonda17](https://github.com/micmusonda17)).
