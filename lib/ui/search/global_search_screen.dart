import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/models/novel.dart';
import '../../core/services/epub_service.dart';
import '../../core/services/global_search_controller.dart';
import '../../core/utils/http_client_factory.dart';
import '../../data/download_service.dart';
import '../../providers/library_provider.dart';
import '../novel/novel_detail_screen.dart';

/// Global Multi-Source Search Screen.
/// Concurrently searches all cataloged sources, streams results in real time,
/// clusters identical novel titles across sources, and provides one-tap direct navigation.
class GlobalSearchScreen extends StatefulWidget {
  final String? initialQuery;
  final bool isEmbeddedInTab;
  final VoidCallback? onSwitchToSources;

  const GlobalSearchScreen({
    super.key,
    this.initialQuery,
    this.isEmbeddedInTab = false,
    this.onSwitchToSources,
  });

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
    'Harry Potter',
    'Dune',
    'The Hobbit',
    'A Game of Thrones',
    'Lord of the Mysteries',
    'Reverend Insanity',
    'Omniscient Reader\'s Viewpoint',
    'Solo Leveling',
    'Mother of Learning',
    'The Beginning After The End',
    'The Primal Hunter',
    'Defiance of the Fall',
    'Overgeared',
    'Frankenstein',
    'Pride and Prejudice',
    'Dracula',
    'Classroom of the Elite',
    'Martial Peak',
    'Against the Gods',
    'Release That Witch',
    'Coiling Dragon',
    'Warlock of the Magus World',
    'Super Gene',
    'Chrysalis',
  ];

  List<String> _recentSearches = [];
  bool _hasSubmitted = false;

  @override
  void initState() {
    super.initState();
    _searchController = GlobalSearchController();
    _loadRecentSearches();

    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _hasSubmitted) {
        setState(() {
          _hasSubmitted = false;
        });
      }
    });

    if (widget.initialQuery != null && widget.initialQuery!.trim().isNotEmpty) {
      _textController.text = widget.initialQuery!.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _executeSearch(_textController.text);
      });
    } else if (!widget.isEmbeddedInTab) {
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
      if (list.length > 15) list.removeLast();
      await prefs.setStringList('global_search_recent', list);
      if (mounted) {
        setState(() => _recentSearches = list);
      }
    } catch (_) {}
  }

  Future<void> _removeRecentSearch(String item) async {
    final clean = item.trim();
    try {
      final prefs = await SharedPreferences.getInstance();
      final list = List<String>.from(_recentSearches);
      list.removeWhere((s) => s.toLowerCase() == clean.toLowerCase());
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
    if (_hasSubmitted) {
      setState(() {
        _hasSubmitted = false;
      });
    } else {
      setState(() {});
    }
  }

  void _executeSearch(String query) {
    final clean = query.trim();
    if (clean.isEmpty) return;
    _debounceTimer?.cancel();
    _focusNode.unfocus();
    setState(() {
      _hasSubmitted = true;
    });
    _saveRecentSearch(clean);
    _searchController.search(clean);
  }

  void _openNovel(Novel novel) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NovelDetailScreen(novel: novel),
      ),
    );
  }

  Future<void> _importLocalEpub() async {
    if (kIsWeb) return;
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.any,
      );
      if (!mounted) return;
      if (files.isNotEmpty && files.first.path != null) {
        final path = files.first.path!;
        if (!path.toLowerCase().endsWith('.epub')) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please select a valid .epub book file.')),
            );
          }
          return;
        }
        final scaffold = ScaffoldMessenger.of(context);
        final libraryProvider = context.read<LibraryProvider>();
        scaffold.showSnackBar(
          const SnackBar(content: Text('Importing EPUB book...')),
        );
        final novel = await EpubService().importEpub(File(path));
        if (!mounted) return;
        await libraryProvider.saveToLibrary(novel);
        scaffold.showSnackBar(
          SnackBar(
            content: Text('Imported "${novel.title}" to Library'),
            action: SnackBarAction(
              label: 'Read Now',
              onPressed: () => _openNovel(novel),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import EPUB: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPop = !widget.isEmbeddedInTab && Navigator.canPop(context);
    return Scaffold(
      backgroundColor: const Color(0xFF121218),
      appBar: AppBar(
        backgroundColor: const Color(0xFF181822),
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        titleSpacing: canPop ? 0 : 16,
        title: Padding(
          padding: EdgeInsets.only(right: widget.onSwitchToSources != null ? 0 : 16),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF222232),
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
                hintText: 'Search books, web novels, authors...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 14),
                prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF6C5CE7), size: 20),
                suffixIcon: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _textController,
                  builder: (context, val, _) {
                    if (val.text.isEmpty) return const SizedBox.shrink();
                    return Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white54),
                          onPressed: () {
                            _textController.clear();
                            _searchController.clear();
                            setState(() {
                              _hasSubmitted = false;
                            });
                            _focusNode.requestFocus();
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.arrow_forward_rounded, size: 18, color: Color(0xFF8B5CF6)),
                          tooltip: 'Search',
                          onPressed: () => _executeSearch(_textController.text),
                        ),
                      ],
                    );
                  },
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                border: InputBorder.none,
              ),
            ),
          ),
        ),
        actions: [
          if (widget.onSwitchToSources != null)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: IconButton(
                icon: const Icon(Icons.source_outlined, color: Color(0xFFA78BFA), size: 22),
                tooltip: 'Browse Single Source',
                onPressed: widget.onSwitchToSources,
              ),
            ),
        ],
      ),
      body: !_hasSubmitted
          ? _buildYouTubeSuggestionsOverlay()
          : ValueListenableBuilder<GlobalSearchState>(
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

  Widget _buildHighlightedText(String fullText, String query) {
    final lowerText = fullText.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final matchIndex = lowerText.indexOf(lowerQuery);

    if (matchIndex == -1 || query.isEmpty) {
      return Text(
        fullText,
        style: const TextStyle(color: Colors.white, fontSize: 14),
      );
    }

    final before = fullText.substring(0, matchIndex);
    final match = fullText.substring(matchIndex, matchIndex + query.length);
    final after = fullText.substring(matchIndex + query.length);

    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Colors.white70, fontSize: 14),
        children: [
          if (before.isNotEmpty) TextSpan(text: before),
          TextSpan(
            text: match,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
    );
  }

  Widget _buildYouTubeSuggestionsOverlay() {
    final query = _textController.text.trim();
    if (query.isEmpty) {
      return _buildSuggestionsView();
    }

    final lowerQuery = query.toLowerCase();

    // 1. History matches
    final matchingHistory = _recentSearches
        .where((s) => s.toLowerCase().contains(lowerQuery))
        .toList();

    // 2. Library & Catalog matches
    final libraryTitles = context.watch<LibraryProvider>().novels.map((n) => n.title).toList();
    final allCandidates = <String>{..._popularSuggestions, ...libraryTitles};
    final matchingCatalog = allCandidates
        .where((s) =>
            s.toLowerCase().contains(lowerQuery) &&
            !matchingHistory.any((h) => h.toLowerCase() == s.toLowerCase()) &&
            s.toLowerCase() != lowerQuery)
        .take(15)
        .toList();

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        // "Search for ..." top action
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 2),
          leading: const Icon(Icons.search_rounded, color: Color(0xFF8B5CF6), size: 20),
          title: RichText(
            text: TextSpan(
              style: const TextStyle(color: Colors.white, fontSize: 14),
              children: [
                const TextSpan(text: 'Search for "'),
                TextSpan(
                  text: query,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFA78BFA)),
                ),
                const TextSpan(text: '" across all sources'),
              ],
            ),
          ),
          trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14, color: Colors.white38),
          onTap: () => _executeSearch(query),
        ),
        const Divider(color: Color(0xFF222230), height: 1),

        // Recent history matching items
        ...matchingHistory.map((item) {
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
            leading: const Icon(Icons.history_rounded, color: Color(0xFFA78BFA), size: 20),
            title: _buildHighlightedText(item, query),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16, color: Colors.white30),
                  tooltip: 'Remove from history',
                  onPressed: () => _removeRecentSearch(item),
                ),
                IconButton(
                  icon: const Icon(Icons.north_west_rounded, size: 18, color: Colors.white38),
                  tooltip: 'Insert into search bar',
                  onPressed: () {
                    _textController.text = item;
                    _textController.selection = TextSelection.fromPosition(
                      TextPosition(offset: item.length),
                    );
                    setState(() {});
                  },
                ),
              ],
            ),
            onTap: () {
              _textController.text = item;
              _executeSearch(item);
            },
          );
        }),

        // Predictive catalog & library matching items
        ...matchingCatalog.map((item) {
          return ListTile(
            dense: true,
            contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 0),
            leading: const Icon(Icons.search_rounded, color: Colors.white38, size: 20),
            title: _buildHighlightedText(item, query),
            trailing: IconButton(
              icon: const Icon(Icons.north_west_rounded, size: 18, color: Colors.white38),
              tooltip: 'Insert into search bar',
              onPressed: () {
                _textController.text = item;
                _textController.selection = TextSelection.fromPosition(
                  TextPosition(offset: item.length),
                );
                setState(() {});
              },
            ),
            onTap: () {
              _textController.text = item;
              _executeSearch(item);
            },
          );
        }),
      ],
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
                'Searched all registered novel and book sources. Try checking the title spelling or searching with a broader keyword.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 13),
              ),
              const SizedBox(height: 20),
              if (!kIsWeb)
                ElevatedButton.icon(
                  onPressed: _importLocalEpub,
                  icon: const Icon(Icons.file_upload_outlined),
                  label: const Text('Import Local EPUB Book'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
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
          // Smart Local EPUB Import Card
          if (!kIsWeb) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1A2C),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.file_upload_outlined, color: Color(0xFFA78BFA), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Have an EPUB book on your device?',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Import Harry Potter, Dune, or any .epub file to read with continuous AI audio.',
                          style: TextStyle(color: Colors.white.withValues(alpha: 0.65), fontSize: 11.5),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _importLocalEpub,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF8B5CF6),
                      foregroundColor: Colors.white,
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('Import', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
          ],

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

          if (_recentSearches.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.travel_explore_rounded,
                      size: 56,
                      color: Colors.white.withValues(alpha: 0.18),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Global Multi-Source Search',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.white.withValues(alpha: 0.7),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Search titles, authors, or genres across all registered sources.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.4),
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

  Widget _buildGroupedList(GlobalSearchState state) {
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: state.groupedMatches.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final match = state.groupedMatches[index];
        return _buildGroupedCard(match);
      },
    );
  }

  Widget _buildGroupedCard(GroupedNovelMatch match) {
    final downloadService = context.watch<DownloadService>();

    final isBook = match.primaryNovel.isFullBook ||
        match.primaryNovel.sourceId == 'local_epub' ||
        match.sourceVariants.values.any((n) => n.isFullBook || n.sourceId == 'local_epub');

    final bookNovel = match.sourceVariants.values.firstWhere(
      (n) => n.isFullBook || n.sourceId == 'local_epub',
      orElse: () => match.primaryNovel,
    );

    final isDownloaded = downloadService.isBookDownloaded(bookNovel.id);
    final bookTask = downloadService.getBookTask(bookNovel.id);
    final isDownloading = bookTask?.status == DownloadStatus.downloading;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A24),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isBook ? const Color(0xFFA78BFA).withValues(alpha: 0.3) : const Color(0xFF282838),
          width: 1,
        ),
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
                              headers: getCoverImageHeaders(match.coverUrl),
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) => const Center(
                                child: Icon(Icons.book_rounded, color: Colors.white24, size: 28),
                              ),
                            )
                          : const Center(
                              child: Icon(Icons.book_rounded, color: Colors.white24, size: 28),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Title, Author, and Badges
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (isBook)
                              Container(
                                margin: const EdgeInsets.only(right: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.book_rounded, size: 10, color: Color(0xFFA78BFA)),
                                    SizedBox(width: 3),
                                    Text(
                                      'BOOK',
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFFA78BFA),
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            Expanded(
                              child: Text(
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
                            ),
                          ],
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
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
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
                        if (isBook && bookNovel.bookDownloadUrl != null && bookNovel.bookDownloadUrl!.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SizedBox(
                            height: 32,
                            child: isDownloaded
                                ? ElevatedButton.icon(
                                    onPressed: () => _openNovel(bookNovel),
                                    icon: const Icon(Icons.menu_book_rounded, size: 14),
                                    label: const Text('Read Now', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF10B981),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(horizontal: 10),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                    ),
                                  )
                                : isDownloading
                                    ? Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF222232),
                                          borderRadius: BorderRadius.circular(6),
                                          border: Border.all(color: const Color(0xFFA78BFA)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFA78BFA)),
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Downloading ${(bookTask!.progress * 100).toInt()}%',
                                              style: const TextStyle(fontSize: 11, color: Color(0xFFA78BFA), fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      )
                                    : ElevatedButton.icon(
                                        onPressed: () async {
                                          final scaffold = ScaffoldMessenger.of(context);
                                          scaffold.showSnackBar(
                                            SnackBar(
                                              content: Text('Downloading "${bookNovel.title}" in background...'),
                                              behavior: SnackBarBehavior.floating,
                                            ),
                                          );
                                          try {
                                            await downloadService.downloadEntireBook(
                                              novel: bookNovel,
                                              downloadUrl: bookNovel.bookDownloadUrl!,
                                            );
                                            scaffold.showSnackBar(
                                              SnackBar(
                                                content: Text('"${bookNovel.title}" ready to read!'),
                                                behavior: SnackBarBehavior.floating,
                                                action: SnackBarAction(
                                                  label: 'Read Now',
                                                  onPressed: () => _openNovel(bookNovel),
                                                ),
                                              ),
                                            );
                                          } catch (e) {
                                            scaffold.showSnackBar(
                                              SnackBar(
                                                content: Text('Download failed: $e'),
                                                behavior: SnackBarBehavior.floating,
                                                backgroundColor: Colors.redAccent,
                                              ),
                                            );
                                          }
                                        },
                                        icon: const Icon(Icons.download_rounded, size: 14),
                                        label: const Text('Download Entire Book', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(0xFF8B5CF6),
                                          foregroundColor: Colors.white,
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                        ),
                                      ),
                          ),
                        ],
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
                            if (source.iconUrl.isNotEmpty) ...[
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: Image.network(
                                  source.iconUrl,
                                  width: 14,
                                  height: 14,
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF10B981),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                            ] else ...[
                              Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF10B981),
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                            ],
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
                  if (source.iconUrl.isNotEmpty) ...[
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.network(
                        source.iconUrl,
                        width: 20,
                        height: 20,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
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
                separatorBuilder: (_, _) => const SizedBox(width: 10),
                itemBuilder: (context, nIdx) {
                  final novel = novels[nIdx];
                  final isBook = novel.isFullBook || novel.sourceId == 'local_epub';

                  return SizedBox(
                    width: 110,
                    child: InkWell(
                      onTap: () => _openNovel(novel),
                      borderRadius: BorderRadius.circular(10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Stack(
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
                                          headers: getCoverImageHeaders(novel.coverUrl),
                                          fit: BoxFit.cover,
                                          errorBuilder: (context, error, stackTrace) => const Center(
                                            child: Icon(Icons.book, color: Colors.white24, size: 30),
                                          ),
                                        )
                                      : const Center(
                                          child: Icon(Icons.book, color: Colors.white24, size: 30),
                                        ),
                                ),
                              ),
                              if (isBook)
                                Positioned(
                                  top: 4,
                                  right: 4,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.85),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: const Text(
                                      'BOOK',
                                      style: TextStyle(
                                        fontSize: 8.5,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
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
