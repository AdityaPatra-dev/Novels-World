import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/services/app_update_service.dart';

/// Shows the in-app update check modal.
Future<void> showAppUpdateDialog(BuildContext context) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF14141E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) => const _UpdateModalContent(),
  );
}

class _UpdateModalContent extends StatefulWidget {
  const _UpdateModalContent();

  @override
  State<_UpdateModalContent> createState() => _UpdateModalContentState();
}

enum _UpdateState { checking, upToDate, updateAvailable, downloading, readyToInstall, error }

class _UpdateModalContentState extends State<_UpdateModalContent> {
  _UpdateState _state = _UpdateState.checking;
  AppReleaseInfo? _release;
  String? _errorMessage;

  double _downloadProgress = 0.0;
  int _bytesReceived = 0;
  int _totalBytes = 0;
  String? _downloadedApkPath;

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
  }

  Future<void> _checkForUpdates() async {
    setState(() {
      _state = _UpdateState.checking;
      _errorMessage = null;
    });

    final release = await AppUpdateService.fetchLatestRelease();
    if (!mounted) return;

    if (release == null) {
      setState(() {
        _state = _UpdateState.error;
        _errorMessage = 'Could not reach GitHub Releases. Please check your internet connection.';
      });
      return;
    }

    _release = release;
    final isNewer = AppUpdateService.isUpdateAvailable(release.tagName);

    setState(() {
      _state = isNewer ? _UpdateState.updateAvailable : _UpdateState.upToDate;
    });
  }

  Future<void> _startDownload() async {
    if (_release == null || _release!.apkDownloadUrl == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No APK asset found for this release.')),
      );
      return;
    }

    setState(() {
      _state = _UpdateState.downloading;
      _downloadProgress = 0.0;
      _bytesReceived = 0;
      _totalBytes = _release!.apkSize ?? 0;
    });

    try {
      final file = await AppUpdateService.downloadApk(
        _release!.apkDownloadUrl!,
        fileName: _release!.apkName ?? 'Novels-World-update.apk',
        onProgress: (progress, received, total) {
          if (mounted) {
            setState(() {
              _downloadProgress = progress;
              _bytesReceived = received;
              _totalBytes = total;
            });
          }
        },
      );

      if (!mounted) return;

      setState(() {
        _state = _UpdateState.readyToInstall;
        _downloadedApkPath = file.path;
      });

      // Automatically launch native Android installer!
      await _launchInstaller();
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _UpdateState.error;
          _errorMessage = 'Download failed: $e';
        });
      }
    }
  }

  Future<void> _launchInstaller() async {
    if (_downloadedApkPath == null) return;
    final success = await AppUpdateService.installApk(_downloadedApkPath!);
    if (!success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Platform.isAndroid
              ? 'Please allow installation from unknown sources in settings.'
              : 'In-app installation is supported on Android devices.'),
          backgroundColor: Colors.orangeAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top grab handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _buildBody(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_state) {
      case _UpdateState.checking:
        return _buildCheckingView();
      case _UpdateState.upToDate:
        return _buildUpToDateView(context);
      case _UpdateState.updateAvailable:
        return _buildUpdateAvailableView(context);
      case _UpdateState.downloading:
        return _buildDownloadingView();
      case _UpdateState.readyToInstall:
        return _buildReadyToInstallView(context);
      case _UpdateState.error:
        return _buildErrorView(context);
    }
  }

  Widget _buildCheckingView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: const [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Checking for Updates...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          SizedBox(height: 6),
          Text(
            'Comparing local build (v${AppUpdateService.currentVersion}) against GitHub Releases',
            style: TextStyle(fontSize: 13, color: Colors.white54),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildUpToDateView(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.green.withValues(alpha: 0.4), width: 1.5),
          ),
          child: const Icon(Icons.verified_rounded, size: 36, color: Colors.greenAccent),
        ),
        const SizedBox(height: 16),
        const Text(
          "You're on the Latest Version!",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E28),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: Text(
            'Novels World v${AppUpdateService.currentVersion}',
            style: const TextStyle(color: Color(0xFFA78BFA), fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ),
        const SizedBox(height: 12),
        const Text(
          'Your app is completely up to date with all the latest web novel sources, studio neural voices, and reader fixes.',
          style: TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF8B5CF6),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(context),
            child: const Text('Great!', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildUpdateAvailableView(BuildContext context) {
    final release = _release!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(Icons.rocket_launch_rounded, size: 28, color: Colors.white),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'New Version Available! 🚀',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        'v${AppUpdateService.currentVersion}',
                        style: const TextStyle(fontSize: 13, color: Colors.white54),
                      ),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 6),
                        child: Icon(Icons.arrow_forward, size: 12, color: Color(0xFF8B5CF6)),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: const Color(0xFF8B5CF6)),
                        ),
                        child: Text(
                          release.tagName,
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFA78BFA)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Package details
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF1E1E28),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.android, size: 18, color: Colors.greenAccent),
                  const SizedBox(width: 8),
                  Text(
                    release.apkName ?? 'Android Package',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                ],
              ),
              Text(
                release.formattedSize,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),

        // Changelog section
        const Text(
          "What's New in This Release:",
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
        ),
        const SizedBox(height: 6),
        Container(
          constraints: const BoxConstraints(maxHeight: 180),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF181822),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white10),
          ),
          child: SingleChildScrollView(
            child: Text(
              release.body.isNotEmpty ? release.body : 'Performance enhancements and bug fixes.',
              style: const TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
            ),
          ),
        ),
        const SizedBox(height: 20),

        // Action buttons
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white24),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: () => Navigator.pop(context),
                child: const Text('Later', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                onPressed: _startDownload,
                icon: const Icon(Icons.download_rounded, color: Colors.white),
                label: const Text(
                  'Update Now',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDownloadingView() {
    final mbReceived = (_bytesReceived / (1024 * 1024)).toStringAsFixed(1);
    final mbTotal = _totalBytes > 0 ? (_totalBytes / (1024 * 1024)).toStringAsFixed(1) : '?';
    final pct = (_downloadProgress * 100).toInt();

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.downloading_rounded, size: 36, color: Color(0xFFA78BFA)),
          ),
          const SizedBox(height: 16),
          const Text(
            'Downloading Update...',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
          ),
          const SizedBox(height: 6),
          Text(
            '$mbReceived MB / $mbTotal MB ($pct%)',
            style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: _downloadProgress > 0 ? _downloadProgress : null,
              minHeight: 8,
              backgroundColor: Colors.white12,
              valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Keep Novels World open. The installer will prompt automatically once finished.',
            style: TextStyle(fontSize: 12, color: Colors.white38),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildReadyToInstallView(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.greenAccent, width: 1.5),
          ),
          child: const Icon(Icons.system_update_rounded, size: 36, color: Colors.greenAccent),
        ),
        const SizedBox(height: 16),
        const Text(
          'Download Complete!',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        const Text(
          'The updated APK has been downloaded. Tap below to launch the package installer.',
          style: TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: _launchInstaller,
            icon: const Icon(Icons.install_mobile_rounded, color: Colors.white),
            label: const Text('Install Update Now', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorView(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            color: Colors.redAccent.withValues(alpha: 0.15),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4), width: 1.5),
          ),
          child: const Icon(Icons.error_outline_rounded, size: 36, color: Colors.redAccent),
        ),
        const SizedBox(height: 16),
        const Text(
          'Update Check Failed',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
        ),
        const SizedBox(height: 8),
        Text(
          _errorMessage ?? 'An error occurred while connecting to GitHub Releases.',
          style: const TextStyle(fontSize: 13, color: Colors.white60),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Close', style: TextStyle(color: Colors.white70)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF8B5CF6)),
                onPressed: _checkForUpdates,
                icon: const Icon(Icons.refresh, color: Colors.white),
                label: const Text('Retry', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
