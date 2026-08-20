import 'package:flutter_test/flutter_test.dart';
import 'package:articles/models/models.dart';
import 'package:articles/services/opml_service.dart';

void main() {
  group('OpmlService - Export and Import Roundtrip', () {
    test('exports feeds to valid OPML 2.0 XML', () {
      // Arrange
      final feeds = [
        Feed(
          id: 'f1',
          title: 'BBC World News',
          url: 'https://feeds.bbci.co.uk/news/world/rss.xml',
          siteUrl: 'https://www.bbc.com/news',
          description: 'BBC World reporting',
          lastUpdated: DateTime.utc(2026, 8, 20),
          category: 'World News',
        ),
        Feed(
          id: 'f2',
          title: 'Ars Technica',
          url: 'https://feeds.arstechnica.com/arstechnica/index',
          siteUrl: 'https://arstechnica.com',
          description: 'Technology analysis',
          lastUpdated: DateTime.utc(2026, 8, 20),
          category: 'Technology',
        ),
      ];

      // Act
      final opmlXml = OpmlService.exportToOpml(feeds);

      // Assert
      expect(opmlXml.contains('<opml version="2.0">'), isTrue);
      expect(opmlXml.contains('BBC World News'), isTrue);
      expect(opmlXml.contains('https://feeds.bbci.co.uk/news/world/rss.xml'), isTrue);
      expect(opmlXml.contains('Ars Technica'), isTrue);
    });

    test('imports feeds accurately from hierarchical OPML 2.0 XML', () {
      // Arrange
      const opmlSource = '''<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>My Subscriptions</title>
  </head>
  <body>
    <outline text="News" title="News">
      <outline type="rss" text="BBC News" title="BBC News" xmlUrl="https://feeds.bbci.co.uk/news/rss.xml" htmlUrl="https://www.bbc.com" />
    </outline>
    <outline text="Tech" title="Tech">
      <outline type="rss" text="Hacker News" title="Hacker News" xmlUrl="https://news.ycombinator.com/rss" htmlUrl="https://news.ycombinator.com" />
    </outline>
  </body>
</opml>''';

      // Act
      final importedEntries = OpmlService.importFromOpml(opmlSource);

      // Assert
      expect(importedEntries.length, equals(2));
      expect(importedEntries[0].title, equals('BBC News'));
      expect(importedEntries[0].xmlUrl, equals('https://feeds.bbci.co.uk/news/rss.xml'));
      expect(importedEntries[0].category, equals('News'));
      expect(importedEntries[1].title, equals('Hacker News'));
      expect(importedEntries[1].xmlUrl, equals('https://news.ycombinator.com/rss'));
      expect(importedEntries[1].category, equals('Tech'));
    });
  });
}

