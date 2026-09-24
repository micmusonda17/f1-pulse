import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import '../config.dart';
import '../models/news_item.dart';
import 'api_exception.dart';

/// Downloads and reads RSS news feeds.
class NewsService {
  NewsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<List<NewsItem>> getNews(NewsSource source) async {
    if (kIsWeb) {
      // Browsers block web pages from reading the news sites (CORS,
      // Chapter 2). But a page may always read files from its own
      // address, so the website reads the copy GitHub saves next to it.
      return _download(Uri.base.resolve('news/${source.id}.xml'), source);
    }
    try {
      return await _download(Uri.parse(source.url), source);
    } on ApiException catch (firstError) {
      // The news site is down or refusing us: try the copy on GitHub.
      try {
        return await _download(
          Uri.parse('${AppConfig.newsMirrorUrl}/${source.id}.xml'),
          source,
        );
      } on ApiException {
        throw firstError; // Both failed: explain why the real site did
      }
    }
  }

  Future<List<NewsItem>> _download(Uri url, NewsSource source) async {
    final http.Response response;
    try {
      response = await _client
          .get(
            url,
            // Some sites refuse requests that do not look like a browser.
            // Browsers do not let web pages change this header, so we only
            // send it on phones and desktops.
            headers: kIsWeb ? null : {'User-Agent': 'Mozilla/5.0 (F1 Pulse)'},
          )
          .timeout(const Duration(seconds: 15));
    } on Exception {
      throw ApiException(
        'Could not load ${source.name}. Check your internet connection.',
      );
    }

    if (kIsWeb && response.statusCode == 404) {
      throw ApiException(
        'The ${source.name} news has not been copied to this website yet. '
        'GitHub copies it every 30 minutes.',
      );
    }
    if (response.statusCode != 200) {
      throw ApiException(
        '${source.name} answered with error ${response.statusCode}.',
      );
    }
    return parseFeed(utf8.decode(response.bodyBytes), source.name);
  }
}

/// Turns the text of an RSS feed into a list of NewsItems.
/// It lives outside the class so the tests can use it without the internet.
List<NewsItem> parseFeed(String xmlText, String sourceName) {
  final XmlDocument document;
  try {
    document = XmlDocument.parse(xmlText);
  } on XmlException {
    throw ApiException('$sourceName sent a feed we could not read.');
  }
  return document
      .findAllElements('item')
      .map((item) => NewsItem.fromXml(item, sourceName))
      .toList();
}
