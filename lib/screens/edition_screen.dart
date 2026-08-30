import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/edition_service.dart';
import '../services/tts_service.dart';
import '../theme/newspaper_theme.dart';
import '../widgets/newspaper_content_view.dart';

/// Full-screen reading screen displaying on-device synthesized newspaper editions.
class EditionScreen extends StatefulWidget {
  final EditorialEdition edition;
  final EditionService editionService;
  final VoidCallback? onStateChanged;
  final TtsService? ttsService;

  const EditionScreen({
    super.key,
    required this.edition,
    required this.editionService,
    this.onStateChanged,
    this.ttsService,
  });

  @override
  State<EditionScreen> createState() => _EditionScreenState();
}

class _EditionScreenState extends State<EditionScreen> {
  late EditorialEdition _currentEdition;
  late final TtsService _ttsService;
  late final bool _ownsTtsService;
  StreamSubscription<TtsPlaybackState>? _ttsSubscription;
  TtsPlaybackState _ttsState = TtsPlaybackState.stopped;
  bool _isRegenerating = false;

  @override
  void initState() {
    super.initState();
    _currentEdition = widget.edition;
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
  }

  @override
  void dispose() {
    _ttsSubscription?.cancel();
    _ttsService.stop();
    if (_ownsTtsService) {
      _ttsService.dispose();
    }
    super.dispose();
  }

  Future<void> _markAsReadAutomatically() async {
    if (!_currentEdition.isRead) {
      await widget.editionService.markEditionAsRead(_currentEdition.id);
      if (mounted) {
        setState(() {
          _currentEdition = _currentEdition.copyWith(isRead: true);
        });
      }
      widget.onStateChanged?.call();
    }
  }

  Future<void> _regenerateEdition() async {
    if (_isRegenerating) return;

    setState(() => _isRegenerating = true);

    try {
      final updated = await widget.editionService.forceRegenerateEdition(_currentEdition.type);
      if (mounted) {
        setState(() {
          _currentEdition = updated;
          _isRegenerating = false;
        });
        widget.onStateChanged?.call();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_currentEdition.type.displayName} successfully re-synthesized on-device.',
              style: const TextStyle(fontFamily: NewspaperTheme.monospaceFamily),
            ),
            backgroundColor: NewspaperTheme.inkBlack,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRegenerating = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Re-synthesis failed: ${e.toString()}',
              style: const TextStyle(fontFamily: NewspaperTheme.monospaceFamily),
            ),
            backgroundColor: NewspaperTheme.editorialAccent,
          ),
        );
      }
    }
  }

  Future<void> _toggleTts() async {
    if (_ttsState == TtsPlaybackState.playing) {
      await _ttsService.stop();
    } else {
      await _ttsService.speakArticle(
        title: _currentEdition.title,
        byline: '${_currentEdition.type.displayName.toUpperCase()} • ON-DEVICE AI SYNTHESIS',
        contentHtml: _currentEdition.contentHtml,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final formattedDate = DateFormat('EEEE, MMMM d, yyyy • HH:mm').format(_currentEdition.generatedAt.toLocal());

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _currentEdition.type.displayName.toUpperCase(),
          style: const TextStyle(
            fontFamily: NewspaperTheme.monospaceFamily,
            fontSize: 13.0,
            letterSpacing: 2.0,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          IconButton(
            tooltip: _ttsState == TtsPlaybackState.playing
                ? 'Stop Reading Aloud'
                : 'Read Edition Aloud (On-Device Voice)',
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
            tooltip: _isRegenerating ? 'Synthesizing...' : 'Regenerate Edition (On-Device AI)',
            icon: _isRegenerating
                ? const SizedBox(
                    width: 18.0,
                    height: 18.0,
                    child: CircularProgressIndicator(strokeWidth: 2.0, color: NewspaperTheme.inkBlack),
                  )
                : const Icon(Icons.refresh, color: NewspaperTheme.inkBlack),
            onPressed: _isRegenerating ? null : _regenerateEdition,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 760.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Masthead Badge
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8.0,
                  runSpacing: 6.0,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 3.0),
                      color: NewspaperTheme.inkBlack,
                      child: const Text(
                        'ON-DEVICE AI SYNTHESIS • 100% PRIVATE',
                        style: TextStyle(
                          fontFamily: NewspaperTheme.monospaceFamily,
                          fontSize: 10.0,
                          fontWeight: FontWeight.bold,
                          color: NewspaperTheme.newsprintBackground,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                    Text(
                      formattedDate,
                      style: const TextStyle(
                        fontFamily: NewspaperTheme.monospaceFamily,
                        fontSize: 11.0,
                        color: NewspaperTheme.inkMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14.0),

                // Main Title
                Text(
                  _currentEdition.title,
                  style: const TextStyle(
                    fontFamily: NewspaperTheme.serifFamily,
                    fontSize: 26.0,
                    fontWeight: FontWeight.bold,
                    color: NewspaperTheme.inkBlack,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 8.0),

                // Subtitle
                if (_currentEdition.subtitle.isNotEmpty) ...[
                  Text(
                    _currentEdition.subtitle,
                    style: const TextStyle(
                      fontFamily: NewspaperTheme.monospaceFamily,
                      fontSize: 12.0,
                      color: NewspaperTheme.inkSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 12.0),
                ],

                // Double Rule Line
                _buildDoubleRule(),
                const SizedBox(height: 16.0),

                // Main Content Body
                NewspaperContentView(
                  content: _currentEdition.contentHtml,
                ),

                const SizedBox(height: 32.0),
                _buildDoubleRule(),
                const SizedBox(height: 24.0),

                // Footer Action
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isRegenerating ? null : _regenerateEdition,
                    icon: const Icon(Icons.auto_awesome, size: 16.0),
                    label: const Text('RE-SYNTHESIZE THIS EDITION (ON-DEVICE AI)'),
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
