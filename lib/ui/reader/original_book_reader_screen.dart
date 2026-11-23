import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/services/pdf_page_renderer.dart';
import '../../core/models/novel.dart';

enum OriginalBookReaderMode {
  pagedHorizontal,
  continuousVertical,
}

class OriginalBookReaderScreen extends StatefulWidget {
  final Novel novel;
  final Directory bookDirectory;
  final int? initialPage;

  const OriginalBookReaderScreen({
    super.key,
    required this.novel,
    required this.bookDirectory,
    this.initialPage,
  });

  @override
  State<OriginalBookReaderScreen> createState() => _OriginalBookReaderScreenState();
}

class _OriginalBookReaderScreenState extends State<OriginalBookReaderScreen> {
  final List<String> _pagePaths = [];
  bool _isLoading = true;
  String? _errorMessage;
  int _currentPage = 0;
  bool _showControls = true;
  OriginalBookReaderMode _readerMode = OriginalBookReaderMode.pagedHorizontal;

  late PageController _pageController;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: widget.initialPage ?? 0);
    _loadPages();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  int _extractPageNumber(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    final match = RegExp(r'page_?(\d+)').firstMatch(fileName);
    return match != null ? int.tryParse(match.group(1)!) ?? 0 : 0;
  }

  Future<void> _loadPages() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final pagesDir = Directory('${widget.bookDirectory.path}/pages');
      final docPdf = File('${widget.bookDirectory.path}/document.pdf');

      List<String> foundPages = [];
      if (await pagesDir.exists()) {
        foundPages = pagesDir
            .listSync()
            .whereType<File>()
            .where((f) {
              final lower = f.path.toLowerCase();
              return lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.png');
            })
            .map((f) => f.path)
            .toList();
      }

      // Check if pages need initial or complete rendering
      int? expectedCount;
      if (await docPdf.exists()) {
        expectedCount = await PdfPageRenderer.getPageCount(docPdf.path);
      }

      final needsRender = foundPages.isEmpty ||
          (expectedCount != null && expectedCount > 0 && foundPages.length < expectedCount);

      if (needsRender && await docPdf.exists()) {
        final rendered = await PdfPageRenderer.renderPages(
          docPdf.path,
          pagesDir.path,
          dpi: 150,
        );
        if (rendered.isNotEmpty) {
          foundPages = rendered;
        }
      }

      // Sort numerically by page number (page_1, page_2, ..., page_10)
      foundPages.sort((a, b) => _extractPageNumber(a).compareTo(_extractPageNumber(b)));

      if (foundPages.isEmpty) {
        setState(() {
          _errorMessage = 'No readable pages found for this book.';
          _isLoading = false;
        });
        return;
      }

      // Restore saved progress
      final prefs = await SharedPreferences.getInstance();
      final savedPage = widget.initialPage ?? prefs.getInt('orig_book_page_${widget.novel.id}') ?? 0;
      final clampedPage = savedPage.clamp(0, foundPages.length - 1);

      setState(() {
        _pagePaths.clear();
        _pagePaths.addAll(foundPages);
        _currentPage = clampedPage;
        _isLoading = false;
      });

      _pageController = PageController(initialPage: clampedPage);
    } catch (e) {
      setState(() {
        _errorMessage = 'Failed to load book pages: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProgress(int pageIndex) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('orig_book_page_${widget.novel.id}', pageIndex);
    } catch (_) {}
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentPage = index;
    });
    _saveProgress(index);
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  void _jumpToPage(int page) {
    if (page < 0 || page >= _pagePaths.length) return;
    setState(() {
      _currentPage = page;
    });
    if (_readerMode == OriginalBookReaderMode.pagedHorizontal) {
      _pageController.jumpToPage(page);
    } else {
      // Approximate scroll position
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final target = (page / (_pagePaths.length - 1)) * maxScroll;
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    }
    _saveProgress(page);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D12),
      body: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: SafeArea(
          top: false,
          child: Stack(
            children: [
              // Page content area
              if (_isLoading)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFF8B5CF6)),
                      SizedBox(height: 16),
                      Text(
                        'Rendering original pages...',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                    ],
                  ),
                )
              else if (_errorMessage != null)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 48, color: Colors.redAccent),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.white70),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadPages,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6),
                            foregroundColor: Colors.white,
                          ),
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              else
                GestureDetector(
                  onTap: _toggleControls,
                  behavior: HitTestBehavior.translucent,
                  child: _readerMode == OriginalBookReaderMode.pagedHorizontal
                      ? PageView.builder(
                          controller: _pageController,
                          itemCount: _pagePaths.length,
                          onPageChanged: _onPageChanged,
                          itemBuilder: (context, index) {
                            return _buildSinglePage(_pagePaths[index], index);
                          },
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          itemCount: _pagePaths.length,
                          padding: EdgeInsets.only(
                            top: MediaQuery.of(context).padding.top + 56,
                            bottom: 100,
                          ),
                          itemBuilder: (context, index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _buildSinglePage(_pagePaths[index], index),
                            );
                          },
                        ),
                ),

              // Animated Top Bar
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                top: _showControls ? 0 : -100,
                left: 0,
                right: 0,
                child: _buildTopBar(),
              ),

              // Animated Bottom Bar
              AnimatedPositioned(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeInOut,
                bottom: _showControls ? 0 : -120,
                left: 0,
                right: 0,
                child: _buildBottomBar(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSinglePage(String path, int index) {
    final file = File(path);
    return InteractiveViewer(
      minScale: 1.0,
      maxScale: 4.0,
      child: Center(
        child: Image.file(
          file,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.high,
          errorBuilder: (context, error, stackTrace) => Container(
            height: 300,
            alignment: Alignment.center,
            child: Text(
              'Page ${index + 1} unavailable',
              style: const TextStyle(color: Colors.white54),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      padding: EdgeInsets.only(top: topPadding + 6, bottom: 10, left: 12, right: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161622).withValues(alpha: 0.95),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, 2)),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.novel.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                Text(
                  'Original Book Edition (${_pagePaths.length} Pages)',
                  style: const TextStyle(
                    color: Color(0xFFA78BFA),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(
              _readerMode == OriginalBookReaderMode.pagedHorizontal
                  ? Icons.view_day_rounded
                  : Icons.view_carousel_rounded,
              color: Colors.white70,
            ),
            tooltip: _readerMode == OriginalBookReaderMode.pagedHorizontal
                ? 'Switch to Continuous Scroll'
                : 'Switch to Horizontal Flip',
            onPressed: () {
              setState(() {
                _readerMode = _readerMode == OriginalBookReaderMode.pagedHorizontal
                    ? OriginalBookReaderMode.continuousVertical
                    : OriginalBookReaderMode.pagedHorizontal;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final totalPages = _pagePaths.length;
    final currentDisplay = totalPages > 0 ? _currentPage + 1 : 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF161622).withValues(alpha: 0.95),
        boxShadow: const [
          BoxShadow(color: Colors.black45, blurRadius: 10, offset: Offset(0, -2)),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Page $currentDisplay of $totalPages',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left_rounded, color: Colors.white70, size: 28),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _currentPage > 0 ? () => _jumpToPage(_currentPage - 1) : null,
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.chevron_right_rounded, color: Colors.white70, size: 28),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: _currentPage < totalPages - 1 ? () => _jumpToPage(_currentPage + 1) : null,
                  ),
                ],
              ),
            ],
          ),
          if (totalPages > 1)
            SliderTheme(
              data: SliderTheme.of(context).copyWith(
                activeTrackColor: const Color(0xFF8B5CF6),
                inactiveTrackColor: Colors.white12,
                thumbColor: const Color(0xFFA78BFA),
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              ),
              child: Slider(
                min: 0,
                max: (totalPages - 1).toDouble(),
                value: _currentPage.clamp(0, totalPages - 1).toDouble(),
                onChanged: (val) {
                  _jumpToPage(val.round());
                },
              ),
            ),
        ],
      ),
    );
  }
}
