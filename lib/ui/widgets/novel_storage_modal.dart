import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/models/novel.dart';
import '../../data/storage_service.dart';

class NovelStorageModal extends StatefulWidget {
  final Novel novel;

  const NovelStorageModal({super.key, required this.novel});

  static Future<void> show(BuildContext context, Novel novel) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF16161E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => NovelStorageModal(novel: novel),
    );
  }

  @override
  State<NovelStorageModal> createState() => _NovelStorageModalState();
}

class _NovelStorageModalState extends State<NovelStorageModal> {
  final StorageService _storageService = StorageService();
  NovelStorageInfo? _storageInfo;
  bool _isLoading = true;
  bool _showFileList = false;

  @override
  void initState() {
    super.initState();
    _loadStorageInfo();
  }

  Future<void> _loadStorageInfo() async {
    setState(() => _isLoading = true);
    final info = await _storageService.getNovelStorageInfo(widget.novel);
    if (mounted) {
      setState(() {
        _storageInfo = info;
        _isLoading = false;
      });
    }
  }

  Future<void> _copyPath(String path) async {
    await Clipboard.setData(ClipboardData(text: path));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied storage path: $path'),
          backgroundColor: const Color(0xFF8B5CF6),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _confirmClearStorage() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E28),
        title: const Text('Clear Novel Storage?'),
        content: Text(
          'This will remove all downloaded chapter files and cached content for "${widget.novel.title}" from device storage. You can re-download or re-import it anytime.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete Files'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      await _storageService.deleteNovelStorage(widget.novel);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Novel storage cleared.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadStorageInfo();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row: Folder Icon + Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withOpacity(0.18),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.folder_special_rounded,
                    color: Color(0xFFA78BFA),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.novel.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Novel Storage & Chapters Folder',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withOpacity(0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            if (_isLoading)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(24.0),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_storageInfo != null) ...[
              // Storage Type Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: widget.novel.sourceId == 'local_epub'
                      ? const Color(0xFF10B981).withOpacity(0.15)
                      : const Color(0xFF8B5CF6).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: widget.novel.sourceId == 'local_epub'
                        ? const Color(0xFF10B981).withOpacity(0.4)
                        : const Color(0xFF8B5CF6).withOpacity(0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.novel.sourceId == 'local_epub'
                          ? Icons.book_rounded
                          : Icons.cloud_download_rounded,
                      size: 14,
                      color: widget.novel.sourceId == 'local_epub'
                          ? const Color(0xFF34D399)
                          : const Color(0xFFA78BFA),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _storageInfo!.storageType,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: widget.novel.sourceId == 'local_epub'
                            ? const Color(0xFF34D399)
                            : const Color(0xFFA78BFA),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Path Container with Copy Button
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF20202E),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'DEVICE STORAGE PATH',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.6,
                            color: Colors.white54,
                          ),
                        ),
                        InkWell(
                          onTap: () => _copyPath(_storageInfo!.directoryPath),
                          borderRadius: BorderRadius.circular(6),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Row(
                              children: const [
                                Icon(Icons.copy_rounded, size: 13, color: Color(0xFFA78BFA)),
                                SizedBox(width: 4),
                                Text(
                                  'Copy Path',
                                  style: TextStyle(fontSize: 12, color: Color(0xFFA78BFA), fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    SelectableText(
                      _storageInfo!.directoryPath,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Metric Cards Row
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E28),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Stored Chapters',
                            style: TextStyle(fontSize: 11, color: Colors.white54),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${_storageInfo!.chapterCount}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E1E28),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Disk Usage',
                            style: TextStyle(fontSize: 11, color: Colors.white54),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            _storageInfo!.formattedSize,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF34D399),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Toggle Chapter Files List
              if (_storageInfo!.fileNames.isNotEmpty) ...[
                InkWell(
                  onTap: () => setState(() => _showFileList = !_showFileList),
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Icon(
                          _showFileList ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_right_rounded,
                          size: 18,
                          color: const Color(0xFFA78BFA),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _showFileList
                              ? 'Hide Stored Files (${_storageInfo!.fileNames.length})'
                              : 'Show Stored Files (${_storageInfo!.fileNames.length})',
                          style: const TextStyle(fontSize: 13, color: Color(0xFFA78BFA), fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showFileList)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    constraints: const BoxConstraints(maxHeight: 140),
                    decoration: BoxDecoration(
                      color: const Color(0xFF12121A),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white10),
                    ),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: _storageInfo!.fileNames.length,
                      separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white10),
                      itemBuilder: (context, index) {
                        final file = _storageInfo!.fileNames[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              const Icon(Icons.insert_drive_file_outlined, size: 14, color: Colors.white54),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  file,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white70),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
              ],
              const SizedBox(height: 16),

              // Action Buttons Row
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _copyPath(_storageInfo!.directoryPath),
                      icon: const Icon(Icons.copy_rounded, size: 16),
                      label: const Text('Copy Path'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  if (_storageInfo!.totalSizeBytes > 0) ...[
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: _confirmClearStorage,
                      icon: const Icon(Icons.delete_outline, size: 16),
                      label: const Text('Clear Storage'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        side: const BorderSide(color: Colors.redAccent),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
