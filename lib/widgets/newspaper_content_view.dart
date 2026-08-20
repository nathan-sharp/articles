import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/security_validator.dart';
import '../theme/newspaper_theme.dart';

/// Renders sanitized HTML and rich text articles in newspaper typography layout.
class NewspaperContentView extends StatelessWidget {
  final String content;

  const NewspaperContentView({
    super.key,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    if (content.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final sanitized = SecurityValidator.sanitizeHtml(content);
    final blocks = _parseHtmlIntoBlocks(sanitized);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: blocks.map((block) => _buildBlockWidget(context, block)).toList(),
    );
  }

  /// Breaks sanitized HTML string into structured logical blocks.
  List<_ContentBlock> _parseHtmlIntoBlocks(String html) {
    final blocks = <_ContentBlock>[];

    // Normalize break tags to paragraph splits
    final normalized = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .trim();

    // Regex to detect block-level HTML tags
    final blockRegex = RegExp(
      r'<(p|h1|h2|h3|h4|h5|h6|blockquote|pre|ul|ol|figure|div)\b[^>]*>([\s\S]*?)</\1>|<img\b[^>]*>',
      caseSensitive: false,
    );

    var lastEnd = 0;
    for (final match in blockRegex.allMatches(normalized)) {
      if (match.start > lastEnd) {
        final textBetween = normalized.substring(lastEnd, match.start).trim();
        if (textBetween.isNotEmpty) {
          blocks.add(_ContentBlock(type: _BlockType.paragraph, htmlContent: textBetween));
        }
      }

      final fullMatch = match.group(0)!;
      final tagName = match.group(1)?.toLowerCase();

      if (fullMatch.startsWith('<img') || tagName == 'figure') {
        final srcMatch = RegExp(r'''src\s*=\s*['"]([^'"]+)['"]''', caseSensitive: false).firstMatch(fullMatch);
        final altMatch = RegExp(r'''alt\s*=\s*['"]([^'"]*)['"]''', caseSensitive: false).firstMatch(fullMatch);
        if (srcMatch != null) {
          blocks.add(_ContentBlock(
            type: _BlockType.image,
            htmlContent: srcMatch.group(1)!,
            extraText: altMatch?.group(1),
          ));
        }
      } else if (tagName == 'h1' || tagName == 'h2' || tagName == 'h3') {
        blocks.add(_ContentBlock(type: _BlockType.heading, htmlContent: match.group(2)!));
      } else if (tagName == 'blockquote') {
        blocks.add(_ContentBlock(type: _BlockType.blockquote, htmlContent: match.group(2)!));
      } else if (tagName == 'pre') {
        blocks.add(_ContentBlock(type: _BlockType.code, htmlContent: match.group(2)!));
      } else if (tagName == 'ul' || tagName == 'ol') {
        blocks.add(_ContentBlock(type: _BlockType.list, htmlContent: match.group(2)!));
      } else {
        blocks.add(_ContentBlock(type: _BlockType.paragraph, htmlContent: match.group(2) ?? ''));
      }

      lastEnd = match.end;
    }

    if (lastEnd < normalized.length) {
      final remaining = normalized.substring(lastEnd).trim();
      if (remaining.isNotEmpty) {
        blocks.add(_ContentBlock(type: _BlockType.paragraph, htmlContent: remaining));
      }
    }

    // If no HTML tags were detected, treat the entire string as plain paragraphs
    if (blocks.isEmpty && normalized.isNotEmpty) {
      final paragraphs = normalized.split(RegExp(r'\n\s*\n'));
      for (final p in paragraphs) {
        if (p.trim().isNotEmpty) {
          blocks.add(_ContentBlock(type: _BlockType.paragraph, htmlContent: p.trim()));
        }
      }
    }

    return blocks;
  }

  /// Builds a Flutter Widget corresponding to a content block type.
  Widget _buildBlockWidget(BuildContext context, _ContentBlock block) {
    switch (block.type) {
      case _BlockType.heading:
        final text = SecurityValidator.extractPlainText(block.htmlContent);
        return Padding(
          padding: const EdgeInsets.only(top: 20.0, bottom: 8.0),
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: NewspaperTheme.serifFamily,
              fontSize: 20.0,
              fontWeight: FontWeight.bold,
              color: NewspaperTheme.inkBlack,
            ),
          ),
        );

      case _BlockType.blockquote:
        final text = SecurityValidator.extractPlainText(block.htmlContent);
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 14.0),
          padding: const EdgeInsets.only(left: 14.0, top: 4.0, bottom: 4.0),
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: NewspaperTheme.inkBlack, width: 3.0),
            ),
          ),
          child: Text(
            text,
            style: const TextStyle(
              fontFamily: NewspaperTheme.serifFamily,
              fontSize: 16.0,
              fontStyle: FontStyle.italic,
              color: NewspaperTheme.inkSecondary,
              height: 1.5,
            ),
          ),
        );

      case _BlockType.code:
        final text = SecurityValidator.extractPlainText(block.htmlContent);
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 12.0),
          padding: const EdgeInsets.all(12.0),
          decoration: BoxDecoration(
            color: NewspaperTheme.containerAccent,
            border: Border.all(color: NewspaperTheme.ruleLine, width: 1.0),
          ),
          child: SelectableText(
            text,
            style: const TextStyle(
              fontFamily: NewspaperTheme.monospaceFamily,
              fontSize: 13.0,
              color: NewspaperTheme.inkBlack,
            ),
          ),
        );

      case _BlockType.list:
        final items = _extractListItems(block.htmlContent);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: items.map((itemText) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 6.0, left: 8.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('■ ', style: TextStyle(fontSize: 10.0, color: NewspaperTheme.inkBlack, height: 1.6)),
                    Expanded(
                      child: Text(
                        itemText,
                        style: const TextStyle(
                          fontFamily: NewspaperTheme.serifFamily,
                          fontSize: 15.0,
                          color: NewspaperTheme.inkBlack,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );

      case _BlockType.image:
        final imageUrl = block.htmlContent.trim();
        final caption = block.extraText;
        if (!imageUrl.startsWith('http://') && !imageUrl.startsWith('https://')) {
          return const SizedBox.shrink();
        }

        return Container(
          margin: const EdgeInsets.symmetric(vertical: 16.0),
          decoration: BoxDecoration(
            border: Border.all(color: NewspaperTheme.ruleLine, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Image.network(
                imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  padding: const EdgeInsets.all(16.0),
                  color: NewspaperTheme.containerAccent,
                  child: const Center(
                    child: Text(
                      '[ Image could not be loaded ]',
                      style: TextStyle(
                        fontFamily: NewspaperTheme.monospaceFamily,
                        fontSize: 12.0,
                        color: NewspaperTheme.inkSecondary,
                      ),
                    ),
                  ),
                ),
              ),
              if (caption != null && caption.trim().isNotEmpty) ...[
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: NewspaperTheme.ruleLine, width: 1.0)),
                  ),
                  child: Text(
                    caption.trim(),
                    style: const TextStyle(
                      fontFamily: NewspaperTheme.monospaceFamily,
                      fontSize: 11.0,
                      color: NewspaperTheme.inkSecondary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        );

      case _BlockType.paragraph:
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: _buildRichParagraph(context, block.htmlContent),
        );
    }
  }

  /// Builds an inline rich paragraph with support for links, bold, italics, and plain text.
  Widget _buildRichParagraph(BuildContext context, String html) {
    final spans = <InlineSpan>[];
    final inlineRegex = RegExp(
      r'<a\b[^>]*href=["\x27]([^"\x27]+)["\x27][^>]*>([\s\S]*?)</a>|<strong>([\s\S]*?)</strong>|<b>([\s\S]*?)</b>|<em>([\s\S]*?)</em>|<i>([\s\S]*?)</i>',
      caseSensitive: false,
    );

    var lastEnd = 0;
    for (final match in inlineRegex.allMatches(html)) {
      if (match.start > lastEnd) {
        final textBefore = html.substring(lastEnd, match.start);
        spans.add(TextSpan(
          text: SecurityValidator.decodeHtmlEntities(SecurityValidator.extractPlainText(textBefore)),
          style: const TextStyle(
            fontFamily: NewspaperTheme.serifFamily,
            fontSize: 16.0,
            color: NewspaperTheme.inkBlack,
            height: 1.6,
          ),
        ));
      }

      final href = match.group(1);
      final linkText = match.group(2);
      final strongText = match.group(3) ?? match.group(4);
      final emText = match.group(5) ?? match.group(6);

      if (href != null && linkText != null) {
        spans.add(TextSpan(
          text: SecurityValidator.decodeHtmlEntities(SecurityValidator.extractPlainText(linkText)),
          style: const TextStyle(
            fontFamily: NewspaperTheme.serifFamily,
            fontSize: 16.0,
            color: NewspaperTheme.editorialAccent,
            decoration: TextDecoration.underline,
            fontWeight: FontWeight.bold,
          ),
          recognizer: TapGestureRecognizer()
            ..onTap = () async {
              final uri = Uri.tryParse(href);
              if (uri != null && await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
        ));
      } else if (strongText != null) {
        spans.add(TextSpan(
          text: SecurityValidator.decodeHtmlEntities(SecurityValidator.extractPlainText(strongText)),
          style: const TextStyle(
            fontFamily: NewspaperTheme.serifFamily,
            fontSize: 16.0,
            fontWeight: FontWeight.bold,
            color: NewspaperTheme.inkBlack,
          ),
        ));
      } else if (emText != null) {
        spans.add(TextSpan(
          text: SecurityValidator.decodeHtmlEntities(SecurityValidator.extractPlainText(emText)),
          style: const TextStyle(
            fontFamily: NewspaperTheme.serifFamily,
            fontSize: 16.0,
            fontStyle: FontStyle.italic,
            color: NewspaperTheme.inkBlack,
          ),
        ));
      }

      lastEnd = match.end;
    }

    if (lastEnd < html.length) {
      final remaining = html.substring(lastEnd);
      spans.add(TextSpan(
        text: SecurityValidator.decodeHtmlEntities(SecurityValidator.extractPlainText(remaining)),
        style: const TextStyle(
          fontFamily: NewspaperTheme.serifFamily,
          fontSize: 16.0,
          color: NewspaperTheme.inkBlack,
          height: 1.6,
        ),
      ));
    }

    return SelectableText.rich(
      TextSpan(children: spans),
      style: const TextStyle(
        fontFamily: NewspaperTheme.serifFamily,
        fontSize: 16.0,
        color: NewspaperTheme.inkBlack,
        height: 1.6,
      ),
    );
  }

  List<String> _extractListItems(String html) {
    final items = <String>[];
    final itemRegex = RegExp(r'<li\b[^>]*>([\s\S]*?)</li>', caseSensitive: false);
    for (final match in itemRegex.allMatches(html)) {
      final text = SecurityValidator.extractPlainText(match.group(1)!);
      if (text.isNotEmpty) {
        items.add(text);
      }
    }
    if (items.isEmpty) {
      final plain = SecurityValidator.extractPlainText(html);
      if (plain.isNotEmpty) {
        items.add(plain);
      }
    }
    return items;
  }
}

enum _BlockType {
  paragraph,
  heading,
  blockquote,
  code,
  list,
  image,
}

class _ContentBlock {
  final _BlockType type;
  final String htmlContent;
  final String? extraText;

  const _ContentBlock({
    required this.type,
    required this.htmlContent,
    this.extraText,
  });
}
