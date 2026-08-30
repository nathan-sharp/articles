import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/edition_service.dart';
import '../services/feed_service.dart';
import '../theme/newspaper_theme.dart';
import 'article_screen.dart';
import 'edition_screen.dart';
import 'manage_feeds_screen.dart';

/// Main screen rendering the aggregated newspaper edition with masthead and article feeds.
class FeedScreen extends StatefulWidget {
  final FeedService feedService;
  final EditionService? editionService;

  const FeedScreen({
    super.key,
    required this.feedService,
    this.editionService,
  });

  @override
  State<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends State<FeedScreen> {
  late final EditionService _editionService;
  List<Article> _articles = [];
  List<Feed> _feeds = [];
  Map<EditionType, EditorialEdition?> _cachedEditions = {};
  String? _selectedFeedId;
  bool _unreadOnly = false;
  bool _bookmarkedOnly = false;
  String _searchQuery = '';
  bool _isSearchExpanded = false;
  bool _isLoading = false;
  bool _isRefreshing = false;
  int _unreadCount = 0;

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _editionService = widget.editionService ?? EditionService(dbService: DatabaseService.instance);
    _loadData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    final feeds = await DatabaseService.instance.getAllFeeds();
    final articles = await DatabaseService.instance.getArticles(
      feedId: _selectedFeedId,
      unreadOnly: _unreadOnly ? true : null,
      bookmarkedOnly: _bookmarkedOnly ? true : null,
      searchQuery: _searchQuery.isNotEmpty ? _searchQuery : null,
      limit: 100,
    );
    final unread = await DatabaseService.instance.getUnreadCount();
    final editions = await _editionService.getAllEditions();

    if (mounted) {
      setState(() {
        _feeds = feeds;
        _articles = articles;
        _unreadCount = unread;
        _cachedEditions = editions;
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshAll() async {
    if (_isRefreshing) return;
    setState(() => _isRefreshing = true);

    final newCount = await widget.feedService.refreshAllFeeds();
    await _loadData();

    if (mounted) {
      setState(() => _isRefreshing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Edition synchronized: $newCount new articles ingested.',
            style: const TextStyle(fontFamily: NewspaperTheme.monospaceFamily),
          ),
          backgroundColor: NewspaperTheme.inkBlack,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _markAllAsRead() async {
    await DatabaseService.instance.markAllAsRead(feedId: _selectedFeedId);
    await _loadData();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Marked all visible articles as read.',
            style: TextStyle(fontFamily: NewspaperTheme.monospaceFamily),
          ),
          backgroundColor: NewspaperTheme.inkBlack,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _openManageFeeds() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ManageFeedsScreen(
          feedService: widget.feedService,
          onFeedsUpdated: _loadData,
        ),
      ),
    );
  }

  void _openArticle(Article article) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => ArticleScreen(
          article: article,
          onStateChanged: _loadData,
        ),
      ),
    );
  }

