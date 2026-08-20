import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:articles/models/models.dart';
import 'package:articles/services/database_service.dart';

void main() {
  late DatabaseService dbService;
  late Database ffiDb;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Arrange: Create in-memory isolated database for test run
    ffiDb = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await ffiDb.execute('''
      CREATE TABLE feeds (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        url TEXT NOT NULL UNIQUE,
        site_url TEXT,
        description TEXT,
        last_updated INTEGER NOT NULL,
        category TEXT NOT NULL DEFAULT 'General',
        is_active INTEGER NOT NULL DEFAULT 1,
        error_message TEXT
      );
    ''');
    await ffiDb.execute('''
      CREATE TABLE articles (
        id TEXT PRIMARY KEY,
        feed_id TEXT NOT NULL,
        feed_title TEXT NOT NULL,
        title TEXT NOT NULL,
        link TEXT NOT NULL,
        author TEXT,
        published_date INTEGER NOT NULL,
        summary TEXT,
        content TEXT,
        image_url TEXT,
        is_read INTEGER NOT NULL DEFAULT 0,
        is_bookmarked INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY (feed_id) REFERENCES feeds (id) ON DELETE CASCADE
      );
    ''');

    dbService = await DatabaseService.init(customDatabase: ffiDb);
  });

  tearDown(() async {
    await dbService.close();
  });

  group('DatabaseService - Feed Operations', () {
    test('inserts and retrieves feeds accurately', () async {
      // Arrange
      final feed = Feed(
        id: 'feed_1',
        title: 'BBC World News',
        url: 'https://feeds.bbci.co.uk/news/world/rss.xml',
        siteUrl: 'https://www.bbc.com/news',
        description: 'World News from BBC',
        lastUpdated: DateTime.utc(2026, 8, 20, 12, 0),
        category: 'News',
      );

      // Act
      await dbService.insertFeed(feed);
      final feeds = await dbService.getAllFeeds();

      // Assert
      expect(feeds.length, equals(1));
      expect(feeds.first.id, equals('feed_1'));
      expect(feeds.first.title, equals('BBC World News'));
      expect(feeds.first.category, equals('News'));
    });

    test('deleting a feed cascades to associated articles', () async {
      // Arrange
      final feed = Feed(
        id: 'feed_to_delete',
        title: 'Tech Blog',
        url: 'https://tech.example.com/rss',
        lastUpdated: DateTime.now().toUtc(),
      );
      final article = Article(
        id: 'art_1',
        feedId: 'feed_to_delete',
        feedTitle: 'Tech Blog',
        title: 'Post 1',
        link: 'https://tech.example.com/1',
        publishedDate: DateTime.now().toUtc(),
      );

      await dbService.insertFeed(feed);
      await dbService.upsertArticles([article]);

      // Act
      await dbService.deleteFeed('feed_to_delete');
      final feeds = await dbService.getAllFeeds();
      final articles = await dbService.getArticles(feedId: 'feed_to_delete');

      // Assert
      expect(feeds.isEmpty, isTrue);
      expect(articles.isEmpty, isTrue);
    });
  });

  group('DatabaseService - Article Operations & State Preservation', () {
    test('preserves isRead and isBookmarked when upserting refreshed articles', () async {
      // Arrange
      final initialArticle = Article(
        id: 'art_100',
        feedId: 'feed_1',
        feedTitle: 'Chronicle',
        title: 'Initial Title',
        link: 'https://chronicle.example.com/100',
        publishedDate: DateTime.utc(2026, 8, 18),
        isRead: false,
        isBookmarked: false,
      );

      await dbService.upsertArticles([initialArticle]);

      // User marks as read and bookmarked
      await dbService.setArticleReadStatus('art_100', true);
      await dbService.setArticleBookmarkStatus('art_100', true);

      // Feed sync provides updated article content
      final updatedArticle = Article(
        id: 'art_100',
        feedId: 'feed_1',
        feedTitle: 'Chronicle',
        title: 'Updated Headline Title',
        link: 'https://chronicle.example.com/100',
        publishedDate: DateTime.utc(2026, 8, 18),
        isRead: false, // Inbound feed has no knowledge of local state
        isBookmarked: false,
      );

      // Act
      await dbService.upsertArticles([updatedArticle]);
      final retrievedArticles = await dbService.getArticles();

      // Assert
      expect(retrievedArticles.length, equals(1));
      expect(retrievedArticles.first.title, equals('Updated Headline Title'));
      expect(retrievedArticles.first.isRead, isTrue, reason: 'isRead must be preserved');
      expect(retrievedArticles.first.isBookmarked, isTrue, reason: 'isBookmarked must be preserved');
    });

    test('filters articles by unread status correctly', () async {
      // Arrange
      final a1 = Article(
        id: 'a1',
        feedId: 'f1',
        feedTitle: 'F1',
        title: 'Article 1',
        link: 'https://example.com/1',
        publishedDate: DateTime.utc(2026, 8, 19),
        isRead: false,
      );
      final a2 = Article(
        id: 'a2',
        feedId: 'f1',
        feedTitle: 'F1',
        title: 'Article 2',
        link: 'https://example.com/2',
        publishedDate: DateTime.utc(2026, 8, 20),
        isRead: false,
      );

      await dbService.upsertArticles([a1, a2]);
      await dbService.setArticleReadStatus('a1', true);

      // Act
      final unreadArticles = await dbService.getArticles(unreadOnly: true);
      final unreadCount = await dbService.getUnreadCount();

      // Assert
      expect(unreadArticles.length, equals(1));
      expect(unreadArticles.first.id, equals('a2'));
      expect(unreadCount, equals(1));
    });
  });
}

