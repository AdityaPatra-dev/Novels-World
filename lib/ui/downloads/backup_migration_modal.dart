import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../core/services/backup_service.dart';

class BackupMigrationModal extends StatefulWidget {
  final VoidCallback onDataRestored;

  const BackupMigrationModal({
    super.key,
    required this.onDataRestored,
  });

  static Future<void> show(BuildContext context, {required VoidCallback onDataRestored}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackupMigrationModal(onDataRestored: onDataRestored),
    );
  }

  @override
  State<BackupMigrationModal> createState() => _BackupMigrationModalState();
}

class _BackupMigrationModalState extends State<BackupMigrationModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final BackupService _backupService = BackupService();

  // Export State
  BackupMode _selectedExportMode = BackupMode.monolithic;
  bool _isExporting = false;
  double _exportProgress = 0.0;
  String _exportStatus = '';
  BackupExportResult? _exportResult;

  // Import State
  List<String> _selectedImportFiles = [];
  BackupManifestSummary? _importSummary;
  RestoreMode _selectedRestoreMode = RestoreMode.safeMerge;
  bool _isInspecting = false;
  bool _isRestoring = false;
  double _restoreProgress = 0.0;
  String _restoreStatus = '';
  BackupImportResult? _importResult;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _startExport() async {
    setState(() {
      _isExporting = true;
      _exportProgress = 0.0;
      _exportStatus = 'Starting export...';
      _exportResult = null;
    });

    final result = await _backupService.exportBackup(
      mode: _selectedExportMode,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _exportProgress = progress;
            _exportStatus = status;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isExporting = false;
        _exportResult = result;
      });
    }
  }

  Future<void> _pickImportFiles() async {
    setState(() {
      _isInspecting = true;
      _importSummary = null;
      _importResult = null;
    });

    try {
      final files = await FilePicker.pickFiles(
        type: FileType.any,
      );

      if (files.isNotEmpty) {
        final paths = files
            .map((f) => f.path)
            .whereType<String>()
            .where((p) => p.toLowerCase().endsWith('.zip'))
            .toList();
        if (paths.isEmpty) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Please select valid .zip backup file(s).')),
            );
            setState(() => _isInspecting = false);
          }
          return;
        }
        final summary = await _backupService.inspectBackup(paths);
        if (mounted) {
          setState(() {
            _selectedImportFiles = paths;
            _importSummary = summary;
            _isInspecting = false;
          });
        }
      } else {
        if (mounted) setState(() => _isInspecting = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isInspecting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to read file: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _startRestore() async {
    if (_selectedImportFiles.isEmpty) return;

    setState(() {
      _isRestoring = true;
      _restoreProgress = 0.0;
      _restoreStatus = 'Initiating restore...';
      _importResult = null;
    });

    final result = await _backupService.restoreBackup(
      zipPaths: _selectedImportFiles,
      mode: _selectedRestoreMode,
      onProgress: (progress, status) {
        if (mounted) {
          setState(() {
            _restoreProgress = progress;
            _restoreStatus = status;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _isRestoring = false;
        _importResult = result;
      });
      if (result.success) {
        widget.onDataRestored();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      decoration: const BoxDecoration(
        color: Color(0xFF14141E),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Drag handle & title
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.archive_rounded, color: Color(0xFFA78BFA), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Backup & Migration (.zip)',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        'Preserve, move or restore novels and audiobooks',
                        style: TextStyle(fontSize: 11, color: Colors.white60),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          // Tab bar
          TabBar(
            controller: _tabController,
            indicatorColor: const Color(0xFFA78BFA),
            indicatorWeight: 3,
            labelColor: const Color(0xFFA78BFA),
            unselectedLabelColor: Colors.white60,
            tabs: const [
              Tab(
                icon: Icon(Icons.file_upload_outlined, size: 20),
                text: 'Export Backup',
              ),
              Tab(
                icon: Icon(Icons.file_download_outlined, size: 20),
                text: 'Import Backup',
              ),
            ],
          ),
          // Tab contents
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildExportTab(),
                _buildImportTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExportTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Export Archive Mode',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 10),
          _buildExportModeOption(
            mode: BackupMode.monolithic,
            title: 'Single Archive (.zip)',
            subtitle: 'Best for local backups & PC transfers. All novels, text, audio & translations in one .zip file.',
            icon: Icons.inventory_2_rounded,
          ),
          const SizedBox(height: 8),
          _buildExportModeOption(
            mode: BackupMode.splitBatches,
            title: '1.5 GB Batched Splits',
            subtitle: 'Recommended for cloud drives and FAT32 cards. Splits into 1.5 GB batches with atomic chapter integrity.',
            icon: Icons.splitscreen_rounded,
          ),
          const SizedBox(height: 20),

          // Action / Progress / Result
          if (_isExporting) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1E1E2C),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.4)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Exporting Offline Archive...',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      Text(
                        '${(_exportProgress * 100).toInt()}%',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFA78BFA)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: _exportProgress,
                      backgroundColor: Colors.white10,
                      color: const Color(0xFFA78BFA),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _exportStatus,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11, color: Colors.white60),
                  ),
                ],
              ),
            ),
          ] else if (_exportResult != null) ...[
            _buildExportResultCard(_exportResult!),
          ] else ...[
            ElevatedButton.icon(
              onPressed: _startExport,
              icon: const Icon(Icons.archive_outlined),
              label: const Text('Export Offline Backup Now', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildExportModeOption({
    required BackupMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedExportMode == mode;
    return InkWell(
      onTap: _isExporting ? null : () => setState(() => _selectedExportMode = mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF8B5CF6).withValues(alpha: 0.12) : const Color(0xFF1B1B26),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF8B5CF6) : Colors.white12,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFFA78BFA) : Colors.white60,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.white60, height: 1.3),
                  ),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFFA78BFA) : Colors.white38,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFA78BFA),
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExportResultCard(BackupExportResult res) {
    if (!res.success) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.redAccent, size: 20),
                SizedBox(width: 8),
                Text('Export Failed', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.redAccent)),
              ],
            ),
            const SizedBox(height: 6),
            Text(res.errorMessage ?? 'An unknown error occurred.', style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: const Color(0xFF10B981).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 20),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Backup Exported Successfully!',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Created ${res.backupFiles.length} file(s) • Total Size: ${res.formattedTotalSize}',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFFA78BFA)),
          ),
          const SizedBox(height: 10),
          // Saved location box with copy path
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF14141E),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.folder_open_rounded, size: 14, color: Colors.white60),
                    SizedBox(width: 6),
                    Text('Saved Location:', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white60)),
                  ],
                ),
                const SizedBox(height: 4),
                SelectableText(
                  res.directoryPath,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace', color: Colors.white70),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          // Generated Files List
          ...res.backupFiles.map((file) {
            final fileName = file.uri.pathSegments.last;
            final sizeMb = (file.lengthSync() / (1024 * 1024)).toStringAsFixed(1);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file_outlined, size: 14, color: Color(0xFFA78BFA)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(fileName, style: const TextStyle(fontSize: 11.5, color: Colors.white)),
                  ),
                  Text('$sizeMb MB', style: const TextStyle(fontSize: 11, color: Colors.white60)),
                ],
              ),
            );
          }),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: res.directoryPath));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Backup folder path copied to clipboard')),
                    );
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy Path'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFA78BFA),
                    side: const BorderSide(color: Color(0xFFA78BFA)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => setState(() => _exportResult = null),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('New Export'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF8B5CF6),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildImportTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Restore Offline Content from .zip',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 4),
          const Text(
            'Select your backup zip archive (or multiple parts if split) to restore novels, chapters, audiobooks, and reading history.',
            style: TextStyle(fontSize: 12, color: Colors.white60, height: 1.3),
          ),
          const SizedBox(height: 16),

          // File Picker Button
          OutlinedButton.icon(
            onPressed: (_isInspecting || _isRestoring) ? null : _pickImportFiles,
            icon: const Icon(Icons.folder_zip_rounded),
            label: Text(_selectedImportFiles.isEmpty ? 'Select Backup File(s) (.zip)' : 'Change Selection (${_selectedImportFiles.length} files)'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFA78BFA),
              side: const BorderSide(color: Color(0xFFA78BFA)),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),

          if (_isInspecting)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(20),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_importSummary != null) ...[
            _buildImportPreviewCard(_importSummary!),
            const SizedBox(height: 16),
            const Text(
              'Restore Mode',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            _buildRestoreModeOption(
              mode: RestoreMode.safeMerge,
              title: 'Safe Merge (Recommended)',
              subtitle: 'Merges novels & chapters into your existing downloads without overwriting existing intact content.',
              icon: Icons.merge_type_rounded,
            ),
            const SizedBox(height: 8),
            _buildRestoreModeOption(
              mode: RestoreMode.replaceAll,
              title: 'Clean Replace All',
              subtitle: 'Wipes current offline downloads and restores exact state from the backup archives.',
              icon: Icons.delete_sweep_rounded,
            ),
            const SizedBox(height: 20),

            if (_isRestoring) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2C),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Restoring Backup...',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                        ),
                        Text(
                          '${(_restoreProgress * 100).toInt()}%',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFA78BFA)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _restoreProgress,
                        backgroundColor: Colors.white10,
                        color: const Color(0xFFA78BFA),
                        minHeight: 6,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _restoreStatus,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                  ],
                ),
              ),
            ] else ...[
              ElevatedButton.icon(
                onPressed: _startRestore,
                icon: const Icon(Icons.system_update_alt_rounded),
                label: const Text('Restore Backup Now', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(48),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ],
          ],

          if (_importResult != null) ...[
            const SizedBox(height: 16),
            _buildImportResultCard(_importResult!),
          ],
        ],
      ),
    );
  }

  Widget _buildImportPreviewCard(BackupManifestSummary summary) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.inventory_rounded, color: Color(0xFFA78BFA), size: 18),
              SizedBox(width: 8),
              Text(
                'Archive Manifest Verified',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatPill('Novels', '${summary.totalNovels}', Icons.book_rounded),
              _buildStatPill('Chapters', '${summary.totalChapters}', Icons.article_rounded),
              _buildStatPill('Audiobooks', '${summary.totalAudiobooks}', Icons.headphones_rounded),
              _buildStatPill('Batches', '${summary.totalBatches}', Icons.splitscreen_rounded),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            'Included: ${summary.novelTitles.take(3).join(', ')}${summary.novelTitles.length > 3 ? '...' : ''}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, color: Colors.white60),
          ),
        ],
      ),
    );
  }

  Widget _buildStatPill(String label, String value, IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 16, color: const Color(0xFFA78BFA)),
        const SizedBox(height: 2),
        Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white)),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white60)),
      ],
    );
  }

  Widget _buildRestoreModeOption({
    required RestoreMode mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _selectedRestoreMode == mode;
    return InkWell(
      onTap: _isRestoring ? null : () => setState(() => _selectedRestoreMode = mode),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF8B5CF6).withValues(alpha: 0.12) : const Color(0xFF1B1B26),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF8B5CF6) : Colors.white12,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: isSelected ? const Color(0xFFA78BFA) : Colors.white60,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: Colors.white60, height: 1.3),
                  ),
                ],
              ),
            ),
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? const Color(0xFFA78BFA) : Colors.white38,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          color: Color(0xFFA78BFA),
                        ),
                      ),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImportResultCard(BackupImportResult res) {
    if (!res.success) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.redAccent.withValues(alpha: 0.3)),
        ),
        child: Text(
          res.errorMessage ?? 'Restore failed.',
          style: const TextStyle(fontSize: 12, color: Colors.white70),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF10B981).withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Color(0xFF34D399), size: 20),
              SizedBox(width: 8),
              Text(
                'Restore Complete!',
                style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Successfully restored ${res.restoredNovelsCount} novels, ${res.restoredChaptersCount} chapters, and ${res.restoredAudiobooksCount} audiobooks.',
            style: const TextStyle(fontSize: 11.5, color: Colors.white70),
          ),
        ],
      ),
    );
  }
}
