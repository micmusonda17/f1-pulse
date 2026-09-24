// Saves a copy of every news feed in lib/config.dart into one folder.
//
// Browsers do not let a web page read the news sites (CORS),
// but a page may always read files from its own address. So every 30
// minutes, GitHub runs this script and publishes the copies next to the
// website, where the web version of Pitbeat can read them.
//
// Try it yourself from the project folder:
//
//   dart run bin/fetch_news.dart build/news_test

// print() is fine in a terminal script, so we switch that lint off here.
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:pitbeat/config.dart';
import 'package:xml/xml.dart';

Future<void> main(List<String> args) async {
  final folder = Directory(args.isEmpty ? 'build/web/news' : args.first);
  await folder.create(recursive: true);

  var saved = 0;
  for (final source in newsSources) {
    try {
      final response = await http
          .get(
            Uri.parse(source.url),
            headers: {'User-Agent': 'Mozilla/5.0 (Pitbeat news copier)'},
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        print('${source.name}: error ${response.statusCode}, skipped');
        continue;
      }
      final feed = keepHeadlinesOnly(utf8.decode(response.bodyBytes));
      await File('${folder.path}/${source.id}.xml').writeAsString(feed);
      print('${source.name}: saved');
      saved++;
    } on Exception catch (error) {
      // One broken site must not stop the others, or the website.
      print('${source.name}: $error, skipped');
    }
  }
  print('Saved $saved of ${newsSources.length} feeds to ${folder.path}');
}

/// Removes the full articles some feeds include (<content:encoded>).
/// The app only shows headlines, summaries, dates and pictures, with a link
/// to the real article, so that is all we republish.
String keepHeadlinesOnly(String xmlText) {
  final document = XmlDocument.parse(xmlText);
  final fullArticles = document.descendants
      .whereType<XmlElement>()
      .where((element) => element.name.local == 'encoded')
      .toList(); // toList first: we cannot remove while walking the tree
  for (final article in fullArticles) {
    article.parent?.children.remove(article);
  }
  return document.toXmlString();
}
