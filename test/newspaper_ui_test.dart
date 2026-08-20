import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:articles/main.dart';
import 'package:articles/models/models.dart';
import 'package:articles/screens/article_screen.dart';
import 'package:articles/services/database_service.dart';
import 'package:articles/services/feed_service.dart';

void main() {
  late DatabaseService dbService;
  late Database ffiDb;
  late FeedService feedService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
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
    feedService = FeedService(dbService: dbService);
  });

  tearDown(() async {
    await dbService.close();
  });

  testWidgets('Renders newspaper masthead and empty state when no subscriptions exist', (tester) async {
    // Arrange & Act
    await tester.pumpWidget(ArticlesApp(feedService: feedService));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // Assert
    expect(find.text('ARTICLES'), findsOneWidget);
    expect(find.text('NO ARTICLES TO DISPLAY'), findsOneWidget);
    expect(find.text('LOAD STARTER FEEDS'), findsOneWidget);
  });

  testWidgets('Renders article headlines and navigates to reader view upon selection', (tester) async {
    // Arrange
    final feed = Feed(
      id: 'f1',
      title: 'The Daily Chronicle',
      url: 'https://chronicle.example.com/rss',
      lastUpdated: DateTime.now().toUtc(),
      category: 'World News',
    );
    final article = Article(
      id: 'art1',
      feedId: 'f1',
      feedTitle: 'The Daily Chronicle',
      title: 'Historic Discovery in Deep Ocean',
      link: 'https://chronicle.example.com/ocean',
      author: 'Captain Nemo',
      publishedDate: DateTime.now().toUtc(),
      summary: 'Oceanographers identify ancient hydrothermal vent system.',
      content: '<p>Complete report regarding deep sea expedition.</p>',
    );

    await dbService.insertFeed(feed);
    await dbService.upsertArticles([article]);

    // Act
    await tester.pumpWidget(ArticlesApp(feedService: feedService));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // Assert Headline
    expect(find.text('Historic Discovery in Deep Ocean'), findsOneWidget);
    expect(find.text('BY CAPTAIN NEMO'), findsOneWidget);

    // Act: Tap article card to enter reader view
    await tester.tap(find.text('Historic Discovery in Deep Ocean'));
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pump();

    // Assert Reader View
    expect(find.byType(ArticleScreen), findsOneWidget);
    expect(find.text('READ FULL STORY AT ORIGINAL SOURCE ↗'), findsOneWidget);
    expect(find.text('Complete report regarding deep sea expedition.'), findsOneWidget);
  });
}

