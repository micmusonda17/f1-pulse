import 'package:xml/xml.dart';

import '../utils/formatting.dart';

/// One news article from an RSS feed.
class NewsItem {
  const NewsItem({
    required this.title,
    required this.link,
    required this.summary,
    required this.source,
    this.published,
    this.imageUrl,
  });

  final String title;
  final String link;
  final String summary;
  final String source; // Which website it came from
  final DateTime? published; // Some feeds leave this out
  final String? imageUrl; // Some feeds have no pictures

  /// Builds a NewsItem from one `<item>` in an RSS feed.
  /// This is the XML version of the fromJson factories in the other models.
  factory NewsItem.fromXml(XmlElement item, String source) {
    // A tiny function inside a function: read the text inside one tag.
    String read(String tag) => item.getElement(tag)?.innerText.trim() ?? '';

    return NewsItem(
      title: cleanHtml(read('title')),
      link: read('link'),
      summary: cleanHtml(read('description')),
      source: source,
      published: parseRssDate(read('pubDate')),
      imageUrl: item.getElement('enclosure')?.getAttribute('url'),
    );
  }
}

/// Feeds put HTML inside their text. This removes the tags and turns the
/// most common codes (like &amp;) back into normal characters.
String cleanHtml(String text) {
  var clean = text.replaceAll(RegExp(r'<[^>]*>'), ' ');
  const codes = {
    '&amp;': '&',
    '&quot;': '"',
    '&#39;': "'",
    '&#039;': "'",
    '&#8216;': "'",
    '&#8217;': "'",
    '&#8220;': '"',
    '&#8221;': '"',
    '&#8211;': '-',
    '&#8212;': ' - ',
    '&#8230;': '...',
    '&hellip;': '...',
    '&nbsp;': ' ',
  };
  for (final entry in codes.entries) {
    clean = clean.replaceAll(entry.key, entry.value);
  }
  clean = clean.replaceAll('Keep reading', '');
  return clean.replaceAll(RegExp(r'\s+'), ' ').trim();
}
