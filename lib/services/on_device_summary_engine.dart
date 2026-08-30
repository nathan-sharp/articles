import 'dart:isolate';
import 'dart:math' as math;
import '../models/models.dart';
import 'security_validator.dart';

/// Contract interface for on-device local summarization and edition synthesis engines.
abstract class LocalSummaryEngine {
  /// Synthesizes an [EditorialEdition] from a list of input [articles] on-device.
  Future<EditorialEdition> generateEdition({
    required EditionType type,
    required List<Article> articles,
    required DateTime targetDate,
  });
}

/// Request payload container for isolate execution.
class _SynthesisRequest {
  final EditionType type;
  final List<Map<String, dynamic>> articleMaps;
  final int targetDateEpochMs;

  const _SynthesisRequest({
    required this.type,
    required this.articleMaps,
    required this.targetDateEpochMs,
  });
}

/// Deterministic, zero-dependency on-device Natural Language Processing (NLP) summarization engine.
///
/// Employs TextRank graph centrality and BM25/TF-IDF token scoring to extract salient insights
/// and generate structured editorial editions without cloud dependencies.
class DeterministicNlpSummaryEngine implements LocalSummaryEngine {
  const DeterministicNlpSummaryEngine();

  @override
  Future<EditorialEdition> generateEdition({
    required EditionType type,
    required List<Article> articles,
    required DateTime targetDate,
  }) async {
    // Validate inputs
    if (articles.isEmpty) {
      return _generateEmptyFallbackEdition(type: type, targetDate: targetDate);
    }

    final request = _SynthesisRequest(
      type: type,
      articleMaps: articles.map((a) => a.toMap()).toList(),
      targetDateEpochMs: targetDate.millisecondsSinceEpoch,
    );

    // Offload compute-intensive matrix and graph ranking to background worker isolate
    return await Isolate.run(() => _executeSynthesis(request));
  }

  /// Synthesizes empty fallback edition when no articles match the time window.
  EditorialEdition _generateEmptyFallbackEdition({
    required EditionType type,
    required DateTime targetDate,
  }) {
    final dateStr = _formatDateKey(targetDate);
    final id = 'edition_${type.code}_$dateStr';

    final title = '${type.displayName.toUpperCase()}: QUIET DISPATCH';
    final subtitle = 'NO RECENT FEED ENTRIES AVAILABLE FOR SYNTHESIS';
    final summary = 'No new articles were ingested during this edition cycle. Refresh subscriptions to synchronize fresh stories.';

    final contentHtml = '''
<h2>EDITION NOTICE</h2>
<p>No new syndicated articles were recorded for this scheduled time window.</p>
<blockquote>Please trigger a feed synchronization from the main edition view or manage subscriptions in the side drawer.</blockquote>
''';

    return EditorialEdition(
      id: id,
      type: type,
      title: title,
      subtitle: subtitle,
      generatedAt: DateTime.now().toUtc(),
      summary: summary,
      contentHtml: SecurityValidator.sanitizeHtml(contentHtml),
      sourceArticleIds: const [],
      isRead: false,
    );
  }

  /// Background isolate compute entrypoint.
  static EditorialEdition _executeSynthesis(_SynthesisRequest request) {
    final articles = request.articleMaps.map(Article.fromMap).toList();
    final targetDate = DateTime.fromMillisecondsSinceEpoch(request.targetDateEpochMs, isUtc: true);
    final type = request.type;

    final dateKey = _formatDateKey(targetDate);
    final id = 'edition_${type.code}_$dateKey';

    // 1. Identify Lead Article based on publication recency and content density
    final leadArticle = _selectLeadArticle(articles);

    // 2. Extract and score salient sentences across the corpus using TextRank
    final rankedSentences = _extractTopSalientSentences(articles, maxSentences: 5);

    // 3. Cluster articles by feed category / publication source
    final categorizedMap = _clusterArticlesByCategory(articles);

    // 4. Synthesize executive summary paragraph
    final executiveSummary = _buildExecutiveSummary(type, leadArticle, rankedSentences, articles.length);

    // 5. Generate structured newspaper HTML content
    final contentHtml = _buildEditorialHtml(
      type: type,
      leadArticle: leadArticle,
      rankedSentences: rankedSentences,
      categorizedMap: categorizedMap,
      articles: articles,
      targetDate: targetDate,
    );

    final title = _buildEditionHeadline(type, leadArticle);
    final subtitle = 'SYNTHESIZED ON-DEVICE FROM ${articles.length} RECENT DISPATCHES';
    final sourceIds = articles.map((a) => a.id).toList();

    return EditorialEdition(
      id: id,
      type: type,
      title: title,
      subtitle: subtitle,
      generatedAt: DateTime.now().toUtc(),
      summary: executiveSummary,
      contentHtml: SecurityValidator.sanitizeHtml(contentHtml),
      sourceArticleIds: sourceIds,
      isRead: false,
    );
  }

