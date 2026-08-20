import 'package:flutter/material.dart';
import 'services/database_service.dart';
import 'services/feed_service.dart';
import 'screens/feed_screen.dart';
import 'theme/newspaper_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize persistent SQLite database
  final dbService = await DatabaseService.init();
  final feedService = FeedService(dbService: dbService);

  runApp(ArticlesApp(feedService: feedService));
}

/// Root application widget for the Articles RSS feed reader.
class ArticlesApp extends StatelessWidget {
  final FeedService feedService;

  const ArticlesApp({
    super.key,
    required this.feedService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Articles',
      debugShowCheckedModeBanner: false,
      theme: NewspaperTheme.themeData,
      home: FeedScreen(feedService: feedService),
    );
  }
}
