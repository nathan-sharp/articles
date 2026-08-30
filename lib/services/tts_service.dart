import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'security_validator.dart';

/// Represents the playback state of the Text-to-Speech (TTS) engine.
enum TtsPlaybackState {
  stopped,
  playing,
  paused,
}

/// Abstract contract for the platform Text-to-Speech engine.
///
/// Enables dependency injection and deterministic unit testing without hardware.
abstract class TtsPlatformEngine {
  Future<dynamic> speak(String text);
  Future<dynamic> stop();
  Future<dynamic> pause();
  Future<dynamic> setLanguage(String language);
  Future<dynamic> setSpeechRate(double rate);
  Future<dynamic> setVolume(double volume);
  Future<dynamic> setPitch(double pitch);
  void setStartHandler(void Function() callback);
  void setCompletionHandler(void Function() callback);
  void setErrorHandler(void Function(dynamic message) callback);
  void setCancelHandler(void Function() callback);
  void setPauseHandler(void Function() callback);
  void setContinueHandler(void Function() callback);
}

/// Default implementation delegating to the native FlutterTts platform plugin.
class DefaultFlutterTtsEngine implements TtsPlatformEngine {
  final FlutterTts _flutterTts;

  DefaultFlutterTtsEngine([FlutterTts? flutterTts])
      : _flutterTts = flutterTts ?? FlutterTts();

  @override
  Future<dynamic> speak(String text) => _flutterTts.speak(text);

  @override
  Future<dynamic> stop() => _flutterTts.stop();

  @override
  Future<dynamic> pause() => _flutterTts.pause();

  @override
  Future<dynamic> setLanguage(String language) => _flutterTts.setLanguage(language);

  @override
  Future<dynamic> setSpeechRate(double rate) => _flutterTts.setSpeechRate(rate);

  @override
  Future<dynamic> setVolume(double volume) => _flutterTts.setVolume(volume);

  @override
  Future<dynamic> setPitch(double pitch) => _flutterTts.setPitch(pitch);

  @override
  void setStartHandler(void Function() callback) => _flutterTts.setStartHandler(callback);

  @override
  void setCompletionHandler(void Function() callback) => _flutterTts.setCompletionHandler(callback);

  @override
  void setErrorHandler(void Function(dynamic message) callback) => _flutterTts.setErrorHandler(callback);

  @override
  void setCancelHandler(void Function() callback) => _flutterTts.setCancelHandler(callback);

  @override
  void setPauseHandler(void Function() callback) => _flutterTts.setPauseHandler(callback);

  @override
  void setContinueHandler(void Function() callback) => _flutterTts.setContinueHandler(callback);
}

/// Service providing on-device speech synthesis for articles.
///
/// Guarantees zero network calls by using native local platform TTS engines.
class TtsService {
  static const int maxChunkCharacterLength = 1500;
  static const int maxTotalChunks = 500;

  final TtsPlatformEngine _engine;
  final StreamController<TtsPlaybackState> _stateController =
      StreamController<TtsPlaybackState>.broadcast();

  TtsPlaybackState _state = TtsPlaybackState.stopped;
  List<String> _currentChunks = const [];
  int _currentChunkIndex = 0;
  bool _isDisposed = false;

  TtsService({TtsPlatformEngine? engine})
      : _engine = engine ?? DefaultFlutterTtsEngine() {
    _registerEngineCallbacks();
  }

  /// Current playback state.
  TtsPlaybackState get state => _state;

  /// Stream of playback state changes.
  Stream<TtsPlaybackState> get stateStream => _stateController.stream;

  /// Indicates if the service is currently synthesizing or playing speech.
  bool get isPlaying => _state == TtsPlaybackState.playing;

  void _registerEngineCallbacks() {
    _engine.setStartHandler(() {
      if (_isDisposed) return;
      _updateState(TtsPlaybackState.playing);
    });

    _engine.setCompletionHandler(() {
      if (_isDisposed) return;
      _handleChunkCompletion();
    });

    _engine.setErrorHandler((dynamic message) {
      if (_isDisposed) return;
      debugPrint('TTS synthesis error: $message');
      _stopInternal();
    });

    _engine.setCancelHandler(() {
      if (_isDisposed) return;
      _updateState(TtsPlaybackState.stopped);
    });

    _engine.setPauseHandler(() {
      if (_isDisposed) return;
      _updateState(TtsPlaybackState.paused);
    });

    _engine.setContinueHandler(() {
      if (_isDisposed) return;
      _updateState(TtsPlaybackState.playing);
    });
  }

  void _updateState(TtsPlaybackState newState) {
    if (_state != newState && !_isDisposed) {
      _state = newState;
      _stateController.add(_state);
    }
  }

  /// Synthesizes an article into speech on the local device.
  ///
  /// Extracts plain text from the title, optional byline, and body HTML.
  Future<void> speakArticle({
    required String title,
    String? byline,
    required String contentHtml,
  }) async {
    assert(title.isNotEmpty || contentHtml.isNotEmpty, 'Cannot speak an empty article.');
    if (_isDisposed) return;

    final preparedText = prepareArticleSpeechText(
      title: title,
      byline: byline,
      contentHtml: contentHtml,
    );

    if (preparedText.trim().isEmpty) {
      await stop();
      return;
    }

    _currentChunks = chunkText(preparedText, maxChunkSize: maxChunkCharacterLength);
    _currentChunkIndex = 0;

    if (_currentChunks.isEmpty) {
      await stop();
      return;
    }

    _updateState(TtsPlaybackState.playing);
    await _speakCurrentChunk();
  }