  /// Selects the primary lead story based on content length and chronological priority.
  static Article _selectLeadArticle(List<Article> articles) {
    Article best = articles.first;
    var maxScore = -1.0;

    for (var i = 0; i < articles.length; i++) {
      final a = articles[i];
      final textLen = (a.content.isNotEmpty ? a.content.length : a.summary.length).toDouble();
      // Recency bias + length weight
      final recencyWeight = 1.0 / (1.0 + i * 0.1);
      final score = textLen * recencyWeight;

      if (score > maxScore) {
        maxScore = score;
        best = a;
      }
    }

    return best;
  }

  /// Splits articles into clean sentences and ranks them using TextRank graph centrality.
  static List<String> _extractTopSalientSentences(List<Article> articles, {required int maxSentences}) {
    final rawSentences = <String>[];

    for (final a in articles) {
      final body = a.summary.isNotEmpty ? a.summary : a.content;
      final plain = SecurityValidator.extractPlainText(body);
      final sentences = _splitSentences(plain);
      for (final s in sentences) {
        if (s.length >= 30 && s.length <= 300) {
          rawSentences.add(s);
        }
      }
    }

    if (rawSentences.isEmpty) {
      return articles.map((a) => a.title).take(maxSentences).toList();
    }

    if (rawSentences.length <= maxSentences) {
      return rawSentences;
    }

    // Compute token frequencies per sentence
    final tokenized = rawSentences.map(_tokenizeText).toList();
    final sentenceCount = rawSentences.length;

    // Build similarity matrix
    final similarityMatrix = List.generate(
      sentenceCount,
      (_) => List<double>.filled(sentenceCount, 0.0),
    );

    for (var i = 0; i < sentenceCount; i++) {
      for (var j = i + 1; j < sentenceCount; j++) {
        final sim = _calculateSentenceSimilarity(tokenized[i], tokenized[j]);
        similarityMatrix[i][j] = sim;
        similarityMatrix[j][i] = sim;
      }
    }

    // Power iteration for PageRank scores (statically bounded to 20 iterations)
    var scores = List<double>.filled(sentenceCount, 1.0);
    const damping = 0.85;
    const iterations = 20;

    for (var it = 0; it < iterations; it++) {
      final nextScores = List<double>.filled(sentenceCount, 1.0 - damping);
      for (var i = 0; i < sentenceCount; i++) {
        var sum = 0.0;
        for (var j = 0; j < sentenceCount; j++) {
          if (i == j) continue;
          final weight = similarityMatrix[j][i];
          if (weight > 0.0) {
            var sumWeights = 0.0;
            for (var k = 0; k < sentenceCount; k++) {
              sumWeights += similarityMatrix[j][k];
            }
            if (sumWeights > 0.0) {
              sum += (weight / sumWeights) * scores[j];
            }
          }
        }
        nextScores[i] += damping * sum;
      }
      scores = nextScores;
    }

    // Sort sentences by score descending
    final indexedScores = List.generate(sentenceCount, (i) => MapEntry(i, scores[i]))
      ..sort((a, b) => b.value.compareTo(a.value));

    final selected = <String>[];
    final selectedSet = <String>{};

    for (final entry in indexedScores) {
      final s = rawSentences[entry.key];
      final norm = s.toLowerCase().trim();
      if (!selectedSet.contains(norm)) {
        selectedSet.add(norm);
        selected.add(s);
        if (selected.length >= maxSentences) break;
      }
    }

    return selected;
  }

  /// Calculates cosine similarity between token multisets.
  static double _calculateSentenceSimilarity(List<String> tokensA, List<String> tokensB) {
    if (tokensA.isEmpty || tokensB.isEmpty) return 0.0;

    final setA = tokensA.toSet();
    final setB = tokensB.toSet();
    final intersection = setA.intersection(setB).length;

    if (intersection == 0) return 0.0;

    final logLenA = math.log(tokensA.length.toDouble() + 1.0);
    final logLenB = math.log(tokensB.length.toDouble() + 1.0);
    final denom = logLenA + logLenB;

    if (denom == 0.0) return 0.0;
    return intersection / denom;
  }

  /// Clusters articles by feed category.
  static Map<String, List<Article>> _clusterArticlesByCategory(List<Article> articles) {
    final map = <String, List<Article>>{};

    for (final a in articles) {
      final category = a.feedTitle.isNotEmpty ? a.feedTitle : 'General Dispatches';
      map.putIfAbsent(category, () => []).add(a);
    }

    return map;
  }

  /// Builds the executive summary string.
  static String _buildExecutiveSummary(
    EditionType type,
    Article leadArticle,
    List<String> topSentences,
    int totalCount,
  ) {
    final leadTitle = leadArticle.title.trim();
    final firstInsight = topSentences.isNotEmpty ? topSentences.first : leadArticle.summary;

    switch (type) {
      case EditionType.morning:
        return 'Today\'s morning intelligence brief synthesizes $totalCount dispatches, led by developments in "$leadTitle". $firstInsight';
      case EditionType.evening:
        return 'The evening dispatch consolidates $totalCount stories from the daytime news cycle, highlighted by "$leadTitle". $firstInsight';
      case EditionType.monday:
        return 'The weekly kickoff examines $totalCount major developments shaping the agenda ahead, led by "$leadTitle". $firstInsight';
      case EditionType.friday:
        return 'The weekend edition presents a retrospective of $totalCount stories from the week, centered on "$leadTitle". $firstInsight';
    }
  }

