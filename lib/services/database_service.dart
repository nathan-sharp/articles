import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../models/models.dart';

/// Database management service for persisting feeds and cached articles.
class DatabaseService {
  static DatabaseService? _instance;
  final Database _db;

  DatabaseService._(this._db);

  /// Returns the singleton instance of [DatabaseService].
  static DatabaseService get instance {
    final inst = _instance;
    if (inst == null) {
      throw StateError('DatabaseService has not been initialized. Call init() first.');
    }
    return inst;
  }

  /// Initialized state checker.
  static bool get isInitialized => _instance != null;

  /// Initializes SQLite database engine with platform FFI support for desktop/mobile.
  static Future<DatabaseService> init({Database? customDatabase, String? dbName}) async {
    if (customDatabase != null) {
      final service = DatabaseService._(customDatabase);
      _instance = service;
      return service;
    }

    if (_instance != null) {
      return _instance!;
    }

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }

    final name = dbName ?? 'articles_reader.db';
    String dbPath;

    if (!kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS)) {
      final docDir = await getApplicationSupportDirectory();
      dbPath = p.join(docDir.path, name);
    } else {
      final defaultDatabasesPath = await getDatabasesPath();
      dbPath = p.join(defaultDatabasesPath, name);
    }

    final database = await openDatabase(
      dbPath,
      version: 1,
      onCreate: _createDatabaseSchema,
    );

    final service = DatabaseService._(database);
    _instance = service;
    return service;
  }

  /// Sets up tables, constraints, and performance indexes.
  static Future<void> _createDatabaseSchema(Database db, int version) async {
    await db.execute('''
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

    await db.execute('''
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

    await db.execute('CREATE INDEX idx_articles_published_date ON articles (published_date DESC);');
    await db.execute('CREATE INDEX idx_articles_feed_id ON articles (feed_id);');
    await db.execute('CREATE INDEX idx_articles_is_read ON articles (is_read);');
    await db.execute('CREATE INDEX idx_articles_is_bookmarked ON articles (is_bookmarked);');
  }

  // --- Feed Operations ---

  /// Inserts or replaces a feed record.
  Future<void> insertFeed(Feed feed) async {
    await _db.insert(
      'feeds',
      feed.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieves all feeds sorted alphabetically by title.
  Future<List<Feed>> getAllFeeds() async {
    final rows = await _db.query('feeds', orderBy: 'title ASC');
    return rows.map(Feed.fromMap).toList();
  }

  /// Retrieves a specific feed by its unique ID.
  Future<Feed?> getFeedById(String id) async {
    final rows = await _db.query(
      'feeds',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Feed.fromMap(rows.first);
  }

  /// Retrieves a feed by its subscription URL.
  Future<Feed?> getFeedByUrl(String url) async {
    final rows = await _db.query(
      'feeds',
      where: 'url = ?',
      whereArgs: [url],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Feed.fromMap(rows.first);
  }

  /// Updates feed metadata and error statuses.
  Future<void> updateFeed(Feed feed) async {
    await _db.update(
      'feeds',
      feed.toMap(),
      where: 'id = ?',
      whereArgs: [feed.id],
    );
  }

  /// Deletes a feed and its associated articles.
  Future<void> deleteFeed(String id) async {
    await _db.transaction((txn) async {
      await txn.delete('articles', where: 'feed_id = ?', whereArgs: [id]);
      await txn.delete('feeds', where: 'id = ?', whereArgs: [id]);
    });
  }

  // --- Article Operations ---

  /// Inserts new articles while preserving existing read/bookmarked user flags.
  Future<int> upsertArticles(List<Article> articles) async {
    if (articles.isEmpty) return 0;

    var newArticlesCount = 0;

    await _db.transaction((txn) async {
      for (final article in articles) {
        final existing = await txn.query(
          'articles',
          columns: ['is_read', 'is_bookmarked'],
          where: 'id = ?',
          whereArgs: [article.id],
          limit: 1,
        );

        if (existing.isEmpty) {
          await txn.insert('articles', article.toMap());
          newArticlesCount++;
        } else {
          // Preserve user-specified states
          final isRead = existing.first['is_read'] as int? ?? 0;
          final isBookmarked = existing.first['is_bookmarked'] as int? ?? 0;

          final updatedMap = article.toMap();
          updatedMap['is_read'] = isRead;
          updatedMap['is_bookmarked'] = isBookmarked;

          await txn.update(
            'articles',
            updatedMap,
            where: 'id = ?',
            whereArgs: [article.id],
          );
        }
      }
    });

    return newArticlesCount;
  }

  /// Queries articles with optional feed filtering, read filters, and search queries.
  Future<List<Article>> getArticles({
    String? feedId,
    bool? unreadOnly,
    bool? bookmarkedOnly,
    String? searchQuery,
    int limit = 100,
    int offset = 0,
  }) async {
    final whereClauses = <String>[];
    final whereArgs = <dynamic>[];

    if (feedId != null && feedId.isNotEmpty) {
      whereClauses.add('feed_id = ?');
      whereArgs.add(feedId);
    }

    if (unreadOnly == true) {
      whereClauses.add('is_read = 0');
    }

    if (bookmarkedOnly == true) {
      whereClauses.add('is_bookmarked = 1');
    }

    if (searchQuery != null && searchQuery.trim().isNotEmpty) {
      final queryPattern = '%${searchQuery.trim()}%';
      whereClauses.add('(title LIKE ? OR summary LIKE ? OR content LIKE ?)');
      whereArgs.addAll([queryPattern, queryPattern, queryPattern]);
    }

    final whereString = whereClauses.isEmpty ? null : whereClauses.join(' AND ');

    final rows = await _db.query(
      'articles',
      where: whereString,
      whereArgs: whereArgs.isEmpty ? null : whereArgs,
      orderBy: 'published_date DESC',
      limit: limit,
      offset: offset,
    );

    return rows.map(Article.fromMap).toList();
  }

  /// Marks a specific article as read or unread.
  Future<void> setArticleReadStatus(String articleId, bool isRead) async {
    await _db.update(
      'articles',
      {'is_read': isRead ? 1 : 0},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  /// Toggles or sets an article bookmark status.
  Future<void> setArticleBookmarkStatus(String articleId, bool isBookmarked) async {
    await _db.update(
      'articles',
      {'is_bookmarked': isBookmarked ? 1 : 0},
      where: 'id = ?',
      whereArgs: [articleId],
    );
  }

  /// Marks all articles as read, optionally scoped to a single feed.
  Future<void> markAllAsRead({String? feedId}) async {
    if (feedId != null && feedId.isNotEmpty) {
      await _db.update(
        'articles',
        {'is_read': 1},
        where: 'feed_id = ? AND is_read = 0',
        whereArgs: [feedId],
      );
    } else {
      await _db.update(
        'articles',
        {'is_read': 1},
        where: 'is_read = 0',
      );
    }
  }

  /// Returns the count of unread articles, optionally scoped to a single feed.
  Future<int> getUnreadCount({String? feedId}) async {
    List<Map<String, Object?>> result;
    if (feedId != null && feedId.isNotEmpty) {
      result = await _db.rawQuery(
        'SELECT COUNT(*) as count FROM articles WHERE feed_id = ? AND is_read = 0',
        [feedId],
      );
    } else {
      result = await _db.rawQuery('SELECT COUNT(*) as count FROM articles WHERE is_read = 0');
    }

    if (result.isEmpty) return 0;
    return (result.first['count'] as int?) ?? 0;
  }

  /// Closes database connection.
  Future<void> close() async {
    await _db.close();
    _instance = null;
  }
}
