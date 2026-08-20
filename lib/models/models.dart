import 'package:flutter/foundation.dart';

/// Immutable domain model representing a syndicated RSS/Atom feed source.
@immutable
class Feed {
  final String id;
  final String title;
  final String url;
  final String siteUrl;
  final String description;
  final DateTime lastUpdated;
  final String category;
  final bool isActive;
  final String? errorMessage;

  const Feed({
    required this.id,
    required this.title,
    required this.url,
    this.siteUrl = '',
    this.description = '',
    required this.lastUpdated,
    this.category = 'General',
    this.isActive = true,
    this.errorMessage,
  });

  /// Factory constructor to deserialize a [Feed] from a database row map.
  factory Feed.fromMap(Map<String, dynamic> map) {
    return Feed(
      id: map['id'] as String? ?? '',
      title: map['title'] as String? ?? 'Untitled Feed',
      url: map['url'] as String? ?? '',
      siteUrl: map['site_url'] as String? ?? '',
      description: map['description'] as String? ?? '',
      lastUpdated: DateTime.fromMillisecondsSinceEpoch(
        map['last_updated'] as int? ?? 0,
        isUtc: true,
      ),
      category: map['category'] as String? ?? 'General',
      isActive: (map['is_active'] as int? ?? 1) == 1,
      errorMessage: map['error_message'] as String?,
    );
  }

  /// Serializes the [Feed] instance to a database-compatible map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'title': title,
      'url': url,
      'site_url': siteUrl,
      'description': description,
      'last_updated': lastUpdated.millisecondsSinceEpoch,
      'category': category,
      'is_active': isActive ? 1 : 0,
      'error_message': errorMessage,
    };
  }

  /// Creates a copy of this [Feed] with updated values.
  Feed copyWith({
    String? id,
    String? title,
    String? url,
    String? siteUrl,
    String? description,
    DateTime? lastUpdated,
    String? category,
    bool? isActive,
    String? errorMessage,
  }) {
    return Feed(
      id: id ?? this.id,
      title: title ?? this.title,
      url: url ?? this.url,
      siteUrl: siteUrl ?? this.siteUrl,
      description: description ?? this.description,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      category: category ?? this.category,
      isActive: isActive ?? this.isActive,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Feed &&
        other.id == id &&
        other.url == url &&
        other.title == title &&
        other.lastUpdated == lastUpdated &&
        other.isActive == isActive;
  }

  @override
  int get hashCode => Object.hash(id, url, title, lastUpdated, isActive);
}

/// Immutable domain model representing an individual article item.
@immutable
class Article {
  final String id;
  final String feedId;
  final String feedTitle;
  final String title;
  final String link;
  final String author;
  final DateTime publishedDate;
  final String summary;
  final String content;
  final String? imageUrl;
  final bool isRead;
  final bool isBookmarked;

  const Article({
    required this.id,
    required this.feedId,
    required this.feedTitle,
    required this.title,
    required this.link,
    this.author = '',
    required this.publishedDate,
    this.summary = '',
    this.content = '',
    this.imageUrl,
    this.isRead = false,
    this.isBookmarked = false,
  });

  /// Factory constructor to deserialize an [Article] from a database row map.
  factory Article.fromMap(Map<String, dynamic> map) {
    return Article(
      id: map['id'] as String? ?? '',
      feedId: map['feed_id'] as String? ?? '',
      feedTitle: map['feed_title'] as String? ?? '',
      title: map['title'] as String? ?? 'Untitled Article',
      link: map['link'] as String? ?? '',
      author: map['author'] as String? ?? '',
      publishedDate: DateTime.fromMillisecondsSinceEpoch(
        map['published_date'] as int? ?? 0,
        isUtc: true,
      ),
      summary: map['summary'] as String? ?? '',
      content: map['content'] as String? ?? '',
      imageUrl: map['image_url'] as String?,
      isRead: (map['is_read'] as int? ?? 0) == 1,
      isBookmarked: (map['is_bookmarked'] as int? ?? 0) == 1,
    );
  }

  /// Serializes the [Article] instance to a database-compatible map.
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'feed_id': feedId,
      'feed_title': feedTitle,
      'title': title,
      'link': link,
      'author': author,
      'published_date': publishedDate.millisecondsSinceEpoch,
      'summary': summary,
      'content': content,
      'image_url': imageUrl,
      'is_read': isRead ? 1 : 0,
      'is_bookmarked': isBookmarked ? 1 : 0,
    };
  }

  /// Creates a copy of this [Article] with updated values.
  Article copyWith({
    String? id,
    String? feedId,
    String? feedTitle,
    String? title,
    String? link,
    String? author,
    DateTime? publishedDate,
    String? summary,
    String? content,
    String? imageUrl,
    bool? isRead,
    bool? isBookmarked,
  }) {
    return Article(
      id: id ?? this.id,
      feedId: feedId ?? this.feedId,
      feedTitle: feedTitle ?? this.feedTitle,
      title: title ?? this.title,
      link: link ?? this.link,
      author: author ?? this.author,
      publishedDate: publishedDate ?? this.publishedDate,
      summary: summary ?? this.summary,
      content: content ?? this.content,
      imageUrl: imageUrl ?? this.imageUrl,
      isRead: isRead ?? this.isRead,
      isBookmarked: isBookmarked ?? this.isBookmarked,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Article &&
        other.id == id &&
        other.feedId == feedId &&
        other.link == link &&
        other.isRead == isRead &&
        other.isBookmarked == isBookmarked;
  }

  @override
  int get hashCode => Object.hash(id, feedId, link, isRead, isBookmarked);
}