  Future<void> _openEdition(EditionType type) async {
    EditorialEdition? edition = _cachedEditions[type];
    if (edition == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Synthesizing ${type.displayName} on-device...',
              style: const TextStyle(fontFamily: NewspaperTheme.monospaceFamily),
            ),
            backgroundColor: NewspaperTheme.inkBlack,
            duration: const Duration(seconds: 1),
          ),
        );
      }
      edition = await _editionService.getOrGenerateEdition(type);
    }

    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => EditionScreen(
          edition: edition!,
          editionService: _editionService,
          onStateChanged: _loadData,
        ),
      ),
    );
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: _buildDrawer(),
      body: Column(
        children: [
          _buildMasthead(),
          _buildFilterToolbar(),
          const Divider(height: 1.0, thickness: 1.0, color: NewspaperTheme.ruleLine),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshAll,
              color: NewspaperTheme.newsprintBackground,
              backgroundColor: NewspaperTheme.inkBlack,
              child: CustomScrollView(
                slivers: [
                  // Article Feed Grid / List
                  if (_isLoading)
                    const SliverFillRemaining(
                      child: Center(
                        child: CircularProgressIndicator(color: NewspaperTheme.inkBlack),
                      ),
                    )
                  else if (_articles.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 16.0),
                      sliver: SliverToBoxAdapter(
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 1100.0),
                            child: _buildArticlesLayout(),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Print Newspaper Masthead with banner and issue line.
  Widget _buildMasthead() {
    return Container(
      color: NewspaperTheme.newsprintBackground,
      padding: const EdgeInsets.only(top: 36.0, left: 20.0, right: 20.0, bottom: 8.0),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100.0),
          child: Column(
            children: [
              // Top Nav with Actions & Title
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Builder(
                    builder: (context) => IconButton(
                      tooltip: 'Feed Sections & Feeds',
                      icon: const Icon(Icons.menu, color: NewspaperTheme.inkBlack),
                      onPressed: () => Scaffold.of(context).openDrawer(),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'ARTICLES',
                      style: TextStyle(
                        fontFamily: NewspaperTheme.serifFamily,
                        fontSize: 28.0,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 4.0,
                        color: NewspaperTheme.inkBlack,
                        height: 1.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Mark Visible as Read',
                        icon: const Icon(Icons.done_all, color: NewspaperTheme.inkBlack),
                        onPressed: _markAllAsRead,
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterLink(String text, bool isSelected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
        child: Text(
          text,
          style: TextStyle(
            fontFamily: NewspaperTheme.monospaceFamily,
            fontSize: 12.0,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            decoration: isSelected ? TextDecoration.underline : TextDecoration.none,
            color: isSelected ? NewspaperTheme.inkBlack : NewspaperTheme.inkSecondary,
          ),
        ),
      ),
    );
  }

  /// Toolbar for filtering by Unread, Bookmarked, and Keyword search.
  Widget _buildFilterToolbar() {
    final isAllSelected = !_unreadOnly && !_bookmarkedOnly && _selectedFeedId == null;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1100.0),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: _isSearchExpanded
                ? Row(
                    key: const ValueKey('search_bar'),
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 32.0,
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            decoration: InputDecoration(
                              hintText: 'Search...',
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                              prefixIconConstraints: const BoxConstraints(minWidth: 32.0, minHeight: 32.0),
                              prefixIcon: const Icon(Icons.search, size: 16.0),
                              suffixIconConstraints: const BoxConstraints(minWidth: 32.0, minHeight: 32.0),
                              suffixIcon: _searchQuery.isNotEmpty
                                  ? IconButton(
                                      padding: EdgeInsets.zero,
                                      icon: const Icon(Icons.clear, size: 16.0),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                        _loadData();
                                      },
                                    )
                                  : null,
                            ),
                            style: const TextStyle(fontFamily: NewspaperTheme.serifFamily, fontSize: 13.0),
                            onSubmitted: (val) {
                              setState(() => _searchQuery = val.trim());
                              _loadData();
                            },
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, color: NewspaperTheme.inkBlack),
                        onPressed: () {
                          setState(() {
                            _isSearchExpanded = false;
                            if (_searchQuery.isNotEmpty) {
                              _searchQuery = '';
                              _searchController.clear();
                              _loadData();
                            }
                          });
                        },
                      ),
                    ],
                  )
                : Row(
                    key: const ValueKey('filter_tabs'),
                    children: [
                      IconButton(
                        icon: const Icon(Icons.search, color: NewspaperTheme.inkBlack, size: 20.0),
                        padding: const EdgeInsets.only(right: 12.0),
                        constraints: const BoxConstraints(),
                        onPressed: () => setState(() => _isSearchExpanded = true),
                      ),
                      Expanded(
                        child: Wrap(
                          spacing: 8.0,
                          runSpacing: 8.0,
                          children: [
                            _buildFilterLink('ALL ARTICLES', isAllSelected, () {
                              if (!isAllSelected) {
                                setState(() {
                                  _unreadOnly = false;
                                  _bookmarkedOnly = false;
                                  _selectedFeedId = null;
                                });
                                _loadData();
                              }
                            }),
                            _buildFilterLink('UNREAD ($_unreadCount)', _unreadOnly, () {
                              setState(() {
                                _unreadOnly = !_unreadOnly;
                                if (_unreadOnly) _bookmarkedOnly = false;
                              });
                              _loadData();
                            }),
                            _buildFilterLink('BOOKMARKS', _bookmarkedOnly, () {
                              setState(() {
                                _bookmarkedOnly = !_bookmarkedOnly;
                                if (_bookmarkedOnly) _unreadOnly = false;
                              });
                              _loadData();
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  /// Builds responsive layout with lead front-page story card and secondary article columns.
  Widget _buildArticlesLayout() {
    final leadArticle = _articles.first;
    final remainingArticles = _articles.skip(1).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 768.0;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Lead Front-Page Story
            _buildLeadArticleCard(leadArticle),
            const SizedBox(height: 16.0),

            // Secondary Stories Grid / List
            if (remainingArticles.isNotEmpty) ...[
              const Divider(thickness: 1.5, color: NewspaperTheme.ruleLine),
              const SizedBox(height: 16.0),
              if (isWide)
                _buildTwoColumnLayout(remainingArticles)
              else
                _buildSingleColumnLayout(remainingArticles),
            ],
          ],
        );
      },
    );
  }

  Widget _buildLeadArticleCard(Article article) {
    final formattedDate = DateFormat('MMM d, yyyy').format(article.publishedDate.toLocal());

    return InkWell(
      onTap: () => _openArticle(article),
      child: Container(
        padding: const EdgeInsets.all(18.0),
        decoration: BoxDecoration(
          color: NewspaperTheme.cardSurface,
          border: Border.all(color: NewspaperTheme.ruleLine, width: 2.0),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                  color: NewspaperTheme.inkBlack,
                  child: Text(
                    article.feedTitle.toUpperCase(),
                    style: const TextStyle(
                      fontFamily: NewspaperTheme.monospaceFamily,
                      fontSize: 10.0,
                      fontWeight: FontWeight.bold,
                      color: NewspaperTheme.newsprintBackground,
                      letterSpacing: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 8.0),
                if (!article.isRead) ...[
                  Container(
                    width: 8.0,
                    height: 8.0,
                    decoration: const BoxDecoration(
                      color: NewspaperTheme.unreadDotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6.0),
                ],
                const Spacer(),
                Text(
                  formattedDate,
                  style: const TextStyle(
                    fontFamily: NewspaperTheme.monospaceFamily,
                    fontSize: 11.0,
                    color: NewspaperTheme.inkSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12.0),
            Text(
              article.title,
              style: const TextStyle(
                fontFamily: NewspaperTheme.serifFamily,
                fontSize: 24.0,
                fontWeight: FontWeight.bold,
                color: NewspaperTheme.inkBlack,
                height: 1.2,
              ),
            ),
            if (article.author.isNotEmpty) ...[
              const SizedBox(height: 6.0),
              Text(
                'BY ${article.author.toUpperCase()}',
                style: const TextStyle(
                  fontFamily: NewspaperTheme.monospaceFamily,
                  fontSize: 11.0,
                  color: NewspaperTheme.inkSecondary,
                ),
              ),
            ],
            const SizedBox(height: 10.0),
            if (article.summary.isNotEmpty) ...[
              Text(
                article.summary,
                style: const TextStyle(
                  fontFamily: NewspaperTheme.serifFamily,
                  fontSize: 15.0,
                  color: NewspaperTheme.inkBlack,
                  height: 1.5,
                ),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTwoColumnLayout(List<Article> articles) {
    final leftColumn = <Article>[];
    final rightColumn = <Article>[];

    for (var i = 0; i < articles.length; i++) {
      if (i % 2 == 0) {
        leftColumn.add(articles[i]);
      } else {
        rightColumn.add(articles[i]);
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildColumnItems(leftColumn)),
        const SizedBox(width: 16.0),
        Container(width: 1.0, color: NewspaperTheme.ruleLine),
        const SizedBox(width: 16.0),
        Expanded(child: _buildColumnItems(rightColumn)),
      ],
    );
  }

  Widget _buildSingleColumnLayout(List<Article> articles) {
    return _buildColumnItems(articles);
  }

  Widget _buildColumnItems(List<Article> articles) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: articles.length,
      separatorBuilder: (context, index) => const Padding(
        padding: EdgeInsets.symmetric(vertical: 12.0),
        child: Divider(thickness: 1.0, color: NewspaperTheme.ruleLine),
      ),
      itemBuilder: (context, index) => _buildArticleItem(articles[index]),
    );
  }

  Widget _buildArticleItem(Article article) {
    final formattedDate = DateFormat('MMM d • HH:mm').format(article.publishedDate.toLocal());

    return InkWell(
      onTap: () => _openArticle(article),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                article.feedTitle.toUpperCase(),
                style: const TextStyle(
                  fontFamily: NewspaperTheme.monospaceFamily,
                  fontSize: 10.0,
                  fontWeight: FontWeight.bold,
                  color: NewspaperTheme.inkSecondary,
                ),
              ),
              if (!article.isRead) ...[
                const SizedBox(width: 6.0),
                Container(
                  width: 6.0,
                  height: 6.0,
                  decoration: const BoxDecoration(
                    color: NewspaperTheme.unreadDotColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                formattedDate,
                style: const TextStyle(
                  fontFamily: NewspaperTheme.monospaceFamily,
                  fontSize: 10.0,
                  color: NewspaperTheme.inkMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Text(
            article.title,
            style: const TextStyle(
              fontFamily: NewspaperTheme.serifFamily,
              fontSize: 16.0,
              fontWeight: FontWeight.bold,
              color: NewspaperTheme.inkBlack,
              height: 1.25,
            ),
          ),
          if (article.summary.isNotEmpty) ...[
            const SizedBox(height: 6.0),
            Text(
              article.summary,
              style: const TextStyle(
                fontFamily: NewspaperTheme.serifFamily,
                fontSize: 13.0,
                color: NewspaperTheme.inkSecondary,
                height: 1.4,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 500.0),
          padding: const EdgeInsets.all(24.0),
          decoration: BoxDecoration(
            color: NewspaperTheme.cardSurface,
            border: Border.all(color: NewspaperTheme.ruleLine, width: 1.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'NO ARTICLES TO DISPLAY',
                style: TextStyle(
                  fontFamily: NewspaperTheme.serifFamily,
                  fontSize: 18.0,
                  fontWeight: FontWeight.bold,
                  color: NewspaperTheme.inkBlack,
                ),
              ),
              const SizedBox(height: 10.0),
              Text(
                _feeds.isEmpty
                    ? 'No subscriptions have been added to your dispatch yet.'
                    : 'No articles match the current filter or search criteria.',
                style: const TextStyle(fontFamily: NewspaperTheme.serifFamily, fontSize: 13.0),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 18.0),
              if (_feeds.isEmpty)
                ElevatedButton.icon(
                  onPressed: () async {
                    setState(() => _isLoading = true);
                    await widget.feedService.loadStarterFeeds();
                    await _loadData();
                  },
                  icon: const Icon(Icons.auto_stories, size: 16.0),
                  label: const Text('LOAD STARTER FEEDS'),
                )
              else
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _unreadOnly = false;
                      _bookmarkedOnly = false;
                      _selectedFeedId = null;
                      _searchQuery = '';
                      _searchController.clear();
                    });
                    _loadData();
                  },
                  child: const Text('CLEAR FILTERS'),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      backgroundColor: NewspaperTheme.newsprintBackground,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(20.0),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: NewspaperTheme.ruleLine, width: 2.0)),
              ),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'SECTIONS & FEEDS',
                    style: TextStyle(
                      fontFamily: NewspaperTheme.serifFamily,
                      fontSize: 18.0,
                      fontWeight: FontWeight.bold,
                      color: NewspaperTheme.inkBlack,
                    ),
                  ),
                  SizedBox(height: 4.0),
                  Text(
                    'Browse stories by publication source',
                    style: TextStyle(
                      fontFamily: NewspaperTheme.monospaceFamily,
                      fontSize: 11.0,
                      color: NewspaperTheme.inkSecondary,
                    ),
                  ),
                ],
              ),
            ),

            // Scrollable Drawer Body
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  // Editorial Editions Section Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    color: NewspaperTheme.containerAccent,
                    child: const Row(
                      children: [
                        Expanded(
                          child: Text(
                            'EDITORIAL EDITIONS',
                            style: TextStyle(
                              fontFamily: NewspaperTheme.monospaceFamily,
                              fontSize: 11.0,
                              fontWeight: FontWeight.bold,
                              color: NewspaperTheme.inkBlack,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),
                        Text(
                          'ON-DEVICE AI',
                          style: TextStyle(
                            fontFamily: NewspaperTheme.monospaceFamily,
                            fontSize: 9.0,
                            fontWeight: FontWeight.bold,
                            color: NewspaperTheme.editorialAccent,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // 4 Editorial Edition Tiles
                  ...EditionType.values.map(_buildEditionDrawerTile),
                  const Divider(thickness: 2.0, color: NewspaperTheme.ruleLine),

                  // Feed Sources Section Header
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                    child: const Text(
                      'SYNDICATED SOURCES',
                      style: TextStyle(
                        fontFamily: NewspaperTheme.monospaceFamily,
                        fontSize: 10.0,
                        fontWeight: FontWeight.bold,
                        color: NewspaperTheme.inkSecondary,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),

                  ListTile(
                    dense: true,
                    title: const Text(
                      'FRONT PAGE (ALL FEEDS)',
                      style: TextStyle(
                        fontFamily: NewspaperTheme.monospaceFamily,
                        fontSize: 12.0,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    selected: _selectedFeedId == null,
                    selectedTileColor: NewspaperTheme.containerAccent,
                    onTap: () {
                      Navigator.of(context).pop();
                      setState(() => _selectedFeedId = null);
                      _loadData();
                    },
                  ),
                  const Divider(thickness: 1.0, color: NewspaperTheme.ruleLine),

                  // Feed List
                  ..._feeds.map((feed) {
                    final isSelected = _selectedFeedId == feed.id;
                    return ListTile(
                      dense: true,
                      title: Text(
                        feed.title,
                        style: TextStyle(
                          fontFamily: NewspaperTheme.serifFamily,
                          fontSize: 14.0,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        feed.category.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: NewspaperTheme.monospaceFamily,
                          fontSize: 10.0,
                          color: NewspaperTheme.inkSecondary,
                        ),
                      ),
                      selected: isSelected,
                      selectedTileColor: NewspaperTheme.containerAccent,
                      onTap: () {
                        Navigator.of(context).pop();
                        setState(() => _selectedFeedId = feed.id);
                        _loadData();
                      },
                    );
                  }),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.all(16.0),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: NewspaperTheme.ruleLine, width: 2.0)),
              ),
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  _openManageFeeds();
                },
                icon: const Icon(Icons.settings, size: 16.0),
                label: const Text('MANAGE SUBSCRIPTIONS'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEditionDrawerTile(EditionType type) {
    final edition = _cachedEditions[type];
    final isUnread = edition != null && !edition.isRead;
    final subtitle = edition != null
        ? 'Generated: ${DateFormat('MMM d • HH:mm').format(edition.generatedAt.toLocal())}'
        : 'Tap to generate on-device';

    return ListTile(
      dense: true,
      leading: Icon(
        type.iconData,
        size: 20.0,
        color: NewspaperTheme.inkBlack,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              type.displayName,
              style: const TextStyle(
                fontFamily: NewspaperTheme.serifFamily,
                fontSize: 13.0,
                fontWeight: FontWeight.bold,
                color: NewspaperTheme.inkBlack,
              ),
            ),
          ),
          if (isUnread) ...[
            Container(
              width: 8.0,
              height: 8.0,
              decoration: const BoxDecoration(
                color: NewspaperTheme.unreadDotColor,
                shape: BoxShape.circle,
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(
          fontFamily: NewspaperTheme.monospaceFamily,
          fontSize: 10.0,
          color: NewspaperTheme.inkSecondary,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right,
        size: 16.0,
        color: NewspaperTheme.inkSecondary,
      ),
      onTap: () {
        Navigator.of(context).pop();
        _openEdition(type);
      },
    );
  }
}
