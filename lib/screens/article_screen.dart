import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/models.dart';
import '../services/article_extractor.dart';
import '../services/database_service.dart';
import '../services/tts_service.dart';
import '../theme/newspaper_theme.dart';
import '../widgets/newspaper_content_view.dart';

/// Screen providing an uninterrupted, distraction-free reading experience for an individual article.
class ArticleScreen extends StatefulWidget {
  final Article article;
  final VoidCallback? onStateChanged;
  final ArticleExtractor? extractor;
  final TtsService? ttsService;

  const ArticleScreen({
    super.key,
    required this.article,
    this.onStateChanged,
    this.extractor,
    this.ttsService,
  });

  @override
  State<ArticleScreen> createState() => _ArticleScreenState();
}

class _ArticleScreenState extends State<ArticleScreen> {
  late Article _currentArticle;
  late final ArticleExtractor _extractor;
  late final bool _ownsExtractor;
  late final TtsService _ttsService;
  late final bool _ownsTtsService;
  StreamSubscription<TtsPlaybackState>? _ttsSubscription;
  TtsPlaybackState _ttsState = TtsPlaybackState.stopped;
  bool _isExtracting = false;
  bool _hasExtractedFullText = false;
  String? _extractionError;

  @override
  void initState() {
    super.initState();
    _currentArticle = widget.article;
    _ownsExtractor = widget.extractor == null;
    _extractor = widget.extractor ?? ArticleExtractor();
    _ownsTtsService = widget.ttsService == null;
    _ttsService = widget.ttsService ?? TtsService();
    _ttsState = _ttsService.state;
    _ttsSubscription = _ttsService.stateStream.listen((state) {
      if (mounted) {
        setState(() {
          _ttsState = state;
        });
      }
    });
    _markAsReadAutomatically();

    // If feed only supplied a short teaser (under 400 chars), automatically fetch full article
    final isTeaserOnly = _currentArticle.content.trim().length < 400;
    if (isTeaserOnly && _currentArticle.link.isNotEmpty) {
      _fetchFullStory(silent: true);
    }
  }

  @override
  void dispose() {
    _ttsSubscription?.cancel();
    _ttsService.stop();
    if (_ownsTtsService) {
      _ttsService.dispose();
    }
    if (_ownsExtractor) {
      _extractor.dispose();
    }
    super.dispose();
  }

  Future<void> _markAsReadAutomatically() async {
    if (!_currentArticle.isRead) {
      await DatabaseService.instance.setArticleReadStatus(_currentArticle.id, true);
      if (mounted) {
        setState(() {
          _currentArticle = _currentArticle.copyWith(isRead: true);
        });
      }
      widget.onStateChanged?.call();
    }
  }

