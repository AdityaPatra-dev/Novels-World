import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

/// Represents a single page with extracted OCR text and optional image asset.
class PdfOcrPage {
  final int pageNumber;
  final String text;
  final String? imagePath;

  PdfOcrPage({
    required this.pageNumber,
    required this.text,
    this.imagePath,
  });
}

/// Service to render PDF pages into images using native platform renderers.
/// On Android, uses the OS built-in android.graphics.pdf.PdfRenderer (API 21+)
/// without requiring any third-party binaries, and Google ML Kit on-device text recognition.
/// On Linux/macOS/Desktop, uses pdftoppm if available.
class PdfPageRenderer {
  static const MethodChannel _channel = MethodChannel('com.novelsworld.novels_world/pdf_renderer');

  /// Gets total page count of a PDF file.
  static Future<int?> getPageCount(String filePath) async {
    if (kIsWeb) return null;

    if (Platform.isAndroid) {
      try {
        final count = await _channel.invokeMethod<int>('getPageCount', {'filePath': filePath});
        return count;
      } catch (e) {
        debugPrint('[PdfPageRenderer] getPageCount error: $e');
        return null;
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      try {
        final res = await Process.run('pdfinfo', [filePath]);
        if (res.exitCode == 0) {
          final match = RegExp(r'Pages:\s+(\d+)').firstMatch(res.stdout.toString());
          if (match != null) {
            return int.tryParse(match.group(1)!);
          }
        }
      } catch (_) {}
    }
    return null;
  }

  /// Renders all pages of a PDF file into JPEG images in [outputDir].
  /// Returns a list of absolute file paths to the generated images in page order.
  static Future<List<String>> renderPages(
    String filePath,
    String outputDir, {
    int dpi = 150,
    int maxPages = 1000,
  }) async {
    if (kIsWeb) return [];

    final outDir = Directory(outputDir);
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeListMethod<String>('renderPages', {
          'filePath': filePath,
          'outputDir': outputDir,
          'dpi': dpi,
          'maxPages': maxPages,
        });
        return result ?? [];
      } catch (e) {
        debugPrint('[PdfPageRenderer] renderPages error on Android: $e');
        return [];
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      try {
        final prefix = '${outDir.path}/page';
        final res = await Process.run('pdftoppm', [
          '-jpeg',
          '-r',
          '$dpi',
          filePath,
          prefix,
        ]);
        if (res.exitCode == 0) {
          final files = outDir
              .listSync()
              .whereType<File>()
              .where((f) => f.path.contains('/page-') && (f.path.endsWith('.jpg') || f.path.endsWith('.jpeg')))
              .map((f) => f.path)
              .toList();
          files.sort();
          return files;
        }
      } catch (e) {
        debugPrint('[PdfPageRenderer] pdftoppm error: $e');
      }
    }

    return [];
  }

