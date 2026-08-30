import 'dart:async';
import '../models/models.dart';
import 'database_service.dart';
import 'on_device_summary_engine.dart';

/// Orchestration service managing periodic editorial edition generation, caching, and retrieval.
class EditionService {
  final DatabaseService _dbService;
  final LocalSummaryEngine _summaryEngine;

  EditionService({
    required DatabaseService dbService,
    LocalSummaryEngine? summaryEngine,
  })  : _dbService = dbService,
        _summaryEngine = summaryEngine ?? const DeterministicNlpSummaryEngine();

  /// Retrieves cached edition or generates a new one on-device.
  Future<EditorialEdition> getOrGenerateEdition(
    EditionType type, {
    DateTime? referenceDate,
    bool force = false,
  }) async {
    final targetDate = (referenceDate ?? DateTime.now()).toUtc();

    if (!force) {
      final cached = await _dbService.getLatestEdition(type);
      if (cached != null && _isCacheValid(cached, type, targetDate)) {
        return cached;
      }
    }

    return await forceRegenerateEdition(type, referenceDate: targetDate);
  }

  /// Forces on-device re-synthesis and updates the SQLite database cache.
  Future<EditorialEdition> forceRegenerateEdition(
    EditionType type, {
    DateTime? referenceDate,
  }) async {
    final targetDate = (referenceDate ?? DateTime.now()).toUtc();
    final articles = await getArticlesForEdition(type, referenceDate: targetDate);

    final edition = await _summaryEngine.generateEdition(
      type: type,
      articles: articles,
      targetDate: targetDate,
    );

    await _dbService.insertEdition(edition);
    return edition;
  }

  /// Pre-computes all four editorial editions in background worker isolates.
  Future<void> precomputeStaleEditions({
    DateTime? referenceDate,
    bool force = false,
  }) async {
    final targetDate = (referenceDate ?? DateTime.now()).toUtc();

    for (final type in EditionType.values) {
      try {
        final cached = await _dbService.getLatestEdition(type);
        if (force || cached == null || !_isCacheValid(cached, type, targetDate)) {
          await forceRegenerateEdition(type, referenceDate: targetDate);
        }
      } catch (_) {
        // Individual edition generation failure does not interrupt the pipeline
      }
    }
  }

  /// Retrieves the current latest cached edition for all four types.
  Future<Map<EditionType, EditorialEdition?>> getAllEditions() async {
    final map = <EditionType, EditorialEdition?>{};
    for (final type in EditionType.values) {
      map[type] = await _dbService.getLatestEdition(type);
    }
    return map;
  }

  /// Partitions database articles matching context-aware time windows.
  Future<List<Article>> getArticlesForEdition(
    EditionType type, {
    DateTime? referenceDate,
  }) async {
    final now = (referenceDate ?? DateTime.now()).toUtc();
    final allArticles = await _dbService.getArticles(limit: 200);

    if (allArticles.isEmpty) {
      return const [];
    }

    final filtered = <Article>[];

    switch (type) {
      case EditionType.morning:
        // Preceding 18 hours
        final startWindow = now.subtract(const Duration(hours: 18));
        for (final a in allArticles) {
          if (a.publishedDate.isAfter(startWindow) && !a.publishedDate.isAfter(now)) {
            filtered.add(a);
          }
        }
        break;

      case EditionType.evening:
        // Daytime: 06:00 today to current time
        final todayStart = DateTime.utc(now.year, now.month, now.day, 6, 0, 0);
        for (final a in allArticles) {
          if (a.publishedDate.isAfter(todayStart) && !a.publishedDate.isAfter(now)) {
            filtered.add(a);
          }
        }
        break;

      case EditionType.monday:
        // Past 7 days (168 hours)
        final sevenDaysAgo = now.subtract(const Duration(days: 7));
        for (final a in allArticles) {
          if (a.publishedDate.isAfter(sevenDaysAgo) && !a.publishedDate.isAfter(now)) {
            filtered.add(a);
          }
        }
        break;

      case EditionType.friday:
        // Workweek: Monday 00:00 of current week to now
        final daysSinceMonday = (now.weekday - DateTime.monday) % 7;
        final mondayStart = DateTime.utc(now.year, now.month, now.day - daysSinceMonday, 0, 0, 0);
        for (final a in allArticles) {
          if (a.publishedDate.isAfter(mondayStart) && !a.publishedDate.isAfter(now)) {
            filtered.add(a);
          }
        }
        break;
    }

    // If the strict time window yields fewer than 3 articles, fallback gracefully to latest available articles
    if (filtered.length < 3) {
      return allArticles.take(15).toList();
    }

    return filtered;
  }

  /// Validates if an edition cache entry remains fresh for its scheduled cycle.
  bool _isCacheValid(EditorialEdition edition, EditionType type, DateTime targetDate) {
    final gen = edition.generatedAt;

    switch (type) {
      case EditionType.morning:
      case EditionType.evening:
        // Daily editions are fresh if generated on the same calendar day within 12 hours
        return gen.year == targetDate.year &&
            gen.month == targetDate.month &&
            gen.day == targetDate.day &&
            targetDate.difference(gen).inHours < 12;

      case EditionType.monday:
      case EditionType.friday:
        // Weekly editions are fresh if generated within the past 48 hours
        return targetDate.difference(gen).inHours < 48;
    }
  }

  /// Marks an edition as read in SQLite.
  Future<void> markEditionAsRead(String editionId) async {
    await _dbService.setEditionReadStatus(editionId, true);
  }
}

