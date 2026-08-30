import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:articles/main.dart';
import 'package:articles/models/models.dart';
import 'package:articles/screens/article_screen.dart';
import 'package:articles/screens/edition_screen.dart';
import 'package:articles/services/database_service.dart';
import 'package:articles/services/edition_service.dart';
import 'package:articles/services/feed_service.dart';
import 'package:articles/services/tts_service.dart';
import 'package:articles/theme/newspaper_theme.dart';

void main() {
  late DatabaseService dbService;
  late Database ffiDb;
  late EditionService editionService;
  late FeedService feedService;
  late http.Client mockClient;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    mockClient = MockClient((request) async => http.Response('', 200));
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
    await ffiDb.execute('''
      CREATE TABLE editorial_editions (
        id TEXT PRIMARY KEY,
        edition_type TEXT NOT NULL,
        title TEXT NOT NULL,
        subtitle TEXT,
        generated_at INTEGER NOT NULL,
        summary TEXT NOT NULL,
        content_html TEXT NOT NULL,
        source_article_ids TEXT NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0
      );
    ''');

    dbService = await DatabaseService.init(customDatabase: ffiDb);
    editionService = EditionService(dbService: dbService);
    feedService = FeedService(
      dbService: dbService,
      editionService: editionService,
      httpClient: mockClient,
    );
  });

  tearDown(() async {
    feedService.dispose();
    await dbService.close();
  });

  testWidgets('Renders newspaper masthead and empty state when no subscriptions exist', (tester) async {
    // Arrange & Act
    await tester.runAsync(() async {
      await tester.pumpWidget(ArticlesApp(
        feedService: feedService,
        editionService: editionService,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    // Assert
    expect(find.text('ARTICLES'), findsOneWidget);
    expect(find.text('NO ARTICLES TO DISPLAY'), findsOneWidget);
    expect(find.text('LOAD STARTER FEEDS'), findsOneWidget);
  });

  testWidgets('Renders article headlines on FeedScreen and navigates to reader view', (tester) async {
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
      content: '<p>Complete report regarding deep sea expedition. ' * 10 + '</p>',
      isRead: true,
    );

    await tester.runAsync(() async {
      await dbService.insertFeed(feed);
      await dbService.upsertArticles([article]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    // Act
    await tester.runAsync(() async {
      await tester.pumpWidget(ArticlesApp(
        feedService: feedService,
        editionService: editionService,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    // Assert Headline
    expect(find.text('Historic Discovery in Deep Ocean'), findsOneWidget);
    expect(find.text('BY CAPTAIN NEMO'), findsOneWidget);

    // Act: Tap article
    await tester.runAsync(() async {
      await tester.tap(find.text('Historic Discovery in Deep Ocean'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Assert Reader View
    expect(find.byType(ArticleScreen), findsOneWidget);
    expect(find.text('READ FULL STORY AT ORIGINAL SOURCE ↗'), findsOneWidget);
    expect(find.textContaining('Complete report regarding deep sea expedition.'), findsOneWidget);
  });

  testWidgets('Side Drawer displays EDITORIAL EDITIONS section with four edition tiles', (tester) async {
    // Arrange
    final morningEdition = EditorialEdition(
      id: 'edition_morning_20260830',
      type: EditionType.morning,
      title: 'MORNING BRIEFING: TEST',
      generatedAt: DateTime.now().toUtc(),
      summary: 'Morning summary text',
      contentHtml: '<p>Morning content</p>',
    );

    await tester.runAsync(() async {
      await dbService.insertEdition(morningEdition);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    // Act
    await tester.runAsync(() async {
      await tester.pumpWidget(ArticlesApp(
        feedService: feedService,
        editionService: editionService,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    // Open drawer
    final menuButton = find.byTooltip('Feed Sections & Feeds');
    expect(menuButton, findsOneWidget);
    await tester.tap(menuButton);
    await tester.pumpAndSettle();

    // Assert Drawer Content
    expect(find.text('EDITORIAL EDITIONS'), findsOneWidget);
    expect(find.text('ON-DEVICE AI'), findsOneWidget);
    expect(find.text('Morning Briefing'), findsOneWidget);
    expect(find.text('Evening Dispatch'), findsOneWidget);
    expect(find.text('Monday Kickoff'), findsOneWidget);
    expect(find.text('Friday Review'), findsOneWidget);
  });

  testWidgets('Tapping an edition tile in the side drawer navigates to EditionScreen', (tester) async {
    // Arrange
    final eveningEdition = EditorialEdition(
      id: 'edition_evening_20260830',
      type: EditionType.evening,
      title: 'EVENING DISPATCH: MAJOR TECH EVENT',
      subtitle: 'SYNTHESIZED ON-DEVICE FROM 5 DISPATCHES',
      generatedAt: DateTime.now().toUtc(),
      summary: 'Evening executive summary overview',
      contentHtml: '<h2>EXECUTIVE OVERVIEW</h2><p>Evening overview body</p>',
    );

    await tester.runAsync(() async {
      await dbService.insertEdition(eveningEdition);
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });

    // Act
    await tester.runAsync(() async {
      await tester.pumpWidget(ArticlesApp(
        feedService: feedService,
        editionService: editionService,
      ));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();

    // Open drawer
    await tester.tap(find.byTooltip('Feed Sections & Feeds'));
    await tester.pumpAndSettle();

    // Tap Evening Dispatch
    await tester.runAsync(() async {
      await tester.tap(find.text('Evening Dispatch'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pumpAndSettle();

    // Assert EditionScreen is displayed
    expect(find.byType(EditionScreen), findsOneWidget);
    expect(find.text('EVENING DISPATCH: MAJOR TECH EVENT'), findsOneWidget);
    expect(find.text('ON-DEVICE AI SYNTHESIS • 100% PRIVATE'), findsOneWidget);
    expect(find.text('RE-SYNTHESIZE THIS EDITION (ON-DEVICE AI)'), findsOneWidget);
  });

  testWidgets('ArticleScreen displays TTS button and toggles speech playback state', (tester) async {
    // Arrange
    final article = Article(
      id: 'art-tts-1',
      feedId: 'f1',
      feedTitle: 'The Daily Chronicle',
      title: 'Ocean Acoustics Study',
      link: 'https://chronicle.example.com/acoustics',
      author: 'Dr. Aronnax',
      publishedDate: DateTime.now().toUtc(),
      summary: 'Hydrophone recordings reveal underwater songs.',
      content: '<p>Acoustic sensors registered low-frequency signatures across the Mariana Trench.</p>',
    );
    final mockEngine = _TestTtsEngine();
    final ttsService = TtsService(engine: mockEngine);

    // Act: Render ArticleScreen with injected TtsService
    await tester.pumpWidget(
      MaterialApp(
        theme: NewspaperTheme.themeData,
        home: ArticleScreen(
          article: article,
          ttsService: ttsService,
        ),
      ),
    );
    await tester.pump();

    // Assert: Idle TTS button is present
    final playButton = find.byTooltip('Read Article Aloud (On-Device Voice)');
    expect(playButton, findsOneWidget);
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    expect(find.byIcon(Icons.stop_circle_outlined), findsNothing);

    // Act: Tap play button
    await tester.tap(playButton);
    await tester.pump();

    // Assert: Playback started, icon switches to stop button
    expect(mockEngine.spokenChunks, isNotEmpty);
    expect(mockEngine.spokenChunks.first, contains('Ocean Acoustics Study'));
    final stopButton = find.byTooltip('Stop Reading Aloud');
    expect(stopButton, findsOneWidget);
    expect(find.byIcon(Icons.stop_circle_outlined), findsOneWidget);

    // Act: Tap stop button
    await tester.tap(stopButton);
    await tester.pump();

    // Assert: Playback stopped, icon reverts to speaker
    expect(find.byTooltip('Read Article Aloud (On-Device Voice)'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
  });
}

class _TestTtsEngine implements TtsPlatformEngine {
  final List<String> spokenChunks = [];
  bool isStopped = false;
  void Function()? onStart;
  void Function()? onComplete;
  void Function(dynamic message)? onError;
  void Function()? onCancel;
  void Function()? onPause;
  void Function()? onContinue;

  @override
  Future<dynamic> speak(String text) async {
    spokenChunks.add(text);
    isStopped = false;
    onStart?.call();
    return 1;
  }

  @override
  Future<dynamic> stop() async {
    isStopped = true;
    onCancel?.call();
    return 1;
  }

  @override
  Future<dynamic> pause() async => 1;

  @override
  Future<dynamic> setLanguage(String language) async => 1;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> setVolume(double volume) async => 1;

  @override
  Future<dynamic> setPitch(double pitch) async => 1;

  @override
  void setStartHandler(void Function() callback) => onStart = callback;

  @override
  void setCompletionHandler(void Function() callback) => onComplete = callback;

  @override
  void setErrorHandler(void Function(dynamic message) callback) => onError = callback;

  @override
  void setCancelHandler(void Function() callback) => onCancel = callback;

  @override
  void setPauseHandler(void Function() callback) => onPause = callback;

  @override
  void setContinueHandler(void Function() callback) => onContinue = callback;
}
