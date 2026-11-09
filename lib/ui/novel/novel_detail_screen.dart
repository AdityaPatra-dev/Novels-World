import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
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
import '../widgets/download_range_dialog.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/text_cleaner.dart';
import '../../core/utils/chapter_range_parser.dart';
import '../../core/utils/http_client_factory.dart';
import '../../core/services/epub_service.dart';

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
  bool _isStreamingChapters = false;
  String? _error;
  bool _ascending = true;
  bool _isSynopsisExpanded = false;
  final ScrollController _scrollController = ScrollController();
  ReadingProgress? _readingProgress;
  Set<String> _readChapterIds = {};

  bool _isSearchOpen = false;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  List<Chapter> get _displayChapters {
    if (_searchQuery.isEmpty) return _chapters;
    final q = _searchQuery.toLowerCase();
    return _chapters.where((c) => c.title.toLowerCase().contains(q) || c.id.toLowerCase().contains(q)).toList();
  }

  String get _sanitizedCoverUrl {
    var url = _novel.coverUrl.trim();
    if (url.isEmpty || !TextCleaner.isValidCoverUrl(url)) {
      url = widget.novel.coverUrl.trim();
    }
    if (url.isEmpty || !TextCleaner.isValidCoverUrl(url)) return '';
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

  Widget _buildPlaceholderCover() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF242436),
            Color(0xFF14141E),
          ],
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: 28,
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.7),
          ),
          const SizedBox(height: 6),
          Text(
            _novel.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _novel = widget.novel;
    _loadCachedDataFirst();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReadingProgress();
    });
    _fetchDetails();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCachedDataFirst() async {
    try {
      final storage = context.read<StorageService>();
      final cachedChapters = await storage.getCachedChapters(_novel.id);
      final cachedDetails = await storage.getCachedNovelDetails(_novel.id);

      if (mounted && cachedChapters != null && cachedChapters.isNotEmpty) {
        setState(() {
          _chapters = cachedChapters;
          if (cachedDetails != null) {
            String bestCover = cachedDetails.coverUrl.trim();
            if (!TextCleaner.isValidCoverUrl(bestCover)) {
              if (TextCleaner.isValidCoverUrl(_novel.coverUrl)) {
                bestCover = _novel.coverUrl.trim();
              } else if (TextCleaner.isValidCoverUrl(widget.novel.coverUrl)) {
                bestCover = widget.novel.coverUrl.trim();
              }
            }
            String bestTitle = TextCleaner.cleanNovelTitle(_novel.title);
            if (bestTitle.isEmpty || bestTitle == 'Unknown Novel' || bestTitle == 'Untitled') {
              if (TextCleaner.isValidNovelTitle(cachedDetails.title, _novel.sourceUrl)) {
                bestTitle = TextCleaner.cleanNovelTitle(cachedDetails.title);
              }
            }
            _novel = cachedDetails.copyWith(
              id: _novel.id,
              title: bestTitle.isNotEmpty ? bestTitle : _novel.title,
              coverUrl: bestCover.isNotEmpty ? bestCover : _novel.coverUrl,
              inLibrary: context.read<LibraryProvider>().isInLibrary(_novel.id),
            );
          }
          _isLoading = false;
        });
        _loadReadingProgress();
        context.read<DownloadService>().checkChaptersDownloaded(cachedChapters);
      }
    } catch (_) {}
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
    final displayList = _displayChapters;
    final rawIdx = displayList.indexWhere((c) => c.id == _lastReadChapter!.id || c.url == _lastReadChapter!.url);
    if (rawIdx >= 0) {
      final idx = _ascending ? rawIdx : (displayList.length - 1 - rawIdx);
      if (_scrollController.hasClients) {
        final targetOffset = (520.0 + (idx * 56.0)).clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _jumpToChapterNumber(int number) {
    if (_chapters.isEmpty) return;
    int targetIdx = -1;
    for (int i = 0; i < _chapters.length; i++) {
      final effNum = ChapterRangeParser.getEffectiveChapterNumber(_chapters[i], i);
      if (effNum == number) {
        targetIdx = i;
        break;
      }
    }
    if (targetIdx == -1 && number > 0 && number <= _chapters.length) {
      targetIdx = number - 1;
    }
    if (targetIdx >= 0) {
      final displayList = _displayChapters;
      final targetChapter = _chapters[targetIdx];
      final dispIdx = displayList.indexOf(targetChapter);
      if (dispIdx >= 0 && _scrollController.hasClients) {
        final listIdx = _ascending ? dispIdx : (displayList.length - 1 - dispIdx);
        final targetOffset = (520.0 + (listIdx * 56.0)).clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
    }
  }

  void _showJumpDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        title: const Text('Jump to Chapter'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Enter a chapter number (1 to ${_chapters.length}):',
              style: const TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF14141E),
                hintText: 'e.g. 500 or 1500',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = int.tryParse(controller.text.trim());
              Navigator.pop(ctx);
              if (val != null) {
                _jumpToChapterNumber(val);
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
            child: const Text('Jump'),
          ),
        ],
      ),
    );
  }

  Future<void> _fetchDetails() async {
    if (_chapters.isEmpty) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final source = SourceRegistry.getSource(_novel.sourceId) ?? SourceRegistry.getDefaultSource();
      final storage = context.read<StorageService>();

      // Fetch metadata details
      final fullNovel = await source.getNovelDetails(_novel.sourceUrl);
      if (mounted) {
        final cleanedFetchedTitle = TextCleaner.cleanNovelTitle(fullNovel.title);
        final isFetchedTitleValid = TextCleaner.isValidNovelTitle(cleanedFetchedTitle, _novel.sourceUrl);
        String bestTitle = TextCleaner.cleanNovelTitle(_novel.title);
        if (bestTitle.isEmpty || bestTitle == 'Unknown Novel' || bestTitle == 'Untitled') {
          if (isFetchedTitleValid) {
            bestTitle = cleanedFetchedTitle;
          }
        } else if (isFetchedTitleValid && cleanedFetchedTitle.isNotEmpty) {
          bestTitle = cleanedFetchedTitle;
        }

        String bestCover = fullNovel.coverUrl.trim();
        if (!TextCleaner.isValidCoverUrl(bestCover)) {
          if (TextCleaner.isValidCoverUrl(_novel.coverUrl)) {
            bestCover = _novel.coverUrl.trim();
          } else if (TextCleaner.isValidCoverUrl(widget.novel.coverUrl)) {
            bestCover = widget.novel.coverUrl.trim();
          }
        }
        setState(() {
          _novel = fullNovel.copyWith(
            id: _novel.id,
            title: bestTitle.isNotEmpty ? bestTitle : _novel.title,
            coverUrl: bestCover.isNotEmpty ? bestCover : _novel.coverUrl,
            inLibrary: context.read<LibraryProvider>().isInLibrary(_novel.id),
          );
        });
        unawaited(storage.cacheNovelDetails(_novel));
      }

      // Fetch chapter list with streaming batch callbacks
      final chapters = await source.getChapterList(
        _novel.sourceUrl,
        onBatchLoaded: (batch) {
          if (!mounted) return;
          if (batch.length > _chapters.length || _chapters.isEmpty) {
            setState(() {
              _chapters = batch;
              _isLoading = false;
              _isStreamingChapters = true;
            });
            _loadReadingProgress();
          }
        },
      );

      if (mounted) {
        setState(() {
          _chapters = chapters;
          _isLoading = false;
          _isStreamingChapters = false;
        });
        _loadReadingProgress();
        context.read<DownloadService>().checkChaptersDownloaded(chapters);
        unawaited(storage.cacheChapterList(_novel.id, chapters));
      }
    } catch (e) {
      if (mounted) {
        if (_chapters.isEmpty) {
          setState(() {
            _error = 'Failed to load novel details: $e';
            _isLoading = false;
            _isStreamingChapters = false;
          });
        } else {
          setState(() {
            _isStreamingChapters = false;
          });
        }
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
    DownloadRangeDialog.show(
      context,
      novel: _novel,
      chapters: _chapters,
    );
  }

  Future<void> _downloadFullBook() async {
    final downloadService = context.read<DownloadService>();
    try {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Starting download for "${_novel.title}"...'),
          duration: const Duration(seconds: 2),
        ),
      );
      final downloadedNovel = await downloadService.downloadEntireBook(novel: _novel);
      if (mounted) {
        setState(() {
          _novel = downloadedNovel;
        });
        await _loadCachedDataFirst();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Downloaded "${_novel.title}"! Unpacked ${_chapters.length} chapters.'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Download failed: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final libraryProvider = context.watch<LibraryProvider>();
    final downloadService = context.watch<DownloadService>();
    final isInLibrary = libraryProvider.isInLibrary(_novel.id);
    final isFullBook = _novel.isFullBook || _novel.sourceId == 'local_epub';
    final isBookDownloaded = !kIsWeb && downloadService.isBookDownloaded(_novel.id);
    final isDownloadingBook = !kIsWeb && downloadService.isDownloadingBook(_novel.id);
    final activeBookTask = !kIsWeb ? downloadService.activeBookDownloads[_novel.id] : null;

    final displayList = _displayChapters;

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
                    ((!kIsWeb && _sanitizedCoverUrl.startsWith('file://'))
                        ? Image.file(
                            File(Uri.parse(_sanitizedCoverUrl).toFilePath()),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(color: Colors.black87),
                          )
                        : Image.network(
                            kIsWeb ? getWebProxiedImageUrl(_sanitizedCoverUrl) : _sanitizedCoverUrl,
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
                                ? ((!kIsWeb && _sanitizedCoverUrl.startsWith('file://'))
                                    ? Image.file(
                                        File(Uri.parse(_sanitizedCoverUrl).toFilePath()),
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => _buildPlaceholderCover(),
                                      )
                                    : Image.network(
                                        kIsWeb ? getWebProxiedImageUrl(_sanitizedCoverUrl) : _sanitizedCoverUrl,
                                        headers: _imageHeaders,
                                        fit: BoxFit.cover,
                                        errorBuilder: (context, error, stackTrace) => _buildPlaceholderCover(),
                                      ))
                                : _buildPlaceholderCover(),
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
                              Row(
                                children: [
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
                                  if (isFullBook) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: const Color(0xFF8B5CF6), width: 0.8),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.auto_stories_rounded, size: 11, color: Color(0xFFA78BFA)),
                                          SizedBox(width: 4),
                                          Text(
                                            'BOOK',
                                            style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFA78BFA)),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ],
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
              if (!kIsWeb)
                IconButton(
                  icon: const Icon(Icons.folder_special_rounded, color: Color(0xFFA78BFA)),
                  tooltip: 'Storage Folder & Chapters',
                  onPressed: () => NovelStorageModal.show(context, _novel),
                ),
              if (!kIsWeb)
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
              if (!kIsWeb)
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
                  // Active Whole-Book Download Progress Banner
                  if (!kIsWeb && isDownloadingBook && activeBookTask != null) ...[
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
                              Row(
                                children: [
                                  const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFA78BFA)),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '${activeBookTask.stage}... (${(activeBookTask.progress * 100).toInt()}%)',
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                  ),
                                ],
                              ),
                              TextButton(
                                onPressed: () => downloadService.cancelBookDownload(_novel.id),
                                style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                                child: const Text('Cancel', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: activeBookTask.progress > 0 ? activeBookTask.progress : null,
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

                  // Active Download Progress Banner (Web Serial Chapters)
                  if (!kIsWeb && downloadService.isProcessing && downloadService.queue.any((t) => t.novel.id == _novel.id)) ...[
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
                        child: isFullBook && !isBookDownloaded
                            ? ElevatedButton.icon(
                                onPressed: isDownloadingBook ? null : _downloadFullBook,
                                icon: isDownloadingBook
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Icon(Icons.download_rounded),
                                label: Text(
                                  isDownloadingBook
                                      ? '${activeBookTask?.stage ?? 'Downloading'} (${((activeBookTask?.progress ?? 0) * 100).toInt()}%)'
                                      : 'Download Entire Book${_novel.bookSizeBytes != null && _novel.bookSizeBytes! > 0 ? ' (${(_novel.bookSizeBytes! / (1024 * 1024)).toStringAsFixed(1)} MB)' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF8B5CF6),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                ),
                              )
                            : ElevatedButton.icon(
                                onPressed: _chapters.isNotEmpty
                                    ? () => _openReader(_lastReadChapter ?? EpubService.getFirstNarrativeChapter(_chapters))
                                    : null,
                                icon: Icon(_lastReadChapter != null
                                    ? Icons.play_circle_fill_rounded
                                    : Icons.menu_book),
                                label: Text(
                                  _chapters.isEmpty
                                      ? (isFullBook ? 'Book Ready' : 'Loading...')
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
                      if (!kIsWeb) ...[
                        const SizedBox(width: 8),
                        if (isFullBook)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            decoration: BoxDecoration(
                              color: isBookDownloaded
                                  ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                  : const Color(0xFF28283C),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isBookDownloaded
                                    ? const Color(0xFF10B981).withValues(alpha: 0.5)
                                    : const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                                width: 0.8,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isBookDownloaded ? Icons.check_circle_rounded : Icons.auto_stories_rounded,
                                  size: 16,
                                  color: isBookDownloaded ? const Color(0xFF10B981) : const Color(0xFFA78BFA),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  isBookDownloaded ? 'Ready' : 'EPUB',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: isBookDownloaded ? const Color(0xFF10B981) : const Color(0xFFA78BFA),
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          ElevatedButton.icon(
                            onPressed: _chapters.isNotEmpty ? _showDownloadModal : null,
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: const Text('Download'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF28283C),
                              foregroundColor: const Color(0xFFA78BFA),
                              side: const BorderSide(color: Color(0xFF8B5CF6), width: 0.8),
                              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                      ],
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
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'Chapters (${displayList.length}/${_chapters.length})'
                                      : 'Chapters (${_chapters.length})',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                                if (_isStreamingChapters) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.sync_rounded,
                                          size: 11,
                                          color: Color(0xFFA78BFA),
                                        ),
                                        SizedBox(width: 4),
                                        Text(
                                          'Batch loading...',
                                          style: TextStyle(fontSize: 9.5, color: Color(0xFFA78BFA)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
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
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(_isSearchOpen ? Icons.close : Icons.search, size: 20),
                            tooltip: _isSearchOpen ? 'Close search' : 'Search chapters',
                            onPressed: () {
                              setState(() {
                                _isSearchOpen = !_isSearchOpen;
                                if (!_isSearchOpen) {
                                  _searchQuery = '';
                                  _searchController.clear();
                                }
                              });
                            },
                          ),
                          if (_chapters.length > 50)
                            IconButton(
                              icon: const Icon(Icons.directions_rounded, size: 20, color: Color(0xFFA78BFA)),
                              tooltip: 'Jump to chapter number',
                              onPressed: _showJumpDialog,
                            ),
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
                  if (_isSearchOpen) ...[
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchController,
                      autofocus: true,
                      onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: const Color(0xFF1E1E2C),
                        hintText: 'Filter by chapter number or title (e.g. 500, Epilogue)...',
                        hintStyle: const TextStyle(fontSize: 12, color: Colors.white38),
                        prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFFA78BFA)),
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 16, color: Colors.white54),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _searchQuery = '');
                                },
                              )
                            : null,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ],
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
                          if (!kIsWeb)
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
          else if (displayList.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
                child: isFullBook && !isBookDownloaded
                    ? Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E2C),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.auto_stories_rounded, size: 40, color: Color(0xFFA78BFA)),
                            const SizedBox(height: 12),
                            const Text(
                              'Complete Digital Book Edition',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'This book is available as a complete EPUB package. Download it once to unpack chapters, navigate the table of contents, and read offline.',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.7), height: 1.4),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: isDownloadingBook ? null : _downloadFullBook,
                              icon: isDownloadingBook
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                    )
                                  : const Icon(Icons.download_rounded),
                              label: Text(isDownloadingBook ? 'Downloading Book...' : 'Download Entire Book'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF8B5CF6),
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ],
                        ),
                      )
                    : Center(
                        child: Text(
                          _searchQuery.isNotEmpty
                              ? 'No chapters found matching "$_searchQuery"'
                              : 'No chapters available yet.',
                          style: const TextStyle(color: Colors.white54, fontSize: 13),
                        ),
                      ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final chapter = _ascending
                      ? displayList[index]
                      : displayList[displayList.length - 1 - index];
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
                          if (!kIsWeb) ...[
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
                          ],
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
                childCount: displayList.length,
              ),
            ),
        ],
      ),
    );
  }
}
