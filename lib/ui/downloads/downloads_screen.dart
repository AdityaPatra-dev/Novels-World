import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/services/webview_session_manager.dart';
import '../../core/utils/text_cleaner.dart';
import '../../data/download_service.dart';
import '../../data/storage_service.dart';
import '../../extractors/source_registry.dart';
import '../../providers/reader_provider.dart';
import '../novel/novel_detail_screen.dart';
import '../reader/reader_screen.dart';
import '../widgets/download_range_dialog.dart';
import '../widgets/novel_storage_modal.dart';

class DownloadsScreen extends StatefulWidget {
  final VoidCallback? onBrowseTap;

  const DownloadsScreen({super.key, this.onBrowseTap});

  @override
  State<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends State<DownloadsScreen> {
  final StorageService _storageService = StorageService();
  List<Novel> _downloadedNovels = [];
  bool _isLoading = true;
  double _totalStorageMb = 0.0;
  int _totalChaptersCount = 0;

  @override
  void initState() {
    super.initState();
    _loadDownloadedNovels();
  }

  Future<void> _loadDownloadedNovels() async {
    setState(() => _isLoading = true);
    final novels = await _storageService.getDownloadedNovels();
    final mb = await _storageService.getCacheSizeMb();
    final chCount = await _storageService.getTotalCachedChapterCount();

    if (mounted) {
      setState(() {
        _downloadedNovels = novels;
        _totalStorageMb = mb;
        _totalChaptersCount = chCount;
        _isLoading = false;
      });
    }
  }

  void _showStorageLocationDialog() {
    final path = _storageService.chaptersDirectoryPath;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E2C),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.folder_open_rounded, color: Color(0xFFA78BFA)),
            SizedBox(width: 10),
            Text('Downloads Location', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Offline chapters and EPUB novels are stored on your local device storage:',
              style: TextStyle(fontSize: 13, color: Colors.white70),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF14141E),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white12),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      path,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Color(0xFFA78BFA),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18, color: Colors.white70),
                    tooltip: 'Copy Path',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: path));
                      Navigator.pop(ctx);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Storage path copied to clipboard'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total Storage: ${_totalStorageMb.toStringAsFixed(2)} MB',
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                ),
                Text(
                  '$_totalChaptersCount files',
                  style: const TextStyle(fontSize: 12, color: Colors.white60),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final downloadService = context.watch<DownloadService>();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Downloads (${_downloadedNovels.length})',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.folder_open_rounded, color: Color(0xFFA78BFA)),
            tooltip: 'Where files are saved',
            onPressed: _showStorageLocationDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Downloads',
            onPressed: _loadDownloadedNovels,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadDownloadedNovels,
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                children: [
                  // Prominent Storage Location Banner
                  _buildStorageLocationCard(),

                  const SizedBox(height: 12),

                  // Active Download Queue Banner
                  if (downloadService.isProcessing || downloadService.queue.isNotEmpty) ...[
                    _buildActiveDownloadBanner(downloadService),
                    const SizedBox(height: 12),
                  ],

                  if (_downloadedNovels.isEmpty)
                    _buildEmptyState()
                  else ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8, top: 4),
                      child: Text(
                        'Downloaded Novels (${_downloadedNovels.length})',
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    ..._downloadedNovels.map(
                      (novel) => _DownloadedNovelCard(
                        novel: novel,
                        onNovelUpdated: _loadDownloadedNovels,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildStorageLocationCard() {
    final path = _storageService.chaptersDirectoryPath;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.folder_rounded, color: Color(0xFFA78BFA), size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Text(
                      'Saved Files Location',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    SizedBox(width: 6),
                    Icon(Icons.check_circle_rounded, size: 12, color: Colors.greenAccent),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  path,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Color(0xFFA78BFA), fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, size: 18, color: Color(0xFFA78BFA)),
            tooltip: 'View file details',
            onPressed: _showStorageLocationDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildActiveDownloadBanner(DownloadService downloadService) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1B26),
        borderRadius: BorderRadius.circular(12),
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
                    'Downloading (${downloadService.completedInCurrentBatch}/${downloadService.totalInCurrentBatch})',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(
                      downloadService.isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      size: 20,
                      color: Colors.white70,
                    ),
                    visualDensity: VisualDensity.compact,
                    onPressed: () {
                      if (downloadService.isPaused) {
                        downloadService.resume();
                      } else {
                        downloadService.pause();
                      }
                    },
                  ),
                  TextButton(
                    onPressed: () => downloadService.cancelAll(),
                    style: TextButton.styleFrom(visualDensity: VisualDensity.compact, padding: EdgeInsets.zero),
                    child: const Text('Cancel All', style: TextStyle(color: Colors.redAccent, fontSize: 11)),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: downloadService.batchProgress,
              backgroundColor: Colors.white10,
              color: const Color(0xFF8B5CF6),
              minHeight: 6,
            ),
          ),
          if (downloadService.currentTask != null) ...[
            const SizedBox(height: 6),
            Text(
              '${downloadService.currentTask!.novel.title} • ${downloadService.currentTask!.chapter.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.6)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_download_outlined, size: 64, color: Colors.white.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            const Text(
              'No Downloaded Novels Yet',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              'Download chapters or entire novels for reading offline anywhere without an internet connection.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
            ),
            const SizedBox(height: 24),
            if (widget.onBrowseTap != null)
              ElevatedButton.icon(
                onPressed: widget.onBrowseTap,
                icon: const Icon(Icons.explore),
                label: const Text('Browse Novels to Download'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DownloadedNovelCard extends StatefulWidget {
  final Novel novel;
  final VoidCallback onNovelUpdated;

  const _DownloadedNovelCard({
    required this.novel,
    required this.onNovelUpdated,
  });

  @override
  State<_DownloadedNovelCard> createState() => _DownloadedNovelCardState();
}

class _DownloadedNovelCardState extends State<_DownloadedNovelCard> {
  final StorageService _storageService = StorageService();
  NovelStorageInfo? _storageInfo;
  List<Chapter> _chapters = [];

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final info = await _storageService.getNovelStorageInfo(widget.novel);
    if (mounted) {
      setState(() {
        _storageInfo = info;
      });
    }
  }

  Future<void> _fetchChaptersIfNeeded() async {
    if (_chapters.isNotEmpty) return;
    try {
      final cached = await _storageService.getCachedChapters(widget.novel.id);
      if (cached != null && cached.isNotEmpty && mounted) {
        setState(() => _chapters = cached);
        return;
      }
      final source = SourceRegistry.getSource(widget.novel.sourceId) ?? SourceRegistry.getDefaultSource();
      final chs = await source.getChapterList(widget.novel.sourceUrl);
      if (mounted) {
        setState(() => _chapters = chs);
        await _storageService.cacheChapterList(widget.novel.id, chs);
      }
    } catch (_) {}
  }

  void _openRangeDownloadDialog() async {
    if (_chapters.isEmpty) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const Center(
          child: CircularProgressIndicator(),
        ),
      );
      await _fetchChaptersIfNeeded();
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }

    if (!mounted) return;
    if (_chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not load chapter list for this novel.')),
      );
      return;
    }

    await DownloadRangeDialog.show(
      context,
      novel: widget.novel,
      chapters: _chapters,
    );
    _loadInfo();
    widget.onNovelUpdated();
  }

  void _startReading() async {
    await _fetchChaptersIfNeeded();
    if (!mounted) return;

    if (_chapters.isEmpty) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => NovelDetailScreen(novel: widget.novel),
        ),
      );
      return;
    }

    // Find first unread or last read chapter
    final progress = _storageService.getProgress(widget.novel.id);
    Chapter targetChapter = _chapters.first;
    if (progress != null) {
      final found = _chapters.where((c) => c.id == progress.chapterId);
      if (found.isNotEmpty) targetChapter = found.first;
    }

    final readerProvider = context.read<ReaderProvider>();
    await readerProvider.initializeNovelReader(
      novel: widget.novel,
      chapters: _chapters,
      initialChapter: targetChapter,
    );
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const ReaderScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chapterCount = _storageInfo?.chapterCount ?? 0;
    final sizeFormatted = _storageInfo?.formattedSize ?? '...';
    final storageDir = _storageInfo?.directoryPath ?? _storageService.chaptersDirectoryPath;

    return Card(
      color: const Color(0xFF1A1A24),
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Colors.white10),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => NovelDetailScreen(novel: widget.novel),
            ),
          ).then((_) {
            _loadInfo();
            widget.onNovelUpdated();
          });
        },
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top Row: Cover Thumbnail + Info + Storage files action
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 64,
                      height: 88,
                      color: const Color(0xFF262636),
                      child: (widget.novel.coverUrl.isNotEmpty && TextCleaner.isValidCoverUrl(widget.novel.coverUrl))
                          ? (widget.novel.coverUrl.startsWith('file://')
                              ? Image.file(
                                  File(Uri.parse(widget.novel.coverUrl).toFilePath()),
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.book, color: Colors.white30),
                                )
                              : Image.network(
                                  widget.novel.coverUrl,
                                  headers: {'User-Agent': WebViewSessionManager.defaultUserAgent},
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.book, color: Colors.white30),
                                ))
                          : const Icon(Icons.book, color: Colors.white30),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          TextCleaner.cleanNovelTitle(widget.novel.title),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          widget.novel.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                        const SizedBox(height: 6),
                        // Download badge and storage size
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF10B981).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.offline_pin_rounded, size: 12, color: Color(0xFF34D399)),
                                  const SizedBox(width: 4),
                                  Text(
                                    '$chapterCount Chapters',
                                    style: const TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF34D399),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                sizeFormatted,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: Color(0xFFA78BFA),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // File / Folder Option for this novel
                  IconButton(
                    icon: const Icon(Icons.folder_special_rounded, color: Color(0xFFA78BFA)),
                    tooltip: 'Where files are saved',
                    onPressed: () => NovelStorageModal.show(context, widget.novel),
                  ),
                ],
              ),

              const SizedBox(height: 8),

              // File Location Pill
              InkWell(
                onTap: () => NovelStorageModal.show(context, widget.novel),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14141E),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.folder_outlined, size: 12, color: Color(0xFFA78BFA)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Saved: $storageDir',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, color: Colors.white60, fontFamily: 'monospace'),
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Text(
                        'View Files',
                        style: TextStyle(fontSize: 9.5, color: Color(0xFFA78BFA), fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              // Action Row: "Start Reading" button + "Download" button just beside it!
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _startReading,
                      icon: const Icon(Icons.play_circle_fill_rounded, size: 18),
                      label: Text(
                        widget.novel.lastReadChapterId != null ? 'Continue Reading' : 'Start Reading',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Download button just beside Start Reading
                  ElevatedButton.icon(
                    onPressed: _openRangeDownloadDialog,
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text(
                      'Download',
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF282838),
                      foregroundColor: const Color(0xFFA78BFA),
                      side: const BorderSide(color: Color(0xFF8B5CF6), width: 0.8),
                      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                    tooltip: 'Delete downloaded chapters',
                    onPressed: () async {
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          backgroundColor: const Color(0xFF1E1E2C),
                          title: const Text('Delete Downloads?'),
                          content: Text('Remove all downloaded chapters for "${widget.novel.title}" from device storage?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
                              child: const Text('Delete'),
                            ),
                          ],
                        ),
                      );
                      if (confirm == true && mounted) {
                        await _storageService.deleteNovelStorage(widget.novel);
                        _loadInfo();
                        widget.onNovelUpdated();
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
