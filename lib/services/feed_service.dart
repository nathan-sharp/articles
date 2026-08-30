import 'dart:async';
import 'package:http/http.dart' as http;
import '../models/models.dart';
import 'database_service.dart';
import 'edition_service.dart';
import 'feed_parser.dart';
import 'security_validator.dart';

/// Starter feed descriptor for onboarding.
class StarterFeed {
  final String title;
  final String url;
  final String category;
  final String description;

  const StarterFeed({
    required this.title,
    required this.url,
    required this.category,
    required this.description,
  });
}

/// Service managing remote feed retrieval, background synchronization, and starter collections.
class FeedService {
  final DatabaseService _dbService;
  final EditionService? _editionService;
  final http.Client _httpClient;

  /// Curated collection of standard, reliable open feeds.
  static const List<StarterFeed> starterFeeds = [
    StarterFeed(
      title: 'BBC World News',
      url: 'https://feeds.bbci.co.uk/news/world/rss.xml',
      category: 'World News',
      description: 'International headlines and analysis from BBC.',
    ),
    StarterFeed(
      title: 'Hacker News',
      url: 'https://news.ycombinator.com/rss',
      category: 'Technology',
      description: 'Computer science, startups, and technology discussions.',
    ),
    StarterFeed(
      title: 'Ars Technica',
      url: 'https://feeds.arstechnica.com/arstechnica/index',
      category: 'Technology',
      description: 'Original technology journalism, science, and policy.',
    ),
    StarterFeed(
      title: 'NASA News Releases',
      url: 'https://www.nasa.gov/news-release/feed/',
      category: 'Science',
      description: 'Aeronautics, space exploration, and scientific discoveries.',
    ),
    StarterFeed(
      title: 'Electronic Frontier Foundation',
      url: 'https://www.eff.org/rss/updates.xml',
      category: 'Digital Rights',
      description: 'Defending privacy, free expression, and innovation.',
    ),
  ];

  FeedService({
    required DatabaseService dbService,
    EditionService? editionService,
    http.Client? httpClient,
  })  : _dbService = dbService,
        _editionService = editionService,
        _httpClient = httpClient ?? http.Client();

  /// Adds a new feed by URL, fetches its metadata and initial articles, and saves to database.
  Future<Feed> subscribeToFeed({
    required String url,
    String? customTitle,
    String category = 'General',
  }) async {
    final trimmedUrl = url.trim();

    if (!SecurityValidator.isValidFeedUrl(trimmedUrl)) {
      throw const FormatException('Invalid or disallowed feed URL scheme/host');
    }

    // Check if feed already exists
    final existing = await _dbService.getFeedByUrl(trimmedUrl);
    if (existing != null) {
      return existing;
    }

    // Fetch and parse remote XML
    final xmlContent = await _fetchFeedXml(trimmedUrl);
    final parsed = FeedParser.parseXml(
      xmlContent: xmlContent,
      feedUrl: trimmedUrl,
    );

    final finalFeed = parsed.feed.copyWith(
      title: (customTitle != null && customTitle.trim().isNotEmpty)
          ? customTitle.trim()
          : parsed.feed.title,
      category: category,
    );

    await _dbService.insertFeed(finalFeed);
    await _dbService.upsertArticles(parsed.articles);

    return finalFeed;
  }

  /// Syncs an individual feed and stores updated articles.
  Future<int> refreshFeed(Feed feed) async {
    try {
      final xmlContent = await _fetchFeedXml(feed.url);
      final parsed = FeedParser.parseXml(
        xmlContent: xmlContent,
        feedUrl: feed.url,
        fallbackFeedId: feed.id,
      );

      final updatedFeed = parsed.feed.copyWith(
        id: feed.id,
        title: feed.title.isNotEmpty ? feed.title : parsed.feed.title,
        category: feed.category,
        lastUpdated: DateTime.now().toUtc(),
        errorMessage: null,
      );

      await _dbService.updateFeed(updatedFeed);
      final newCount = await _dbService.upsertArticles(parsed.articles);
      return newCount;
    } catch (e) {
      // Record error on feed record without failing globally
      final errorFeed = feed.copyWith(
        errorMessage: e.toString(),
        lastUpdated: DateTime.now().toUtc(),
      );
      await _dbService.updateFeed(errorFeed);
      return 0;
    }
  }

  /// Refreshes all active feeds concurrently with bounded timeouts.
  Future<int> refreshAllFeeds() async {
    final feeds = await _dbService.getAllFeeds();
    if (feeds.isEmpty) {
      return 0;
    }

    var totalNewArticles = 0;
    final futures = feeds.where((f) => f.isActive).map((feed) async {
      final newCount = await refreshFeed(feed);
      totalNewArticles += newCount;
    });

    await Future.wait(futures);

    // Precompute on-device editorial editions in background worker isolates
    if (_editionService != null) {
      unawaited(_editionService.precomputeStaleEditions());
    }

    return totalNewArticles;
  }

  /// Populates the database with the curated starter feeds collection.
  Future<int> loadStarterFeeds() async {
    var loadedCount = 0;
    for (final starter in starterFeeds) {
      try {
        await subscribeToFeed(
          url: starter.url,
          customTitle: starter.title,
          category: starter.category,
        );
        loadedCount++;
      } catch (_) {
        // Individual starter feed failure is skipped safely
      }
    }

    // Trigger on-device edition synthesis for newly ingested starter articles
    if (_editionService != null) {
      unawaited(_editionService.precomputeStaleEditions());
    }

    return loadedCount;
  }

  /// Performs network GET request with strict 10.0-second timeout.
  Future<String> _fetchFeedXml(String url) async {
    final response = await _httpClient
        .get(
          Uri.parse(url),
          headers: {
            'User-Agent': 'Articles/1.0 (Open-Source Minimalist Newspaper RSS Reader)',
            'Accept': 'application/rss+xml, application/atom+xml, application/xml, text/xml, */*',
          },
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('HTTP Request Failed with status code: ${response.statusCode}');
    }

    return response.body;
  }

  /// Disposes underlying HTTP client.
  void dispose() {
    _httpClient.close();
  }
}

/// Simple exception representing HTTP transfer errors.
class HttpException implements Exception {
  final String message;
  const HttpException(this.message);

  @override
  String toString() => 'HttpException: $message';
}

