import 'package:flutter_test/flutter_test.dart';
import 'package:articles/services/security_validator.dart';

void main() {
  group('SecurityValidator - URL Validation (SSRF Prevention)', () {
    test('allows valid public HTTPS and HTTP URLs', () {
      // Arrange
      const validUrls = [
        'https://feeds.bbci.co.uk/news/rss.xml',
        'http://feeds.arstechnica.com/arstechnica/index',
        'https://news.ycombinator.com/rss',
        'https://www.nasa.gov/news-release/feed/',
      ];

      for (final url in validUrls) {
        // Act
        final isValid = SecurityValidator.isValidFeedUrl(url);

        // Assert
        expect(isValid, isTrue, reason: 'Failed for valid URL: $url');
      }
    });

    test('rejects loopback and localhost URLs', () {
      // Arrange
      const invalidUrls = [
        'http://localhost/feed.xml',
        'http://127.0.0.1:8000/rss',
        'https://0.0.0.0/atom.xml',
        'http://[::1]/feed',
      ];

      for (final url in invalidUrls) {
        // Act
        final isValid = SecurityValidator.isValidFeedUrl(url);

        // Assert
        expect(isValid, isFalse, reason: 'Failed to reject loopback: $url');
      }
    });

    test('rejects private IPv4 subnet URLs', () {
      // Arrange
      const privateSubnetUrls = [
        'http://10.0.0.1/rss',
        'http://10.254.1.1/feed',
        'http://192.168.1.1/feed.xml',
        'http://192.168.0.254/atom',
        'http://172.16.0.1/rss',
        'http://172.31.255.255/rss',
        'http://169.254.169.254/latest/meta-data',
      ];

      for (final url in privateSubnetUrls) {
        // Act
        final isValid = SecurityValidator.isValidFeedUrl(url);

        // Assert
        expect(isValid, isFalse, reason: 'Failed to reject private IP: $url');
      }
    });

    test('rejects invalid schemes and empty strings', () {
      // Arrange
      const invalidSchemes = [
        '',
        '   ',
        'ftp://example.com/feed.xml',
        'file:///etc/passwd',
        'javascript:alert(1)',
        'data:text/html,<h1>Hello</h1>',
      ];

      for (final url in invalidSchemes) {
        // Act
        final isValid = SecurityValidator.isValidFeedUrl(url);

        // Assert
        expect(isValid, isFalse, reason: 'Failed to reject scheme: $url');
      }
    });
  });

  group('SecurityValidator - HTML Sanitization (XSS Prevention)', () {
    test('strips dangerous script, iframe, and object tags', () {
      // Arrange
      const rawHtml = '<p>Normal text</p><script>alert("xss")</script><iframe src="evil.com"></iframe>';

      // Act
      final sanitized = SecurityValidator.sanitizeHtml(rawHtml);

      // Assert
      expect(sanitized.contains('<script>'), isFalse);
      expect(sanitized.contains('alert'), isFalse);
      expect(sanitized.contains('<iframe'), isFalse);
      expect(sanitized.contains('Normal text'), isTrue);
    });

    test('strips inline event handlers and javascript pseudo-protocols', () {
      // Arrange
      const rawHtml = '<a href="javascript:doEvil()" onclick="stealCookies()">Click me</a><img src="x" onerror="alert(1)">';

      // Act
      final sanitized = SecurityValidator.sanitizeHtml(rawHtml);

      // Assert
      expect(sanitized.contains('onclick'), isFalse);
      expect(sanitized.contains('onerror'), isFalse);
      expect(sanitized.contains('javascript:'), isFalse);
      expect(sanitized.contains('Click me'), isTrue);
    });

    test('extracts plain text and decodes HTML entities correctly', () {
      // Arrange
      const rawHtml = '<p>Breaking News &amp; Updates: It&#39;s a <strong>&quot;historic&quot;</strong> event.</p>';

      // Act
      final plainText = SecurityValidator.extractPlainText(rawHtml);

      // Assert
      expect(plainText, equals("Breaking News & Updates: It's a \"historic\" event."));
    });
  });
}