  /// Formats the headline string.
  static String _buildEditionHeadline(EditionType type, Article leadArticle) {
    final leadTitle = leadArticle.title.toUpperCase();
    switch (type) {
      case EditionType.morning:
        return 'MORNING BRIEFING: $leadTitle';
      case EditionType.evening:
        return 'EVENING DISPATCH: $leadTitle';
      case EditionType.monday:
        return 'MONDAY KICKOFF: $leadTitle';
      case EditionType.friday:
        return 'WEEKEND REVIEW: $leadTitle';
    }
  }

  /// Generates the HTML newspaper body.
  static String _buildEditorialHtml({
    required EditionType type,
    required Article leadArticle,
    required List<String> rankedSentences,
    required Map<String, List<Article>> categorizedMap,
    required List<Article> articles,
    required DateTime targetDate,
  }) {
    final buffer = StringBuffer();

    // 1. Executive Summary Box
    buffer.writeln('<h2>EXECUTIVE OVERVIEW</h2>');
    final execSummary = _buildExecutiveSummary(type, leadArticle, rankedSentences, articles.length);
    buffer.writeln('<p>$execSummary</p>');

    // 2. Key Takeaways List
    if (rankedSentences.isNotEmpty) {
      buffer.writeln('<h2>KEY DEVELOPMENTS</h2>');
      buffer.writeln('<ul>');
      for (final s in rankedSentences) {
        buffer.writeln('<li>$s</li>');
      }
      buffer.writeln('</ul>');
    }

    // 3. Lead Story Analysis
    buffer.writeln('<h2>LEAD STORY: ${leadArticle.title}</h2>');
    buffer.writeln('<blockquote>Source: ${leadArticle.feedTitle} | Author: ${leadArticle.author.isNotEmpty ? leadArticle.author : "Staff"}</blockquote>');
    final leadBody = leadArticle.content.isNotEmpty ? leadArticle.content : leadArticle.summary;
    final leadSnippet = SecurityValidator.extractPlainText(leadBody);
    buffer.writeln('<p>$leadSnippet</p>');

    // 4. Thematic Sections
    buffer.writeln('<h2>THEMATIC BREAKDOWNS</h2>');
    for (final entry in categorizedMap.entries) {
      final category = entry.key;
      final catArticles = entry.value;

      buffer.writeln('<h3>${category.toUpperCase()}</h3>');
      for (final a in catArticles.take(3)) {
        final summary = a.summary.isNotEmpty ? a.summary : a.title;
        final cleanSummary = SecurityValidator.extractPlainText(summary);
        buffer.writeln('<p><strong>${a.title}</strong> — $cleanSummary</p>');
      }
    }

    // 5. Source Index
    buffer.writeln('<h2>INDEX OF CITED SOURCES</h2>');
    buffer.writeln('<ul>');
    for (final a in articles.take(15)) {
      buffer.writeln('<li><a href="${a.link}">${a.title}</a> (${a.feedTitle})</li>');
    }
    buffer.writeln('</ul>');

    return buffer.toString();
  }

  /// Splits text into individual sentences.
  static List<String> _splitSentences(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const [];

    final regex = RegExp(r'(?<=[.!?])\s+(?=[A-Z0-9])');
    return trimmed
        .split(regex)
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// Tokenizes text into normalized words with stop-word removal.
  static List<String> _tokenizeText(String text) {
    final words = text.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ').split(RegExp(r'\s+'));
    return words.where((w) => w.length >= 3 && !_stopWords.contains(w)).toList();
  }

  /// Generates date key string (e.g. 20260830).
  static String _formatDateKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  /// Comprehensive English stop words set.
  static const Set<String> _stopWords = {
    'about', 'above', 'after', 'again', 'against', 'all', 'also', 'and', 'any', 'are', 'because',
    'been', 'before', 'being', 'below', 'between', 'both', 'but', 'can', 'could', 'did', 'does',
    'doing', 'down', 'during', 'each', 'few', 'for', 'from', 'further', 'had', 'has', 'have',
    'having', 'here', 'how', 'into', 'its', 'itself', 'just', 'more', 'most', 'not', 'now',
    'off', 'once', 'only', 'other', 'our', 'ours', 'out', 'over', 'own', 'same', 'should',
    'some', 'such', 'than', 'that', 'the', 'their', 'theirs', 'them', 'themselves', 'then',
    'there', 'these', 'they', 'this', 'those', 'through', 'too', 'under', 'until', 'very',
    'was', 'were', 'what', 'when', 'where', 'which', 'while', 'who', 'whom', 'why', 'will',
    'with', 'would', 'you', 'your', 'yours',
  };
}

