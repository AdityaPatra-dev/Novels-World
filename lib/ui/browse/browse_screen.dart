import 'dart:io';
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

  List<Novel> _novels = [];
  bool _isLoading = true;
  String? _errorMessage;
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _currentSource = SourceRegistry.getDefaultSource();
    _loadPopular();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPopular() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isSearching = false;
    });

    try {
      final list = await _currentSource.getPopular(page: 1);
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

  Future<void> _performSearch(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      _loadPopular();
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
    if (source != null && source.id != _currentSource.id) {
      setState(() {
        _currentSource = source;
      });
      _searchController.clear();
      _loadPopular();
    }
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
        _loadPopular();
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
        if (!path.toLowerCase().endsWith('.epub')) {
          scaffold.showSnackBar(
            const SnackBar(content: Text('Please select an .epub file (e.g. book.epub)')),
          );
          return;
        }
        scaffold.showSnackBar(
          const SnackBar(content: Text('Importing EPUB book...')),
        );
        final file = File(path);
        final novel = await EpubService().importEpub(file);
        if (mounted) {
          await context.read<LibraryProvider>().saveToLibrary(novel);
          scaffold.hideCurrentSnackBar();
          scaffold.showSnackBar(
            SnackBar(
              content: Text('Successfully imported "${novel.title}"!'),
              backgroundColor: const Color(0xFF10B981),
            ),
          );
          _loadPopular();
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
        _loadPopular();
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
    final allSources = SourceRegistry.getAllSources();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse Novels', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          if (_currentSource.id == 'local_epub') ...[
            IconButton(
              icon: const Icon(Icons.file_upload_outlined, color: Color(0xFFA78BFA)),
              tooltip: 'Import EPUB File',
              onPressed: _importEpubFile,
            ),
            IconButton(
              icon: const Icon(Icons.folder_open_outlined, color: Color(0xFFA78BFA)),
              tooltip: 'Scan Downloads Folder',
              onPressed: _scanDeviceEpubs,
            ),
          ],
          IconButton(
            icon: const Icon(Icons.travel_explore_rounded, size: 24, color: Color(0xFFA78BFA)),
            tooltip: 'Global Search (All Sources)',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GlobalSearchScreen(initialQuery: _searchController.text),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.system_update_rounded, size: 22, color: Color(0xFFA78BFA)),
            tooltip: 'Check for Updates',
            onPressed: () => showAppUpdateDialog(context),
          ),
          IconButton(
            icon: const Icon(Icons.public, size: 22),
            tooltip: 'Open in WebView / Bypass Cloudflare',
            onPressed: _openSourceWebView,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(115),
          child: Column(
            children: [
              // Source Selector Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Icon(Icons.source, size: 18, color: Color(0xFF8B5CF6)),
                    const SizedBox(width: 8),
                    const Text('Source:', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E28),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<NovelSource>(
                            value: _currentSource,
                            isExpanded: true,
                            dropdownColor: const Color(0xFF1E1E28),
                            items: allSources.map((s) {
                              return DropdownMenuItem(
                                value: s,
                                child: Text('${s.name} (${s.lang.toUpperCase()})', style: const TextStyle(fontSize: 13)),
                              );
                            }).toList(),
                            onChanged: _onSourceChanged,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),

              // Search Bar with In-Line Global Search Trigger
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search title or author...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_searchController.text.isNotEmpty)
                          IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _loadPopular();
                            },
                          ),
                        IconButton(
                          icon: const Icon(Icons.travel_explore_rounded, size: 20, color: Color(0xFF8B5CF6)),
                          tooltip: 'Global Search across all sources',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => GlobalSearchScreen(initialQuery: _searchController.text),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1E1E28),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: _performSearch,
                ),
              ),
            ],
          ),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          if (_isSearching) {
            await _performSearch(_searchController.text);
          } else {
            await _loadPopular();
          }
        },
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
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
                    onPressed: _loadPopular,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
                  if (_currentSource.id != 'readnovelfull')
                    OutlinedButton.icon(
                      onPressed: () {
                        final rnf = SourceRegistry.getSource('readnovelfull');
                        if (rnf != null) {
                          _onSourceChanged(rnf);
                        }
                      },
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: const Text('Switch to ReadNovelFull'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () {
                        final novgo = SourceRegistry.getSource('novgo');
                        if (novgo != null) {
                          _onSourceChanged(novgo);
                        }
                      },
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: const Text('Switch to NOVGO'),
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
                  'No Local EPUBs Imported Yet',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  'Import EPUB books directly from your phone (e.g. Harry Potter, Dune, Lord of the Rings) to read completely offline with Text-to-Speech support.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13, height: 1.4),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _importEpubFile,
                  icon: const Icon(Icons.file_upload_outlined, size: 18),
                  label: const Text('Import EPUB File', style: TextStyle(fontWeight: FontWeight.bold)),
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
        // Responsive grid columns: 2 on phone, 3 on tablet, 4+ on laptop
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
