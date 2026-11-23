import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../../core/models/novel.dart';
import '../../core/services/epub_service.dart';
import '../../extractors/novel_source.dart';
import '../../extractors/source_registry.dart';
import '../../providers/library_provider.dart';
import '../novel/novel_detail_screen.dart';
import '../widgets/novel_card.dart';
import '../widgets/source_webview_screen.dart';
import '../widgets/source_selection_modal.dart';
import '../search/global_search_screen.dart';
import '../widgets/update_dialog.dart';

class BrowseScreen extends StatefulWidget {
  const BrowseScreen({super.key});

  @override
  State<BrowseScreen> createState() => _BrowseScreenState();
}

class _BrowseScreenState extends State<BrowseScreen> {
  final TextEditingController _searchController = TextEditingController();
  late NovelSource _currentSource;
  bool _isGlobalSearch = false;
  String _feedMode = 'popular'; // 'popular' or 'latest'

  List<Novel> _novels = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isSearching = false;

  // Stale-While-Revalidate memory cache for instant source switching (0ms delay)
  static final Map<String, List<Novel>> _sourceNovelsCache = {};
  static final Map<String, DateTime> _sourceCacheTime = {};
  static const Duration _cacheTtl = Duration(minutes: 30);
  static bool _prewarmingStarted = false;
  Timer? _prewarmTimer;

  @override
  void initState() {
    super.initState();
    _currentSource = SourceRegistry.getDefaultSource();
    _loadPopular();
    if (!_prewarmingStarted && !Platform.environment.containsKey('FLUTTER_TEST')) {
      _prewarmingStarted = true;
      _prewarmPopularSources();
    }
  }

  void _prewarmPopularSources() {
    _prewarmTimer?.cancel();
    _prewarmTimer = Timer(const Duration(milliseconds: 1500), () async {
      if (!mounted) return;
      final topSourceIds = ['readnovelfull', 'novelfull', 'openlibrary', 'odiabibhaba', 'royalroad'];
      for (final sId in topSourceIds) {
        if (!mounted) break;
        if (_sourceNovelsCache.containsKey(sId)) continue;
        final src = SourceRegistry.getSource(sId);
        if (src != null && src.id != _currentSource.id) {
          try {
            final list = await src.getPopular(page: 1);
            if (list.isNotEmpty) {
              _sourceNovelsCache[src.id] = list;
              _sourceCacheTime[src.id] = DateTime.now();
            }
          } catch (_) {}
          if (!mounted) break;
          await Future.delayed(const Duration(milliseconds: 350));
        }
      }
    });
  }

