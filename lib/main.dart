import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'services/database_service.dart';
import 'services/edition_service.dart';
import 'services/feed_service.dart';
import 'screens/feed_screen.dart';
import 'theme/newspaper_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Configure system overlays to match print newspaper theme
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: NewspaperTheme.newsprintBackground,
      systemNavigationBarIconBrightness: Brightness.dark,
    ),
  );

  // Initialize persistent SQLite database
  final dbService = await DatabaseService.init();
  final editionService = EditionService(dbService: dbService);
  final feedService = FeedService(
    dbService: dbService,
    editionService: editionService,
  );

  runApp(ArticlesApp(
    feedService: feedService,
    editionService: editionService,
  ));
}

/// Root application widget for the Articles RSS feed reader.
class ArticlesApp extends StatelessWidget {
  final FeedService feedService;
  final EditionService editionService;

  const ArticlesApp({
    super.key,
    required this.feedService,
    required this.editionService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Articles',
      debugShowCheckedModeBanner: false,
      theme: NewspaperTheme.themeData,
      home: FeedScreen(
        feedService: feedService,
        editionService: editionService,
      ),
    );
  }
}
