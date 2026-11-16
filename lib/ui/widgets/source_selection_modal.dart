import 'package:flutter/material.dart';
import '../../extractors/novel_source.dart';
import '../../extractors/source_registry.dart';

enum SourceTypeFilter {
  all,
  novels,
  books,
}

/// Rich source selection modal with real-time search,
/// category filters (Books vs Novels), and language filters.
class SourceSelectionModal extends StatefulWidget {
  final NovelSource? currentSource;
  final ValueChanged<NovelSource?> onSourceSelected;

  const SourceSelectionModal({
    super.key,
    required this.currentSource,
    required this.onSourceSelected,
  });

  static Future<void> show({
    required BuildContext context,
    required NovelSource? currentSource,
    required ValueChanged<NovelSource?> onSourceSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => SourceSelectionModal(
        currentSource: currentSource,
        onSourceSelected: onSourceSelected,
      ),
    );
  }

  @override
  State<SourceSelectionModal> createState() => _SourceSelectionModalState();
}

class _SourceSelectionModalState extends State<SourceSelectionModal> {
  final TextEditingController _searchController = TextEditingController();
  SourceTypeFilter _selectedType = SourceTypeFilter.all;
  String _selectedLanguage = 'all';

  late final List<NovelSource> _allSources;
  late final List<String> _availableLanguages;

  static const Set<String> _bookSourceIds = {
    'oceanofpdf',
    'vdocpub',
    'gutenberg',
    'internet_archive',
    'libgen',
    'standard_ebooks',
    'openlibrary',
    'fadedpage',
    'local_epub',
    'novelpdf',
  };

