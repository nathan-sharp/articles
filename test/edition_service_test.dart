import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:articles/models/models.dart';
import 'package:articles/services/database_service.dart';
import 'package:articles/services/edition_service.dart';
import 'package:articles/services/on_device_summary_engine.dart';

void main() {
  late DatabaseService dbService;
  late Database ffiDb;
  late EditionService editionService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    // Arrange: In-memory isolated database
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
    editionService = EditionService(
      dbService: dbService,
      summaryEngine: const DeterministicNlpSummaryEngine(),
    );
  });

  tearDown(() async {
    await dbService.close();
  });

  group('EditionService - Lifecycle & Caching (IEEE 29119 & AAA Pattern)', () {
    test('retrieves cached edition when fresh and avoids redundant generation', () async {
      // Arrange
      final refDate = DateTime.utc(2026, 8, 30, 9, 0);
      final existingCached = EditorialEdition(
        id: 'edition_morning_20260830',
        type: EditionType.morning,
        title: 'CACHED MORNING BRIEFING',
        generatedAt: DateTime.utc(2026, 8, 30, 8, 30),
        summary: 'Cached executive overview',
        contentHtml: '<p>Cached content</p>',
      );
      await dbService.insertEdition(existingCached);

      // Act
      final result = await editionService.getOrGenerateEdition(
        EditionType.morning,
        referenceDate: refDate,
        force: false,
      );

      // Assert
      expect(result.id, equals('edition_morning_20260830'));
      expect(result.title, equals('CACHED MORNING BRIEFING'));
    });

    test('forceRegenerateEdition forces on-device re-synthesis and persists to database', () async {
      // Arrange
      final refDate = DateTime.utc(2026, 8, 30, 9, 0);
      final articles = [
        Article(
          id: 'art_1',
          feedId: 'f1',
          feedTitle: 'Reuters Tech',
          title: 'Autonomous Navigation Systems Pass Urban Certification',
          link: 'https://example.com/auto',
          publishedDate: DateTime.utc(2026, 8, 30, 7, 30),
          summary: 'Certification authorities approved new redundant sensor architectures for municipal transit.',
        ),
      ];
      await dbService.upsertArticles(articles);

      // Act
      final edition = await editionService.forceRegenerateEdition(
        EditionType.morning,
        referenceDate: refDate,
      );
      final fromDb = await dbService.getLatestEdition(EditionType.morning);

      // Assert
      expect(edition.id, equals('edition_morning_20260830'));
      expect(edition.title, contains('AUTONOMOUS NAVIGATION'));
      expect(fromDb, isNotNull);
      expect(fromDb!.id, equals('edition_morning_20260830'));
    });

    test('precomputeStaleEditions generates and caches all four edition types', () async {
      // Arrange
      final refDate = DateTime.utc(2026, 8, 30, 9, 0);
      final articles = [
        Article(
          id: 'art_test',
          feedId: 'f1',
          feedTitle: 'World Wire',
          title: 'International Energy Council Releases Annual Global Outlook',
          link: 'https://example.com/energy',
          publishedDate: DateTime.utc(2026, 8, 30, 6, 0),
          summary: 'The comprehensive report outlines projected investments in modern grid resilience.',
        ),
      ];
      await dbService.upsertArticles(articles);

      // Act
      await editionService.precomputeStaleEditions(referenceDate: refDate);
      final allEditions = await editionService.getAllEditions();

      // Assert
      expect(allEditions.length, equals(4));
      expect(allEditions[EditionType.morning], isNotNull);
      expect(allEditions[EditionType.evening], isNotNull);
      expect(allEditions[EditionType.monday], isNotNull);
      expect(allEditions[EditionType.friday], isNotNull);
    });

    test('partitions articles into context-aware time windows correctly', () async {
      // Arrange
      final now = DateTime.utc(2026, 8, 30, 15, 0); // Sunday afternoon

      final artMorning = Article(
        id: 'art_morning',
        feedId: 'f1',
        feedTitle: 'F1',
        title: 'Morning Story',
        link: 'https://example.com/m',
        publishedDate: DateTime.utc(2026, 8, 30, 7, 0), // 8 hours ago
        summary: 'Morning news summary text here.',
      );
      final artEvening = Article(
        id: 'art_evening',
        feedId: 'f1',
        feedTitle: 'F1',
        title: 'Evening Story',
        link: 'https://example.com/e',
        publishedDate: DateTime.utc(2026, 8, 30, 14, 0), // 1 hour ago
        summary: 'Evening news summary text here.',
      );
      final artFourDaysAgo = Article(
        id: 'art_midweek',
        feedId: 'f1',
        feedTitle: 'F1',
        title: 'Midweek Story',
        link: 'https://example.com/w',
        publishedDate: DateTime.utc(2026, 8, 26, 12, 0), // 4 days ago
        summary: 'Midweek news summary text here.',
      );
      final artTenDaysAgo = Article(
        id: 'art_old',
        feedId: 'f1',
        feedTitle: 'F1',
        title: 'Old Story',
        link: 'https://example.com/o',
        publishedDate: DateTime.utc(2026, 8, 20, 12, 0), // 10 days ago
        summary: 'Old news summary text here.',
      );

      await dbService.upsertArticles([artMorning, artEvening, artFourDaysAgo, artTenDaysAgo]);

      // Act
      final mondayArticles = await editionService.getArticlesForEdition(EditionType.monday, referenceDate: now);

      // Assert
      // Monday edition looks at the past 7 days (168 hours)
      final ids = mondayArticles.map((a) => a.id).toList();
      expect(ids, contains('art_morning'));
      expect(ids, contains('art_evening'));
      expect(ids, contains('art_midweek'));
      expect(ids, isNot(contains('art_old')));
    });

    test('markEditionAsRead updates isRead in database', () async {
      // Arrange
      final edition = EditorialEdition(
        id: 'edition_test_read',
        type: EditionType.morning,
        title: 'UNREAD EDITION',
        generatedAt: DateTime.now().toUtc(),
        summary: 'Summary',
        contentHtml: '<p>Body</p>',
        isRead: false,
      );
      await dbService.insertEdition(edition);

      // Act
      await editionService.markEditionAsRead('edition_test_read');
      final updated = await dbService.getEditionById('edition_test_read');

      // Assert
      expect(updated, isNotNull);
      expect(updated!.isRead, isTrue);
    });
  });
}

