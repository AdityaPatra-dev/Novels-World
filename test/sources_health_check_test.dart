import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/extractors/source_registry.dart';
import 'package:novels_world/core/models/novel.dart';

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (cert, host, port) => true;
  }
}

class SourceHealthResult {
  final String id;
  final String name;
  final String baseUrl;
  final String lang;
  final bool isHealthy;
  final String errorType;
  final String errorMessage;
  final int latencyMs;
  final String? sampleTitle;
  final int? chapterCount;

  SourceHealthResult({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.lang,
    required this.isHealthy,
    this.errorType = '',
    this.errorMessage = '',
    required this.latencyMs,
    this.sampleTitle,
    this.chapterCount,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'lang': lang,
    'status': isHealthy ? 'HEALTHY' : 'FAILED',
    'error_type': errorType,
    'error_message': errorMessage,
    'latency_ms': latencyMs,
    'sample_title': sampleTitle,
    'chapter_count': chapterCount,
  };
}

void main() {
  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  final allSources = SourceRegistry.getAllSources();
  final onlineSources = allSources.where((s) => s.id != 'local_epub').toList();
  final results = <SourceHealthResult>[];

  group('Daily Live Source Health Checks', () {
    for (final source in onlineSources) {
      test('Health Check: [${source.id}] ${source.name} (${source.lang})', () async {
        final stopwatch = Stopwatch()..start();
        try {
          // 1. Fetch popular novels (or latest as fallback)
          List<Novel> novels = [];
          try {
            novels = await source.getPopular(page: 1).timeout(const Duration(seconds: 25));
          } catch (e) {
            // Fallback to latest
            novels = await source.getLatest(page: 1).timeout(const Duration(seconds: 25));
          }

          if (novels.isEmpty) {
            throw Exception('Empty novel catalog returned (0 items parsed from popular/latest)');
          }

          final firstNovel = novels.first;
          if (firstNovel.title.trim().isEmpty) {
            throw Exception('Novel item parsed with empty title');
          }
          if (firstNovel.sourceUrl.trim().isEmpty) {
            throw Exception('Novel item parsed with empty sourceUrl');
          }

          // 2. Fetch chapter list for first novel
          int? chaptersFound;
          try {
            final chapters = await source.getChapterList(firstNovel.sourceUrl).timeout(const Duration(seconds: 20));
            chaptersFound = chapters.length;
          } catch (_) {
            // Chapter listing failure is non-fatal if catalog list works, but recorded
          }

          stopwatch.stop();
          final res = SourceHealthResult(
            id: source.id,
            name: source.name,
            baseUrl: source.baseUrl,
            lang: source.lang,
            isHealthy: true,
            latencyMs: stopwatch.elapsedMilliseconds,
            sampleTitle: firstNovel.title,
            chapterCount: chaptersFound,
          );
          results.add(res);
          // ignore: avoid_print
          print('✅ [${source.id}] ${source.name}: OK (${stopwatch.elapsedMilliseconds}ms, sample: "${firstNovel.title}", chapters: $chaptersFound)');
        } catch (e) {
          stopwatch.stop();
          final errStr = e.toString();
          String classifiedType = 'Unknown Error';
          if (errStr.contains('403') || errStr.toLowerCase().contains('cloudflare') || errStr.toLowerCase().contains('ddos-guard')) {
            classifiedType = 'Cloudflare / 403 Forbidden';
          } else if (errStr.contains('SocketException') || errStr.contains('Failed host lookup') || errStr.contains('Connection refused')) {
            classifiedType = 'DNS / Network Unreachable';
          } else if (errStr.contains('TimeoutException') || errStr.contains('timed out')) {
            classifiedType = 'Request Timeout (>25s)';
          } else if (errStr.contains('Empty novel catalog')) {
            classifiedType = 'Empty Catalog (DOM Changed)';
          } else if (errStr.contains('500') || errStr.contains('502') || errStr.contains('503') || errStr.contains('504')) {
            classifiedType = 'Remote Server Error (5xx)';
          } else if (errStr.contains('404')) {
            classifiedType = 'HTTP 404 Not Found';
          }

          final res = SourceHealthResult(
            id: source.id,
            name: source.name,
            baseUrl: source.baseUrl,
            lang: source.lang,
            isHealthy: false,
            errorType: classifiedType,
            errorMessage: errStr,
            latencyMs: stopwatch.elapsedMilliseconds,
          );
          results.add(res);
          // ignore: avoid_print
          print('❌ [${source.id}] ${source.name}: FAILED ($classifiedType in ${stopwatch.elapsedMilliseconds}ms) -> $errStr');
        }
      }, timeout: const Timeout(Duration(seconds: 40)));
    }

    test('Generate Health Check Report and Validate Catalog Health', () {
      final total = results.length;
      final healthy = results.where((r) => r.isHealthy).toList();
      final failed = results.where((r) => !r.isHealthy).toList();

      // Ensure output directory exists
      final reportsDir = Directory('build/reports');
      if (!reportsDir.existsSync()) {
        reportsDir.createSync(recursive: true);
      }

      final reportJson = {
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'total_sources': total,
        'healthy_count': healthy.length,
        'failed_count': failed.length,
        'health_percentage': total > 0 ? ((healthy.length / total) * 100).toStringAsFixed(1) : '0',
        'results': results.map((r) => r.toJson()).toList(),
      };

      final jsonFile = File('build/reports/source_health_summary.json');
      jsonFile.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(reportJson));

      // Generate Markdown Report
      final mdBuffer = StringBuffer();
      mdBuffer.writeln('# 🌐 Daily Source Health & Availability Report');
      mdBuffer.writeln('**Run Timestamp:** `${DateTime.now().toUtc().toIso8601String()}`  ');
      mdBuffer.writeln('**Total Sources Tested:** `$total` | **Healthy:** `${healthy.length}` ✅ | **Failed:** `${failed.length}` ❌  ');
      mdBuffer.writeln('**Catalog Health:** `${reportJson['health_percentage']}%`\n');

      if (failed.isNotEmpty) {
        mdBuffer.writeln('## ❌ Failing Sources Details');
        mdBuffer.writeln('| Source Name | ID | Lang | Base URL | Error Category | Latency | Details |');
        mdBuffer.writeln('| :--- | :--- | :--- | :--- | :--- | :--- | :--- |');
        for (final f in failed) {
          final cleanMsg = f.errorMessage.replaceAll('\n', ' ').replaceAll('|', '/');
          final shortMsg = cleanMsg.length > 80 ? '${cleanMsg.substring(0, 77)}...' : cleanMsg;
          mdBuffer.writeln('| **${f.name}** | `${f.id}` | `${f.lang}` | [${f.baseUrl}](${f.baseUrl}) | **${f.errorType}** | `${f.latencyMs}ms` | `$shortMsg` |');
        }
        mdBuffer.writeln();
      }

      mdBuffer.writeln('## ✅ Healthy Sources (${healthy.length})');
      mdBuffer.writeln('| Source Name | ID | Lang | Base URL | Sample Novel | Chapters | Latency |');
      mdBuffer.writeln('| :--- | :--- | :--- | :--- | :--- | :--- | :--- |');
      for (final h in healthy) {
        final sample = (h.sampleTitle ?? '').replaceAll('|', '/');
        final shortSample = sample.length > 35 ? '${sample.substring(0, 32)}...' : sample;
        mdBuffer.writeln('| **${h.name}** | `${h.id}` | `${h.lang}` | [${h.baseUrl}](${h.baseUrl}) | $shortSample | `${h.chapterCount ?? 'N/A'}` | `${h.latencyMs}ms` |');
      }

      final mdFile = File('build/reports/source_health_summary.md');
      mdFile.writeAsStringSync(mdBuffer.toString());

      // ignore: avoid_print
      print('\n========================================');
      // ignore: avoid_print
      print('📊 SOURCE HEALTH SUMMARY');
      // ignore: avoid_print
      print('Total: $total | Healthy: ${healthy.length} | Failed: ${failed.length} (${reportJson['health_percentage']}%)');
      // ignore: avoid_print
      print('Reports generated at: ${jsonFile.path} and ${mdFile.path}');
      // ignore: avoid_print
      print('========================================\n');

      // Fail test if failed sources > 0 so GitHub Actions captures the failure
      if (failed.isNotEmpty) {
        final failedSummary = failed.map((f) => '${f.name} (${f.errorType})').join(', ');
        fail('Source Health Check: ${failed.length}/$total sources failed: $failedSummary');
      }
    });
  });
}
