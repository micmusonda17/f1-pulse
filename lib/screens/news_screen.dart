import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../models/news_item.dart';
import '../services/news_service.dart';
import '../utils/formatting.dart';
import '../widgets/common_widgets.dart';

/// The fourth tab: headlines from RSS feeds.
class NewsScreen extends StatefulWidget {
  const NewsScreen({super.key});

  @override
  State<NewsScreen> createState() => _NewsScreenState();
}

class _NewsScreenState extends State<NewsScreen> {
  final NewsService _service = NewsService();
  int _sourceIndex = 0;
  late Future<List<NewsItem>> _news;

  @override
  void initState() {
    super.initState();
    _news = _service.getNews(newsSources[_sourceIndex]);
  }

  void _pickSource(int index) {
    setState(() {
      _sourceIndex = index;
      _news = _service.getNews(newsSources[index]);
    });
  }

  Future<void> _refresh() async {
    setState(() {
      _news = _service.getNews(newsSources[_sourceIndex]);
    });
    try {
      await _news;
    } catch (_) {
      // The FutureBuilder shows the error.
    }
  }

  /// Opens the full article in the phone's browser.
  Future<void> _open(NewsItem item) async {
    final url = Uri.tryParse(item.link);
    var opened = false;
    if (url != null) {
      try {
        opened = await launchUrl(url, mode: LaunchMode.externalApplication);
      } catch (_) {
        opened = false; // Handled just below
      }
    }
    if (!mounted) return; // We waited, so check the screen is still there
    if (!opened) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open that article.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('News')),
      body: Column(
        children: [
          // A row of chips to pick the website.
          SizedBox(
            height: 56,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                for (var i = 0; i < newsSources.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Center(
                      child: ChoiceChip(
                        label: Text(newsSources[i].name),
                        selected: i == _sourceIndex,
                        onSelected: (_) => _pickSource(i),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: FutureBuilder<List<NewsItem>>(
              future: _news,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const LoadingView(message: 'Loading headlines');
                }
                if (snapshot.hasError) {
                  return ErrorView(
                    message: '${snapshot.error}',
                    onRetry: _refresh,
                  );
                }
                final news = snapshot.data ?? [];
                if (news.isEmpty) {
                  return const Center(child: Text('No stories right now.'));
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView.builder(
                    itemCount: news.length,
                    itemBuilder: (context, index) => NewsCard(
                      item: news[index],
                      onTap: () => _open(news[index]),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// One story: picture (if there is one), headline, summary, source and age.
class NewsCard extends StatelessWidget {
  const NewsCard({super.key, required this.item, required this.onTap});

  final NewsItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final published = item.published;
    final image = item.imageUrl;
    final byline = published == null
        ? item.source
        : '${item.source}  ·  ${formatTimeAgo(published)}';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (image != null)
              Image.network(
                image,
                height: 180,
                width: double.infinity,
                fit: BoxFit.cover,
                // If the picture fails to load, just leave it out.
                errorBuilder: (context, error, stackTrace) =>
                    const SizedBox.shrink(),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    item.summary,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(byline, style: theme.textTheme.labelSmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
