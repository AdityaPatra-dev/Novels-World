import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/utils/chapter_range_parser.dart';
import '../../data/audiobook_download_service.dart';
import '../../data/download_service.dart';
import '../../data/storage_service.dart';
import '../../tts/language_voice_registry.dart';
import 'narrator_selection_sheet.dart';
import 'novel_storage_modal.dart';

class DownloadRangeDialog extends StatefulWidget {
  final Novel novel;
  final List<Chapter> chapters;

  const DownloadRangeDialog({
    super.key,
    required this.novel,
    required this.chapters,
  });

  /// Displays the download range modal bottom sheet
  static Future<void> show(
    BuildContext context, {
    required Novel novel,
    required List<Chapter> chapters,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161622),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => DownloadRangeDialog(
        novel: novel,
        chapters: chapters,
      ),
    );
  }

  @override
  State<DownloadRangeDialog> createState() => _DownloadRangeDialogState();
}

class _DownloadRangeDialogState extends State<DownloadRangeDialog> {
  final TextEditingController _textController = TextEditingController();
  final StorageService _storageService = StorageService();

  Set<int> _parsedNumbers = {};
  List<Chapter> _selectedChapters = [];
  int _alreadyDownloadedCount = 0;
  int _toDownloadCount = 0;

  AudiobookDownloadMode _downloadMode = AudiobookDownloadMode.both;
  LanguageVoiceInfo _selectedLanguage = LanguageVoiceRegistry.defaultLanguage;
  late String _selectedVoice;

  @override
  void initState() {
    super.initState();
    _selectedVoice = _selectedLanguage.defaultFemaleVoice;
    _textController.addListener(_onTextChanged);

    // Initial default: Next 10 unread or 1-10
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _applyNextUnreadPreset(10);
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    final text = _textController.text.trim();
    final downloadService = context.read<DownloadService>();

    if (text.isEmpty) {
      setState(() {
        _parsedNumbers = {};
        _selectedChapters = [];
        _alreadyDownloadedCount = 0;
        _toDownloadCount = 0;
      });
      return;
    }

    final nums = ChapterRangeParser.parseRange(text);
    final matched = ChapterRangeParser.filterChapters(widget.chapters, nums);

    int downloaded = 0;
    int toDownload = 0;
    for (final ch in matched) {
      if (downloadService.isChapterDownloaded(ch.id)) {
        downloaded++;
      } else {
        toDownload++;
      }
    }

    setState(() {
      _parsedNumbers = nums;
      _selectedChapters = matched;
      _alreadyDownloadedCount = downloaded;
      _toDownloadCount = toDownload;
    });
  }

  void _applyNextUnreadPreset(int count) {
    if (widget.chapters.isEmpty) return;
    final downloadService = context.read<DownloadService>();

    final unreadChapters = widget.chapters
        .where((ch) => !downloadService.isChapterDownloaded(ch.id))
        .take(count)
        .toList();

    if (unreadChapters.isNotEmpty) {
      final nums = unreadChapters
          .asMap()
          .entries
          .map((e) => ChapterRangeParser.getEffectiveChapterNumber(e.value, widget.chapters.indexOf(e.value)))
          .toSet();

      final rangeStr = ChapterRangeParser.formatRangeDescription(nums).replaceAll('–', '-');
      _textController.text = rangeStr;
      _textController.selection = TextSelection.collapsed(offset: _textController.text.length);
    } else {
      // If all are downloaded or chapters are fresh
      final maxCh = widget.chapters.length < count ? widget.chapters.length : count;
      _textController.text = '1-$maxCh';
      _textController.selection = TextSelection.collapsed(offset: _textController.text.length);
    }
  }

  void _applyAllUnreadPreset() {
    if (widget.chapters.isEmpty) return;
    final downloadService = context.read<DownloadService>();

    final unreadChapters = widget.chapters
        .where((ch) => !downloadService.isChapterDownloaded(ch.id))
        .toList();

    if (unreadChapters.isNotEmpty) {
      final nums = unreadChapters
          .map((ch) => ChapterRangeParser.getEffectiveChapterNumber(ch, widget.chapters.indexOf(ch)))
          .toSet();

      final rangeStr = ChapterRangeParser.formatRangeDescription(nums).replaceAll('–', '-');
      _textController.text = rangeStr;
      _textController.selection = TextSelection.collapsed(offset: _textController.text.length);
    }
  }

  void _applyAllChaptersPreset() {
    if (widget.chapters.isEmpty) return;
    _textController.text = '1-${widget.chapters.length}';
    _textController.selection = TextSelection.collapsed(offset: _textController.text.length);
  }

  void _applySample(String sample) {
    _textController.text = sample;
    _textController.selection = TextSelection.collapsed(offset: _textController.text.length);
  }

