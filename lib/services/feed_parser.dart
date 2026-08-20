import 'package:intl/intl.dart';
import 'package:xml/xml.dart';
import '../models/models.dart';
import 'security_validator.dart';

/// Result object containing parsed feed metadata and its articles.
class ParsedFeedResult {
  final Feed feed;
  final List<Article> articles;

  const ParsedFeedResult({
    required this.feed,
    required this.articles,
  });
}

/// Parser for RSS 2.0, RSS 0.9x, and Atom 1.0 syndication XML feeds.
class FeedParser {
  FeedParser._();

  /// Maximum number of articles parsed per feed to maintain bounded memory execution.
  static const int maxArticlesPerFeed = 100;

  /// Parses an XML string into a [ParsedFeedResult] domain model.
  static ParsedFeedResult parseXml({
    required String xmlContent,
    required String feedUrl,
    String? fallbackFeedId,
  }) {
    final cleanXml = xmlContent.trim();
    if (cleanXml.isEmpty) {
      throw const FormatException('Feed XML content is empty');
    }

    final document = XmlDocument.parse(cleanXml);
    final feedId = fallbackFeedId ?? feedUrl;

    // Detect RSS 2.0 / RSS 0.9x
    final rssNode = document.findAllElements('rss').firstOrNull;
    if (rssNode != null) {
      return _parseRss(document, feedId, feedUrl);
    }

    // Detect RDF (RSS 1.0)
    final rdfNode = document.findAllElements('rdf:RDF').firstOrNull ??
        document.findAllElements('RDF').firstOrNull;
    if (rdfNode != null) {
      return _parseRss(document, feedId, feedUrl);
    }

    // Detect Atom 1.0
    final atomNode = document.findAllElements('feed').firstOrNull;
    if (atomNode != null) {
      return _parseAtom(atomNode, feedId, feedUrl);
    }

    // Fallback attempt for direct channel node
    final channelNode = document.findAllElements('channel').firstOrNull;
    if (channelNode != null) {
      return _parseRss(document, feedId, feedUrl);
    }

    throw const FormatException('Unrecognized syndication feed format');
  }

  /// Parses RSS 2.0 / 0.9x channel and items.
  static ParsedFeedResult _parseRss(
    XmlDocument document,
    String feedId,
    String feedUrl,
  ) {
    final channel = document.findAllElements('channel').firstOrNull;
    if (channel == null) {
      throw const FormatException('Missing RSS <channel> element');
    }

    final feedTitle = _getNodeText(channel, ['title']) ?? 'Untitled Feed';
    final siteUrl = _getNodeText(channel, ['link']) ?? '';
    final feedDesc = _getNodeText(channel, ['description']) ?? '';
    final now = DateTime.now().toUtc();

    final feed = Feed(
      id: feedId,
      title: feedTitle.trim(),
      url: feedUrl,
      siteUrl: siteUrl.trim(),
      description: feedDesc.trim(),
      lastUpdated: now,
    );

    final itemElements = channel.findAllElements('item').take(maxArticlesPerFeed);
    final articles = <Article>[];

    for (final item in itemElements) {
      final article = _parseRssItem(item, feed);
      if (article != null) {
        articles.add(article);
      }
    }

    return ParsedFeedResult(feed: feed, articles: articles);
  }

  /// Parses a single RSS `<item>` node into an [Article].
  static Article? _parseRssItem(XmlElement item, Feed feed) {
    final rawTitle = _getNodeText(item, ['title']) ?? 'Untitled Article';
    final link = _getNodeText(item, ['link']) ?? '';
    final guid = _getNodeText(item, ['guid']) ?? link;

    if (link.isEmpty && guid.isEmpty && rawTitle.isEmpty) {
      return null;
    }

    final author = _getNodeText(item, ['dc:creator', 'author', 'creator']) ?? '';
    final pubDateStr = _getNodeText(item, ['pubDate', 'dc:date', 'date']);
    final publishedDate = _parseDateTime(pubDateStr);

    final rawContent = _getNodeText(item, ['content:encoded', 'content', 'description']) ?? '';
    final rawSummary = _getNodeText(item, ['description', 'summary']) ?? '';

    final sanitizedContent = SecurityValidator.sanitizeHtml(rawContent);
    final plainSummary = SecurityValidator.extractPlainText(rawSummary);

    final imageUrl = _extractImageUrl(item, rawContent);
    final articleId = guid.isNotEmpty ? '${feed.id}_$guid' : '${feed.id}_$link';

    return Article(
      id: articleId,
      feedId: feed.id,
      feedTitle: feed.title,
      title: SecurityValidator.decodeHtmlEntities(rawTitle.trim()),
      link: link.trim(),
      author: SecurityValidator.decodeHtmlEntities(author.trim()),
      publishedDate: publishedDate,
      summary: plainSummary,
      content: sanitizedContent.isNotEmpty ? sanitizedContent : plainSummary,
      imageUrl: imageUrl,
      isRead: false,
      isBookmarked: false,
    );
  }

  /// Parses Atom 1.0 `<feed>` and `<entry>` elements.
  static ParsedFeedResult _parseAtom(
    XmlElement feedNode,
    String feedId,
    String feedUrl,
  ) {
    final feedTitle = _getNodeText(feedNode, ['title']) ?? 'Untitled Feed';
    final siteUrl = _extractAtomLink(feedNode);
    final feedDesc = _getNodeText(feedNode, ['subtitle']) ?? '';
    final now = DateTime.now().toUtc();

    final feed = Feed(
      id: feedId,
      title: feedTitle.trim(),
      url: feedUrl,
      siteUrl: siteUrl,
      description: feedDesc.trim(),
      lastUpdated: now,
    );

    final entryElements = feedNode.findAllElements('entry').take(maxArticlesPerFeed);
    final articles = <Article>[];

    for (final entry in entryElements) {
      final article = _parseAtomEntry(entry, feed);
      if (article != null) {
        articles.add(article);
      }
    }

    return ParsedFeedResult(feed: feed, articles: articles);
  }