  /// Ensures Tesseract traineddata for [lang] is present on device.
  /// Downloads from official GitHub fast tessdata if not already present.
  /// Returns the base directory whose child is 'tessdata'.
  static Future<String?> ensureTessData(String lang) async {
    if (kIsWeb) return null;
    try {
      final docDir = await getApplicationDocumentsDirectory();
      final baseDir = Directory('${docDir.path}/tesseract');
      final tessdataDir = Directory('${baseDir.path}/tessdata');
      if (!await tessdataDir.exists()) {
        await tessdataDir.create(recursive: true);
      }
      final targetFile = File('${tessdataDir.path}/$lang.traineddata');
      if (!await targetFile.exists() || await targetFile.length() < 1000) {
        debugPrint('[PdfPageRenderer] Downloading tessdata for $lang...');
        final url = 'https://raw.githubusercontent.com/tesseract-ocr/tessdata_fast/main/$lang.traineddata';
        final resp = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 45));
        if (resp.statusCode == 200 && resp.bodyBytes.isNotEmpty) {
          await targetFile.writeAsBytes(resp.bodyBytes);
          debugPrint('[PdfPageRenderer] Downloaded tessdata for $lang: ${resp.bodyBytes.length} bytes');
        } else {
          debugPrint('[PdfPageRenderer] Failed to download tessdata for $lang: status ${resp.statusCode}');
          return null;
        }
      }
      return baseDir.path;
    } catch (e) {
      debugPrint('[PdfPageRenderer] ensureTessData error: $e');
      return null;
    }
  }

  /// Extracts text from a list of image paths using on-device OCR (ML Kit or Tesseract).
  static Future<List<Map<String, String>>> extractTextFromImages(
    List<String> imagePaths, {
    String script = 'latin',
    String? tessDataDir,
  }) async {
    if (kIsWeb || imagePaths.isEmpty) return [];

    if (Platform.isAndroid) {
      try {
        final raw = await _channel.invokeListMethod<Map>('extractTextFromImages', {
          'imagePaths': imagePaths,
          'script': script,
          'tessDataDir': ?tessDataDir,
        });
        if (raw != null) {
          return raw.map((m) => {
            'imagePath': (m['imagePath'] as String?) ?? '',
            'text': (m['text'] as String?) ?? '',
          }).toList();
        }
      } catch (e) {
        debugPrint('[PdfPageRenderer] extractTextFromImages error on Android: $e');
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      final results = <Map<String, String>>[];
      for (final imgPath in imagePaths) {
        var text = '';
        try {
          final outTxtBase = '${imgPath}_ocr';
          final lang = script.startsWith('ori') ? 'ori' : (script.startsWith('hin') ? 'hin' : 'eng');
          final ocrRes = await Process.run('tesseract', [imgPath, outTxtBase, '-l', lang]);
          if (ocrRes.exitCode == 0) {
            final txtFile = File('$outTxtBase.txt');
            if (await txtFile.exists()) {
              text = await txtFile.readAsString();
              try {
                await txtFile.delete();
              } catch (_) {}
            }
          }
        } catch (_) {}
        results.add({'imagePath': imgPath, 'text': text});
      }
      return results;
    }

    return [];
  }

  /// Extracts text and page illustrations from a PDF file using on-device OCR.
  /// On Android, uses Google ML Kit Text Recognition running directly on in-memory bitmaps,
  /// or Tesseract OCR for Indic scripts (such as Odia 'ori' and Hindi 'hin').
  /// Returns structured [PdfOcrPage] items containing cleaned text paragraphs.
  static Future<List<PdfOcrPage>> extractPagesWithOcr(
    String filePath,
    String outputDir, {
    String script = 'latin',
    int dpi = 150,
    int maxPages = 1000,
    String? tessDataDir,
  }) async {
    if (kIsWeb) return [];

    final outDir = Directory(outputDir);
    if (!await outDir.exists()) {
      await outDir.create(recursive: true);
    }

    if (Platform.isAndroid) {
      try {
        final rawList = await _channel.invokeListMethod<Map>('extractPagesWithOcr', {
          'filePath': filePath,
          'outputDir': outputDir,
          'script': script,
          'dpi': dpi,
          'maxPages': maxPages,
          'tessDataDir': ?tessDataDir,
        });

        if (rawList != null) {
          return rawList.map((m) {
            return PdfOcrPage(
              pageNumber: (m['pageNumber'] as num?)?.toInt() ?? 1,
              text: (m['text'] as String?) ?? '',
              imagePath: m['imagePath'] as String?,
            );
          }).toList();
        }
      } catch (e) {
        debugPrint('[PdfPageRenderer] extractPagesWithOcr error: $e');
      }
    } else if (Platform.isLinux || Platform.isMacOS) {
      try {
        final imgPaths = await renderPages(filePath, outputDir, dpi: dpi, maxPages: maxPages);
        final results = <PdfOcrPage>[];
        for (int i = 0; i < imgPaths.length; i++) {
          final imgPath = imgPaths[i];
          final outTxtBase = '${outDir.path}/page_${i + 1}_ocr';
          var text = '';
          final lang = script.startsWith('ori') ? 'ori' : (script.startsWith('hin') ? 'hin' : 'eng');
          final ocrRes = await Process.run('tesseract', [imgPath, outTxtBase, '-l', lang]);
          if (ocrRes.exitCode == 0) {
            final txtFile = File('$outTxtBase.txt');
            if (await txtFile.exists()) {
              text = await txtFile.readAsString();
              try {
                await txtFile.delete();
              } catch (_) {}
            }
          }
          results.add(PdfOcrPage(
            pageNumber: i + 1,
            text: text,
            imagePath: imgPath,
          ));
        }
        return results;
      } catch (_) {}
    }

    return [];
  }
}