  Future<void> _fetchFullStory({bool silent = false}) async {
    if (_isExtracting || _currentArticle.link.isEmpty) return;

    if (!silent) {
      setState(() {
        _isExtracting = true;
        _extractionError = null;
      });
    } else {
      _isExtracting = true;
    }

    try {
      final extracted = await _extractor.extractFromUrl(_currentArticle.link);
      if (extracted.contentHtml.trim().isNotEmpty) {
        await DatabaseService.instance.updateArticleContent(
          _currentArticle.id,
          extracted.contentHtml,
          imageUrl: extracted.leadImageUrl ?? _currentArticle.imageUrl,
        );

        if (mounted) {
          setState(() {
            _currentArticle = _currentArticle.copyWith(
              content: extracted.contentHtml,
              imageUrl: extracted.leadImageUrl ?? _currentArticle.imageUrl,
            );
            _hasExtractedFullText = true;
            _isExtracting = false;
          });
          widget.onStateChanged?.call();
        }
      } else {
        if (mounted) {
          setState(() {
            _isExtracting = false;
            if (!silent) _extractionError = 'Could not isolate main story body.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isExtracting = false;
          if (!silent) _extractionError = 'Extraction failed: ${e.toString()}';
        });
      }
    }
  }

  Future<void> _toggleBookmark() async {
    final nextState = !_currentArticle.isBookmarked;
    await DatabaseService.instance.setArticleBookmarkStatus(_currentArticle.id, nextState);
    if (mounted) {
      setState(() {
        _currentArticle = _currentArticle.copyWith(isBookmarked: nextState);
      });
    }
    widget.onStateChanged?.call();
  }

  Future<void> _toggleReadStatus() async {
    final nextState = !_currentArticle.isRead;
    await DatabaseService.instance.setArticleReadStatus(_currentArticle.id, nextState);
    if (mounted) {
      setState(() {
        _currentArticle = _currentArticle.copyWith(isRead: nextState);
      });
    }
    widget.onStateChanged?.call();
  }

  Future<void> _toggleTts() async {
    if (_ttsState == TtsPlaybackState.playing) {
      await _ttsService.stop();
    } else {
      final contentToSpeak = _currentArticle.content.isNotEmpty
          ? _currentArticle.content
          : _currentArticle.summary;
      await _ttsService.speakArticle(
        title: _currentArticle.title,
        byline: _buildBylineString(),
        contentHtml: contentToSpeak,
      );
    }
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
            tooltip: _ttsState == TtsPlaybackState.playing
                ? 'Stop Reading Aloud'
                : 'Read Article Aloud (On-Device Voice)',
            icon: Icon(
              _ttsState == TtsPlaybackState.playing
                  ? Icons.stop_circle_outlined
                  : Icons.volume_up_outlined,
              color: _ttsState == TtsPlaybackState.playing
                  ? NewspaperTheme.editorialAccent
                  : NewspaperTheme.inkBlack,
            ),
            onPressed: _toggleTts,
          ),
          IconButton(
            tooltip: _isExtracting ? 'Extracting...' : 'Fetch Full Story (Readability Mode)',
            icon: _isExtracting
                ? const SizedBox(
                    width: 18.0,
                    height: 18.0,
                    child: CircularProgressIndicator(strokeWidth: 2.0, color: NewspaperTheme.inkBlack),
                  )
                : const Icon(Icons.auto_stories_outlined, color: NewspaperTheme.inkBlack),
            onPressed: _isExtracting ? null : () => _fetchFullStory(silent: false),
          ),
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
                Row(
                  children: [
                    Text(
                      formattedDate,
                      style: const TextStyle(
                        fontFamily: NewspaperTheme.monospaceFamily,
                        fontSize: 11.0,
                        color: NewspaperTheme.inkMuted,
                      ),
                    ),
                    const Spacer(),
                    if (_hasExtractedFullText) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                        color: NewspaperTheme.inkBlack,
                        child: const Text(
                          'FULL STORY EXTRACTED',
                          style: TextStyle(
                            fontFamily: NewspaperTheme.monospaceFamily,
                            fontSize: 9.0,
                            fontWeight: FontWeight.bold,
                            color: NewspaperTheme.newsprintBackground,
                            letterSpacing: 1.0,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16.0),

                // Newspaper Double Rule Divider
                _buildDoubleRule(),
                const SizedBox(height: 12.0),

                // Extraction Progress or Notification Banner
                if (_isExtracting) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16.0),
                    padding: const EdgeInsets.all(12.0),
                    decoration: BoxDecoration(
                      color: NewspaperTheme.containerAccent,
                      border: Border.all(color: NewspaperTheme.ruleLine, width: 1.0),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 14.0,
                          height: 14.0,
                          child: CircularProgressIndicator(strokeWidth: 2.0, color: NewspaperTheme.inkBlack),
                        ),
                        SizedBox(width: 10.0),
                        Text(
                          'EXTRACTING COMPLETE ARTICLE STORY...',
                          style: TextStyle(
                            fontFamily: NewspaperTheme.monospaceFamily,
                            fontSize: 11.0,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                if (_extractionError != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16.0),
                    padding: const EdgeInsets.all(10.0),
                    decoration: BoxDecoration(
                      color: NewspaperTheme.cardSurface,
                      border: Border.all(color: NewspaperTheme.editorialAccent, width: 1.0),
                    ),
                    child: Text(
                      _extractionError!,
                      style: const TextStyle(
                        fontFamily: NewspaperTheme.monospaceFamily,
                        fontSize: 11.0,
                        color: NewspaperTheme.editorialAccent,
                      ),
                    ),
                  ),
                ],

                // Main Article Content
                NewspaperContentView(
                  content: _currentArticle.content.isNotEmpty
                      ? _currentArticle.content
                      : _currentArticle.summary,
                ),

                const SizedBox(height: 32.0),
                _buildDoubleRule(),
                const SizedBox(height: 20.0),

                // Fetch Full Story Manual Button (if not already full text)
                if (!_hasExtractedFullText && !_isExtracting) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _fetchFullStory(silent: false),
                      icon: const Icon(Icons.auto_stories, size: 16.0),
                      label: const Text('FETCH FULL STORY (READABILITY)'),
                    ),
                  ),
                  const SizedBox(height: 12.0),
                ],

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
