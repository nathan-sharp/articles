import 'package:flutter_test/flutter_test.dart';
import 'package:articles/services/tts_service.dart';

class MockTtsPlatformEngine implements TtsPlatformEngine {
  final List<String> spokenChunks = [];
  bool isStopped = false;
  bool isPaused = false;
  void Function()? onStart;
  void Function()? onComplete;
  void Function(dynamic message)? onError;
  void Function()? onCancel;
  void Function()? onPause;
  void Function()? onContinue;

  @override
  Future<dynamic> speak(String text) async {
    spokenChunks.add(text);
    isStopped = false;
    onStart?.call();
    return 1;
  }

  @override
  Future<dynamic> stop() async {
    isStopped = true;
    onCancel?.call();
    return 1;
  }

  @override
  Future<dynamic> pause() async {
    isPaused = true;
    onPause?.call();
    return 1;
  }

  @override
  Future<dynamic> setLanguage(String language) async => 1;

  @override
  Future<dynamic> setSpeechRate(double rate) async => 1;

  @override
  Future<dynamic> setVolume(double volume) async => 1;

  @override
  Future<dynamic> setPitch(double pitch) async => 1;

  @override
  void setStartHandler(void Function() callback) {
    onStart = callback;
  }

  @override
  void setCompletionHandler(void Function() callback) {
    onComplete = callback;
  }

  @override
  void setErrorHandler(void Function(dynamic message) callback) {
    onError = callback;
  }

  @override
  void setCancelHandler(void Function() callback) {
    onCancel = callback;
  }

  @override
  void setPauseHandler(void Function() callback) {
    onPause = callback;
  }

  @override
  void setContinueHandler(void Function() callback) {
    onContinue = callback;
  }
}

void main() {
  group('TtsService - Text Preparation & Chunking (AAA Pattern)', () {
    test('prepareArticleSpeechText combines headline, byline, and sanitized body', () {
      // Arrange
      const title = 'Breaking News: Ocean Research';
      const byline = 'BY JANE DOE | DAILY NEWS';
      const contentHtml = '<p>Scientists have discovered a <strong>new coral reef</strong>.</p>';

      // Act
      final result = TtsService.prepareArticleSpeechText(
        title: title,
        byline: byline,
        contentHtml: contentHtml,
      );

      // Assert
      expect(result, contains('Breaking News: Ocean Research'));
      expect(result, contains('BY JANE DOE | DAILY NEWS'));
      expect(result, contains('Scientists have discovered a new coral reef.'));
      expect(result, isNot(contains('<p>')));
      expect(result, isNot(contains('<strong>')));
    });

    test('chunkText splits text exceeding maximum length into bounded pieces', () {
      // Arrange
      final paragraph1 = 'Sentence one of paragraph one. ' * 30; // ~930 chars
      final paragraph2 = 'Sentence two of paragraph two. ' * 30; // ~930 chars
      final fullText = '$paragraph1\n\n$paragraph2';

      // Act
      final chunks = TtsService.chunkText(fullText, maxChunkSize: 1000);

      // Assert
      expect(chunks.length, greaterThanOrEqualTo(2));
      for (final chunk in chunks) {
        expect(chunk.length, lessThanOrEqualTo(1000));
        expect(chunk.trim().isNotEmpty, isTrue);
      }
    });

    test('chunkText returns single chunk when text is under maxChunkSize', () {
      // Arrange
      const shortText = 'This is a brief article summary.';

      // Act
      final chunks = TtsService.chunkText(shortText, maxChunkSize: 1500);

      // Assert
      expect(chunks.length, equals(1));
      expect(chunks.first, equals(shortText));
    });

    test('chunkText handles empty input gracefully', () {
      // Arrange
      const emptyText = '   ';

      // Act
      final chunks = TtsService.chunkText(emptyText);

      // Assert
      expect(chunks, isEmpty);
    });
  });

  group('TtsService - State & Engine Execution (AAA Pattern)', () {
    late MockTtsPlatformEngine mockEngine;
    late TtsService service;

    setUp(() {
      mockEngine = MockTtsPlatformEngine();
      service = TtsService(engine: mockEngine);
    });

    tearDown(() {
      service.dispose();
    });

    test('Initial state is stopped', () {
      // Arrange & Act (performed in setUp)

      // Assert
      expect(service.state, equals(TtsPlaybackState.stopped));
      expect(service.isPlaying, isFalse);
    });

    test('speakArticle transitions state to playing and speaks first chunk', () async {
      // Arrange
      const title = 'Article Title';
      const content = '<p>Article body content.</p>';

      // Act
      await service.speakArticle(
        title: title,
        contentHtml: content,
      );

      // Assert
      expect(service.state, equals(TtsPlaybackState.playing));
      expect(service.isPlaying, isTrue);
      expect(mockEngine.spokenChunks, isNotEmpty);
      expect(mockEngine.spokenChunks.first, contains('Article Title'));
    });

    test('Engine completion triggers next chunk and concludes with stopped state', () async {
      // Arrange
      final longContent = '<p>${'Long sentence number one. ' * 40}</p><p>${'Long sentence number two. ' * 40}</p>';
      await service.speakArticle(
        title: 'Headline',
        contentHtml: longContent,
      );
      final initialSpokenCount = mockEngine.spokenChunks.length;

      // Act: Simulate engine finishing chunk 1
      mockEngine.onComplete?.call();

      // Assert
      expect(mockEngine.spokenChunks.length, greaterThan(initialSpokenCount));

      // Act: Complete all remaining chunks
      while (service.isPlaying) {
        mockEngine.onComplete?.call();
      }

      // Assert final state
      expect(service.state, equals(TtsPlaybackState.stopped));
      expect(service.isPlaying, isFalse);
    });

    test('stop() halts engine and resets state to stopped', () async {
      // Arrange
      await service.speakArticle(
        title: 'Headline',
        contentHtml: '<p>Content</p>',
      );
      expect(service.isPlaying, isTrue);

      // Act
      await service.stop();

      // Assert
      expect(service.state, equals(TtsPlaybackState.stopped));
      expect(service.isPlaying, isFalse);
      expect(mockEngine.isStopped, isTrue);
    });

    test('Engine error triggers state reset to stopped without exception', () async {
      // Arrange
      await service.speakArticle(
        title: 'Headline',
        contentHtml: '<p>Content</p>',
      );
      expect(service.isPlaying, isTrue);

      // Act: Simulate engine error
      mockEngine.onError?.call('Platform synthesis initialization failed.');

      // Assert
      expect(service.state, equals(TtsPlaybackState.stopped));
      expect(service.isPlaying, isFalse);
    });
  });
}

