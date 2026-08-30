import 'package:flutter_test/flutter_test.dart';
import 'package:articles/models/models.dart';
import 'package:articles/services/on_device_summary_engine.dart';

void main() {
  const engine = DeterministicNlpSummaryEngine();

  group('DeterministicNlpSummaryEngine - Unit Tests (IEEE 29119 & AAA Pattern)', () {
    test('synthesizes structured edition with executive overview from articles', () async {
      // Arrange
      final articles = [
        Article(
          id: 'art_1',
          feedId: 'feed_tech',
          feedTitle: 'Tech News',
          title: 'Quantum Computing Reaches Milestone in Quantum Error Mitigation',
          link: 'https://example.com/quantum',
          publishedDate: DateTime.utc(2026, 8, 30, 7, 0),
          summary: 'Researchers demonstrate a 100-qubit processor maintaining coherence for extended computations.',
          content: 'Researchers have demonstrated a breakthrough in quantum error mitigation. The new architecture achieves high fidelity operations. Commercial deployments are anticipated within the decade.',
        ),
        Article(
          id: 'art_2',
          feedId: 'feed_science',
          feedTitle: 'Space Digest',
          title: 'Deep Space Telescope Discovers Atmospheric Water Vapor on Exoplanet',
          link: 'https://example.com/exoplanet',
          publishedDate: DateTime.utc(2026, 8, 30, 6, 30),
          summary: 'Spectroscopic observations confirm water vapor signatures on a nearby habitable-zone exoplanet.',
          content: 'Spectroscopic analysis reveals unequivocal signatures of water vapor. The telescope gathered data over consecutive orbital transits. Scientists plan follow-up observations next month.',
        ),
      ];
      final targetDate = DateTime.utc(2026, 8, 30, 8, 0);

      // Act
      final edition = await engine.generateEdition(
        type: EditionType.morning,
        articles: articles,
        targetDate: targetDate,
      );

      // Assert
      expect(edition.id, equals('edition_morning_20260830'));
      expect(edition.type, equals(EditionType.morning));
      expect(edition.title, contains('MORNING BRIEFING'));
      expect(edition.summary, isNotEmpty);
      expect(edition.contentHtml, contains('<h2>EXECUTIVE OVERVIEW</h2>'));
      expect(edition.contentHtml, contains('<h2>LEAD STORY:'));
      expect(edition.contentHtml, contains('<h2>INDEX OF CITED SOURCES</h2>'));
      expect(edition.sourceArticleIds, equals(['art_1', 'art_2']));
    });

    test('generates deterministic output for identical input corpora', () async {
      // Arrange
      final articles = [
        Article(
          id: 'art_a',
          feedId: 'feed_1',
          feedTitle: 'Global Dispatch',
          title: 'Global Renewable Capacity Increases by Record Margin',
          link: 'https://example.com/renewables',
          publishedDate: DateTime.utc(2026, 8, 30, 5, 0),
          summary: 'Solar and wind installations grew exponentially over the past calendar quarter.',
          content: 'Solar installations surged across all regions. Grid storage systems expanded capacity to stabilize power delivery.',
        ),
      ];
      final targetDate = DateTime.utc(2026, 8, 30, 10, 0);

      // Act
      final edition1 = await engine.generateEdition(
        type: EditionType.evening,
        articles: articles,
        targetDate: targetDate,
      );
      final edition2 = await engine.generateEdition(
        type: EditionType.evening,
        articles: articles,
        targetDate: targetDate,
      );

      // Assert
      expect(edition1.id, equals(edition2.id));
      expect(edition1.title, equals(edition2.title));
      expect(edition1.summary, equals(edition2.summary));
      expect(edition1.contentHtml, equals(edition2.contentHtml));
    });

    test('handles empty articles collection gracefully with fallback notice', () async {
      // Arrange
      final targetDate = DateTime.utc(2026, 8, 30);

      // Act
      final edition = await engine.generateEdition(
        type: EditionType.monday,
        articles: const [],
        targetDate: targetDate,
      );

      // Assert
      expect(edition.id, equals('edition_monday_20260830'));
      expect(edition.type, equals(EditionType.monday));
      expect(edition.title, contains('QUIET DISPATCH'));
      expect(edition.contentHtml, contains('EDITION NOTICE'));
      expect(edition.sourceArticleIds, isEmpty);
    });

    test('sanitizes script injections from raw article summaries', () async {
      // Arrange
      final maliciousArticles = [
        Article(
          id: 'art_malicious',
          feedId: 'feed_x',
          feedTitle: 'Untrusted Feed',
          title: 'Security Alert <script>alert("xss")</script>',
          link: 'https://example.com/hack',
          publishedDate: DateTime.utc(2026, 8, 30),
          summary: 'Vulnerability discovered <img src="x" onerror="maliciousCode()"/> in authentication protocols.',
          content: '<script>window.location="http://attacker.com";</script>Protocol patch deployed immediately.',
        ),
      ];
      final targetDate = DateTime.utc(2026, 8, 30);

      // Act
      final edition = await engine.generateEdition(
        type: EditionType.friday,
        articles: maliciousArticles,
        targetDate: targetDate,
      );

      // Assert
      expect(edition.contentHtml, isNot(contains('<script>')));
      expect(edition.contentHtml, isNot(contains('onerror=')));
      expect(edition.contentHtml, isNot(contains('javascript:')));
    });

    test('generates specific headlines for each EditionType', () async {
      // Arrange
      final articles = [
        Article(
          id: 'art_test',
          feedId: 'feed_test',
          feedTitle: 'Test Source',
          title: 'Major Breakthrough Announced',
          link: 'https://example.com/breakthrough',
          publishedDate: DateTime.utc(2026, 8, 30),
          summary: 'Comprehensive testing confirms initial laboratory findings across multiple trials.',
        ),
      ];
      final targetDate = DateTime.utc(2026, 8, 30);

      // Act & Assert
      final morning = await engine.generateEdition(type: EditionType.morning, articles: articles, targetDate: targetDate);
      expect(morning.title, startsWith('MORNING BRIEFING:'));

      final evening = await engine.generateEdition(type: EditionType.evening, articles: articles, targetDate: targetDate);
      expect(evening.title, startsWith('EVENING DISPATCH:'));

      final monday = await engine.generateEdition(type: EditionType.monday, articles: articles, targetDate: targetDate);
      expect(monday.title, startsWith('MONDAY KICKOFF:'));

      final friday = await engine.generateEdition(type: EditionType.friday, articles: articles, targetDate: targetDate);
      expect(friday.title, startsWith('WEEKEND REVIEW:'));
    });
  });
}

