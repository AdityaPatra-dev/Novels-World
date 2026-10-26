import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Metadata for a published GitHub release.
class AppReleaseInfo {
  final String tagName;
  final String name;
  final String body;
  final DateTime publishedAt;
  final String htmlUrl;
  final String? apkDownloadUrl;
  final int? apkSize;
  final String? apkName;

  AppReleaseInfo({
    required this.tagName,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.htmlUrl,
    this.apkDownloadUrl,
    this.apkSize,
    this.apkName,
  });

  String get formattedSize {
    if (apkSize == null || apkSize! <= 0) return 'Unknown size';
    final mb = apkSize! / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }

  factory AppReleaseInfo.fromJson(Map<String, dynamic> json) {
    String? apkUrl;
    int? apkBytes;
    String? apkFileName;

    final assets = json['assets'] as List<dynamic>?;
    if (assets != null) {
      for (final asset in assets) {
        final assetName = (asset['name'] as String? ?? '').toLowerCase();
        if (assetName.endsWith('.apk')) {
          apkUrl = asset['browser_download_url'] as String?;
          apkBytes = asset['size'] as int?;
          apkFileName = asset['name'] as String?;
          break;
        }
      }
    }

    return AppReleaseInfo(
      tagName: json['tag_name'] as String? ?? '',
      name: json['name'] as String? ?? json['tag_name'] as String? ?? 'New Update',
      body: json['body'] as String? ?? '',
      publishedAt: DateTime.tryParse(json['published_at'] as String? ?? '') ?? DateTime.now(),
      htmlUrl: json['html_url'] as String? ?? '',
      apkDownloadUrl: apkUrl,
      apkSize: apkBytes,
      apkName: apkFileName,
    );
  }
}

/// Service to query GitHub releases, detect updates, stream APK downloads,
/// and trigger the native Android in-app installer.
class AppUpdateService {
  static const String currentVersion = '1.3.0';
  static const String repoOwner = 'AdityaPatra-dev';
  static const String repoName = 'Novels-World';
  static const String _latestReleaseApiUrl =
      'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

  static const MethodChannel _channel = MethodChannel('com.novelsworld.novels_world/app_updater');

  /// Compares two semver strings (e.g. "v1.3.0" vs "1.2.0" or "1.4.0+4").
  /// Returns:
  ///   positive if v1 > v2 (v1 is newer)
  ///   negative if v1 < v2 (v1 is older)
  ///   0 if v1 == v2
  static int compareVersions(String v1, String v2) {
    List<int> parse(String v) {
      final clean = v.trim().toLowerCase().replaceAll(RegExp(r'^v'), '').split('+').first;
      final parts = clean.split('.');
      final numbers = <int>[];
      for (final p in parts) {
        numbers.add(int.tryParse(RegExp(r'\d+').stringMatch(p) ?? '0') ?? 0);
      }
      while (numbers.length < 3) {
        numbers.add(0);
      }
      return numbers;
    }

    final nums1 = parse(v1);
    final nums2 = parse(v2);
    final maxLen = nums1.length > nums2.length ? nums1.length : nums2.length;

    while (nums1.length < maxLen) {
      nums1.add(0);
    }
    while (nums2.length < maxLen) {
      nums2.add(0);
    }

    for (int i = 0; i < maxLen; i++) {
      if (nums1[i] > nums2[i]) return 1;
      if (nums1[i] < nums2[i]) return -1;
    }
    return 0;
  }

  /// Returns true if [latestTag] is strictly newer than [currentVersion].
  static bool isUpdateAvailable(String latestTag, {String current = currentVersion}) {
    return compareVersions(latestTag, current) > 0;
  }

  /// Fetches the latest published release metadata from GitHub.
  static Future<AppReleaseInfo?> fetchLatestRelease() async {
    try {
      final client = http.Client();
      final response = await client.get(
        Uri.parse(_latestReleaseApiUrl),
        headers: {
          'Accept': 'application/vnd.github.v3+json',
          'User-Agent': 'Novels-World-App-Updater/1.0',
        },
      ).timeout(const Duration(seconds: 12));

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(response.body);
        return AppReleaseInfo.fromJson(data);
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Streams the download of the APK file to cache directory with progress callback.
  static Future<File> downloadApk(
    String downloadUrl, {
    required String fileName,
    required void Function(double progress, int bytesReceived, int totalBytes) onProgress,
  }) async {
    final client = http.Client();
    final request = http.Request('GET', Uri.parse(downloadUrl));
    request.headers['User-Agent'] = 'Novels-World-App-Updater/1.0';

    final response = await client.send(request);
    final totalBytes = response.contentLength ?? 0;

    final tempDir = await getTemporaryDirectory();
    final updateDir = Directory('${tempDir.path}/updates');
    if (!await updateDir.exists()) {
      await updateDir.create(recursive: true);
    }

    final safeName = fileName.isNotEmpty ? fileName : 'Novels-World-update.apk';
    final targetFile = File('${updateDir.path}/$safeName');
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final sink = targetFile.openWrite();
    int bytesReceived = 0;

    await for (final chunk in response.stream) {
      sink.add(chunk);
      bytesReceived += chunk.length;
      final progress = totalBytes > 0 ? (bytesReceived / totalBytes).clamp(0.0, 1.0) : 0.0;
      onProgress(progress, bytesReceived, totalBytes);
    }

    await sink.flush();
    await sink.close();
    return targetFile;
  }

  /// Triggers the native Android package installer intent for the downloaded APK.
  static Future<bool> installApk(String filePath) async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('installApk', {'filePath': filePath});
      return result ?? false;
    } catch (_) {
      return false;
    }
  }
}