  @override
  void dispose() {
    _prewarmTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadFeed({bool forceRefresh = false}) async {
    if (_feedMode == 'latest') {
      await _loadLatest(forceRefresh: forceRefresh);
    } else {
      await _loadPopular(forceRefresh: forceRefresh);
    }
  }

  Future<void> _loadPopular({bool forceRefresh = false}) async {
    final cacheKey = _currentSource.id;
    final cached = _sourceNovelsCache[cacheKey];
    final cacheTime = _sourceCacheTime[cacheKey];
    final isCacheValid = cached != null && cacheTime != null && DateTime.now().difference(cacheTime) < _cacheTtl;

    if (!forceRefresh && cached != null && cached.isNotEmpty) {
      setState(() {
        _novels = cached;
        _isLoading = false;
        _errorMessage = null;
        _isSearching = false;
      });

      if (!isCacheValid) {
        _revalidateInBackground(_currentSource);
      }
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isSearching = false;
    });

    try {
      final list = await _currentSource.getPopular(page: 1);
      if (list.isNotEmpty) {
        _sourceNovelsCache[cacheKey] = list;
        _sourceCacheTime[cacheKey] = DateTime.now();
      }
      if (mounted) {
        setState(() {
          _novels = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load novels from ${_currentSource.name}: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _loadLatest({bool forceRefresh = false}) async {
    final cacheKey = '${_currentSource.id}_latest';
    final cached = _sourceNovelsCache[cacheKey];

    if (!forceRefresh && cached != null && cached.isNotEmpty) {
      setState(() {
        _novels = cached;
        _isLoading = false;
        _errorMessage = null;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isSearching = false;
    });

    try {
      final list = await _currentSource.getLatest(page: 1);
      if (list.isNotEmpty) {
        _sourceNovelsCache[cacheKey] = list;
        _sourceCacheTime[cacheKey] = DateTime.now();
      }
      if (mounted) {
        setState(() {
          _novels = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Failed to load latest novels from ${_currentSource.name}: $e';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _revalidateInBackground(NovelSource source) async {
    try {
      final list = await source.getPopular(page: 1);
      if (list.isNotEmpty) {
        _sourceNovelsCache[source.id] = list;
        _sourceCacheTime[source.id] = DateTime.now();
        if (mounted && _currentSource.id == source.id && !_isSearching && _feedMode == 'popular') {
          setState(() {
            _novels = list;
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _loadFeed();
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isSearching = true;
    });

    try {
      final list = await _currentSource.search(trimmed, page: 1);
      if (mounted) {
        setState(() {
          _novels = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Search failed on ${_currentSource.name}: $e';
          _isLoading = false;
        });
      }
    }
  }

  void _onSourceChanged(NovelSource? source) {
    if (source == null) {
      setState(() {
        _isGlobalSearch = true;
      });
      return;
    }
    setState(() {
      _isGlobalSearch = false;
      _currentSource = source;
    });
    _searchController.clear();
    _loadFeed();
  }

  void _openSourceModal() {
    SourceSelectionModal.show(
      context: context,
      currentSource: _currentSource,
      onSourceSelected: _onSourceChanged,
    );
  }

  Future<void> _openSourceWebView() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => SourceWebViewScreen(
          initialUrl: _currentSource.baseUrl,
          sourceName: _currentSource.name,
        ),
      ),
    );
    if (result == true && mounted) {
      if (_isSearching) {
        _performSearch(_searchController.text);
      } else {
        _loadFeed();
      }
    }
  }

  Future<void> _importEpubFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.any,
      );
      if (files.isNotEmpty && files.first.path != null) {
        final path = files.first.path!;
        if (!mounted) return;
        final scaffold = ScaffoldMessenger.of(context);
        final lower = path.toLowerCase();
        if (!lower.endsWith('.epub') && !lower.endsWith('.pdf')) {
          scaffold.showSnackBar(
            const SnackBar(content: Text('Please select an .epub or .pdf file (e.g. book.epub, novel.pdf)')),
          );
          return;
        }
        final isPdf = lower.endsWith('.pdf');
        scaffold.showSnackBar(
          SnackBar(content: Text(isPdf ? 'Importing PDF book...' : 'Importing EPUB book...')),
        );
        final file = File(path);
        final novel = await EpubService().importBook(file);
        if (mounted) {
          await context.read<LibraryProvider>().saveToLibrary(novel);
          scaffold.hideCurrentSnackBar();
          scaffold.showSnackBar(
            SnackBar(
              content: Text('Successfully imported "${novel.title}"!'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          _loadFeed();
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import EPUB: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _scanDeviceEpubs() async {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      const SnackBar(content: Text('Scanning device downloads for EPUBs...')),
    );
    try {
      final epubs = await EpubService().findDeviceEpubs();
      if (epubs.isEmpty) {
        scaffold.hideCurrentSnackBar();
        scaffold.showSnackBar(
          const SnackBar(content: Text('No .epub files found in Download folder.')),
        );
        return;
      }
      int count = 0;
      for (final f in epubs) {
        try {
          final novel = await EpubService().importEpub(f);
          if (mounted) {
            await context.read<LibraryProvider>().saveToLibrary(novel);
          }
          count++;
        } catch (_) {}
      }
      scaffold.hideCurrentSnackBar();
      scaffold.showSnackBar(
        SnackBar(
          content: Text('Found and imported $count EPUB books!'),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      if (mounted) {
        _loadFeed();
      }
    } catch (e) {
      scaffold.hideCurrentSnackBar();
      scaffold.showSnackBar(
        SnackBar(content: Text('Error scanning downloads: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isGlobalSearch) {
      return GlobalSearchScreen(
        isEmbeddedInTab: true,
        onSwitchToSources: () {
          setState(() {
            _isGlobalSearch = false;
          });
          if (_novels.isEmpty) {
            _loadFeed();
          }
        },
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F16),
      appBar: AppBar(
        backgroundColor: const Color(0xFF14141E),
        elevation: 0,
        titleSpacing: 16,
        title: const Row(
          children: [
            Icon(Icons.explore_rounded, color: Color(0xFFA78BFA), size: 24),
            SizedBox(width: 10),
            Text(
              'Browse',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 20,
                color: Colors.white,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _feedMode == 'popular' ? Icons.local_fire_department_rounded : Icons.flash_on_rounded,
              color: const Color(0xFFA78BFA),
              size: 22,
            ),
            tooltip: _feedMode == 'popular' ? 'Feed: Popular (tap for Latest)' : 'Feed: Latest (tap for Popular)',
            onPressed: () {
              setState(() {
                _feedMode = _feedMode == 'popular' ? 'latest' : 'popular';
              });
              _loadFeed();
            },
          ),
          if (!kIsWeb && _currentSource.id == 'local_epub') ...[
            IconButton(
              icon: const Icon(Icons.file_upload_outlined, color: Color(0xFFA78BFA)),
              tooltip: 'Import EPUB / PDF File',
              onPressed: _importEpubFile,
            ),
            IconButton(
              icon: const Icon(Icons.folder_open_outlined, color: Color(0xFFA78BFA)),
              tooltip: 'Scan Downloads Folder',
              onPressed: _scanDeviceEpubs,
            ),
          ],
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.public, size: 21, color: Colors.white70),
              tooltip: 'Open in WebView / Bypass Cloudflare',
              onPressed: _openSourceWebView,
            ),
          if (!kIsWeb)
            IconButton(
              icon: const Icon(Icons.system_update_rounded, size: 21, color: Color(0xFFA78BFA)),
              tooltip: 'Check for Updates',
              onPressed: () => showAppUpdateDialog(context),
            ),
          const SizedBox(width: 4),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(104),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Top Partition: Explore Sources (Active) vs Global Search
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  height: 38,
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A26),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          alignment: Alignment.center,
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.source_rounded, size: 16, color: Colors.white),
                              SizedBox(width: 6),
                              Text(
                                'Explore Sources',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: InkWell(
                          onTap: () => setState(() => _isGlobalSearch = true),
                          borderRadius: BorderRadius.circular(9),
                          child: Container(
                            alignment: Alignment.center,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.travel_explore_rounded, size: 16, color: Colors.white.withValues(alpha: 0.7)),
                                const SizedBox(width: 6),
                                Text(
                                  'Global Search',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: Colors.white.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              // Clean Search Bar + Filter/Source Button in a single horizontal row
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 44,
                        child: TextField(
                          controller: _searchController,
                          style: const TextStyle(fontSize: 14, color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Search in ${_currentSource.name}...',
                            hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                            prefixIcon: const Icon(Icons.search, size: 20, color: Color(0xFFA78BFA)),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18, color: Colors.white70),
                                    onPressed: () {
                                      _searchController.clear();
                                      _loadFeed();
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: const Color(0xFF1E1E28),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Colors.white12),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Colors.white12),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5),
                            ),
                          ),
                          onSubmitted: _performSearch,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Standard Source Filter Button that opens the vertical source selector
                    Material(
                      color: const Color(0xFF1E1E28),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: _openSourceModal,
                        borderRadius: BorderRadius.circular(10),
                        child: Container(
                          height: 44,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.45)),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tune_rounded, color: Color(0xFFA78BFA), size: 19),
                              SizedBox(width: 6),
                              Text(
                                'Sources',
                                style: TextStyle(
                                  color: Color(0xFFA78BFA),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        color: const Color(0xFF8B5CF6),
        backgroundColor: const Color(0xFF1E1E28),
        onRefresh: () async {
          if (_isSearching) {
            await _performSearch(_searchController.text);
          } else {
            await _loadFeed(forceRefresh: true);
          }
        },
        child: _buildBody(),
      ),
    );
  }


  Widget _buildBody() {
    if (_isLoading) {
      return LayoutBuilder(
        builder: (context, constraints) {
          int crossAxisCount = 2;
          if (constraints.maxWidth > 900) {
            crossAxisCount = 5;
          } else if (constraints.maxWidth > 600) {
            crossAxisCount = 3;
          }
          return GridView.builder(
            padding: const EdgeInsets.all(16),
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              childAspectRatio: 0.58,
              crossAxisSpacing: 14,
              mainAxisSpacing: 18,
            ),
            itemCount: crossAxisCount * 3,
            itemBuilder: (context, index) {
              return Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E28),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Color(0xFF262636),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 12,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              color: const Color(0xFF2E2E42),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 10,
                            width: 80,
                            decoration: BoxDecoration(
                              color: const Color(0xFF242436),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    }

    if (_errorMessage != null) {
      final isCloudflare = _errorMessage!.toLowerCase().contains('cloudflare') || _errorMessage!.contains('403');
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isCloudflare ? Icons.security : Icons.cloud_off,
                size: 52,
                color: isCloudflare ? Colors.amberAccent : Colors.orangeAccent,
              ),
              const SizedBox(height: 12),
              Text(
                isCloudflare ? 'Protection / Verification Required' : 'Failed to Load Novels',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  if (!kIsWeb)
                    ElevatedButton.icon(
                      onPressed: _openSourceWebView,
                      icon: const Icon(Icons.security, size: 16),
                      label: Text(isCloudflare ? 'Solve Cloudflare Challenge' : 'Open in WebView'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF8B5CF6),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _loadFeed(forceRefresh: true),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openSourceModal,
                    icon: const Icon(Icons.swap_horiz, size: 16),
                    label: const Text('Switch Source'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_novels.isEmpty) {
      if (_currentSource.id == 'local_epub') {
        return Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.menu_book_rounded, size: 54, color: Color(0xFFA78BFA)),
                ),
                const SizedBox(height: 18),
                const Text(
                  'No Local EPUBs or PDFs Imported Yet',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Import EPUB or PDF books directly from your device storage to read completely offline with Text-to-Speech support.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, height: 1.4),
                ),
                if (!kIsWeb) ...[
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: _importEpubFile,
                    icon: const Icon(Icons.file_upload_outlined, size: 18),
                    label: const Text('Import EPUB / PDF File', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _scanDeviceEpubs,
                    icon: const Icon(Icons.folder_open_outlined, size: 18),
                    label: const Text('Scan Downloads Folder'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFA78BFA),
                      side: const BorderSide(color: Color(0xFF8B5CF6)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      }

      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.search_off, size: 48, color: Colors.white30),
            const SizedBox(height: 12),
            Text(
              _isSearching ? 'No novels found for your search.' : 'No novels available right now.',
              style: const TextStyle(color: Colors.white60),
            ),
          ],
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        int crossAxisCount = 2;
        if (constraints.maxWidth > 900) {
          crossAxisCount = 5;
        } else if (constraints.maxWidth > 600) {
          crossAxisCount = 3;
        }

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            childAspectRatio: 0.58,
            crossAxisSpacing: 14,
            mainAxisSpacing: 18,
          ),
          itemCount: _novels.length,
          itemBuilder: (context, index) {
            final novel = _novels[index];
            return NovelCard(
              novel: novel,
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => NovelDetailScreen(novel: novel),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
