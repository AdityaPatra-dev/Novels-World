import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/epub_service.dart';
import '../../providers/library_provider.dart';
import '../novel/novel_detail_screen.dart';
import '../widgets/novel_card.dart';

class LibraryScreen extends StatefulWidget {
  final VoidCallback onBrowseTap;

  const LibraryScreen({super.key, required this.onBrowseTap});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  int _selectedFilter = 0; // 0 = All, 1 = Reading, 2 = Completed

  @override
  Widget build(BuildContext context) {
    final libraryProvider = context.watch<LibraryProvider>();
    final allNovels = libraryProvider.novels;

    final filteredNovels = allNovels.where((n) {
      if (_selectedFilter == 1) {
        return n.lastReadChapterId != null;
      } else if (_selectedFilter == 2) {
        return n.status == 'COMPLETED';
      }
      return true;
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'My Library (${allNovels.length})',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.file_upload_outlined),
            tooltip: 'Import EPUB Book',
            onPressed: () => _importEpub(context),
          ),
        ],
        bottom: allNovels.isNotEmpty
            ? PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Row(
                    children: [
                      _buildFilterChip(0, 'All (${allNovels.length})'),
                      const SizedBox(width: 8),
                      _buildFilterChip(1, 'Reading (${allNovels.where((n) => n.lastReadChapterId != null).length})'),
                      const SizedBox(width: 8),
                      _buildFilterChip(2, 'Completed (${allNovels.where((n) => n.status == 'COMPLETED').length})'),
                    ],
                  ),
                ),
              )
            : null,
      ),
      body: allNovels.isEmpty
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.collections_bookmark_outlined, size: 64, color: Colors.white.withValues(alpha: 0.3)),
                    const SizedBox(height: 16),
                    const Text(
                      'Your library is empty',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Explore web novels and bookmark your favorite stories for instant offline reading.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.6)),
                    ),
                    const SizedBox(height: 24),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      alignment: WrapAlignment.center,
                      children: [
                        ElevatedButton.icon(
                          onPressed: widget.onBrowseTap,
                          icon: const Icon(Icons.explore),
                          label: const Text('Browse Novels'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF8B5CF6),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _importEpub(context),
                          icon: const Icon(Icons.file_upload_outlined),
                          label: const Text('Import EPUB'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white,
                            side: const BorderSide(color: Color(0xFF8B5CF6)),
                            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                int crossAxisCount = 2;
                if (constraints.maxWidth > 900) {
                  crossAxisCount = 5;
                } else if (constraints.maxWidth > 600) {
                  crossAxisCount = 3;
                }

                if (filteredNovels.isEmpty) {
                  return const Center(
                    child: Text('No novels match this filter.', style: TextStyle(color: Colors.white60)),
                  );
                }

                return GridView.builder(
                  padding: const EdgeInsets.all(16),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    childAspectRatio: 0.58,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 18,
                  ),
                  itemCount: filteredNovels.length,
                  itemBuilder: (context, index) {
                    final novel = filteredNovels[index];
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
            ),
    );
  }

  Future<void> _importEpub(BuildContext context) async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.any,
      );
      if (files.isNotEmpty && files.first.path != null) {
        final path = files.first.path!;
        final scaffold = ScaffoldMessenger.of(this.context);
        if (!path.toLowerCase().endsWith('.epub')) {
          scaffold.showSnackBar(
            const SnackBar(content: Text('Please select an .epub file (e.g. book.epub)')),
          );
          return;
        }
        if (!mounted) return;
        scaffold.showSnackBar(
          const SnackBar(content: Text('Importing EPUB book...')),
        );
        final novel = await EpubService().importEpub(File(path));
        if (!mounted) return;
        await this.context.read<LibraryProvider>().saveToLibrary(novel);
        scaffold.showSnackBar(
          SnackBar(
            content: Text('Imported "${novel.title}" to Library'),
            action: SnackBarAction(
              label: 'Open',
              onPressed: () {
                if (!mounted) return;
                Navigator.push(
                  this.context,
                  MaterialPageRoute(builder: (context) => NovelDetailScreen(novel: novel)),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(this.context).showSnackBar(
          SnackBar(content: Text('Failed to import EPUB: $e')),
        );
      }
    }
  }

  Widget _buildFilterChip(int index, String label) {
    final isSelected = _selectedFilter == index;
    return GestureDetector(
      onTap: () => setState(() => _selectedFilter = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF8B5CF6) : const Color(0xFF1E1E28),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : Colors.white70,
          ),
        ),
      ),
    );
  }
}
