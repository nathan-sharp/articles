import 'package:flutter_test/flutter_test.dart';
import 'package:articles/services/feed_parser.dart';

void main() {
  group('FeedParser - RSS 2.0 Parsing', () {
    test('parses standard RSS 2.0 channel and item metadata', () {
      // Arrange
      const rssXml = '''<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>The Daily Chronicle</title>
    <link>https://chronicle.example.com</link>
    <description>Independent global reporting</description>
    <item>
      <title>Historic Expedition Reaches Summit</title>
      <link>https://chronicle.example.com/summit</link>
      <guid>https://chronicle.example.com/summit</guid>
      <dc:creator>Jane Doe</dc:creator>
      <pubDate>Mon, 18 Aug 2026 14:30:00 +0000</pubDate>
      <description>&lt;p&gt;Explorers have confirmed the milestone arrival.&lt;/p&gt;</description>
      <content:encoded>&lt;p&gt;Full story details regarding the expedition team.&lt;/p&gt;</content:encoded>
      <enclosure url="https://chronicle.example.com/image.jpg" type="image/jpeg" />
    </item>
  </channel>
</rss>''';

      // Act
      final result = FeedParser.parseXml(
        xmlContent: rssXml,
        feedUrl: 'https://chronicle.example.com/rss.xml',
      );

      // Assert
      expect(result.feed.title, equals('The Daily Chronicle'));
      expect(result.feed.siteUrl, equals('https://chronicle.example.com'));
      expect(result.feed.description, equals('Independent global reporting'));
      expect(result.articles.length, equals(1));

      final article = result.articles.first;
      expect(article.title, equals('Historic Expedition Reaches Summit'));
      expect(article.link, equals('https://chronicle.example.com/summit'));
      expect(article.author, equals('Jane Doe'));
      expect(article.summary, equals('Explorers have confirmed the milestone arrival.'));
      expect(article.content.contains('Full story details'), isTrue);
      expect(article.imageUrl, equals('https://chronicle.example.com/image.jpg'));
    });
  });

  group('FeedParser - Atom 1.0 Parsing', () {
    test('parses standard Atom 1.0 feed and entry metadata', () {
      // Arrange
      const atomXml = '''<?xml version="1.0" encoding="utf-8"?>
<feed xmlns="http://www.w3.org/2005/Atom">
  <title>Tech Dispatch</title>
  <link rel="alternate" href="https://techdispatch.example.org" />
  <subtitle>Open Systems Analysis</subtitle>
  <entry>
    <title>New Compiler Optimization Techniques</title>
    <link rel="alternate" href="https://techdispatch.example.org/compiler" />
    <id>tag:techdispatch.example.org,2026:post-101</id>
    <published>2026-08-19T10:00:00Z</published>
    <author>
      <name>Alan Turing</name>
    </author>
    <summary>A deep dive into register allocation algorithms.</summary>
    <content type="html">&lt;p&gt;Detailed algorithmic breakdown and benchmarks.&lt;/p&gt;</content>
  </entry>
</feed>''';

      // Act
      final result = FeedParser.parseXml(
        xmlContent: atomXml,
        feedUrl: 'https://techdispatch.example.org/atom.xml',
      );

      // Assert
      expect(result.feed.title, equals('Tech Dispatch'));
      expect(result.feed.siteUrl, equals('https://techdispatch.example.org'));
      expect(result.feed.description, equals('Open Systems Analysis'));
      expect(result.articles.length, equals(1));

      final article = result.articles.first;
      expect(article.title, equals('New Compiler Optimization Techniques'));
      expect(article.link, equals('https://techdispatch.example.org/compiler'));
      expect(article.author, equals('Alan Turing'));
      expect(article.summary, equals('A deep dive into register allocation algorithms.'));
      expect(article.content.contains('Detailed algorithmic breakdown'), isTrue);
      expect(article.publishedDate.year, equals(2026));
    });
  });

  group('FeedParser - Error Handling & Edge Cases', () {
    test('throws FormatException on empty or unparseable input', () {
      // Arrange
      const emptyContent = '';

      // Act & Assert
      expect(
        () => FeedParser.parseXml(xmlContent: emptyContent, feedUrl: 'https://example.com/feed'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws FormatException on non-feed XML document', () {
      // Arrange
      const arbitraryXml = '<catalog><book id="bk101"><title>XML Guide</title></book></catalog>';

      // Act & Assert
      expect(
        () => FeedParser.parseXml(xmlContent: arbitraryXml, feedUrl: 'https://example.com/feed'),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

