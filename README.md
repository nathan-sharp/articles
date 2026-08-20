# Articles

An open-source, distraction-free Really Simple Syndication (RSS) and Atom feed reader application.

---

## Overview

Articles provides a minimalist, purely functional reading experience styled after traditional print newspapers. It features offline-first SQLite persistence, feed subscription management, Outline Processor Markup Language (OPML) 2.0 import and export, and an interruption-free typography reader.

### Core Features
- **Print Newspaper Aesthetic**: Newsprint linen background (`#F6F3EB`), ink black text (`#141414`), serif headlines, date line masthead banner, and 1-2px solid rule borders.
- **Syndication Ingestion**: Ingests RSS 2.0, RSS 0.9x, and Atom 1.0 XML syndication feeds.
- **Aggregated Front Page**: Aggregates all subscribed feeds into a single chronological newspaper feed with lead story cards and multi-column article snippets.
- **Interruption-Free Reader**: Renders clean, sanitized typography free of ads, tracking scripts, and popups.
- **Subscription Bureau**: Add feeds by URL, load curated starter packs, and import or export OPML 2.0 XML outlines.
- **Offline Persistence**: Uses indexed SQLite tables (`sqflite` / `sqflite_common_ffi`) to cache articles and preserve read/bookmarked statuses offline.
- **Security Protections**: Positive URL validation prevents Server-Side Request Forgery (SSRF) and local network scanning. HTML sanitization strips dangerous tags to prevent Cross-Site Scripting (XSS).

---

## Architecture

| Layer | Component | File Path | Responsibility |
| :--- | :--- | :--- | :--- |
| **Domain** | `Feed`, `Article` | [`lib/models/models.dart`](file:///c:/Users/User/Downloads/articles/lib/models/models.dart) | Immutable domain entities and database mapping. |
| **Security** | `SecurityValidator` | [`lib/services/security_validator.dart`](file:///c:/Users/User/Downloads/articles/lib/services/security_validator.dart) | SSRF prevention allow-list and HTML sanitization. |
| **Parser** | `FeedParser` | [`lib/services/feed_parser.dart`](file:///c:/Users/User/Downloads/articles/lib/services/feed_parser.dart) | RSS 2.0, RSS 0.9x, and Atom 1.0 XML parser. |
| **Portability** | `OpmlService` | [`lib/services/opml_service.dart`](file:///c:/Users/User/Downloads/articles/lib/services/opml_service.dart) | OPML 2.0 XML import and export engine. |
| **Storage** | `DatabaseService` | [`lib/services/database_service.dart`](file:///c:/Users/User/Downloads/articles/lib/services/database_service.dart) | SQLite database with FFI desktop support and migrations. |
| **Network** | `FeedService` | [`lib/services/feed_service.dart`](file:///c:/Users/User/Downloads/articles/lib/services/feed_service.dart) | Network retrieval, background synchronization, starter feeds. |
| **Theme** | `NewspaperTheme` | [`lib/theme/newspaper_theme.dart`](file:///c:/Users/User/Downloads/articles/lib/theme/newspaper_theme.dart) | Print newspaper typography, color tokens, and Material styles. |
| **Presentation** | `FeedScreen` | [`lib/screens/feed_screen.dart`](file:///c:/Users/User/Downloads/articles/lib/screens/feed_screen.dart) | Masthead, edition date banner, timeline, and section drawer. |
| **Presentation** | `ArticleScreen` | [`lib/screens/article_screen.dart`](file:///c:/Users/User/Downloads/articles/lib/screens/article_screen.dart) | Typography reader and external browser launcher. |
| **Presentation** | `ManageFeedsScreen`| [`lib/screens/manage_feeds_screen.dart`](file:///c:/Users/User/Downloads/articles/lib/screens/manage_feeds_screen.dart) | Feed management, OPML actions, and starter feed loader. |

---

## Getting Started

### Prerequisites
1. Flutter SDK version 3.20.0 or higher.
2. Dart SDK version 3.3.0 or higher.

### Installation
1. Clone repository:
   ```bash
   git clone https://github.com/nathan-sharp/articles.git
   cd articles
   ```
2. Install dependencies:
   ```bash
   flutter pub get
   ```
3. Run the application:
   - For Windows Desktop:
     ```bash
     flutter run -d windows
     ```
   - For Mobile:
     ```bash
     flutter run
     ```

---

## Verification & Testing

Execute unit and widget tests:
```bash
flutter test test/security_validator_test.dart
flutter test test/feed_parser_test.dart
flutter test test/opml_service_test.dart
flutter test test/database_service_test.dart
flutter test test/newspaper_ui_test.dart
```

Execute static code analysis:
```bash
flutter analyze
```