  @override
  void initState() {
    super.initState();
    _allSources = SourceRegistry.getAllSources();

    final langs = _allSources.map((s) => s.lang.toLowerCase()).toSet().toList();
    langs.sort((a, b) {
      if (a == 'en') return -1;
      if (b == 'en') return 1;
      return a.compareTo(b);
    });
    _availableLanguages = langs;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _isBookSource(NovelSource source) {
    final id = source.id.toLowerCase();
    if (_bookSourceIds.contains(id)) return true;
    if (id.contains('pdf') || id.contains('ebook') || id.contains('gutenberg')) return true;
    return false;
  }

  String _getLanguageDisplayName(String langCode) {
    switch (langCode.toLowerCase()) {
      case 'en':
        return '🇬🇧 English';
      case 'ja':
        return '🇯🇵 Japanese';
      case 'es':
        return '🇪🇸 Spanish';
      case 'ar':
        return '🇸🇦 Arabic';
      case 'tr':
        return '🇹🇷 Turkish';
      case 'th':
        return '🇹🇭 Thai';
      case 'hi':
        return '🇮🇳 Hindi';
      case 'or':
        return '🇮🇳 Odia';
      case 'zh':
        return '🇨🇳 Chinese';
      case 'ko':
        return '🇰🇷 Korean';
      default:
        return '🌐 ${langCode.toUpperCase()}';
    }
  }

  List<NovelSource> _getFilteredSources() {
    final query = _searchController.text.trim().toLowerCase();

    return _allSources.where((source) {
      // 1. Type Filter
      if (_selectedType == SourceTypeFilter.novels && _isBookSource(source)) {
        return false;
      }
      if (_selectedType == SourceTypeFilter.books && !_isBookSource(source)) {
        return false;
      }

      // 2. Language Filter
      if (_selectedLanguage != 'all' && source.lang.toLowerCase() != _selectedLanguage) {
        return false;
      }

      // 3. Search Query Filter
      if (query.isNotEmpty) {
        final matchesName = source.name.toLowerCase().contains(query);
        final matchesId = source.id.toLowerCase().contains(query);
        final matchesLang = source.lang.toLowerCase().contains(query);
        final isBook = _isBookSource(source);
        final matchesType = (isBook && (query.contains('book') || query.contains('pdf') || query.contains('epub'))) ||
            (!isBook && (query.contains('novel') || query.contains('web')));

        if (!matchesName && !matchesId && !matchesLang && !matchesType) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filteredSources = _getFilteredSources();
    final query = _searchController.text.trim().toLowerCase();
    final showGlobalSearch = (_selectedType == SourceTypeFilter.all && _selectedLanguage == 'all') ||
        query.contains('global') ||
        query.contains('all');

    final novelCount = _allSources.where((s) => !_isBookSource(s)).length;
    final bookCount = _allSources.where((s) => _isBookSource(s)).length;

    return DraggableScrollableSheet(
      initialChildSize: 0.88,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Title Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.source_rounded, size: 20, color: Color(0xFFA78BFA)),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Select Source',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Browse webnovels, light novels, and digital books',
                          style: TextStyle(fontSize: 12, color: Colors.white60),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white60),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 14),

              // Search Bar
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                style: const TextStyle(fontSize: 14, color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search sources by name, type, or language...',
                  hintStyle: const TextStyle(fontSize: 13, color: Colors.white38),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Color(0xFFA78BFA)),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear_rounded, size: 18, color: Colors.white54),
                          onPressed: () {
                            _searchController.clear();
                            setState(() {});
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF1E1E28),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.white12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Filter Category Chips (Novels vs Books)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildTypeChip('All Types (${_allSources.length})', SourceTypeFilter.all, Icons.grid_view_rounded),
                    const SizedBox(width: 8),
                    _buildTypeChip('📖 Novels ($novelCount)', SourceTypeFilter.novels, null),
                    const SizedBox(width: 8),
                    _buildTypeChip('📚 Books & PDF ($bookCount)', SourceTypeFilter.books, null),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Language Filter Chips
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    _buildLangChip('All Languages', 'all'),
                    const SizedBox(width: 6),
                    ..._availableLanguages.map((lang) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _buildLangChip(_getLanguageDisplayName(lang), lang),
                      );
                    }),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Sources Count Bar
              Row(
                children: [
                  Text(
                    '${filteredSources.length} sources available',
                    style: const TextStyle(fontSize: 12, color: Colors.white54, fontWeight: FontWeight.w500),
                  ),
                  const Spacer(),
                  if (_searchController.text.isNotEmpty || _selectedType != SourceTypeFilter.all || _selectedLanguage != 'all')
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _searchController.clear();
                          _selectedType = SourceTypeFilter.all;
                          _selectedLanguage = 'all';
                        });
                      },
                      child: const Text(
                        'Reset Filters',
                        style: TextStyle(fontSize: 12, color: Color(0xFFA78BFA), fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              // Source List
              Expanded(
                child: filteredSources.isEmpty && !showGlobalSearch
                    ? _buildEmptyState()
                    : ListView.builder(
                        controller: scrollController,
                        itemCount: filteredSources.length + (showGlobalSearch ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (showGlobalSearch && index == 0) {
                            return _buildGlobalSearchCard();
                          }
                          final source = filteredSources[index - (showGlobalSearch ? 1 : 0)];
                          return _buildSourceCard(source);
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTypeChip(String label, SourceTypeFilter type, IconData? icon) {
    final isSelected = _selectedType == type;
    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      avatar: icon != null ? Icon(icon, size: 15, color: isSelected ? Colors.white : Colors.white60) : null,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : Colors.white70,
        ),
      ),
      backgroundColor: const Color(0xFF1E1E28),
      selectedColor: const Color(0xFF8B5CF6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? const Color(0xFFA78BFA) : Colors.white12,
        ),
      ),
      onSelected: (_) {
        setState(() {
          _selectedType = type;
        });
      },
    );
  }

  Widget _buildLangChip(String label, String langCode) {
    final isSelected = _selectedLanguage == langCode;
    return FilterChip(
      selected: isSelected,
      showCheckmark: false,
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          color: isSelected ? Colors.white : Colors.white70,
        ),
      ),
      backgroundColor: const Color(0xFF1E1E28),
      selectedColor: const Color(0xFF7C3AED),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: isSelected ? const Color(0xFFA78BFA) : Colors.white12,
        ),
      ),
      onSelected: (_) {
        setState(() {
          _selectedLanguage = langCode;
        });
      },
    );
  }

  Widget _buildGlobalSearchCard() {
    final isSelected = widget.currentSource == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected
            ? const Color(0xFF8B5CF6).withValues(alpha: 0.18)
            : const Color(0xFF1E1E28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected ? const Color(0xFFA78BFA) : Colors.white10,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onTap: () {
            widget.onSourceSelected(null);
            Navigator.pop(context);
          },
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(Icons.travel_explore_rounded, color: Colors.white, size: 22),
          ),
          title: const Text(
            'All Sources (Global Search)',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: Color(0xFFA78BFA),
            ),
          ),
          subtitle: const Text(
            'Search across all web novel & digital book sources simultaneously',
            style: TextStyle(fontSize: 11.5, color: Colors.white54),
          ),
          trailing: isSelected
              ? const Icon(Icons.check_circle_rounded, color: Color(0xFFA78BFA), size: 22)
              : null,
        ),
      ),
    );
  }

  Widget _buildSourceCard(NovelSource source) {
    final isSelected = widget.currentSource?.id == source.id;
    final isBook = _isBookSource(source);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: isSelected
            ? const Color(0xFF8B5CF6).withValues(alpha: 0.14)
            : const Color(0xFF1E1E28),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected ? const Color(0xFFA78BFA) : Colors.white10,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: ListTile(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          onTap: () {
            widget.onSourceSelected(source);
            Navigator.pop(context);
          },
          leading: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: isBook
                  ? const Color(0xFF059669).withValues(alpha: 0.2)
                  : const Color(0xFF3B82F6).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white12),
            ),
            child: source.iconUrl.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      source.iconUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => Icon(
                        isBook ? Icons.menu_book_rounded : Icons.auto_stories_rounded,
                        color: isBook ? const Color(0xFF34D399) : const Color(0xFF60A5FA),
                        size: 20,
                      ),
                    ),
                  )
                : Icon(
                    isBook ? Icons.menu_book_rounded : Icons.auto_stories_rounded,
                    color: isBook ? const Color(0xFF34D399) : const Color(0xFF60A5FA),
                    size: 20,
                  ),
          ),
          title: Text(
            source.name,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: isSelected ? const Color(0xFFA78BFA) : Colors.white,
            ),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Row(
              children: [
                // Content Type Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: isBook
                        ? const Color(0xFF059669).withValues(alpha: 0.3)
                        : const Color(0xFF3B82F6).withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    isBook ? '📚 Book / PDF' : '📖 Web Novel',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: isBook ? const Color(0xFF34D399) : const Color(0xFF93C5FD),
                    ),
                  ),
                ),
                const SizedBox(width: 6),

                // Language Badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    source.lang.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.bold,
                      color: Colors.white70,
                    ),
                  ),
                ),

                // Novel Count if available
                if (source.estimatedNovelCount > 0) ...[
                  const SizedBox(width: 8),
                  Text(
                    '${(source.estimatedNovelCount / 1000).toStringAsFixed(0)}k+ titles',
                    style: const TextStyle(fontSize: 11, color: Colors.white38),
                  ),
                ],
              ],
            ),
          ),
          trailing: isSelected
              ? const Icon(Icons.check_circle_rounded, color: Color(0xFFA78BFA), size: 22)
              : const Icon(Icons.chevron_right_rounded, color: Colors.white24, size: 20),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.search_off_rounded, size: 48, color: Colors.white24),
            const SizedBox(height: 12),
            const Text(
              'No sources found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 4),
            const Text(
              'Try changing your search term or filter options',
              style: TextStyle(fontSize: 12, color: Colors.white54),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('Reset Search & Filters'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: () {
                setState(() {
                  _searchController.clear();
                  _selectedType = SourceTypeFilter.all;
                  _selectedLanguage = 'all';
                });
              },
            ),
          ],
        ),
      ),
    );
  }
}
