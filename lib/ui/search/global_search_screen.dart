import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/novel.dart';
import '../../core/services/global_search_controller.dart';
import '../../core/services/webview_session_manager.dart';
import '../../extractors/novel_source.dart';
import '../novel/novel_detail_screen.dart';

/// Global Multi-Source Search Screen.
/// Concurrently searches all cataloged sources, streams results in real time,
/// clusters identical novel titles across sources, and provides one-tap direct navigation.
class GlobalSearchScreen extends StatefulWidget {
  final String? initialQuery;

  const GlobalSearchScreen({super.key, this.initialQuery});

  @override
  State<GlobalSearchScreen> createState() => _GlobalSearchScreenState();
}

class _GlobalSearchScreenState extends State<GlobalSearchScreen> {
  final TextEditingController _textController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final GlobalSearchController _searchController;
  Timer? _debounceTimer;

  bool _isGroupedView = true;

  final List<String> _popularSuggestions = const [
    'Shadow Slave',
    'Lord of the Mysteries',
    'Reverend Insanity',
    'Omniscient Reader\'s Viewpoint',
    'Solo Leveling',
    'Mother of Learning',
    'The Beginning After The End',
    'The Primal Hunter',
    'Defiance of the Fall',
    'Overgeared',
    'SSS-Class Suicide Hunter',
    'Trash of the Count\'s Family',
    'Second Coming of Gluttony',
    'Classroom of the Elite',
    'Martial Peak',
    'Against the Gods',
    'Release That Witch',
    'Coiling Dragon',
    'Warlock of the Magus World',
    'Super Gene',
    'A Will Eternal',
    'Chrysalis',
  ];

  List<String> _recentSearches = [];

  List<String> get _matchingSuggestions {
    final q = _textController.text.trim().toLowerCase();
    if (q.isEmpty) return _popularSuggestions.take(10).toList();
    return _popularSuggestions.where((s) => s.toLowerCase().contains(q) && s.toLowerCase() != q).take(6).toList();
  }

