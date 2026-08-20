import 'package:intl/intl.dart';
import 'package:xml/xml.dart';
import '../models/models.dart';
import 'security_validator.dart';

/// Representation of a feed entry parsed from an OPML outline node.
class OpmlFeedEntry {
  final String title;
  final String xmlUrl;
  final String htmlUrl;
  final String category;

  const OpmlFeedEntry({
    required this.title,
    required this.xmlUrl,
    this.htmlUrl = '',
    this.category = 'General',
  });
}

/// Service for importing and exporting subscriptions using OPML (Outline Processor Markup Language) 2.0.
class OpmlService {
  OpmlService._();

  /// Generates an OPML 2.0 XML string from a list of [Feed] instances.
  static String exportToOpml(List<Feed> feeds, {String title = 'Articles Subscriptions'}) {
    final builder = XmlBuilder();
    builder.processing('xml', 'version="1.0" encoding="UTF-8"');
    builder.element('opml', attributes: {'version': '2.0'}, nest: () {
      builder.element('head', nest: () {
        builder.element('title', nest: () => builder.text(title));
        builder.element(
          'dateCreated',
          nest: () => builder.text(DateFormat('EEE, dd MMM yyyy HH:mm:ss Z').format(DateTime.now().toUtc())),
        );
        builder.element('docs', nest: () => builder.text('http://opml.org/spec2.opml'));
      });

      builder.element('body', nest: () {
        // Group feeds by category
        final categoryMap = <String, List<Feed>>{};
        for (final feed in feeds) {
          final cat = feed.category.isEmpty ? 'General' : feed.category;
          categoryMap.putIfAbsent(cat, () => []).add(feed);
        }

        for (final entry in categoryMap.entries) {
          final categoryName = entry.key;
          final categoryFeeds = entry.value;

          if (categoryName == 'General' && categoryMap.length == 1) {
            // Flat export if only default category
            for (final feed in categoryFeeds) {
              _buildOutlineNode(builder, feed);
            }
          } else {
            // Grouped folder outline
            builder.element('outline', attributes: {'text': categoryName, 'title': categoryName}, nest: () {
              for (final feed in categoryFeeds) {
                _buildOutlineNode(builder, feed);
              }
            });
          }
        }
      });
    });

    return builder.buildDocument().toXmlString(pretty: true);
  }

  /// Builds a leaf outline node for a feed.
  static void _buildOutlineNode(XmlBuilder builder, Feed feed) {
    final attributes = <String, String>{
      'type': 'rss',
      'text': feed.title,
      'title': feed.title,
      'xmlUrl': feed.url,
    };
    if (feed.siteUrl.isNotEmpty) {
      attributes['htmlUrl'] = feed.siteUrl;
    }
    if (feed.description.isNotEmpty) {
      attributes['description'] = feed.description;
    }
    if (feed.category.isNotEmpty) {
      attributes['category'] = feed.category;
    }

    builder.element('outline', attributes: attributes);
  }

  /// Parses an OPML XML string and extracts all valid feed entries.
  static List<OpmlFeedEntry> importFromOpml(String opmlContent) {
    final cleanXml = opmlContent.trim();
    if (cleanXml.isEmpty) {
      throw const FormatException('OPML content is empty');
    }

    final document = XmlDocument.parse(cleanXml);
    final opmlNode = document.findAllElements('opml').firstOrNull;
    if (opmlNode == null) {
      throw const FormatException('Invalid OPML document: missing <opml> root element');
    }

    final entries = <OpmlFeedEntry>[];
    final body = opmlNode.findAllElements('body').firstOrNull;
    if (body == null) {
      return entries;
    }

    _extractOutlines(body, 'General', entries);

    return entries;
  }

  /// Recursively extracts feed outline nodes from OPML hierarchy.
  static void _extractOutlines(
    XmlElement parent,
    String currentCategory,
    List<OpmlFeedEntry> entries,
  ) {
    for (final node in parent.children.whereType<XmlElement>()) {
      if (node.name.local == 'outline') {
        final xmlUrl = node.getAttribute('xmlUrl') ?? node.getAttribute('url') ?? '';
        final title = node.getAttribute('title') ?? node.getAttribute('text') ?? 'Untitled Feed';
        final htmlUrl = node.getAttribute('htmlUrl') ?? '';
        final nodeCategory = node.getAttribute('category');

        if (xmlUrl.isNotEmpty && SecurityValidator.isValidFeedUrl(xmlUrl)) {
          // Leaf feed node
          entries.add(OpmlFeedEntry(
            title: SecurityValidator.decodeHtmlEntities(title),
            xmlUrl: xmlUrl.trim(),
            htmlUrl: htmlUrl.trim(),
            category: nodeCategory ?? currentCategory,
          ));
        } else {
          // Folder node
          final folderName = node.getAttribute('text') ?? node.getAttribute('title') ?? currentCategory;
          _extractOutlines(node, folderName, entries);
        }
      }
    }
  }
}

