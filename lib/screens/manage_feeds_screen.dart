import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/models.dart';
import '../services/database_service.dart';
import '../services/feed_service.dart';
import '../services/opml_service.dart';
import '../services/security_validator.dart';
import '../theme/newspaper_theme.dart';

/// Screen enabling users to add, manage, refresh, import, and export feed subscriptions.
class ManageFeedsScreen extends StatefulWidget {
  final FeedService feedService;
  final VoidCallback? onFeedsUpdated;

  const ManageFeedsScreen({
    super.key,
    required this.feedService,
    this.onFeedsUpdated,
  });

  @override
  State<ManageFeedsScreen> createState() => _ManageFeedsScreenState();
}

class _ManageFeedsScreenState extends State<ManageFeedsScreen> {
  List<Feed> _feeds = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadFeeds();
  }

  Future<void> _loadFeeds() async {
    setState(() => _isLoading = true);
    final feeds = await DatabaseService.instance.getAllFeeds();
    if (mounted) {
      setState(() {
        _feeds = feeds;
        _isLoading = false;
      });
    }
  }

  Future<void> _showAddFeedDialog() async {
    final urlController = TextEditingController();
    final titleController = TextEditingController();
    final categoryController = TextEditingController(text: 'General');
    String? validationError;
    var isSubscribing = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text(
                'SUBSCRIBE TO FEED',
                style: TextStyle(
                  fontFamily: NewspaperTheme.serifFamily,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.0,
                ),
              ),
              content: SizedBox(
                width: 480.0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter the public RSS or Atom syndication feed URL.',
                      style: TextStyle(
                        fontFamily: NewspaperTheme.serifFamily,
                        fontSize: 13.0,
                        color: NewspaperTheme.inkSecondary,
                      ),
                    ),
                    const SizedBox(height: 16.0),
                    TextField(
                      controller: urlController,
                      decoration: InputDecoration(
                        labelText: 'FEED URL *',
                        hintText: 'https://example.com/feed.xml',
                        errorText: validationError,
                      ),
                      keyboardType: TextInputType.url,
                      autofocus: true,
                    ),
                    const SizedBox(height: 12.0),
                    TextField(
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'CUSTOM TITLE (OPTIONAL)',
                        hintText: 'Leave blank to use feed title',
                      ),
                    ),
                    const SizedBox(height: 12.0),
                    TextField(
                      controller: categoryController,
                      decoration: const InputDecoration(
                        labelText: 'SECTION / CATEGORY',
                        hintText: 'General, World, Tech, Science...',
                      ),
                    ),
                    if (isSubscribing) ...[
                      const SizedBox(height: 16.0),
                      const LinearProgressIndicator(color: NewspaperTheme.inkBlack),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubscribing ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: isSubscribing
                      ? null
                      : () async {
                          final url = urlController.text.trim();
                          if (!SecurityValidator.isValidFeedUrl(url)) {
                            setDialogState(() {
                              validationError = 'Please enter a valid HTTP/HTTPS public feed URL';
                            });
                            return;
                          }

                          setDialogState(() {
                            isSubscribing = true;
                            validationError = null;
                          });

                          try {
                            await widget.feedService.subscribeToFeed(
                              url: url,
                              customTitle: titleController.text.trim().isNotEmpty
                                  ? titleController.text.trim()
                                  : null,
                              category: categoryController.text.trim().isNotEmpty
                                  ? categoryController.text.trim()
                                  : 'General',
                            );
                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            await _loadFeeds();
                            widget.onFeedsUpdated?.call();
                          } catch (e) {
                            setDialogState(() {
                              isSubscribing = false;
                              validationError = 'Failed to subscribe: ${e.toString()}';
                            });
                          }
                        },
                  child: const Text('SUBSCRIBE'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _loadStarterFeeds() async {
    setState(() => _isLoading = true);
    final count = await widget.feedService.loadStarterFeeds();
    await _loadFeeds();
    widget.onFeedsUpdated?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Successfully loaded $count starter feeds into your dispatch.',
            style: const TextStyle(fontFamily: NewspaperTheme.monospaceFamily),
          ),
          backgroundColor: NewspaperTheme.inkBlack,
        ),
      );
    }
  }

  Future<void> _exportOpml() async {
    final feeds = await DatabaseService.instance.getAllFeeds();
    if (feeds.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No active feeds to export.'),
            backgroundColor: NewspaperTheme.editorialAccent,
          ),
        );
      }
      return;
    }

    final opmlXml = OpmlService.exportToOpml(feeds);
    await Clipboard.setData(ClipboardData(text: opmlXml));

    if (mounted) {
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('OPML SUBSCRIPTIONS EXPORTED'),
          content: SizedBox(
            width: 500.0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'The OPML XML outline has been copied to your clipboard. You can paste it into an .opml file or import it into any feed reader.',
                  style: TextStyle(fontFamily: NewspaperTheme.serifFamily, fontSize: 13.0),
                ),
                const SizedBox(height: 12.0),
                Container(
                  constraints: const BoxConstraints(maxHeight: 180.0),
                  padding: const EdgeInsets.all(8.0),
                  color: const Color(0xFFECE7DC),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      opmlXml,
                      style: const TextStyle(fontFamily: NewspaperTheme.monospaceFamily, fontSize: 11.0),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('DONE'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showImportOpmlDialog() async {
    final controller = TextEditingController();
    String? errorMessage;
    var isImporting = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (builderContext, setDialogState) {
            return AlertDialog(
              title: const Text('IMPORT OPML SUBSCRIPTIONS'),
              content: SizedBox(
                width: 500.0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Paste the raw XML content of an OPML file below:',
                      style: TextStyle(fontFamily: NewspaperTheme.serifFamily, fontSize: 13.0),
                    ),
                    const SizedBox(height: 12.0),
                    TextField(
                      controller: controller,
                      maxLines: 8,
                      decoration: InputDecoration(
                        hintText: '<opml version="2.0">...',
                        errorText: errorMessage,
                      ),
                      style: const TextStyle(fontFamily: NewspaperTheme.monospaceFamily, fontSize: 12.0),
                    ),
                    if (isImporting) ...[
                      const SizedBox(height: 12.0),
                      const LinearProgressIndicator(color: NewspaperTheme.inkBlack),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isImporting ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('CANCEL'),
                ),
                ElevatedButton(
                  onPressed: isImporting
                      ? null
                      : () async {
                          final text = controller.text.trim();
                          if (text.isEmpty) return;

                          setDialogState(() {
                            isImporting = true;
                            errorMessage = null;
                          });

                          try {
                            final entries = OpmlService.importFromOpml(text);
                            var imported = 0;
                            for (final entry in entries) {
                              try {
                                await widget.feedService.subscribeToFeed(
                                  url: entry.xmlUrl,
                                  customTitle: entry.title,
                                  category: entry.category,
                                );
                                imported++;
                              } catch (_) {}
                            }

                            if (dialogContext.mounted) {
                              Navigator.of(dialogContext).pop();
                            }
                            await _loadFeeds();
                            widget.onFeedsUpdated?.call();

                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Successfully imported $imported feeds from OPML.'),
                                  backgroundColor: NewspaperTheme.inkBlack,
                                ),
                              );
                            }
                          } catch (e) {
                            setDialogState(() {
                              isImporting = false;
                              errorMessage = 'Invalid OPML XML: ${e.toString()}';
                            });
                          }
                        },
                  child: const Text('IMPORT FEEDS'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteFeed(Feed feed) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('UNSUBSCRIBE FROM FEED'),
        content: Text(
          'Are you sure you want to remove "${feed.title}" and delete all its cached articles?',
          style: const TextStyle(fontFamily: NewspaperTheme.serifFamily),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('CANCEL'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: NewspaperTheme.editorialAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('UNSUBSCRIBE'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseService.instance.deleteFeed(feed.id);
      await _loadFeeds();
      widget.onFeedsUpdated?.call();
    }
  }

  Future<void> _refreshFeed(Feed feed) async {
    setState(() => _isLoading = true);
    final count = await widget.feedService.refreshFeed(feed);
    await _loadFeeds();
    widget.onFeedsUpdated?.call();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Refreshed "${feed.title}": $count new articles fetched.',
            style: const TextStyle(fontFamily: NewspaperTheme.monospaceFamily),
          ),
          backgroundColor: NewspaperTheme.inkBlack,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SUBSCRIPTION BUREAU'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: NewspaperTheme.inkBlack))
          : SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 20.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Action Toolbar
                      Wrap(
                        spacing: 8.0,
                        runSpacing: 8.0,
                        children: [
                          ElevatedButton.icon(
                            onPressed: _showAddFeedDialog,
                            icon: const Icon(Icons.add, size: 16.0),
                            label: const Text('+ ADD NEW FEED'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _loadStarterFeeds,
                            icon: const Icon(Icons.auto_stories, size: 16.0),
                            label: const Text('STARTER PACK'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _showImportOpmlDialog,
                            icon: const Icon(Icons.file_download, size: 16.0),
                            label: const Text('IMPORT OPML'),
                          ),
                          OutlinedButton.icon(
                            onPressed: _exportOpml,
                            icon: const Icon(Icons.file_upload, size: 16.0),
                            label: const Text('EXPORT OPML'),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20.0),
                      const Divider(thickness: 2.0, color: NewspaperTheme.ruleLine),
                      const SizedBox(height: 16.0),

                      // Feed Count Header
                      Text(
                        'ACTIVE SYNDICATIONS (${_feeds.length})',
                        style: const TextStyle(
                          fontFamily: NewspaperTheme.monospaceFamily,
                          fontSize: 13.0,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                          color: NewspaperTheme.inkBlack,
                        ),
                      ),
                      const SizedBox(height: 12.0),

                      if (_feeds.isEmpty) ...[
                        Container(
                          padding: const EdgeInsets.all(32.0),
                          decoration: BoxDecoration(
                            border: Border.all(color: NewspaperTheme.ruleLine, width: 1.0),
                            color: NewspaperTheme.cardSurface,
                          ),
                          child: Column(
                            children: [
                              const Text(
                                'NO SUBSCRIPTIONS REGISTERED',
                                style: TextStyle(
                                  fontFamily: NewspaperTheme.serifFamily,
                                  fontSize: 18.0,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8.0),
                              const Text(
                                'Add a public feed URL or load the starter edition pack to begin reading.',
                                style: TextStyle(fontFamily: NewspaperTheme.serifFamily),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 16.0),
                              ElevatedButton(
                                onPressed: _loadStarterFeeds,
                                child: const Text('LOAD STARTER FEEDS'),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _feeds.length,
                          separatorBuilder: (context, index) => const SizedBox(height: 10.0),
                          itemBuilder: (context, index) {
                            final feed = _feeds[index];
                            return _buildFeedCard(feed);
                          },
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
    );
  }

  Widget _buildFeedCard(Feed feed) {
    final formattedUpdated = DateFormat('MMM d, yyyy • HH:mm').format(feed.lastUpdated.toLocal());

    return Container(
      padding: const EdgeInsets.all(14.0),
      decoration: BoxDecoration(
        color: NewspaperTheme.cardSurface,
        border: Border.all(color: NewspaperTheme.ruleLine, width: 1.0),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section badge
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 2.0),
                      decoration: const BoxDecoration(
                        color: NewspaperTheme.inkBlack,
                      ),
                      child: Text(
                        feed.category.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: NewspaperTheme.monospaceFamily,
                          fontSize: 10.0,
                          fontWeight: FontWeight.bold,
                          color: NewspaperTheme.newsprintBackground,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6.0),
                    Text(
                      feed.title,
                      style: const TextStyle(
                        fontFamily: NewspaperTheme.serifFamily,
                        fontSize: 17.0,
                        fontWeight: FontWeight.bold,
                        color: NewspaperTheme.inkBlack,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Refresh Feed',
                icon: const Icon(Icons.refresh, size: 18.0),
                onPressed: () => _refreshFeed(feed),
              ),
              IconButton(
                tooltip: 'Unsubscribe',
                icon: const Icon(Icons.delete_outline, size: 18.0, color: NewspaperTheme.editorialAccent),
                onPressed: () => _deleteFeed(feed),
              ),
            ],
          ),
          const SizedBox(height: 6.0),
          Text(
            feed.url,
            style: const TextStyle(
              fontFamily: NewspaperTheme.monospaceFamily,
              fontSize: 11.0,
              color: NewspaperTheme.inkSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (feed.description.isNotEmpty) ...[
            const SizedBox(height: 6.0),
            Text(
              feed.description,
              style: const TextStyle(
                fontFamily: NewspaperTheme.serifFamily,
                fontSize: 13.0,
                color: NewspaperTheme.inkSecondary,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          const SizedBox(height: 8.0),
          Row(
            children: [
              Text(
                'UPDATED: $formattedUpdated',
                style: const TextStyle(
                  fontFamily: NewspaperTheme.monospaceFamily,
                  fontSize: 10.0,
                  color: NewspaperTheme.inkMuted,
                ),
              ),
              if (feed.errorMessage != null) ...[
                const Spacer(),
                const Icon(Icons.error_outline, size: 12.0, color: NewspaperTheme.editorialAccent),
                const SizedBox(width: 4.0),
                const Text(
                  'SYNC ERROR',
                  style: TextStyle(
                    fontFamily: NewspaperTheme.monospaceFamily,
                    fontSize: 10.0,
                    fontWeight: FontWeight.bold,
                    color: NewspaperTheme.editorialAccent,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
