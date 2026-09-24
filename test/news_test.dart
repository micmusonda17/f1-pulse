import 'dart:convert';

import 'package:f1_pulse/config.dart';
import 'package:f1_pulse/models/news_item.dart';
import 'package:f1_pulse/services/news_service.dart';
import 'package:f1_pulse/utils/formatting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

// A cut-down copy of a real RSS feed.
const sampleFeed = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0">
  <channel>
    <title>Autosport F1</title>
    <item>
      <title><![CDATA[F1 reports 35% CO2 reduction ahead of 2030 targets]]></title>
      <link>https://www.autosport.com/f1/news/example/10830967/</link>
      <description><![CDATA[Formula 1 says it cut emissions by 12% in 2025.<br>More text here ...<a class='more' href='https://example.com'>Keep reading</a>]]></description>
      <guid isPermaLink="false">10830967</guid>
      <pubDate>Wed, 17 Jun 2026 09:06:39 +0000</pubDate>
      <enclosure url="https://cdn.example.com/paddock.jpg" type="image/jpeg" length="473162"/>
    </item>
    <item>
      <title>No picture and no date</title>
      <link>https://www.example.com/story</link>
      <description>Short &amp; simple.</description>
    </item>
  </channel>
</rss>
''';

void main() {
  group('parseRssDate', () {
    test('reads a UTC date', () {
      expect(
        parseRssDate('Wed, 23 Sep 2026 11:27:50 +0000'),
        DateTime.utc(2026, 9, 23, 11, 27, 50),
      );
    });

    test('moves a +0200 date back to UTC', () {
      expect(
        parseRssDate('Wed, 23 Sep 2026 13:27:50 +0200'),
        DateTime.utc(2026, 9, 23, 11, 27, 50),
      );
    });

    test('returns null for text that is not a date', () {
      expect(parseRssDate('not a date'), isNull);
      expect(parseRssDate('Wed, 23 Foo 2026 11:27:50 +0000'), isNull);
      expect(parseRssDate(null), isNull);
    });
  });

  group('NewsService', () {
    test('falls back to the copy on GitHub when a news site is down',
        () async {
      // A pretend internet: the news site fails, the GitHub copy works.
      final client = MockClient((request) async {
        if (request.url.toString().startsWith(AppConfig.newsMirrorUrl)) {
          return http.Response.bytes(utf8.encode(sampleFeed), 200);
        }
        return http.Response('Down for maintenance', 503);
      });

      final items = await NewsService(client: client).getNews(newsSources[2]);
      expect(items.length, 2);
    });
  });

  group('parseFeed', () {
    final items = parseFeed(sampleFeed, 'Autosport');

    test('finds every item', () {
      expect(items.length, 2);
    });

    test('reads the title, link, date and picture', () {
      final first = items.first;
      expect(first.title, 'F1 reports 35% CO2 reduction ahead of 2030 targets');
      expect(first.link, 'https://www.autosport.com/f1/news/example/10830967/');
      expect(first.published, DateTime.utc(2026, 6, 17, 9, 6, 39));
      expect(first.imageUrl, 'https://cdn.example.com/paddock.jpg');
      expect(first.source, 'Autosport');
    });

    test('strips the HTML out of the summary', () {
      expect(
        items.first.summary,
        'Formula 1 says it cut emissions by 12% in 2025. More text here ...',
      );
    });

    test('copes with missing picture and date', () {
      final second = items[1];
      expect(second.imageUrl, isNull);
      expect(second.published, isNull);
      expect(second.summary, 'Short & simple.');
    });
  });

  test('cleanHtml removes tags and codes', () {
    expect(cleanHtml('<p>Pit&nbsp;stop &amp; tyres</p>'), 'Pit stop & tyres');
  });

  test('formatTimeAgo', () {
    final now = DateTime.utc(2026, 9, 23, 12);
    expect(formatTimeAgo(now, now: now), 'just now');
    expect(
      formatTimeAgo(now.subtract(const Duration(minutes: 5)), now: now),
      '5 min ago',
    );
    expect(
      formatTimeAgo(now.subtract(const Duration(hours: 3)), now: now),
      '3 h ago',
    );
    expect(
      formatTimeAgo(now.subtract(const Duration(days: 4)), now: now),
      '4 days ago',
    );
  });
}
