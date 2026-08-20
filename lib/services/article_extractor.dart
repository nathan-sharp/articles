import 'package:http/http.dart' as http;
import 'security_validator.dart';

/// Result object holding extracted readable article content.
class ExtractedArticle {
  final String title;
  final String byline;
  final String contentHtml;
  final String? leadImageUrl;

  const ExtractedArticle({
    required this.title,
    required this.byline,
    required this.contentHtml,
    this.leadImageUrl,
  });
}

/// Service that extracts full-text articles and media from web pages for truncated feeds.
class ArticleExtractor {
  final http.Client _httpClient;

  ArticleExtractor({http.Client? httpClient}) : _httpClient = httpClient ?? http.Client();

  /// Extracts readable full-text content from the provided article URL.
  Future<ExtractedArticle> extractFromUrl(String url) async {
    final trimmedUrl = url.trim();
    if (!SecurityValidator.isValidFeedUrl(trimmedUrl)) {
      throw const FormatException('Invalid or disallowed article URL scheme/host');
    }

    final response = await _httpClient
        .get(
          Uri.parse(trimmedUrl),
          headers: {
            'User-Agent':
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36',
            'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
          },
        )
        .timeout(const Duration(seconds: 10));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('HTTP request failed with status code ${response.statusCode}');
    }

    final baseUri = Uri.parse(trimmedUrl);
    return parseHtmlPage(response.body, baseUri);
  }

  /// Parses raw HTML web page string and extracts main article content.
  static ExtractedArticle parseHtmlPage(String rawHtml, Uri baseUri) {
    if (rawHtml.trim().isEmpty) {
      throw const FormatException('HTML content is empty');
    }

    // 1. Remove scripts, styles, forms, navigation, header, footer, and aside elements
    var cleanedHtml = rawHtml;
    final nonContentTags = [
      'script',
      'style',
      'nav',
      'header',
      'footer',
      'aside',
      'form',
      'svg',
      'noscript',
      'iframe',
      'button',
      'input',
    ];

    for (final tag in nonContentTags) {
      cleanedHtml = cleanedHtml.replaceAll(
        RegExp('<$tag\\b[^>]*>[\\s\\S]*?</$tag>', caseSensitive: false),
        '',
      );
      cleanedHtml = cleanedHtml.replaceAll(
        RegExp('<$tag\\b[^>]*/>', caseSensitive: false),
        '',
      );
    }

    // 2. Extract Title
    final titleMatch = RegExp(r'<title\b[^>]*>([\s\S]*?)</title>', caseSensitive: false).firstMatch(cleanedHtml);
    final title = titleMatch != null
        ? SecurityValidator.decodeHtmlEntities(SecurityValidator.extractPlainText(titleMatch.group(1)!))
        : '';

    // 3. Extract OpenGraph or Twitter lead image
    String? leadImageUrl;
    final ogImageMatch = RegExp(r'''<meta\b[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']''', caseSensitive: false)
            .firstMatch(rawHtml) ??
        RegExp(r'''<meta\b[^>]*content=["']([^"']+)["'][^>]*property=["']og:image["']''', caseSensitive: false)
            .firstMatch(rawHtml);
    if (ogImageMatch != null) {
      leadImageUrl = _resolveUrl(ogImageMatch.group(1)!, baseUri);
    }

    // 4. Identify candidate article container
    var candidateContent = _findArticleContainer(cleanedHtml);

    // If no candidate container found, extract high-density paragraph sequences
    if (candidateContent.isEmpty) {
      candidateContent = _extractParagraphSequence(cleanedHtml);
    }

    // 5. Clean and sanitize candidate HTML
    candidateContent = _cleanExtractedContent(candidateContent, baseUri);
    final sanitizedHtml = SecurityValidator.sanitizeHtml(candidateContent);

    return ExtractedArticle(
      title: title,
      byline: '',
      contentHtml: sanitizedHtml,
      leadImageUrl: leadImageUrl,
    );
  }

  /// Finds the highest-scoring article container element.
  static String _findArticleContainer(String html) {
    // Check semantic <article> tags first
    final articleMatches = RegExp(r'<article\b[^>]*>([\s\S]*?)</article>', caseSensitive: false).allMatches(html);
    String bestMatch = '';
    var maxParagraphs = 0;

    for (final match in articleMatches) {
      final content = match.group(1)!;
      final pCount = RegExp(r'<p\b[^>]*>', caseSensitive: false).allMatches(content).length;
      if (pCount > maxParagraphs) {
        maxParagraphs = pCount;
        bestMatch = content;
      }
    }

    if (bestMatch.isNotEmpty && maxParagraphs >= 2) {
      return bestMatch;
    }

    // Check class and ID based selectors (e.g. story-body, post-content, article-body)
    final classPatterns = [
      r'itemprop=["\x27]articleBody["\x27]',
      r'class=["\x27][^"\x27]*(?:story-body|article-body|post-content|entry-content|article__body|article-content|story-content)[^"\x27]*["\x27]',
      r'id=["\x27][^"\x27]*(?:story-body|article-body|post-content|main-content)[^"\x27]*["\x27]',
    ];

    for (final pattern in classPatterns) {
      final match = RegExp('<(?:div|section|main)\\b[^>]*$pattern[^>]*>([\\s\\S]*?)</(?:div|section|main)>', caseSensitive: false)
          .firstMatch(html);
      if (match != null) {
        final content = match.group(1)!;
        final pCount = RegExp(r'<p\b[^>]*>', caseSensitive: false).allMatches(content).length;
        if (pCount >= 2) {
          return content;
        }
      }
    }

    return '';
  }

  /// Extracts sequence of paragraphs when no container wrapper exists.
  static String _extractParagraphSequence(String html) {
    final buffer = StringBuffer();
    final pMatches = RegExp(r'<p\b[^>]*>([\s\S]*?)</p>', caseSensitive: false).allMatches(html);

    for (final match in pMatches) {
      final pText = SecurityValidator.extractPlainText(match.group(1)!);
      // Filter out short cookie/disclaimer snippets
      if (pText.length > 35) {
        buffer.writeln('<p>${match.group(1)}</p>');
      }
    }

    return buffer.toString();
  }

  /// Cleans and formats extracted content and resolves relative image/link paths.
  static String _cleanExtractedContent(String content, Uri baseUri) {
    var cleaned = content;

    // Resolve relative img src
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'''(<img\b[^>]*\bsrc=["'])([^"']+)(["'])''', caseSensitive: false),
      (match) {
        final prefix = match.group(1)!;
        final rawSrc = match.group(2)!;
        final suffix = match.group(3)!;
        final resolved = _resolveUrl(rawSrc, baseUri);
        return '$prefix$resolved$suffix';
      },
    );

    // Resolve relative a href
    cleaned = cleaned.replaceAllMapped(
      RegExp(r'''(<a\b[^>]*\bhref=["'])([^"']+)(["'])''', caseSensitive: false),
      (match) {
        final prefix = match.group(1)!;
        final rawHref = match.group(2)!;
        final suffix = match.group(3)!;
        final resolved = _resolveUrl(rawHref, baseUri);
        return '$prefix$resolved$suffix';
      },
    );

    return cleaned;
  }

  /// Resolves relative URLs to absolute HTTP/HTTPS URLs.
  static String _resolveUrl(String relativeUrl, Uri baseUri) {
    final trimmed = relativeUrl.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      return trimmed;
    }
    try {
      final resolved = baseUri.resolve(trimmed);
      return resolved.toString();
    } catch (_) {
      return trimmed;
    }
  }

  /// Disposes underlying HTTP client.
  void dispose() {
    _httpClient.close();
  }
}