  Future<void> _speakCurrentChunk() async {
    if (_isDisposed || _state != TtsPlaybackState.playing) return;
    if (_currentChunkIndex >= _currentChunks.length) {
      _stopInternal();
      return;
    }

    final chunk = _currentChunks[_currentChunkIndex];
    await _engine.speak(chunk);
  }

  void _handleChunkCompletion() {
    if (_state != TtsPlaybackState.playing || _isDisposed) return;

    _currentChunkIndex++;
    if (_currentChunkIndex < _currentChunks.length) {
      _speakCurrentChunk();
    } else {
      _stopInternal();
    }
  }

  /// Halts speech synthesis immediately and resets playback position.
  Future<void> stop() async {
    if (_isDisposed) return;
    await _engine.stop();
    _stopInternal();
  }

  void _stopInternal() {
    _currentChunks = const [];
    _currentChunkIndex = 0;
    _updateState(TtsPlaybackState.stopped);
  }

  /// Releases audio engine handles and closes stream listeners.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _engine.stop();
    _stateController.close();
  }

  /// Combines title, byline, and content HTML into sanitized plain text for speech.
  static String prepareArticleSpeechText({
    required String title,
    String? byline,
    required String contentHtml,
  }) {
    final buffer = StringBuffer();
    final cleanTitle = SecurityValidator.extractPlainText(title).trim();
    if (cleanTitle.isNotEmpty) {
      buffer.writeln(cleanTitle);
      buffer.writeln();
    }

    if (byline != null) {
      final cleanByline = SecurityValidator.extractPlainText(byline).trim();
      if (cleanByline.isNotEmpty) {
        buffer.writeln(cleanByline);
        buffer.writeln();
      }
    }

    final cleanBody = SecurityValidator.extractPlainText(contentHtml).trim();
    if (cleanBody.isNotEmpty) {
      buffer.writeln(cleanBody);
    }

    return buffer.toString().trim();
  }

  /// Splits long text into bounded chunks along sentence and paragraph boundaries.
  static List<String> chunkText(
    String fullText, {
    int maxChunkSize = maxChunkCharacterLength,
  }) {
    final trimmed = fullText.trim();
    if (trimmed.isEmpty) return const [];
    if (trimmed.length <= maxChunkSize) return [trimmed];

    final chunks = <String>[];
    final paragraphs = trimmed.split(RegExp(r'\n+'));
    final currentChunk = StringBuffer();

    for (var i = 0; i < paragraphs.length && chunks.length < maxTotalChunks; i++) {
      final paragraph = paragraphs[i].trim();
      if (paragraph.isEmpty) continue;

      if (paragraph.length > maxChunkSize) {
        if (currentChunk.isNotEmpty) {
          chunks.add(currentChunk.toString().trim());
          currentChunk.clear();
        }

        final sentenceChunks = _splitIntoSentences(paragraph, maxChunkSize);
        for (var j = 0; j < sentenceChunks.length && chunks.length < maxTotalChunks; j++) {
          chunks.add(sentenceChunks[j]);
        }
      } else if (currentChunk.length + paragraph.length + 1 > maxChunkSize) {
        chunks.add(currentChunk.toString().trim());
        currentChunk.clear();
        currentChunk.write(paragraph);
      } else {
        if (currentChunk.isNotEmpty) {
          currentChunk.write('\n');
        }
        currentChunk.write(paragraph);
      }
    }

    if (currentChunk.isNotEmpty && chunks.length < maxTotalChunks) {
      chunks.add(currentChunk.toString().trim());
    }

    return chunks;
  }

  static List<String> _splitIntoSentences(String text, int maxChunkSize) {
    final result = <String>[];
    final sentencePattern = RegExp(r'(?<=[.!?])\s+');
    final sentences = text.split(sentencePattern);
    final buffer = StringBuffer();

    for (var i = 0; i < sentences.length && result.length < maxTotalChunks; i++) {
      final sentence = sentences[i].trim();
      if (sentence.isEmpty) continue;

      if (sentence.length > maxChunkSize) {
        if (buffer.isNotEmpty) {
          result.add(buffer.toString().trim());
          buffer.clear();
        }
        // Force split oversized sentence by character bound
        var start = 0;
        while (start < sentence.length && result.length < maxTotalChunks) {
          final end = (start + maxChunkSize < sentence.length)
              ? start + maxChunkSize
              : sentence.length;
          result.add(sentence.substring(start, end).trim());
          start = end;
        }
      } else if (buffer.length + sentence.length + 1 > maxChunkSize) {
        result.add(buffer.toString().trim());
        buffer.clear();
        buffer.write(sentence);
      } else {
        if (buffer.isNotEmpty) {
          buffer.write(' ');
        }
        buffer.write(sentence);
      }
    }

    if (buffer.isNotEmpty && result.length < maxTotalChunks) {
      result.add(buffer.toString().trim());
    }

    return result;
  }
}