  @override
  void initState() {
    super.initState();
    _searchController = GlobalSearchController();
    _loadRecentSearches();

    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _textController.text = widget.initialQuery!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _executeSearch(_textController.text);
      });
    } else {
      _focusNode.requestFocus();
    }
  }

  Future<void> _loadRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = prefs.getStringList('global_search_recent') ?? [];
      if (mounted) {
        setState(() => _recentSearches = list);
      }
    } catch (_) {}
  }

  Future<void> _saveRecentSearch(String query) async {
    final clean = query.trim();
    if (clean.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = List<String>.from(_recentSearches);
      list.removeWhere((s) => s.toLowerCase() == clean.toLowerCase());
      list.insert(0, clean);
      if (list.length > 10) list.removeLast();
      await prefs.setStringList('global_search_recent', list);
      if (mounted) {
        setState(() => _recentSearches = list);
      }
    } catch (_) {}
  }

  Future<void> _clearRecentSearches() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('global_search_recent');
      if (mounted) {
        setState(() => _recentSearches.clear());
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _textController.dispose();
    _focusNode.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 450), () {
      if (mounted) {
        _searchController.search(query);
      }
    });
  }

  void _executeSearch(String query) {
    _debounceTimer?.cancel();
    _focusNode.unfocus();
    _saveRecentSearch(query);
    _searchController.search(query);
  }

  void _openNovel(Novel novel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NovelDetailScreen(novel: novel),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121218),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181822),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        titleSpacing: 0,
        title: Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF22222E),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF6C5CE7).withValues(alpha: 0.3), width: 1),
            ),
            child: TextField(
              controller: _textController,
              focusNode: _focusNode,
              onChanged: _onQueryChanged,
              onSubmitted: _executeSearch,
              textInputAction: TextInputAction.search,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search across all sources...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF6C5CE7), size: 20),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textController,
                  builder: (context, val, _) {
                    return val.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white54),
                            onPressed: () {
                              _textController.clear();
                              _searchController.clear();
                            },
                          )
                        : const SizedBox.shrink();
                  },
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
      ),
      body: ValueListenableBuilder<GlobalSearchState>(
        valueListenable: _searchController,
        builder: (context, state, _) {
          return Column(
            children: [
              // Search Progress & Status Header
              if (state.totalSources > 0) _buildProgressHeader(state),

              // Live Matching Suggestions Bar
              _buildLiveSuggestionsBar(),

              // View Mode Selector Tabs
              if (state.totalNovelsFound > 0) _buildViewTabs(state),

              // Main Results Body
              Expanded(
                child: _buildBody(state),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLiveSuggestionsBar() {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _textController,
      builder: (context, val, _) {
        final query = val.text.trim().toLowerCase();
        if (query.isEmpty) return const SizedBox.shrink();

        final suggestions = _popularSuggestions
            .where((s) => s.toLowerCase().contains(query) && s.toLowerCase() != query)
            .take(6)
            .toList();

        if (suggestions.isEmpty) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          color: const Color(0xFF161622),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                const Icon(Icons.lightbulb_outline_rounded, size: 14, color: Color(0xFFF59E0B)),
                const SizedBox(width: 8),
                Text(
                  'Suggestions:',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 8),
                ...suggestions.map((title) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: InkWell(
                      onTap: () {
                        _textController.text = title;
                        _textController.selection = TextSelection.fromPosition(
                          TextPosition(offset: title.length),
                        );
                        _executeSearch(title);
                      },
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF232334),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: const Color(0xFF6C5CE7).withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.search_rounded, size: 12, color: Color(0xFFA78BFA)),
                            const SizedBox(width: 4),
                            Text(
                              title,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildProgressHeader(GlobalSearchState state) {
    return Container(
      color: const Color(0xFF181822),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (state.isSearching) ...[
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF6C5CE7)),
                  ),
                ),
                const SizedBox(width: 8),
              ] else ...[
                const Icon(Icons.check_circle_rounded, size: 14, color: Colors.greenAccent),
                const SizedBox(width: 6),
              ],
              Text(
                state.isSearching
                    ? 'Searching: ${state.completedSources}/${state.totalSources} sources completed'
                    : 'Search complete across ${state.totalSources} sources',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF6C5CE7).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${state.totalNovelsFound} matches',
                  style: const TextStyle(
                    color: Color(0xFFA78BFA),
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: state.progress,
              minHeight: 4,
              backgroundColor: const Color(0xFF2D2D3A),
              valueColor: AlwaysStoppedAnimation<Color>(
                state.isCompleted ? Colors.greenAccent : const Color(0xFF6C5CE7),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewTabs(GlobalSearchState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: const BoxDecoration(
        color: Color(0xFF14141E),
        border: Border(bottom: BorderSide(color: Color(0xFF222230), width: 1)),
      ),
      child: Row(
        children: [
          _buildTabButton(
            title: 'Grouped Titles (${state.groupedMatches.length})',
            isSelected: _isGroupedView,
            icon: Icons.layers_rounded,
            onTap: () => setState(() => _isGroupedView = true),
          ),
          const SizedBox(width: 10),
          _buildTabButton(
            title: 'By Source (${state.sourceResults.where((r) => r.novels.isNotEmpty).length})',
            isSelected: !_isGroupedView,
            icon: Icons.source_rounded,
            onTap: () => setState(() => _isGroupedView = false),
          ),
        ],
      ),
    );
  }

  Widget _buildTabButton({
    required String title,
    required bool isSelected,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C5CE7) : const Color(0xFF1E1E28),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFF2D2D3C),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: isSelected ? Colors.white : Colors.white60),
            const SizedBox(width: 6),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(GlobalSearchState state) {
    if (state.query.isEmpty && state.allNovelsRaw.isEmpty) {
      return _buildSuggestionsView();
    }

    if (state.isSearching && state.allNovelsRaw.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: Color(0xFF6C5CE7)),
            const SizedBox(height: 16),
            Text(
              'Scanning 14+ sources in parallel...',
              style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (!state.isSearching && state.allNovelsRaw.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.search_off_rounded, size: 56, color: Colors.white.withValues(alpha: 0.3)),
              const SizedBox(height: 12),
              Text(
                'No matches found for "${state.query}"',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 8),
              Text(
                'Searched all ${state.totalSources} registered novel sources. Try checking the title spelling or searching with a broader keyword.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
              ),
            ],
          ),
        ),
      );
    }

    return _isGroupedView ? _buildGroupedList(state) : _buildBySourceList(state);
  }

  Widget _buildSuggestionsView() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_recentSearches.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.history_rounded, size: 18, color: Color(0xFFA78BFA)),
                const SizedBox(width: 8),
                Text(
                  'Recent Searches',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.9),
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _clearRecentSearches,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: Colors.white38,
                    padding: EdgeInsets.zero,
                  ),
                  child: const Text('Clear', style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _recentSearches.map((title) {
                return ActionChip(
                  backgroundColor: const Color(0xFF1E1E28),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: const BorderSide(color: Color(0xFF333348)),
                  ),
                  label: Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                  avatar: const Icon(Icons.history_rounded, size: 14, color: Color(0xFFA78BFA)),
                  onPressed: () {
                    _textController.text = title;
                    _textController.selection = TextSelection.fromPosition(
                      TextPosition(offset: title.length),
                    );
                    _executeSearch(title);
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
          ],

          Row(
            children: [
              const Icon(Icons.flash_on_rounded, size: 18, color: Color(0xFFF59E0B)),
              const SizedBox(width: 8),
              Text(
                'Popular Across All Sources',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _popularSuggestions.map((title) {
              return ActionChip(
                backgroundColor: const Color(0xFF1E1E28),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: const BorderSide(color: Color(0xFF2D2D3C)),
                ),
                label: Text(
                  title,
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                avatar: const Icon(Icons.search, size: 14, color: Color(0xFFA78BFA)),
                onPressed: () {
                  _textController.text = title;
                  _textController.selection = TextSelection.fromPosition(
                    TextPosition(offset: title.length),
                  );
                  _executeSearch(title);
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1B1B26),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF2A2A3C)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_awesome, color: Color(0xFF6C5CE7), size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'True Global Search',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'One search query simultaneously browses NovelFull, NovelFire, Royal Road, ScribbleHub, WuxiaBox, and all other sources. Results appear instantly as each source responds.',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 12, height: 1.4),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedList(GlobalSearchState state) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: state.groupedMatches.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final match = state.groupedMatches[index];
        return _buildGroupedCard(match);
      },
    );
  }

  Widget _buildGroupedCard(GroupedNovelMatch match) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF282838), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Novel Overview Header
          InkWell(
            onTap: () => _openNovel(match.primaryNovel),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Cover Image Thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 65,
                      height: 90,
                      color: const Color(0xFF242434),
                      child: match.coverUrl.isNotEmpty
                          ? Image.network(
                              match.coverUrl,
                              headers: {
                                'User-Agent': WebViewSessionManager.defaultUserAgent,
                                'Accept': 'image/*,*/*;q=0.8',
                              },
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => const Center(
                                child: Icon(Icons.book_rounded, color: Colors.white24, size: 28),
                              ),
                            )
                          : const Center(
                              child: Icon(Icons.book_rounded, color: Colors.white24, size: 28),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Title, Author, and Badge
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          match.canonicalTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          match.author,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: match.sourceCount > 1
                                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                                : const Color(0xFF6C5CE7).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            match.sourceCount > 1
                                ? 'Available in ${match.sourceCount} sources'
                                : 'Available in 1 source',
                            style: TextStyle(
                              color: match.sourceCount > 1
                                  ? const Color(0xFF34D399)
                                  : const Color(0xFFA78BFA),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
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

          const Divider(height: 1, color: Color(0xFF242434)),

          // Available Sources Direct Navigation Chips
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Select source to read:',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: match.sourceVariants.entries.map((entry) {
                    final source = entry.key;
                    final novelVariant = entry.value;

                    return InkWell(
                      onTap: () => _openNovel(novelVariant),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF222232),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: const Color(0xFF6C5CE7).withValues(alpha: 0.4),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: const BoxDecoration(
                                color: Color(0xFF10B981),
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              source.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 10,
                              color: Color(0xFFA78BFA),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBySourceList(GlobalSearchState state) {
    final activeSources = state.sourceResults.where((r) => r.novels.isNotEmpty).toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: activeSources.length,
      itemBuilder: (context, index) {
        final result = activeSources[index];
        final source = result.source;
        final novels = result.novels;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Source Header
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6C5CE7),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      source.lang.toUpperCase(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    source.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${novels.length} found',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Horizontal novel scroll
            SizedBox(
              height: 195,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: novels.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, nIdx) {
                  final novel = novels[nIdx];
                  return SizedBox(
                    width: 110,
                    child: InkWell(
                      onTap: () => _openNovel(novel),
                      borderRadius: BorderRadius.circular(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              width: 110,
                              height: 140,
                              color: const Color(0xFF1E1E28),
                              child: novel.coverUrl.isNotEmpty
                                  ? Image.network(
                                      novel.coverUrl,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Center(
                                        child: Icon(Icons.book, color: Colors.white24, size: 30),
                                      ),
                                    )
                                  : const Center(
                                      child: Icon(Icons.book, color: Colors.white24, size: 30),
                                    ),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            novel.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              height: 1.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Divider(color: Color(0xFF222230), height: 1),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }
}