  void _startDownload() {
    if (_toDownloadCount == 0 || _selectedChapters.isEmpty) return;

    final chaptersToEnqueue = _selectedChapters.toList();

    if (_downloadMode == AudiobookDownloadMode.textOnly) {
      final downloadService = context.read<DownloadService>();
      final filtered = chaptersToEnqueue
          .where((ch) => !downloadService.isChapterDownloaded(ch.id))
          .toList();
      downloadService.enqueueChapters(widget.novel, filtered);
    } else {
      AudiobookDownloadService().enqueueChapters(
        novel: widget.novel,
        chapters: chaptersToEnqueue,
        mode: _downloadMode,
        targetLang: _selectedLanguage.code,
        voice: _selectedVoice,
      );
    }

    Navigator.pop(context);
    final modeLabel = _downloadMode == AudiobookDownloadMode.textOnly
        ? 'text'
        : (_downloadMode == AudiobookDownloadMode.audiobookOnly
            ? 'audiobooks (${_selectedLanguage.englishName})'
            : 'text & audiobooks (${_selectedLanguage.englishName})');
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Queued ${chaptersToEnqueue.length} chapters for $modeLabel download.',
        ),
        backgroundColor: const Color(0xFF8B5CF6),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final downloadService = context.watch<DownloadService>();
    final storagePath = _storageService.chaptersDirectoryPath;

    // How many chapters already downloaded for this novel
    final totalDownloaded = widget.chapters
        .where((c) => downloadService.isChapterDownloaded(c.id))
        .length;

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: bottomInset + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header handle
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

