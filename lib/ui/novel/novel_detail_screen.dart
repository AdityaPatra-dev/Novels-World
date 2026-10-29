import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/models/reading_progress.dart';
import '../../data/storage_service.dart';
import '../../extractors/source_registry.dart';
import '../../data/download_service.dart';
import '../../providers/library_provider.dart';
import '../../providers/reader_provider.dart';
import '../reader/reader_screen.dart';
import '../widgets/source_webview_screen.dart';
import '../widgets/novel_storage_modal.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/text_cleaner.dart';

class NovelDetailScreen extends StatefulWidget {
  final Novel novel;

  const NovelDetailScreen({super.key, required this.novel});

  @override
  State<NovelDetailScreen> createState() => _NovelDetailScreenState();
}

class _NovelDetailScreenState extends State<NovelDetailScreen> {
  late Novel _novel;
  List<Chapter> _chapters = [];
  bool _isLoading = true;
  String? _error;
  bool _ascending = true;
  bool _isSynopsisExpanded = false;
  final ScrollController _scrollController = ScrollController();
  ReadingProgress? _readingProgress;
  Set<String> _readChapterIds = {};

  String get _sanitizedCoverUrl {
    var url = _novel.coverUrl.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('//')) {
      url = 'https:$url';
    }
    if (url.startsWith('/')) {
      final origin = Uri.tryParse(_novel.sourceUrl)?.origin;
      if (origin != null && origin.isNotEmpty) {
        url = '$origin$url';
      }
    }
    url = url.replaceAll(RegExp(r'render_js.*$'), '');
    if (url.contains('dflazy.jpg') || url.contains('placeholder') || url.startsWith('data:')) {
      return '';
    }
    try {
      final uri = Uri.parse(url);
      url = uri.toString();
    } catch (_) {
      url = Uri.encodeFull(url);
    }
    return url;
  }

  Map<String, String> get _imageHeaders {
    final headers = <String, String>{
      'User-Agent': WebViewSessionManager.defaultUserAgent,
      'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    };
    if (_novel.sourceUrl.isNotEmpty) {
      final origin = Uri.tryParse(_novel.sourceUrl)?.origin;
      if (origin != null && origin.isNotEmpty) {
        headers['Referer'] = '$origin/';
      }
    }
    final cookie = WebViewSessionManager.instance.getCookieHeader(_novel.sourceUrl);
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  @override
  void initState() {
    super.initState();
    _novel = widget.novel;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReadingProgress();
    });
    _fetchDetails();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadReadingProgress() {
    if (!mounted) return;
    try {
      final storage = context.read<StorageService>();
      setState(() {
        _readingProgress = storage.getProgress(_novel.id);
        _readChapterIds = storage.getReadChapterIds(_novel.id);
      });
    } catch (_) {}
  }

  Chapter? get _lastReadChapter {
    if (_readingProgress == null || _chapters.isEmpty) return null;
    final targetId = _readingProgress!.chapterId;
    final targetTitle = _readingProgress!.chapterTitle;
    for (final ch in _chapters) {
      if (ch.id == targetId || ch.url == targetId) return ch;
    }
    if (targetTitle != null && targetTitle.isNotEmpty) {
      for (final ch in _chapters) {
        if (ch.title == targetTitle) return ch;
      }
    }
    return null;
  }

  bool _isChapterRead(Chapter chapter) {
    if (_readChapterIds.contains(chapter.id) || _readChapterIds.contains(chapter.url)) {
      return true;
    }
    final last = _lastReadChapter;
    if (last != null) {
      final lastIdx = _chapters.indexOf(last);
      final thisIdx = _chapters.indexOf(chapter);
      if (thisIdx >= 0 && lastIdx >= 0 && thisIdx <= lastIdx) {
        return true;
      }
    }
    return false;
  }

  int get _readCount {
    if (_chapters.isEmpty) return 0;
    int count = 0;
    for (final ch in _chapters) {
      if (_isChapterRead(ch)) count++;
    }
    return count;
  }

  void _jumpToCurrentChapter() {
    if (_lastReadChapter == null || _chapters.isEmpty) return;
    final sorted = _ascending ? _chapters : _chapters.reversed.toList();
    final idx = sorted.indexWhere((c) => c.id == _lastReadChapter!.id || c.url == _lastReadChapter!.url);
    if (idx >= 0 && _scrollController.hasClients) {
      final targetOffset = (520.0 + (idx * 56.0)).clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
    }
  }

  Future<void> _fetchDetails() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final source = SourceRegistry.getSource(_novel.sourceId) ?? SourceRegistry.getDefaultSource();
      final fullNovel = await source.getNovelDetails(_novel.sourceUrl);
      final chapters = await source.getChapterList(_novel.sourceUrl);

      if (mounted) {
        setState(() {
          final isFetchedTitleValid = TextCleaner.isValidNovelTitle(fullNovel.title, _novel.sourceUrl);
          _novel = fullNovel.copyWith(
            id: _novel.id,
            title: isFetchedTitleValid ? fullNovel.title : _novel.title,
            inLibrary: context.read<LibraryProvider>().isInLibrary(_novel.id),
          );
          _chapters = chapters;
          _isLoading = false;
        });
        _loadReadingProgress();
        context.read<DownloadService>().checkChaptersDownloaded(chapters);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load novel details: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _openReader(Chapter chapter) async {
    final readerProvider = context.read<ReaderProvider>();
    await readerProvider.initializeNovelReader(
      novel: _novel,
      chapters: _chapters,
      initialChapter: chapter,
    );

    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const ReaderScreen()),
      );
      if (mounted) {
        _loadReadingProgress();
      }
    }
  }

  void _showDownloadModal() {
    final downloadService = context.read<DownloadService>();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF181822),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Download Chapters (Offline)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                'Downloaded chapters can be read and listened to offline with zero internet access.',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 16),
              ListTile(
                leading: const Icon(Icons.download, color: Color(0xFF8B5CF6)),
                title: const Text('Download Next 5 Chapters'),
                onTap: () {
                  Navigator.pop(context);
                  downloadService.enqueueNextUnread(_novel, _chapters, 5);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download, color: Color(0xFF8B5CF6)),
                title: const Text('Download Next 10 Chapters'),
                onTap: () {
                  Navigator.pop(context);
                  downloadService.enqueueNextUnread(_novel, _chapters, 10);
                },
              ),
              ListTile(
                leading: const Icon(Icons.download, color: Color(0xFF8B5CF6)),
                title: const Text('Download Next 25 Chapters'),
                onTap: () {
                  Navigator.pop(context);
                  downloadService.enqueueNextUnread(_novel, _chapters, 25);
                },
              ),
              ListTile(
                leading: const Icon(Icons.cloud_download_outlined, color: Color(0xFF8B5CF6)),
                title: Text('Download All Unread (${_chapters.length})'),
                onTap: () {
                  Navigator.pop(context);
                  downloadService.enqueueAllUnread(_novel, _chapters);
                },
              ),
              const Divider(color: Colors.white12),
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
                title: const Text('Delete Downloaded Chapters', style: TextStyle(color: Colors.redAccent)),
                onTap: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  await downloadService.deleteNovelDownloads(_novel.id, _chapters);
                  if (mounted) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Downloaded chapters cleared from disk.')),
                    );
                  }
                },
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final libraryProvider = context.watch<LibraryProvider>();
    final downloadService = context.watch<DownloadService>();
    final isInLibrary = libraryProvider.isInLibrary(_novel.id);

    final sortedChapters = _ascending ? _chapters : _chapters.reversed.toList();

    return Scaffold(
      body: CustomScrollView(
        controller: _scrollController,
        slivers: [
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (_sanitizedCoverUrl.isNotEmpty)
                    (_sanitizedCoverUrl.startsWith('file://')
                        ? Image.file(
                            File(Uri.parse(_sanitizedCoverUrl).toFilePath()),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(color: Colors.black87),
                          )
                        : Image.network(
                            _sanitizedCoverUrl,
                            headers: _imageHeaders,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(color: Colors.black87),
                          )),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.3),
                          const Color(0xFF0B0B0F).withValues(alpha: 0.85),
                          const Color(0xFF0B0B0F),
                        ],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: SizedBox(
                            width: 100,
                            height: 140,
                            child: _sanitizedCoverUrl.isNotEmpty
                                ? (_sanitizedCoverUrl.startsWith('file://')
                                    ? Image.file(
                                        File(Uri.parse(_sanitizedCoverUrl).toFilePath()),
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[800]),
                                      )
                                    : Image.network(
                                        _sanitizedCoverUrl,
                                        headers: _imageHeaders,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[800]),
                                      ))
                                : Container(color: Colors.grey[800]),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _novel.title,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _novel.author,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: Colors.white.withValues(alpha: 0.8),
                                ),
                              ),
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: _novel.status == 'COMPLETED' ? Colors.green[800] : Colors.blueGrey[800],
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  _novel.status,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.folder_special_rounded, color: Color(0xFFA78BFA)),
                tooltip: 'Storage Folder & Chapters',
                onPressed: () => NovelStorageModal.show(context, _novel),
              ),
              IconButton(
                icon: const Icon(Icons.public),
                tooltip: 'Open in WebView / Bypass Cloudflare',
                onPressed: () async {
                  final res = await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                      builder: (context) => SourceWebViewScreen(
                        initialUrl: _novel.sourceUrl,
                        sourceName: _novel.title,
                      ),
                    ),
                  );
                  if (res == true && mounted) {
                    _fetchDetails();
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Download Options',
                onPressed: _chapters.isNotEmpty ? _showDownloadModal : null,
              ),
              IconButton(
                icon: Icon(
                  isInLibrary ? Icons.bookmark : Icons.bookmark_border,
                  color: isInLibrary ? Colors.purpleAccent : Colors.white,
                ),
                onPressed: () => libraryProvider.toggleLibrary(_novel),
                tooltip: isInLibrary ? 'Remove from Library' : 'Add to Library',
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Active Download Progress Banner
                  if (downloadService.isProcessing && downloadService.queue.any((t) => t.novel.id == _novel.id)) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E28),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Downloading chapters (${downloadService.completedInCurrentBatch}/${downloadService.totalInCurrentBatch})...',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              TextButton(
                                onPressed: () => downloadService.cancelAll(),
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                                child: const Text('Cancel', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: downloadService.batchProgress,
                              backgroundColor: Colors.white12,
                              color: const Color(0xFF8B5CF6),
                              minHeight: 6,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _chapters.isNotEmpty
                              ? () => _openReader(_lastReadChapter ?? _chapters.first)
                              : null,
                          icon: Icon(_lastReadChapter != null
                              ? Icons.play_circle_fill_rounded
                              : Icons.menu_book),
                          label: Text(
                            _chapters.isEmpty
                                ? 'Loading...'
                                : (_lastReadChapter != null
                                    ? 'Continue: ${_lastReadChapter!.title}'
                                    : 'Start Reading'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        onPressed: _chapters.isNotEmpty ? _showDownloadModal : null,
                        icon: const Icon(Icons.download),
                        tooltip: 'Download Chapters',
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: () => libraryProvider.toggleLibrary(_novel),
                        icon: Icon(isInLibrary ? Icons.check : Icons.add),
                        label: Text(isInLibrary ? 'In Library' : 'Library'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),

                  // Genres
                  if (_novel.genres.isNotEmpty) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: _novel.genres.map((genre) {
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF1E1E28),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                          ),
                          child: Text(
                            genre,
                            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.8)),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Synopsis
                  if (_novel.description.isNotEmpty) ...[
                    const Text(
                      'Synopsis',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    InkWell(
                      onTap: () => setState(() => _isSynopsisExpanded = !_isSynopsisExpanded),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _novel.description,
                            maxLines: _isSynopsisExpanded ? null : 4,
                            overflow: _isSynopsisExpanded ? null : TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.5,
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _isSynopsisExpanded ? 'Show less' : 'Read more...',
                            style: const TextStyle(fontSize: 13, color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],

                  // Chapter List Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Chapters (${_chapters.length})',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                          if (_chapters.isNotEmpty && _readCount > 0)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Read $_readCount of ${_chapters.length} (${((_readCount / _chapters.length) * 100).toInt()}%)',
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFFA78BFA),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_lastReadChapter != null)
                            IconButton(
                              icon: const Icon(Icons.my_location_rounded, size: 19, color: Color(0xFFA78BFA)),
                              tooltip: 'Jump to current chapter',
                              onPressed: _jumpToCurrentChapter,
                            ),
                          IconButton(
                            icon: Icon(_ascending ? Icons.arrow_downward : Icons.arrow_upward, size: 20),
                            tooltip: _ascending ? 'Showing Oldest First' : 'Showing Newest First',
                            onPressed: () => setState(() => _ascending = !_ascending),
                          ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 20, color: Colors.white70),
                            tooltip: 'Reading Options',
                            onSelected: (val) async {
                              final storage = context.read<StorageService>();
                              if (val == 'mark_all_read') {
                                await storage.markChaptersAsRead(_novel.id, _chapters.map((c) => c.id));
                                _loadReadingProgress();
                              } else if (val == 'clear_progress') {
                                await storage.clearReadChapters(_novel.id);
                                _loadReadingProgress();
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'mark_all_read',
                                child: Row(
                                  children: [
                                    Icon(Icons.done_all, size: 18, color: Color(0xFF10B981)),
                                    SizedBox(width: 8),
                                    Text('Mark all as read'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'clear_progress',
                                child: Row(
                                  children: [
                                    Icon(Icons.restart_alt, size: 18, color: Colors.redAccent),
                                    SizedBox(width: 8),
                                    Text('Clear reading progress'),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                  const Divider(color: Colors.white12),
                ],
              ),
            ),
          ),
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                      const SizedBox(height: 12),
                      Text(_error!, textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: () async {
                              final res = await Navigator.push<bool>(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => SourceWebViewScreen(
                                    initialUrl: _novel.sourceUrl,
                                    sourceName: _novel.title,
                                  ),
                                ),
                              );
                              if (res == true && mounted) {
                                _fetchDetails();
                              }
                            },
                            icon: const Icon(Icons.security, size: 16),
                            label: const Text('Solve in WebView'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF8B5CF6),
                              foregroundColor: Colors.white,
                            ),
                          ),
                          OutlinedButton(
                            onPressed: _fetchDetails,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final chapter = sortedChapters[index];
                  final isLastRead = _lastReadChapter != null &&
                      (chapter.id == _lastReadChapter!.id || chapter.url == _lastReadChapter!.url);
                  final isRead = _isChapterRead(chapter);
                  final isDownloaded = downloadService.isChapterDownloaded(chapter.id);
                  final isDownloading = downloadService.currentTask?.chapter.id == chapter.id;

                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    child: Material(
                      color: isLastRead
                          ? const Color(0xFF8B5CF6).withValues(alpha: 0.14)
                          : Colors.transparent,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: isLastRead
                            ? BorderSide(
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                                width: 1.2,
                              )
                            : BorderSide.none,
                      ),
                      child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                      leading: isLastRead
                          ? Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                                shape: BoxShape.circle,
                                border: Border.all(color: const Color(0xFF8B5CF6), width: 1.5),
                              ),
                              child: const Icon(
                                Icons.bookmark_rounded,
                                color: Color(0xFFA78BFA),
                                size: 16,
                              ),
                            )
                          : (isRead
                              ? const Icon(Icons.check_circle_rounded, size: 18, color: Color(0xFF10B981))
                              : const Icon(Icons.circle_outlined, size: 16, color: Colors.white24)),
                      title: Text(
                        chapter.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: isLastRead ? FontWeight.bold : FontWeight.normal,
                          color: isLastRead
                              ? Colors.white
                              : (isRead ? Colors.white.withValues(alpha: 0.5) : Colors.white.withValues(alpha: 0.95)),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Row(
                        children: [
                          if (isLastRead) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.history, size: 10, color: Color(0xFFA78BFA)),
                                  SizedBox(width: 3),
                                  Text(
                                    'Left off here',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFFA78BFA),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 6),
                          ],
                          if (chapter.releaseDate != null)
                            Expanded(
                              child: Text(
                                chapter.releaseDate!,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.white.withValues(alpha: isRead ? 0.3 : 0.45),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (isDownloading)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B5CF6)),
                            )
                          else if (isDownloaded)
                            const Icon(Icons.check_circle, size: 18, color: Colors.greenAccent)
                          else
                            IconButton(
                              icon: const Icon(Icons.download_outlined, size: 18, color: Colors.white38),
                              tooltip: 'Download Chapter',
                              onPressed: () => downloadService.enqueueChapters(_novel, [chapter]),
                            ),
                          PopupMenuButton<String>(
                            icon: const Icon(Icons.more_vert, size: 16, color: Colors.white30),
                            tooltip: 'Chapter Options',
                            onSelected: (action) async {
                              final storage = context.read<StorageService>();
                              if (action == 'mark_read') {
                                await storage.markChapterAsRead(_novel.id, chapter.id);
                                _loadReadingProgress();
                              } else if (action == 'mark_unread') {
                                await storage.markChapterAsUnread(_novel.id, chapter.id);
                                _loadReadingProgress();
                              } else if (action == 'set_as_current') {
                                await storage.saveProgress(
                                  ReadingProgress(
                                    novelId: _novel.id,
                                    chapterId: chapter.id,
                                    chapterTitle: chapter.title,
                                    activeSentenceIndex: 0,
                                    lastReadAt: DateTime.now(),
                                  ),
                                );
                                _loadReadingProgress();
                              } else if (action == 'mark_previous_read') {
                                final thisIdx = _chapters.indexOf(chapter);
                                if (thisIdx >= 0) {
                                  final priorIds = _chapters.sublist(0, thisIdx + 1).map((c) => c.id);
                                  await storage.markChaptersAsRead(_novel.id, priorIds);
                                  _loadReadingProgress();
                                }
                              }
                            },
                            itemBuilder: (context) => [
                              PopupMenuItem(
                                value: isRead ? 'mark_unread' : 'mark_read',
                                child: Text(isRead ? 'Mark as unread' : 'Mark as read'),
                              ),
                              const PopupMenuItem(
                                value: 'set_as_current',
                                child: Text('Set as current position'),
                              ),
                              const PopupMenuItem(
                                value: 'mark_previous_read',
                                child: Text('Mark all prior as read'),
                              ),
                            ],
                          ),
                        ],
                      ),
                      onTap: () => _openReader(chapter),
                    ),
                  ),
                );
                },
                childCount: sortedChapters.length,
              ),
            ),
        ],
      ),
    );
  }
}
