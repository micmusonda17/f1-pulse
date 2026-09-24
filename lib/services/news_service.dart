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
    final http.Response response;
    try {
      response = await _client
          .get(
            Uri.parse(source.url),
            // Some sites refuse requests that do not look like a browser.
            // Browsers do not let web pages change this header, so we only
            // send it on phones and desktops.
            headers: kIsWeb ? null : {'User-Agent': 'Mozilla/5.0 (F1 Pulse)'},
          )
          .timeout(const Duration(seconds: 15));
    } on Exception {
      // In a browser this is almost always CORS (Chapter 2), not the Wi-Fi.
      throw ApiException(
        kIsWeb
            ? '${source.name} does not let web pages read its feed. '
                'The News tab works on a phone or the simulator.'
            : 'Could not load ${source.name}. Check your internet connection.',
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
