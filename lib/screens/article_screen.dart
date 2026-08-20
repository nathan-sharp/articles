import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../theme/newspaper_theme.dart';
import '../widgets/newspaper_content_view.dart';

/// Screen providing an uninterrupted, distraction-free reading experience for an individual article.
class ArticleScreen extends StatefulWidget {
  final Article article;
  final VoidCallback? onStateChanged;

  const ArticleScreen({
    super.key,
    required this.article,
    this.onStateChanged,
  });

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late Article _currentArticle;

  @override
  void initState() {
    super.initState();
    _currentArticle = widget.article;
    _markAsReadAutomatically();
  }

  Future<void> _markAsReadAutomatically() async {
    if (!_currentArticle.isRead) {
      await DatabaseService.instance.setArticleReadStatus(_currentArticle.id, true);
      setState(() {
        _currentArticle = _currentArticle.copyWith(isRead: true);
      });
      widget.onStateChanged?.call();
    }
  }

  Future<void> _toggleBookmark() async {
    final nextState = !_currentArticle.isBookmarked;
    await DatabaseService.instance.setArticleBookmarkStatus(_currentArticle.id, nextState);
    setState(() {
      _currentArticle = _currentArticle.copyWith(isBookmarked: nextState);
    });
    widget.onStateChanged?.call();
  }

  Future<void> _toggleReadStatus() async {
    final nextState = !_currentArticle.isRead;
    await DatabaseService.instance.setArticleReadStatus(_currentArticle.id, nextState);
    setState(() {
      _currentArticle = _currentArticle.copyWith(isRead: nextState);
    });
    widget.onStateChanged?.call();
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(_currentArticle.link);
    if (uri != null && await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('EEEE, MMMM d, yyyy • HH:mm').format(_currentArticle.publishedDate.toLocal());

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentArticle.feedTitle.toUpperCase(),
          style: const TextStyle(
            fontFamily: NewspaperTheme.monospaceFamily,
            fontSize: 14.0,
            letterSpacing: 2.0,
          ),
        ),
        actions: [
          IconButton(
            tooltip: _currentArticle.isBookmarked ? 'Remove Bookmark' : 'Bookmark Article',
            icon: Icon(
              _currentArticle.isBookmarked ? Icons.bookmark : Icons.bookmark_outline,
              color: _currentArticle.isBookmarked ? NewspaperTheme.editorialAccent : NewspaperTheme.inkBlack,
            ),
            onPressed: _toggleBookmark,
          ),
          IconButton(
            tooltip: _currentArticle.isRead ? 'Mark as Unread' : 'Mark as Read',
            icon: Icon(
              _currentArticle.isRead ? Icons.mark_email_read_outlined : Icons.mark_email_unread,
              color: NewspaperTheme.inkBlack,
            ),
            onPressed: _toggleReadStatus,
          ),
          IconButton(
            tooltip: 'Open in Browser',
            icon: const Icon(Icons.open_in_new, color: NewspaperTheme.inkBlack),
            onPressed: _openInBrowser,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Headline
                Text(
                  _currentArticle.title,
                  style: const TextStyle(
                    fontFamily: NewspaperTheme.serifFamily,
                    fontSize: 28.0,
                    fontWeight: FontWeight.bold,
                    color: NewspaperTheme.inkBlack,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12.0),

                // Byline and Metadata
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _buildBylineString(),
                        style: const TextStyle(
                          fontFamily: NewspaperTheme.monospaceFamily,
                          fontSize: 12.0,
                          color: NewspaperTheme.inkSecondary,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6.0),
                Text(
                  formattedDate,
                  style: const TextStyle(
                    fontFamily: NewspaperTheme.monospaceFamily,
                    fontSize: 11.0,
                    color: NewspaperTheme.inkMuted,
                  ),
                ),
                const SizedBox(height: 16.0),

                // Newspaper Double Rule Divider
                _buildDoubleRule(),
                const SizedBox(height: 20.0),

                // Main Article Content
                NewspaperContentView(
                  content: _currentArticle.content.isNotEmpty
                      ? _currentArticle.content
                      : _currentArticle.summary,
                ),

                const SizedBox(height: 32.0),
                _buildDoubleRule(),
                const SizedBox(height: 20.0),

                // External Source Link Button
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _openInBrowser,
                    icon: const Icon(Icons.open_in_browser, size: 18.0),
                    label: const Text('READ FULL STORY AT ORIGINAL SOURCE ↗'),
                  ),
                ),
                const SizedBox(height: 40.0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _buildBylineString() {
    final parts = <String>[];
    if (_currentArticle.author.isNotEmpty) {
      parts.add('BY ${_currentArticle.author.toUpperCase()}');
    }
    if (_currentArticle.feedTitle.isNotEmpty) {
      parts.add(_currentArticle.feedTitle.toUpperCase());
    }
    return parts.isEmpty ? 'SPECIAL DISPATCH' : parts.join(' | ');
  }

  Widget _buildDoubleRule() {
    return Column(
      children: const [
        Divider(thickness: 2.0, color: NewspaperTheme.ruleLine),
        SizedBox(height: 3.0),
        Divider(thickness: 1.0, color: NewspaperTheme.ruleLine),
      ],
    );
  }
}