  /// Parses a single Atom `<entry>` node into an [Article].
  static Article? _parseAtomEntry(XmlElement entry, Feed feed) {
    final rawTitle = _getNodeText(entry, ['title']) ?? 'Untitled Article';
    final link = _extractAtomLink(entry);
    final id = _getNodeText(entry, ['id']) ?? link;

    if (link.isEmpty && id.isEmpty && rawTitle.isEmpty) {
      return null;
    }

    final author = _extractAtomAuthor(entry);
    final pubDateStr = _getNodeText(entry, ['published', 'updated', 'dc:date']);
    final publishedDate = _parseDateTime(pubDateStr);

    final rawContent = _getNodeText(entry, ['content']) ?? '';
    final rawSummary = _getNodeText(entry, ['summary']) ?? '';

    final sanitizedContent = SecurityValidator.sanitizeHtml(
      rawContent.isNotEmpty ? rawContent : rawSummary,
    );
    final plainSummary = SecurityValidator.extractPlainText(
      rawSummary.isNotEmpty ? rawSummary : rawContent,
    );

    final imageUrl = _extractImageUrl(entry, rawContent.isNotEmpty ? rawContent : rawSummary);
    final articleId = id.isNotEmpty ? '${feed.id}_$id' : '${feed.id}_$link';

    return Article(
      id: articleId,
      feedId: feed.id,
      feedTitle: feed.title,
      title: SecurityValidator.decodeHtmlEntities(rawTitle.trim()),
      link: link.trim(),
      author: SecurityValidator.decodeHtmlEntities(author.trim()),
      publishedDate: publishedDate,
      summary: plainSummary,
      content: sanitizedContent.isNotEmpty ? sanitizedContent : plainSummary,
      imageUrl: imageUrl,
      isRead: false,
      isBookmarked: false,
    );
  }

  /// Extracts Atom link prioritizing alternate/HTML rel types.
  static String _extractAtomLink(XmlElement element) {
    final links = element.findElements('link');
    for (final link in links) {
      final rel = link.getAttribute('rel');
      final href = link.getAttribute('href');
      if (href != null && href.isNotEmpty) {
        if (rel == null || rel == 'alternate' || rel == '') {
          return href;
        }
      }
    }
    // Fallback to first href found
    for (final link in links) {
      final href = link.getAttribute('href');
      if (href != null && href.isNotEmpty) {
        return href;
      }
    }
    return '';
  }

  /// Extracts Atom author name.
  static String _extractAtomAuthor(XmlElement entry) {
    final authorNode = entry.findElements('author').firstOrNull;
    if (authorNode != null) {
      final name = _getNodeText(authorNode, ['name']);
      if (name != null && name.isNotEmpty) {
        return name;
      }
    }
    return '';
  }

  /// Extracts image URL from enclosures, media tags, or inline HTML.
  static String? _extractImageUrl(XmlElement element, String rawHtml) {
    // 1. Enclosure tag
    for (final enc in element.findElements('enclosure')) {
      final type = enc.getAttribute('type') ?? '';
      final url = enc.getAttribute('url');
      if (url != null && (type.startsWith('image/') || url.endsWith('.jpg') || url.endsWith('.png') || url.endsWith('.webp'))) {
        return url;
      }
    }

    // 2. Media content / thumbnail
    for (final media in element.findElements('media:content')) {
      final url = media.getAttribute('url');
      if (url != null && url.isNotEmpty) {
        return url;
      }
    }
    for (final thumb in element.findElements('media:thumbnail')) {
      final url = thumb.getAttribute('url');
      if (url != null && url.isNotEmpty) {
        return url;
      }
    }

    // 3. First img src tag inside HTML
    if (rawHtml.isNotEmpty) {
      final match = RegExp(r'''<img\b[^>]*\bsrc\s*=\s*['"]([^'"]+)['"]''', caseSensitive: false).firstMatch(rawHtml);
      if (match != null) {
        final src = match.group(1);
        if (src != null && src.startsWith('http')) {
          return src;
        }
      }
    }

    return null;
  }

  /// Retrieves text content from the first matching element name.
  static String? _getNodeText(XmlElement parent, List<String> nodeNames) {
    for (final name in nodeNames) {
      final element = parent.findElements(name).firstOrNull;
      if (element != null) {
        return element.innerText;
      }
    }
    return null;
  }

  /// Parses date-time strings conforming to RFC 822, RFC 1123, or ISO 8601.
  static DateTime _parseDateTime(String? dateStr) {
    if (dateStr == null || dateStr.trim().isEmpty) {
      return DateTime.now().toUtc();
    }

    final trimmed = dateStr.trim();

    // 1. Standard ISO 8601 parsing
    try {
      return DateTime.parse(trimmed).toUtc();
    } catch (_) {}

    // 2. RFC 822 / RFC 1123 formats
    final rfcFormats = [
      'EEE, dd MMM yyyy HH:mm:ss Z',
      'EEE, dd MMM yyyy HH:mm:ss zzz',
      'dd MMM yyyy HH:mm:ss Z',
      'EEE, dd MMM yy HH:mm:ss Z',
      'yyyy-MM-ddTHH:mm:ssZ',
      'yyyy-MM-dd HH:mm:ss',
    ];

    for (final formatStr in rfcFormats) {
      try {
        final format = DateFormat(formatStr, 'en_US');
        return format.parse(trimmed, true).toUtc();
      } catch (_) {}
    }

    return DateTime.now().toUtc();
  }
}

