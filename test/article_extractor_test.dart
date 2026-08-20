import 'package:flutter_test/flutter_test.dart';
import 'package:articles/services/article_extractor.dart';

void main() {
  group('ArticleExtractor - HTML Content Extraction', () {
    test('extracts article body from semantic <article> tags', () {
      // Arrange
      const html = '''
<!DOCTYPE html>
<html>
<head>
  <title>Global Energy Transition Progress</title>
  <meta property="og:image" content="https://news.example.com/solar.jpg" />
</head>
<body>
  <nav><a href="/">Home</a><a href="/news">News</a></nav>
  <header><h1>Site Header</h1></header>
  <article>
    <h2>Milestone in Solar Deployment</h2>
    <p>Renewable power generation achieved a significant milestone across global utility networks this quarter.</p>
    <p>Grid operators reported record stability and lower operating costs during peak hours.</p>
    <p>Substantial infrastructure investments continue to accelerate deployment schedules.</p>
  </article>
  <aside><p>Sponsored advertisement</p></aside>
  <footer><p>Copyright 2026</p></footer>
</body>
</html>
''';

      // Act
      final result = ArticleExtractor.parseHtmlPage(html, Uri.parse('https://news.example.com/story/101'));

      // Assert
      expect(result.title, equals('Global Energy Transition Progress'));
      expect(result.leadImageUrl, equals('https://news.example.com/solar.jpg'));
      expect(result.contentHtml.contains('Renewable power generation achieved'), isTrue);
      expect(result.contentHtml.contains('Sponsored advertisement'), isFalse);
      expect(result.contentHtml.contains('Site Header'), isFalse);
    });

    test('resolves relative image URLs to absolute URLs', () {
      // Arrange
      const html = '''
<html>
<body>
  <div class="story-body">
    <p>First paragraph of the comprehensive news article story.</p>
    <p>Second paragraph detailing the key findings and scientific observations.</p>
    <img src="/images/chart.png" alt="Deployment Graph" />
  </div>
</body>
</html>
''';

      // Act
      final result = ArticleExtractor.parseHtmlPage(html, Uri.parse('https://example.org/articles/tech'));

      // Assert
      expect(result.contentHtml.contains('https://example.org/images/chart.png'), isTrue);
      expect(result.contentHtml.contains('First paragraph'), isTrue);
    });
  });
}

