import 'package:flutter/material.dart';
import '../../core/models/novel.dart';
import '../../extractors/novel_source.dart';
import '../../extractors/source_registry.dart';
import '../novel/novel_detail_screen.dart';
import '../widgets/novel_card.dart';
import '../widgets/source_webview_screen.dart';
import '../search/global_search_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final allSources = SourceRegistry.getAllSources();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Browse Novels', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
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
                  if (_currentSource.id != 'royalroad')
                    OutlinedButton.icon(
                      onPressed: () {
                        final rr = SourceRegistry.getSource('royalroad');
                        if (rr != null) {
                          _onSourceChanged(rr);
                        }
                      },
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: const Text('Switch to Royal Road'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () {
                        final rnf = SourceRegistry.getSource('readnovelfull');
                        if (rnf != null) {
                          _onSourceChanged(rnf);
                        }
                      },
                      icon: const Icon(Icons.swap_horiz, size: 16),
                      label: const Text('Switch to ReadNovelFull'),
                    ),
                ],
              ),
            ],
          ),
        ),
      );
    }

    if (_novels.isEmpty) {
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