            // Title & Novel Info
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.download_rounded,
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
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Total: ${widget.chapters.length} chapters • $totalDownloaded downloaded',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.white.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Download Mode Selection Cards
            const Text(
              'Select Download Mode:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildModeCard(AudiobookDownloadMode.textOnly, '📖 Text Only', 'Fast (~10 KB)'),
                const SizedBox(width: 8),
                _buildModeCard(AudiobookDownloadMode.audiobookOnly, '🎧 Audio Only', '~1.2 MB / ch'),
                const SizedBox(width: 8),
                _buildModeCard(AudiobookDownloadMode.both, '🌟 Both (T+A)', 'Read + Listen'),
              ],
            ),

            if (_downloadMode != AudiobookDownloadMode.textOnly) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Audio Language & Narrator',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          '${_selectedLanguage.flag} ${_selectedLanguage.englishName}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFA78BFA), fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedLanguage.code,
                      key: ValueKey(_selectedLanguage.code),
                      dropdownColor: const Color(0xFF1A1A26),
                      style: const TextStyle(fontSize: 13, color: Colors.white),
                      decoration: InputDecoration(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        filled: true,
                        fillColor: const Color(0xFF14141E),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                      items: LanguageVoiceRegistry.supportedLanguages.map((l) {
                        return DropdownMenuItem(
                          value: l.code,
                          child: Text('${l.flag} ${l.nativeName} (${l.englishName})'),
                        );
                      }).toList(),
                      onChanged: (code) {
                        if (code != null) {
                          setState(() {
                            _selectedLanguage = LanguageVoiceRegistry.getByCode(code);
                            _selectedVoice = _selectedLanguage.defaultFemaleVoice;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Narrator: $_selectedVoice',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                          ),
                        ),
                        TextButton(
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF8B5CF6),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          onPressed: () {
                            NarratorSelectionSheet.show(
                              context: context,
                              language: _selectedLanguage,
                              currentVoice: _selectedVoice,
                              onVoiceSelected: (voice) {
                                setState(() {
                                  _selectedVoice = voice;
                                });
                              },
                            );
                          },
                          child: const Text('Change', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 16),

            // Storage Folder / File Location Option
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2C),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.folder_open_rounded, size: 18, color: Color(0xFFA78BFA)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Storage Location',
                          style: TextStyle(fontSize: 10.5, color: Colors.white54, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          storagePath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 16, color: Color(0xFFA78BFA)),
                    tooltip: 'Copy Path',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: storagePath));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Storage path copied to clipboard'),
                          duration: Duration(seconds: 2),
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_special_rounded, size: 16, color: Color(0xFFA78BFA)),
                    tooltip: 'Inspect Storage Files',
                    onPressed: () {
                      NovelStorageModal.show(context, widget.novel);
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Chapter Range Input Field
            const Text(
              'Enter Chapter Range or List:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _textController,
              autofocus: false,
              style: const TextStyle(fontSize: 15, color: Colors.white, fontWeight: FontWeight.w500),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF1F1F30),
                hintText: 'e.g. 1-40 or 1-30,40-50 or 1,2 or 30',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.35), fontSize: 13),
                prefixIcon: const Icon(Icons.numbers_rounded, color: Color(0xFFA78BFA)),
                suffixIcon: _textController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, size: 18, color: Colors.white54),
                        onPressed: () => _textController.clear(),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: Color(0xFF8B5CF6)),
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

            const SizedBox(height: 10),

            // Sample Syntax Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  const Text('Examples: ', style: TextStyle(fontSize: 11, color: Colors.white54)),
                  const SizedBox(width: 4),
                  _buildExampleChip('1-40'),
                  const SizedBox(width: 6),
                  _buildExampleChip('1-30,40-50'),
                  const SizedBox(width: 6),
                  _buildExampleChip('1,2'),
                  const SizedBox(width: 6),
                  _buildExampleChip('30'),
                ],
              ),
            ),

            const SizedBox(height: 10),

            // Quick Preset Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildPresetButton(
                    label: '+10 Chapters',
                    onTap: () => _applyNextUnreadPreset(10),
                  ),
                  const SizedBox(width: 6),
                  _buildPresetButton(
                    label: '+25 Chapters',
                    onTap: () => _applyNextUnreadPreset(25),
                  ),
                  const SizedBox(width: 6),
                  _buildPresetButton(
                    label: '+50 Chapters',
                    onTap: () => _applyNextUnreadPreset(50),
                  ),
                  const SizedBox(width: 6),
                  _buildPresetButton(
                    label: 'All Unread',
                    onTap: _applyAllUnreadPreset,
                  ),
                  const SizedBox(width: 6),
                  _buildPresetButton(
                    label: 'All (${widget.chapters.length})',
                    onTap: _applyAllChaptersPreset,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Live Selection Breakdown Box
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2C),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _selectedChapters.isNotEmpty
                      ? const Color(0xFF8B5CF6).withValues(alpha: 0.4)
                      : Colors.white12,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${_selectedChapters.length} Chapters Matched',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      if (_selectedChapters.isNotEmpty)
                        Text(
                          'Range: ${ChapterRangeParser.formatRangeDescription(_parsedNumbers)}',
                          style: const TextStyle(fontSize: 11, color: Color(0xFFA78BFA)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.greenAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle_outline, size: 13, color: Colors.greenAccent),
                            const SizedBox(width: 4),
                            Text(
                              '$_alreadyDownloadedCount already saved',
                              style: const TextStyle(fontSize: 11, color: Colors.greenAccent),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.download_rounded, size: 13, color: Color(0xFFA78BFA)),
                            const SizedBox(width: 4),
                            Text(
                              '$_toDownloadCount to download',
                              style: const TextStyle(fontSize: 11, color: Color(0xFFA78BFA), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Download Action Button
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton.icon(
                onPressed: _toDownloadCount > 0 ? _startDownload : null,
                icon: const Icon(Icons.download_rounded),
                label: Text(
                  _toDownloadCount > 0
                      ? 'Download $_toDownloadCount Chapters'
                      : (_selectedChapters.isEmpty
                          ? 'Enter Chapter Numbers'
                          : 'All Selected Chapters Downloaded'),
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white10,
                  disabledForegroundColor: Colors.white38,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),

            if (totalDownloaded > 0) ...[
              const SizedBox(height: 10),
              Center(
                child: TextButton.icon(
                  onPressed: () async {
                    Navigator.pop(context);
                    await downloadService.deleteNovelDownloads(widget.novel.id, widget.chapters);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cleared downloaded chapters for this novel.')),
                      );
                    }
                  },
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                  label: const Text('Delete Downloaded Chapters', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExampleChip(String text) {
    return InkWell(
      onTap: () => _applySample(text),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: const Color(0xFF26263A),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35)),
        ),
        child: Text(
          text,
          style: const TextStyle(fontSize: 11, color: Color(0xFFA78BFA), fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _buildPresetButton({required String label, required VoidCallback onTap}) {
    return ActionChip(
      onPressed: onTap,
      label: Text(label, style: const TextStyle(fontSize: 11, color: Colors.white)),
      backgroundColor: const Color(0xFF232334),
      side: const BorderSide(color: Colors.white12),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildModeCard(AudiobookDownloadMode mode, String title, String subtitle) {
    final isSelected = _downloadMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          setState(() {
            _downloadMode = mode;
          });
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          decoration: BoxDecoration(
            color: isSelected
                ? const Color(0xFF8B5CF6).withValues(alpha: 0.2)
                : const Color(0xFF1E1E2C),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? const Color(0xFF8B5CF6) : Colors.white10,
              width: isSelected ? 1.8 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : Colors.white70,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10,
                  color: isSelected ? const Color(0xFFA78BFA) : Colors.white38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
