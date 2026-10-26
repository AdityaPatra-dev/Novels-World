import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/services/app_update_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  group('AppUpdateService Semantic Versioning & Detection Tests', () {
    test('compareVersions correctly identifies version precedence', () {
      // Newer versions
      expect(AppUpdateService.compareVersions('1.4.0', '1.3.0'), greaterThan(0));
      expect(AppUpdateService.compareVersions('v1.3.1', '1.3.0'), greaterThan(0));
      expect(AppUpdateService.compareVersions('2.0.0', '1.9.9'), greaterThan(0));
      expect(AppUpdateService.compareVersions('v1.3.0.1', '1.3.0'), greaterThan(0));

      // Same versions
      expect(AppUpdateService.compareVersions('v1.3.0', '1.3.0'), equals(0));
      expect(AppUpdateService.compareVersions('1.3.0+4', '1.3.0+3'), equals(0));
      expect(AppUpdateService.compareVersions('v1.0.0', 'v1.0.0'), equals(0));

      // Older versions
      expect(AppUpdateService.compareVersions('1.2.9', '1.3.0'), lessThan(0));
      expect(AppUpdateService.compareVersions('v1.1.0', 'v1.3.0'), lessThan(0));
      expect(AppUpdateService.compareVersions('0.9.5', '1.0.0'), lessThan(0));
    });

    test('isUpdateAvailable correctly detects if an update is available', () {
      expect(AppUpdateService.isUpdateAvailable('v1.4.0', current: '1.3.0'), isTrue);
      expect(AppUpdateService.isUpdateAvailable('v1.3.1', current: '1.3.0'), isTrue);
      expect(AppUpdateService.isUpdateAvailable('v2.0.0', current: '1.3.0'), isTrue);

      expect(AppUpdateService.isUpdateAvailable('v1.3.0', current: '1.3.0'), isFalse);
      expect(AppUpdateService.isUpdateAvailable('v1.2.0', current: '1.3.0'), isFalse);
      expect(AppUpdateService.isUpdateAvailable('1.1.0', current: '1.3.0'), isFalse);
    });

    test('AppReleaseInfo.fromJson parses release metadata and discovers APK asset', () {
      final mockJson = {
        'tag_name': 'v1.4.0',
        'name': 'Novels World v1.4.0 🚀',
        'body': '### Features\n* Added in-app updater\n* Enhanced audio',
        'published_at': '2026-10-27T02:00:00Z',
        'html_url': 'https://github.com/AdityaPatra-dev/Novels-World/releases/tag/v1.4.0',
        'assets': [
          {
            'name': 'Novels-World-Linux-x64.tar.gz',
            'browser_download_url': 'https://github.com/releases/download/v1.4.0/linux.tar.gz',
            'size': 45000000,
          },
          {
            'name': 'Novels-World-Android.apk',
            'browser_download_url': 'https://github.com/releases/download/v1.4.0/Novels-World-Android.apk',
            'size': 29884416, // ~28.5 MB
          },
          {
            'name': 'Novels-World-Windows-x64.zip',
            'browser_download_url': 'https://github.com/releases/download/v1.4.0/windows.zip',
            'size': 50000000,
          }
        ]
      };

      final release = AppReleaseInfo.fromJson(mockJson);
      expect(release.tagName, 'v1.4.0');
      expect(release.name, contains('v1.4.0'));
      expect(release.apkName, 'Novels-World-Android.apk');
      expect(release.apkDownloadUrl, contains('.apk'));
      expect(release.formattedSize, '28.5 MB');
      expect(release.body, contains('Added in-app updater'));
    });

    test('Live GitHub Releases API integration check', () async {
      final release = await AppUpdateService.fetchLatestRelease();
      expect(release, isNotNull, reason: 'GitHub Releases API should be reachable');
      expect(release!.tagName, isNotEmpty);
      expect(release.htmlUrl, contains('AdityaPatra-dev/Novels-World'));
      // ignore: avoid_print
      print('✅ Live GitHub Releases Latest: ${release.tagName} (${release.name})');
      // ignore: avoid_print
      print('   APK: ${release.apkName ?? "None"} | Size: ${release.formattedSize} | URL: ${release.apkDownloadUrl ?? "None"}');
    });
  });
}

