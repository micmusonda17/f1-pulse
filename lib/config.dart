/// Every web address and setting the app uses, kept in one place.
/// If a URL ever changes, this is the only file you need to edit.
class AppConfig {
  /// Calendar, standings and results. Free, no key.
  static const String jolpicaBaseUrl = 'https://api.jolpi.ca/ergast/f1';

  /// Car positions on track. Historical data is free, live data is paid.
  static const String openF1BaseUrl = 'https://api.openf1.org/v1';
  static const String openF1TokenUrl = 'https://api.openf1.org/token';

  /// How much race time one location request covers during a replay.
  static const Duration replayWindow = Duration(seconds: 60);

  /// How far behind "now" the live map draws, so the data has time to arrive.
  static const Duration liveDelay = Duration(seconds: 8);

  /// How often the live map asks OpenF1 for new data.
  static const Duration livePollEvery = Duration(seconds: 5);

  /// Driver photos come from formula1.com. They are fine in the app on your
  /// own phone, but they are not ours to put on a public website, so the
  /// web version is built with --dart-define=SHOW_PHOTOS=false.
  static const bool showDriverPhotos =
      bool.fromEnvironment('SHOW_PHOTOS', defaultValue: true);

  /// Where GitHub saves a copy of every news feed, every 30 minutes
  /// (bin/fetch_news.dart). The website reads the news from here, and the
  /// phone app falls back to it if a news site is down.
  static const String newsMirrorUrl =
      'https://micmusonda17.github.io/f1-pulse/news';
}

/// A news website that publishes an RSS feed.
class NewsSource {
  const NewsSource(this.id, this.name, this.url);

  final String id; // Short name for the saved copy: news/racefans.xml
  final String name;
  final String url;
}

const List<NewsSource> newsSources = [
  NewsSource('racefans', 'RaceFans', 'https://www.racefans.net/feed/'),
  NewsSource(
    'formula1',
    'Formula1.com',
    'https://www.formula1.com/content/fom-website/en/latest/all.xml',
  ),
  NewsSource(
    'autosport',
    'Autosport',
    'https://www.autosport.com/rss/f1/news/',
  ),
];
