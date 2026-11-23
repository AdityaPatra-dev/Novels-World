import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import '../models/novel.dart';
import '../models/chapter.dart';
import '../models/chapter_content.dart';
import '../utils/text_cleaner.dart';
import 'webview_session_manager.dart';
import 'pdf_page_renderer.dart';

/// Service responsible for parsing, extracting, and importing local EPUB and PDF files
/// into the Novels-World offline library.
class EpubService {
  static final EpubService _instance = EpubService._internal();
  factory EpubService() => _instance;
  EpubService._internal();

  /// Universal book importer: automatically detects whether the file is an EPUB archive
  /// or a PDF document, and unpacks it into the reader database.
  Future<Novel> importBook(File bookFile, {Directory? targetDir, Novel? originalNovel}) async {
    final bytes = await bookFile.readAsBytes();
    if (bytes.length >= 4 &&
        bytes[0] == 0x25 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x44 &&
        bytes[3] == 0x46) {
      return importPdf(bookFile, targetDir: targetDir, originalNovel: originalNovel, bytes: bytes);
    }
    return importEpub(bookFile, targetDir: targetDir, originalNovel: originalNovel, bytes: bytes);
  }

  /// Imports an EPUB file, extracts its contents into app documents,
  /// parses its metadata/spine/TOC, and returns a fully initialized [Novel].
  Future<Novel> importEpub(File epubFile, {Directory? targetDir, Novel? originalNovel, List<int>? bytes}) async {
    final epubBytes = bytes ?? await epubFile.readAsBytes();

    // Verify magic bytes: Standard ZIP/EPUB starts with PK\x03\x04 (0x50, 0x4B, 0x03, 0x04)
    if (epubBytes.length < 4 ||
        epubBytes[0] != 0x50 ||
        epubBytes[1] != 0x4B ||
        epubBytes[2] != 0x03 ||
        epubBytes[3] != 0x04) {
      throw const FormatException('Corrupt or invalid EPUB archive: missing PK signature header');
    }

    final archive = ZipDecoder().decodeBytes(epubBytes);

    // Compute a stable ID from file content hash or use originalNovel.id
    final digest = md5.convert(epubBytes.sublist(0, epubBytes.length > 8192 ? 8192 : epubBytes.length)).toString().substring(0, 12);
    final novelId = (originalNovel != null && originalNovel.id.isNotEmpty)
        ? originalNovel.id
        : 'local_epub_$digest';

    final baseDir = targetDir ?? await _getImportDirectory();
    final bookDir = Directory('${baseDir.path}/$novelId');
    if (!await bookDir.exists()) {
      await bookDir.create(recursive: true);
    }

    // 1. Unpack all files to disk
    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        final outFile = File('${bookDir.path}/$filename');
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(data);
      }
    }

    // 2. Locate container.xml to find the root .opf file
    final containerFile = File('${bookDir.path}/META-INF/container.xml');
    if (!await containerFile.exists()) {
      throw Exception('Invalid EPUB: META-INF/container.xml not found');
    }

    final containerDoc = XmlDocument.parse(await containerFile.readAsString());
    final rootfileEl = containerDoc.findAllElements('rootfile').firstOrNull;
    final opfRelPath = rootfileEl?.getAttribute('full-path');
    if (opfRelPath == null || opfRelPath.isEmpty) {
      throw Exception('Invalid EPUB: rootfile path missing in container.xml');
    }

    final opfFile = File('${bookDir.path}/$opfRelPath');
    if (!await opfFile.exists()) {
      throw Exception('Invalid EPUB: OPF file not found at $opfRelPath');
    }

    final opfDir = opfFile.parent.path;
    final opfDoc = XmlDocument.parse(await opfFile.readAsString());

    // 3. Parse Metadata
    final titleEl = opfDoc.findAllElements('dc:title').firstOrNull ?? opfDoc.findAllElements('title').firstOrNull;
    var title = titleEl?.innerText.trim() ?? '';
    if (title.isEmpty) {
      title = epubFile.uri.pathSegments.last.replaceAll('.epub', '');
    }

    final creatorEl = opfDoc.findAllElements('dc:creator').firstOrNull ?? opfDoc.findAllElements('creator').firstOrNull;
    final author = creatorEl?.innerText.trim().isNotEmpty == true ? creatorEl!.innerText.trim() : 'Unknown Author';

    final descEl = opfDoc.findAllElements('dc:description').firstOrNull ?? opfDoc.findAllElements('description').firstOrNull;
    final description = descEl?.innerText.trim() ?? '';

    // 4. Manifest map (id -> href, media-type)
    final manifestMap = <String, Map<String, String>>{};
    for (final item in opfDoc.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      final mediaType = item.getAttribute('media-type') ?? '';
      if (id != null && href != null) {
        manifestMap[id] = {'href': href, 'type': mediaType};
      }
    }

    // 5. Look for cover image
    String coverUrl = '';
    String? coverHref;
    // Check <meta name="cover" content="id">
    for (final meta in opfDoc.findAllElements('meta')) {
      if (meta.getAttribute('name') == 'cover') {
        final coverId = meta.getAttribute('content');
        if (coverId != null && manifestMap.containsKey(coverId)) {
          coverHref = manifestMap[coverId]!['href'];
          break;
        }
      }
    }
    // Fallback: look for image with "cover" in ID or href
    if (coverHref == null) {
      for (final entry in manifestMap.entries) {
        final id = entry.key.toLowerCase();
        final href = (entry.value['href'] ?? '').toLowerCase();
        final type = entry.value['type'] ?? '';
        if (type.startsWith('image/') && (id.contains('cover') || href.contains('cover'))) {
          coverHref = entry.value['href'];
          break;
        }
      }
    }

    if (coverHref != null) {
      final decodedCover = Uri.decodeFull(coverHref);
      File coverFile = File('$opfDir/$decodedCover');
      if (!await coverFile.exists()) {
        coverFile = File('${bookDir.path}/$decodedCover');
      }
      if (await coverFile.exists()) {
        coverUrl = coverFile.uri.toString();
      }
    }

    // 6. Build spine chapter list
    final spineItems = <String>[];
    for (final itemref in opfDoc.findAllElements('itemref')) {
      final idref = itemref.getAttribute('idref');
      if (idref != null && manifestMap.containsKey(idref)) {
        spineItems.add(idref);
      }
    }

    // Parse TOC (toc.ncx or nav.xhtml) if present for chapter titles
    final tocTitles = <String, String>{};
    for (final entry in manifestMap.entries) {
      final href = entry.value['href'] ?? '';
      if (href.endsWith('.ncx') || href.endsWith('nav.xhtml') || href.endsWith('nav.html')) {
        final decodedHref = Uri.decodeFull(href);
        File tocFile = File('$opfDir/$decodedHref');
        if (!await tocFile.exists()) {
          tocFile = File('${bookDir.path}/$decodedHref');
        }
        if (await tocFile.exists()) {
          try {
            final tocXml = XmlDocument.parse(await tocFile.readAsString());
            for (final navPoint in tocXml.findAllElements('navPoint')) {
              final label = navPoint.findAllElements('text').firstOrNull?.innerText.trim();
              final src = navPoint.findAllElements('content').firstOrNull?.getAttribute('src');
              if (label != null && src != null) {
                final cleanSrc = Uri.decodeFull(src.split('#').first);
                tocTitles[cleanSrc] = label;
              }
            }
          } catch (_) {}
        }
      }
    }

    final chapters = <Chapter>[];
    int chapterIndex = 1;

    for (final idref in spineItems) {
      final item = manifestMap[idref]!;
      final relHref = item['href']!;
      final decodedRelHref = Uri.decodeFull(relHref);
      File chFile = File('$opfDir/$decodedRelHref');
      if (!await chFile.exists()) {
        chFile = File('${bookDir.path}/$decodedRelHref');
      }
      if (!await chFile.exists()) continue;

      String chTitle = tocTitles[decodedRelHref] ?? tocTitles[relHref] ?? '';
      if (chTitle.isEmpty) {
        // Inspect file for <h1>, <h2> or <title>
        try {
          final content = await chFile.readAsString();
          final parsed = html_parser.parse(content);
          final heading = parsed.querySelector('h1, h2, h3, title')?.text.trim();
          if (heading != null && heading.isNotEmpty) {
            chTitle = heading;
          }
        } catch (_) {}
      }

      if (chTitle.isEmpty) {
        chTitle = 'Chapter $chapterIndex';
      }

      chapters.add(Chapter(
        id: '${novelId}_$chapterIndex',
        novelId: novelId,
        title: chTitle,
        url: chFile.uri.toString(),
        chapterNumber: chapterIndex.toDouble(),
      ));
      chapterIndex++;
    }

    // Tier 3: Monolith Chunking (if only 1 continuous chapter file was found with > 25 paragraphs)
    if (chapters.length == 1) {
      try {
        final monoFile = File(Uri.parse(chapters.first.url).toFilePath());
        if (await monoFile.exists()) {
          final content = await monoFile.readAsString();
          final parsed = html_parser.parse(content);
          final paragraphs = parsed.querySelectorAll('p, div.paragraph');

          if (paragraphs.length > 25) {
            final chunkedChapters = <Chapter>[];
            const paragraphsPerSection = 30;
            int sectionIndex = 1;

            for (int i = 0; i < paragraphs.length; i += paragraphsPerSection) {
              final end = (i + paragraphsPerSection < paragraphs.length)
                  ? i + paragraphsPerSection
                  : paragraphs.length;
              final sectionParas = paragraphs.sublist(i, end).map((p) => '<p>${p.innerHtml}</p>').join('\n');

              final sectionFileName = 'section_$sectionIndex.xhtml';
              final sectionFile = File('${bookDir.path}/$sectionFileName');
              await sectionFile.writeAsString(
                '<!DOCTYPE html><html><head><title>Section $sectionIndex</title></head><body>$sectionParas</body></html>',
              );

              chunkedChapters.add(Chapter(
                id: '${novelId}_$sectionIndex',
                novelId: novelId,
                title: 'Section $sectionIndex',
                url: sectionFile.uri.toString(),
                chapterNumber: sectionIndex.toDouble(),
              ));
              sectionIndex++;
            }

            if (chunkedChapters.length > 1) {
              chapters.clear();
              chapters.addAll(chunkedChapters);
            }
          }
        }
      } catch (_) {}
    }

    final effectiveTitle = (originalNovel != null && originalNovel.title.isNotEmpty)
        ? originalNovel.title
        : title;
    final effectiveAuthor = (originalNovel != null &&
            originalNovel.author.isNotEmpty &&
            originalNovel.author != 'Unknown Author')
        ? originalNovel.author
        : author;
    final effectiveCover = coverUrl.isNotEmpty
        ? coverUrl
        : (originalNovel?.coverUrl ?? '');
    final effectiveDesc = description.isNotEmpty
        ? description
        : (originalNovel?.description ?? '');
    final effectiveGenres = (originalNovel?.genres.isNotEmpty == true)
        ? originalNovel!.genres
        : const <String>[];

    final novel = Novel(
      id: novelId,
      sourceId: originalNovel?.sourceId ?? 'local_epub',
      title: effectiveTitle,
      author: effectiveAuthor,
      description: effectiveDesc,
      coverUrl: effectiveCover,
      genres: effectiveGenres,
      sourceUrl: bookDir.uri.toString(),
      inLibrary: true,
      status: 'COMPLETED',
      isFullBook: true,
      bookFormat: 'epub',
      bookSizeBytes: epubBytes.length,
      bookDownloadUrl: originalNovel?.bookDownloadUrl,
    );

    // Save metadata.json for high-speed instant re-reading
    final metaMap = {
      'novel': novel.toJson(),
      'chapters': chapters.map((c) => c.toJson()).toList(),
    };
    final metaFile = File('${bookDir.path}/metadata.json');
    await metaFile.writeAsString(jsonEncode(metaMap));

    return novel;
  }

  /// Imports a PDF file, parses its text streams and images into reflowable chapters,
  /// saves metadata and cover, and returns a fully initialized [Novel].
  Future<Novel> importPdf(File pdfFile, {Directory? targetDir, Novel? originalNovel, List<int>? bytes}) async {
    final pdfBytes = bytes ?? await pdfFile.readAsBytes();

    if (pdfBytes.length < 4 ||
        pdfBytes[0] != 0x25 ||
        pdfBytes[1] != 0x50 ||
        pdfBytes[2] != 0x44 ||
        pdfBytes[3] != 0x46) {
      throw const FormatException('Corrupt or invalid PDF document: missing %PDF signature header');
    }

    final digest = md5.convert(pdfBytes.sublist(0, pdfBytes.length > 8192 ? 8192 : pdfBytes.length)).toString().substring(0, 12);
    final novelId = (originalNovel != null && originalNovel.id.isNotEmpty)
        ? originalNovel.id
        : 'local_pdf_$digest';

    final baseDir = targetDir ?? await _getImportDirectory();
    final bookDir = Directory('${baseDir.path}/$novelId');
    if (!await bookDir.exists()) {
      await bookDir.create(recursive: true);
    }

    final chaptersDir = Directory('${bookDir.path}/chapters');
    if (!await chaptersDir.exists()) {
      await chaptersDir.create(recursive: true);
    }

    // Persist a copy of the original PDF document
    final docCopy = File('${bookDir.path}/document.pdf');
    if (!await docCopy.exists()) {
      await docCopy.writeAsBytes(pdfBytes);
    }

    // Extract text from PDF content streams
    final rawPages = PdfBookParser.extractPages(pdfBytes);
    final meaningfulPages = <String>[];
    for (final page in rawPages) {
      final filteredLines = page.split('\n').where((line) {
        final t = line.trim().toLowerCase();
        if (t.isEmpty) return false;
        if (t.contains('digitized by') ||
            t.contains('scanned by') ||
            t.contains('pprachin') ||
            t.contains('archive.org')) {
          return false;
        }
        return true;
      }).toList();
      final filteredText = filteredLines.join('\n').trim();
      if (filteredText.isNotEmpty) {
        meaningfulPages.add(filteredText);
      }
    }

    final totalTextChars = meaningfulPages.fold<int>(0, (sum, p) => sum + p.length);
    final hasSufficientText = (meaningfulPages.length >= 2 && totalTextChars > 200) || totalTextChars > 500;

    // Group extracted pages into reader chapters (5 pages per chapter)
    final chapters = <Chapter>[];
    String coverUrl = originalNovel?.coverUrl ?? '';
    List<String> renderedImagePaths = [];

    if (hasSufficientText) {
      const pagesPerChapter = 5;
      final totalChapters = (meaningfulPages.length / pagesPerChapter).ceil();
      for (int c = 0; c < totalChapters; c++) {
        final startPage = c * pagesPerChapter;
        final endPage = (startPage + pagesPerChapter > meaningfulPages.length) ? meaningfulPages.length : startPage + pagesPerChapter;
        final chapterPages = meaningfulPages.sublist(startPage, endPage);
        final chapterIndex = c + 1;
        final chapterTitle = 'Chapter $chapterIndex (Pages ${startPage + 1}-$endPage)';
        final chapterFile = File('${chaptersDir.path}/chapter_$chapterIndex.xhtml');

        final sb = StringBuffer();
        sb.writeln('<?xml version="1.0" encoding="utf-8"?>');
        sb.writeln('<!DOCTYPE html>');
        sb.writeln('<html xmlns="http://www.w3.org/1999/xhtml">');
        sb.writeln('<head><title>$chapterTitle</title></head>');
        sb.writeln('<body>');
        sb.writeln('<h2>$chapterTitle</h2>');
        for (final pText in chapterPages) {
          final paras = formatPdfTextToParagraphs(pText, bookTitle: originalNovel?.title);
          for (final para in paras) {
            sb.writeln('<p>${_escapeHtml(para)}</p>');
          }
          sb.writeln('<hr/>');
        }
        sb.writeln('</body></html>');
        await chapterFile.writeAsString(sb.toString());

        chapters.add(
          Chapter(
            id: '${novelId}_ch_$chapterIndex',
            novelId: novelId,
            title: chapterTitle,
            url: chapterFile.uri.toString(),
            chapterNumber: chapterIndex.toDouble(),
          ),
        );
      }
    } else {
      // Scanned document or image-based PDF: render high-resolution authentic original pages
      final pagesDir = Directory('${bookDir.path}/pages');

      try {
        renderedImagePaths = await PdfPageRenderer.renderPages(docCopy.path, pagesDir.path);
      } catch (e) {
        debugPrint('[EpubService] Native PdfPageRenderer failed: $e');
      }

      if (renderedImagePaths.isNotEmpty) {
        const pagesPerChapter = 5;
        final totalChapters = (renderedImagePaths.length / pagesPerChapter).ceil();
        for (int c = 0; c < totalChapters; c++) {
          final startIdx = c * pagesPerChapter;
          final endIdx = (startIdx + pagesPerChapter > renderedImagePaths.length) ? renderedImagePaths.length : startIdx + pagesPerChapter;
          final chapterIndex = c + 1;
          final chapterTitle = 'Chapter $chapterIndex (Pages ${startIdx + 1}-$endIdx)';
          final chapterFile = File('${chaptersDir.path}/chapter_$chapterIndex.xhtml');

          final sb = StringBuffer();
          sb.writeln('<?xml version="1.0" encoding="utf-8"?>');
          sb.writeln('<!DOCTYPE html>');
          sb.writeln('<html xmlns="http://www.w3.org/1999/xhtml">');
          sb.writeln('<head><title>$chapterTitle</title></head>');
          sb.writeln('<body>');
          sb.writeln('<h2>$chapterTitle</h2>');

          for (int imgIdx = startIdx; imgIdx < endIdx; imgIdx++) {
            final imgPath = renderedImagePaths[imgIdx];
            sb.writeln('<p>[IMAGE:file://$imgPath]</p>');
          }

          sb.writeln('</body></html>');
          await chapterFile.writeAsString(sb.toString());

          chapters.add(
            Chapter(
              id: '${novelId}_ch_$chapterIndex',
              novelId: novelId,
              title: chapterTitle,
              url: chapterFile.uri.toString(),
              chapterNumber: chapterIndex.toDouble(),
            ),
          );
        }

        if (coverUrl.isEmpty && renderedImagePaths.isNotEmpty) {
          final firstImg = File(renderedImagePaths.first);
          if (await firstImg.exists()) {
            final coverFile = File('${bookDir.path}/cover.jpg');
            try {
              await firstImg.copy(coverFile.path);
              coverUrl = coverFile.uri.toString();
            } catch (_) {
              coverUrl = firstImg.uri.toString();
            }
          }
        }
      } else {
        // Fallback: extract JPEG byte streams via PdfBookParser
          final imagePages = PdfBookParser.extractAllImages(pdfBytes);
          if (imagePages.isNotEmpty) {
            const pagesPerChapter = 5;
            final totalChapters = (imagePages.length / pagesPerChapter).ceil();
            for (int c = 0; c < totalChapters; c++) {
              final startIdx = c * pagesPerChapter;
              final endIdx = (startIdx + pagesPerChapter > imagePages.length) ? imagePages.length : startIdx + pagesPerChapter;
              final chapterIndex = c + 1;
              final chapterTitle = 'Chapter $chapterIndex (Pages ${startIdx + 1}-$endIdx)';
              final chapterFile = File('${chaptersDir.path}/chapter_$chapterIndex.xhtml');

              final sb = StringBuffer();
              sb.writeln('<?xml version="1.0" encoding="utf-8"?>');
              sb.writeln('<!DOCTYPE html>');
              sb.writeln('<html xmlns="http://www.w3.org/1999/xhtml">');
              sb.writeln('<head><title>$chapterTitle</title></head>');
              sb.writeln('<body>');
              sb.writeln('<h2>$chapterTitle</h2>');

              for (int imgIdx = startIdx; imgIdx < endIdx; imgIdx++) {
                final imgFile = File('${bookDir.path}/page_${imgIdx + 1}.jpg');
                if (!await imgFile.exists()) {
                  await imgFile.writeAsBytes(imagePages[imgIdx]);
                }
                sb.writeln('<p>[IMAGE:file://${imgFile.path}]</p>');
              }

              sb.writeln('</body></html>');
              await chapterFile.writeAsString(sb.toString());

              chapters.add(
                Chapter(
                  id: '${novelId}_ch_$chapterIndex',
                  novelId: novelId,
                  title: chapterTitle,
                  url: chapterFile.uri.toString(),
                  chapterNumber: chapterIndex.toDouble(),
                ),
              );
            }
          } else {
            // Fallback with authentic localized metadata
            final isOdia = (originalNovel?.genres.any((g) => g.toLowerCase() == 'odia' || g.toLowerCase() == 'or') == true) ||
                (originalNovel?.id.startsWith('or_') == true || originalNovel?.id.startsWith('odiabibhaba') == true);
            final isHindi = (originalNovel?.genres.any((g) => g.toLowerCase() == 'hindi' || g.toLowerCase() == 'hi') == true) ||
                (originalNovel?.id.startsWith('hindisamay') == true ||
                    originalNovel?.id.startsWith('gadyakosh') == true ||
                    originalNovel?.id.startsWith('kavitakosh') == true ||
                    originalNovel?.id.startsWith('epustakalay') == true);

            final title = isOdia ? 'ସମ୍ପୂର୍ଣ୍ଣ ଗ୍ରନ୍ଥ ବିବରଣୀ' : (isHindi ? 'सम्पूर्ण ग्रन्थ विवरण' : 'Document Overview');
            final chapterFile = File('${chaptersDir.path}/chapter_1.xhtml');
            final sb = StringBuffer();
            sb.writeln('<?xml version="1.0" encoding="utf-8"?>');
            sb.writeln('<!DOCTYPE html>');
            sb.writeln('<html xmlns="http://www.w3.org/1999/xhtml">');
            sb.writeln('<head><title>$title</title></head>');
            sb.writeln('<body>');
            sb.writeln('<h2>$title</h2>');
            if (originalNovel?.title != null) sb.writeln('<p>${_escapeHtml(originalNovel!.title)}</p>');
            if (originalNovel?.author != null) {
              sb.writeln('<p>${isOdia ? "ରଚୟିତା: " : (isHindi ? "लेखକ: " : "Author: ")}${_escapeHtml(originalNovel!.author)}</p>');
            }
            if (originalNovel?.description != null) sb.writeln('<p>${_escapeHtml(originalNovel!.description)}</p>');
            sb.writeln('</body></html>');
            await chapterFile.writeAsString(sb.toString());

            chapters.add(
              Chapter(
                id: '${novelId}_ch_1',
                novelId: novelId,
                title: title,
                url: chapterFile.uri.toString(),
                chapterNumber: 1.0,
              ),
            );
          }
        }
      }

    // Cover image extraction fallback
    if (coverUrl.isEmpty) {
      if (renderedImagePaths.isNotEmpty) {
        final firstPage = File(renderedImagePaths.first);
        if (await firstPage.exists()) {
          final coverFile = File('${bookDir.path}/cover.jpg');
          try {
            await firstPage.copy(coverFile.path);
            coverUrl = coverFile.uri.toString();
          } catch (_) {
            coverUrl = firstPage.uri.toString();
          }
        }
      } else {
        final imgBytes = PdfBookParser.extractFirstImage(pdfBytes);
        if (imgBytes != null && imgBytes.isNotEmpty) {
          final coverFile = File('${bookDir.path}/cover.jpg');
          await coverFile.writeAsBytes(imgBytes);
          coverUrl = coverFile.uri.toString();
        }
      }
    }

    var title = originalNovel?.title ?? '';
    if (title.isEmpty || title.toLowerCase() == 'unknown book' || title.toLowerCase() == 'untitled') {
      title = pdfFile.uri.pathSegments.last.replaceAll('.pdf', '');
    }
    var author = originalNovel?.author ?? 'Unknown Author';

    final novel = Novel(
      id: novelId,
      sourceId: originalNovel?.sourceId ?? 'local_epub',
      title: title,
      author: author,
      description: originalNovel?.description ?? 'Format: PDF',
      coverUrl: coverUrl,
      sourceUrl: bookDir.uri.toString(),
      inLibrary: true,
      status: 'COMPLETED',
      isFullBook: true,
      bookFormat: 'pdf',
      bookSizeBytes: pdfBytes.length,
      bookDownloadUrl: originalNovel?.bookDownloadUrl,
    );

    final metaMap = {
      'novel': novel.toJson(),
      'chapters': chapters.map((c) => c.toJson()).toList(),
    };
    final metaFile = File('${bookDir.path}/metadata.json');
    await metaFile.writeAsString(jsonEncode(metaMap));

    return novel;
  }

  static String _escapeHtml(String text) {
    return text
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  static String _filterWatermarks(String rawText) {
    final lines = rawText.split('\n');
    final validLines = <String>[];
    for (final l in lines) {
      final t = l.trim();
      final lower = t.toLowerCase();
      if (lower.isEmpty) continue;
      if (lower.contains('digitized by') ||
          lower.contains('scanned by') ||
          lower.contains('srujanika@') ||
          lower.contains('pprachin') ||
          lower.contains('archive.org') ||
          lower.contains('dli.ernet.in')) {
        continue;
      }
      validLines.add(t);
    }
    return validLines.join('\n');
  }

  static List<String> _groupOcrLinesToParagraphs(String text) {
    final lines = text.split('\n').map((l) => l.trim()).toList();
    final paragraphs = <String>[];
    final currentPara = StringBuffer();

    for (final line in lines) {
      if (line.isEmpty) {
        if (currentPara.isNotEmpty) {
          paragraphs.add(currentPara.toString().trim());
          currentPara.clear();
        }
        continue;
      }

      if (line.startsWith('Digitized by') || line.length < 2) {
        continue;
      }

      if (currentPara.isNotEmpty) {
        currentPara.write(' ');
      }
      currentPara.write(line);

      if (line.endsWith('।') || line.endsWith('.') || line.endsWith('?') || line.endsWith('!')) {
        if (currentPara.length > 80) {
          paragraphs.add(currentPara.toString().trim());
          currentPara.clear();
        }
      }
    }

    if (currentPara.isNotEmpty) {
      paragraphs.add(currentPara.toString().trim());
    }

    return paragraphs.where((p) => p.length >= 3).toList();
  }

  /// Converts an image-based chapter XHTML to real text using on-device OCR (Tesseract / ML Kit).
  static Future<bool> ocrChapterFile(File chapterFile, {String? defaultScript}) async {
    try {
      if (!await chapterFile.exists()) return false;
      final rawHtml = await chapterFile.readAsString();
      final doc = html_parser.parse(rawHtml);
      final pElements = doc.querySelectorAll('p');

      final imagePaths = <String>[];
      for (final p in pElements) {
        final text = p.text.trim();
        if (text.startsWith('[IMAGE:file://') || text.startsWith('[IMAGE:')) {
          final uriStr = text.startsWith('[IMAGE:file://')
              ? text.substring(7, text.endsWith(']') ? text.length - 1 : text.length)
              : text.substring(7, text.endsWith(']') ? text.length - 1 : text.length);
          try {
            final path = Uri.parse(uriStr).toFilePath();
            if (File(path).existsSync()) {
              imagePaths.add(path);
            }
          } catch (_) {
            final path = uriStr.replaceFirst('file://', '');
            if (File(path).existsSync()) {
              imagePaths.add(path);
            }
          }
        }
      }

      if (imagePaths.isEmpty) return false;

      String script = defaultScript ?? 'latin';
      if (defaultScript == null) {
        final lowerPath = chapterFile.path.toLowerCase();
        if (lowerPath.contains('odiabibhaba') || lowerPath.contains('odia') || lowerPath.contains('or_')) {
          script = 'ori';
        } else if (lowerPath.contains('hindi') || lowerPath.contains('epustakalay') || lowerPath.contains('hindisamay')) {
          script = 'devanagari';
        }
      }

      String? tessDataDir;
      if (script.startsWith('ori')) {
        tessDataDir = await PdfPageRenderer.ensureTessData('ori');
        await PdfPageRenderer.ensureTessData('eng');
        script = 'ori+eng';
      }

      final ocrResults = await PdfPageRenderer.extractTextFromImages(
        imagePaths,
        script: script,
        tessDataDir: tessDataDir,
      );

      final hasValidText = ocrResults.any((r) => (r['text'] ?? '').trim().length > 40);
      if (!hasValidText) return false;

      final title = doc.querySelector('title')?.text ?? doc.querySelector('h2')?.text ?? 'Chapter';
      final sb = StringBuffer();
      sb.writeln('<?xml version="1.0" encoding="utf-8"?>');
      sb.writeln('<!DOCTYPE html>');
      sb.writeln('<html xmlns="http://www.w3.org/1999/xhtml">');
      sb.writeln('<head><title>$title</title></head>');
      sb.writeln('<body>');
      sb.writeln('<h2>$title</h2>');

      for (int i = 0; i < ocrResults.length; i++) {
        final res = ocrResults[i];
        final rawText = res['text'] ?? '';
        final imgPath = res['imagePath'] ?? '';
        final cleanText = _filterWatermarks(rawText);

        final paragraphs = _groupOcrLinesToParagraphs(cleanText);
        if (paragraphs.isNotEmpty) {
          for (final p in paragraphs) {
            sb.writeln('<p>${_escapeHtml(p)}</p>');
          }
        } else if (imgPath.isNotEmpty && File(imgPath).existsSync()) {
          sb.writeln('<p>[IMAGE:file://$imgPath]</p>');
        }
        sb.writeln('<hr/>');
      }

      sb.writeln('</body></html>');
      await chapterFile.writeAsString(sb.toString());
      return true;
    } catch (e) {
      debugPrint('[EpubService] ocrChapterFile error: $e');
      return false;
    }
  }

  /// Progressively extracts text for all chapters of a book in the background.
  static void extractBookTextInBackground(Directory bookDir, {String script = 'ori'}) {
    Future.microtask(() async {
      try {
        final chaptersDir = Directory('${bookDir.path}/chapters');
        if (!await chaptersDir.exists()) return;
        final files = chaptersDir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.xhtml'))
            .toList();

        files.sort((a, b) => a.path.compareTo(b.path));

        for (final chapterFile in files) {
          final content = await chapterFile.readAsString();
          if (content.contains('[IMAGE:file://')) {
            await ocrChapterFile(chapterFile, defaultScript: script);
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
      } catch (e) {
        debugPrint('[EpubService] extractBookTextInBackground error: $e');
      }
    });
  }

  /// Reads and parses an XHTML chapter file into cleaned paragraphs.
  Future<ChapterContent> loadChapterContent(String fileUriStr) async {
    final String filePath;
    if (fileUriStr.startsWith('file:')) {
      filePath = Uri.parse(fileUriStr).toFilePath();
    } else {
      filePath = fileUriStr;
    }
    final file = File(filePath);

    if (!await file.exists()) {
      // Auto-heal missing chapter: unpack document.pdf if present
      final bookDir = file.parent.parent;
      final docPdf = File('${bookDir.path}/document.pdf');
      if (await docPdf.exists()) {
        try {
          await importPdf(docPdf, targetDir: bookDir.parent);
        } catch (_) {}
      }
      if (!await file.exists()) {
        throw Exception('Chapter file not found at $filePath');
      }
    }

    final rawHtml = await file.readAsString();
    final doc = html_parser.parse(rawHtml);

    // Remove unwanted non-narrative tags
    doc.querySelectorAll('script, style, link, meta').forEach((el) => el.remove());

    // Extract any embedded images (cover pages, scene illustrations)
    final imageElements = doc.querySelectorAll('img, svg image, image');
    final validImageTokens = <String>[];
    for (final img in imageElements) {
      final src = img.attributes['src'] ??
          img.attributes['xlink:href'] ??
          img.attributes['href'] ??
          '';
      if (src.trim().isNotEmpty) {
        final decoded = Uri.decodeFull(src.trim());
        final resolvedPath = p.normalize(p.join(file.parent.path, decoded));
        if (File(resolvedPath).existsSync()) {
          validImageTokens.add('[IMAGE:file://$resolvedPath]');
        }
      }
    }

    final rawParas = <String>[];
    final pElements = doc.querySelectorAll('p');

    if (pElements.isNotEmpty) {
      for (final p in pElements) {
        final text = p.text.trim();
        if (text.isNotEmpty) {
          rawParas.add(text);
        }
      }
    } else {
      // Fallback: look at headings, divs, blockquotes, or body text
      final bodyEl = doc.body;
      if (bodyEl != null) {
        for (final div in bodyEl.querySelectorAll('div, blockquote, li, h1, h2, h3, h4, h5, h6')) {
          final text = div.text.trim();
          if (text.length > 20) {
            rawParas.add(text);
          }
        }
        if (rawParas.isEmpty && bodyEl.text.trim().isNotEmpty) {
          rawParas.add(bodyEl.text.trim());
        }
      }
    }

    // Include resolved illustrations if present
    if (validImageTokens.isNotEmpty) {
      if (rawParas.isEmpty) {
        rawParas.addAll(validImageTokens);
      } else {
        rawParas.insertAll(0, validImageTokens);
      }
    }

    // Safety fallback: ensure section is never empty so reader view never crashes
    if (rawParas.isEmpty) {
      rawParas.add('This section contains no text content.');
    }

    final paragraphs = TextCleaner.cleanParagraphs(rawParas);
    final finalParagraphs = paragraphs.isNotEmpty ? paragraphs : rawParas;
    final rawText = TextCleaner.toCleanRawText(finalParagraphs);
    final title = doc.querySelector('h1, h2, title')?.text.trim() ?? 'Chapter';

    return ChapterContent(
      chapterId: filePath,
      novelId: 'local_epub',
      title: title,
      rawText: rawText.isNotEmpty ? rawText : 'Section',
      paragraphs: finalParagraphs,
    );
  }

  /// Returns the first narrative chapter, skipping non-narrative front-matter
  /// such as cover images, title pages, wrappers, or jacket pages.
  static Chapter getFirstNarrativeChapter(List<Chapter> chapters) {
    if (chapters.isEmpty) {
      throw StateError('Cannot get first narrative chapter from empty chapters list');
    }
    for (final ch in chapters) {
      final t = ch.title.toLowerCase();
      final u = ch.url.toLowerCase();
      final isFrontMatter = t.contains('cover') ||
          t.contains('title page') ||
          t.contains('titlepage') ||
          t.contains('jacket') ||
          u.contains('wrap0000') ||
          u.contains('cover.x') ||
          u.contains('cover.h') ||
          u.contains('titlepage');
      if (!isFrontMatter) {
        return ch;
      }
    }
    return chapters.first;
  }

  /// Returns all previously imported EPUB novels stored locally.
  Future<List<Novel>> getImportedNovels({Directory? targetDir}) async {
    final baseDir = targetDir ?? await _getImportDirectory();
    final novels = <Novel>[];
    if (await baseDir.exists()) {
      await for (final entity in baseDir.list()) {
        if (entity is Directory) {
          final metaFile = File('${entity.path}/metadata.json');
          if (await metaFile.exists()) {
            try {
              final json = jsonDecode(await metaFile.readAsString()) as Map<String, dynamic>;
              final novelJson = json['novel'] as Map<String, dynamic>;
              novels.add(Novel.fromJson(novelJson));
            } catch (_) {}
          }
        }
      }
    }

    // Auto-discover and import any EPUBs in the device Downloads directory if none imported yet
    if (novels.isEmpty && targetDir == null) {
      final downloadedEpubs = await findDeviceEpubs();
      for (final epub in downloadedEpubs) {
        try {
          final imported = await importEpub(epub);
          novels.add(imported);
        } catch (_) {}
      }

      // If still empty, seed the bundled classic sample so the user never sees an empty library
      if (novels.isEmpty) {
        await seedDefaultEpubIfNeeded();
        return getImportedNovels(targetDir: targetDir);
      }
    }

    // Sort descending by ID so newest appears first
    novels.sort((a, b) => b.id.compareTo(a.id));
    return novels;
  }

  /// Seeds the bundled sample classic EPUB on first launch
  Future<void> seedDefaultEpubIfNeeded({Directory? targetDir}) async {
    try {
      final byteData = await rootBundle.load('assets/epubs/sample_classic.epub');
      final baseDir = targetDir ?? await _getImportDirectory();
      final tempFile = File('${baseDir.path}/temp_sample.epub');
      await tempFile.writeAsBytes(byteData.buffer.asUint8List(byteData.offsetInBytes, byteData.lengthInBytes));
      await importEpub(tempFile, targetDir: targetDir);
      if (await tempFile.exists()) {
        await tempFile.delete();
      }
    } catch (_) {}
  }

  /// Downloads an EPUB from a remote URL, unpacks it into app storage,
  /// and returns a fully initialized [Novel]. Supports both GET and POST downloads.
  Future<Novel> importEpubFromUrl(
    String url, {
    String method = 'GET',
    String? body,
    Map<String, String>? headers,
    void Function(double progress, String stage)? onProgress,
    Novel? originalNovel,
  }) async {
    if (kIsWeb) {
      throw 'EPUB URL import is not supported in browser environment';
    }
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    client.autoUncompress = true;
    File? tempFile;
    File? tempTmpFile;
    try {
      onProgress?.call(0.05, 'Connecting');

      Uri currentUri = Uri.parse(url);
      HttpClientResponse? response;

      // Handle redirects manually to preserve and forward User-Agent, Referer, and Cookies
      for (int redirect = 0; redirect < 10; redirect++) {
        final HttpClientRequest request;
        if (redirect == 0 && method.toUpperCase() == 'POST') {
          request = await client.postUrl(currentUri);
          if (body != null && body.isNotEmpty) {
            final bodyBytes = utf8.encode(body);
            request.headers.set(HttpHeaders.contentTypeHeader, 'application/x-www-form-urlencoded');
            request.headers.set(HttpHeaders.contentLengthHeader, bodyBytes.length.toString());
            request.add(bodyBytes);
          }
        } else {
          request = await client.getUrl(currentUri);
        }
        request.followRedirects = false;

        // Apply caller headers (except cookie/referer which we manage dynamically)
        if (headers != null) {
          headers.forEach((key, value) {
            final lower = key.toLowerCase();
            if (lower != 'cookie' && lower != 'referer') {
              request.headers.set(key, value);
            }
          });
        }

        // Forward User-Agent matching active WebView session
        if (request.headers.value(HttpHeaders.userAgentHeader) == null) {
          request.headers.set(HttpHeaders.userAgentHeader, WebViewSessionManager.defaultUserAgent);
        }

        // Maintain Referer across redirects: forward original referer so CDN recognizes source site
        String? referer = headers?['Referer'];
        if (referer == null || referer.isEmpty) {
          if (originalNovel != null && originalNovel.sourceUrl.isNotEmpty) {
            referer = originalNovel.sourceUrl;
          } else {
            referer = '${currentUri.scheme}://${currentUri.host}/';
          }
        }
        request.headers.set(HttpHeaders.refererHeader, referer);

        final origin = '${currentUri.scheme}://${currentUri.host}';
        request.headers.set('Origin', origin);
        request.headers.set('Sec-Fetch-Dest', 'document');
        request.headers.set('Sec-Fetch-Mode', 'navigate');
        request.headers.set('Sec-Fetch-Site', 'same-origin');
        request.headers.set('Sec-Fetch-User', '?1');
        request.headers.set('Upgrade-Insecure-Requests', '1');

        // Resolve cookie from currentUri, falling back to original source domain
        String? cookie = WebViewSessionManager.instance.getCookieHeader(currentUri.toString());
        if (cookie == null || cookie.isEmpty) {
          if (originalNovel != null && originalNovel.sourceUrl.isNotEmpty) {
            cookie = WebViewSessionManager.instance.getCookieHeader(originalNovel.sourceUrl);
          }
        }
        if (cookie == null || cookie.isEmpty) {
          cookie = headers?['Cookie'];
        }
        if (cookie != null && cookie.isNotEmpty) {
          request.headers.set(HttpHeaders.cookieHeader, cookie);
        }

        response = await request.close();

        if (response.isRedirect) {
          final location = response.headers.value(HttpHeaders.locationHeader);
          if (location == null || location.isEmpty) {
            throw HttpException('Redirect with no Location header from $currentUri');
          }
          currentUri = currentUri.resolve(location);
          await response.drain();
          continue;
        }

        break;
      }

      if (response == null || response.statusCode != 200) {
        final code = response?.statusCode ?? 500;
        if (code == 522 || code == 502 || code == 504) {
          throw HttpException(
            'The storage mirror server (${currentUri.host}) is temporarily unreachable (HTTP $code). '
            'Please choose another edition of this book or try again in a few moments.',
          );
        }
        throw HttpException('Failed to download EPUB: HTTP $code');
      }

      final contentLength = response.contentLength;
      final baseDir = await _getImportDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      tempTmpFile = File('${baseDir.path}/temp_dl_$timestamp.tmp');
      final sink = tempTmpFile.openWrite();

      int downloaded = 0;
      onProgress?.call(0.1, 'Downloading');

      await for (final chunk in response) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0 && onProgress != null) {
          final p = (downloaded / contentLength).clamp(0.0, 1.0);
          onProgress(p * 0.85 + 0.1, 'Downloading');
        }
      }
      await sink.flush();
      await sink.close();

      onProgress?.call(0.95, 'Verifying');
      // Validate magic bytes
      final headerBytes = await tempTmpFile.openRead(0, 4).first;
      final isPdf = headerBytes.length >= 4 &&
          headerBytes[0] == 0x25 &&
          headerBytes[1] == 0x50 &&
          headerBytes[2] == 0x44 &&
          headerBytes[3] == 0x46;
      final isZip = headerBytes.length >= 4 &&
          headerBytes[0] == 0x50 &&
          headerBytes[1] == 0x4B &&
          headerBytes[2] == 0x03 &&
          headerBytes[3] == 0x04;

      if (!isPdf && !isZip) {
        try {
          final previewBytes = await tempTmpFile.openRead(0, 4096).first;
          final previewStr = String.fromCharCodes(previewBytes);

          // Check if server returned a meta-refresh redirection page (e.g. Standard Ebooks landing page)
          final metaRefresh = RegExp(r'<meta[^>]+http-equiv=["\x27]?refresh["\x27]?[^>]+url=([^"\x27\s>]+)', caseSensitive: false).firstMatch(previewStr);
          if (metaRefresh != null) {
            var refreshTarget = metaRefresh.group(1)!.trim();
            if (refreshTarget.startsWith('/')) {
              final u = Uri.parse(url);
              refreshTarget = '${u.scheme}://${u.host}$refreshTarget';
            }
            if (refreshTarget != url) {
              await tempTmpFile.delete();
              return importEpubFromUrl(
                refreshTarget,
                headers: headers,
                originalNovel: originalNovel,
                onProgress: onProgress,
              );
            }
          }

          final previewLower = previewStr.toLowerCase();
          if (previewLower.contains('<!doctype') || previewLower.contains('<html') || previewLower.contains('just a moment')) {
            throw const FormatException(
              'The source returned an HTML verification or protection page instead of a book file. '
              'Please open in the In-App Browser to solve the challenge or verify session.',
            );
          }
        } catch (e) {
          if (e is FormatException) rethrow;
        }
        throw const FormatException('Downloaded file is not a valid book archive (corrupted or blocked download).');
      }

      final ext = isPdf ? 'pdf' : 'epub';
      tempFile = File('${baseDir.path}/temp_dl_$timestamp.$ext');
      await tempTmpFile.rename(tempFile.path);
      tempTmpFile = null;

      onProgress?.call(0.98, 'Extracting');
      final novel = await importBook(tempFile, originalNovel: originalNovel);
      onProgress?.call(1.0, 'Completed');
      return novel;
    } finally {
      client.close();
      try {
        if (tempTmpFile != null && await tempTmpFile.exists()) {
          await tempTmpFile.delete();
        }
        if (tempFile != null && await tempFile.exists()) {
          await tempFile.delete();
        }
      } catch (_) {}
    }
  }

  /// Scans common download folders on the device for .epub files
  Future<List<File>> findDeviceEpubs() async {
    final epubs = <File>[];
    final candidateDirs = [
      Directory('/sdcard/Download'),
      Directory('/storage/emulated/0/Download'),
    ];
    for (final dir in candidateDirs) {
      if (await dir.exists()) {
        try {
          await for (final entity in dir.list()) {
            if (entity is File && entity.path.toLowerCase().endsWith('.epub')) {
              epubs.add(entity);
            }
          }
        } catch (_) {}
      }
    }
    return epubs;
  }

  static bool _isHeading(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 80) return false;
    final lower = trimmed.toLowerCase();

    // Explicit heading words in English, Odia, Hindi
    if (RegExp(
      r'^(?:chapter|part|act|scene|section|book|canto|volume|prologue|epilogue|ଅଧ୍ୟାୟ|ପ୍ରକରଣ|ପ୍ରସ୍ତର|ଭାଗ|ପର୍ବ|କାଣ୍ଡ|ଅଧ୍ଯାୟ|ସୂଚୀପତ୍ର|ସୂଚନା|ଭୂମିକା|ମୁଖବନ୍ଧ|ପ୍ରଥମ|ଦ୍ୱିତୀୟ|ତୃତୀୟ|ଚତୁର୍ଥ|ପଞ୍ଚମ|ଷଷ୍ଠ|ସପ୍ତମ|ଅଷ୍ଟମ|ନବମ|ଦଶମ|अध्याय|भाग|खण्ड|सर्ग)\b',
      caseSensitive: false,
    ).hasMatch(lower)) {
      return true;
    }

    // Roman or numeric chapters: "Chapter 1", "IV.", "II - Title"
    if (RegExp(r'^(?:[IVXLCDMivxlcdm]+|\d+)[\.\:\-\s]+[A-Za-z\u0B00-\u0B7F\u0900-\u097F]').hasMatch(trimmed) && trimmed.length < 50) {
      return true;
    }

    return false;
  }

  /// Formats raw extracted PDF text into clean, reflowable, readable paragraphs.
  /// Removes running headers, page numbers (in English and Odia digits), and digitizer watermarks.
  /// Recombines hyphenated word breaks across lines and joins wrapped lines into cohesive paragraphs.
  static List<String> formatPdfTextToParagraphs(String rawText, {String? bookTitle}) {
    if (rawText.trim().isEmpty) return [];

    final rawLines = rawText.split(RegExp(r'\r?\n'));
    final filteredLines = <({String text, bool isIndented})>[];

    final titleLower = bookTitle?.trim().toLowerCase();

    for (final rawLine in rawLines) {
      var line = rawLine.trim();
      if (line.isEmpty) {
        filteredLines.add((text: '', isIndented: false));
        continue;
      }

      final lower = line.toLowerCase();

      // 1. Filter digitizer watermarks & scanner artifacts
      if (lower.contains('odiabibhaba.in') ||
          lower.contains('odia bibhaba') ||
          lower.contains('digitized by') ||
          lower.contains('scanned by') ||
          lower.contains('archive.org') ||
          lower.contains('dli.ernet.in') ||
          lower.contains('epustakalay.com') ||
          lower.contains('universal digital library')) {
        continue;
      }

      // 2. Filter standalone page numbers (English digits and Odia digits ୦-୯)
      if (RegExp(r'^(?:page\s*)?[-–—\[\(]?\s*\d+\s*[-–—\]\)]?$', caseSensitive: false).hasMatch(lower) ||
          RegExp(r'^(?:ପୃଷ୍ଠା\s*[:\-]?)?\s*[-–—\[\(]?\s*[୦-୯\d]+\s*[-–—\]\)]?$', caseSensitive: false).hasMatch(line)) {
        continue;
      }

      // 3. Filter repeated book title header
      if (titleLower != null && titleLower.isNotEmpty && lower == titleLower) {
        continue;
      }

      line = line.replaceAll(RegExp(r'[ \t]+'), ' ');
      final isIndented = rawLine.startsWith('   ') || rawLine.startsWith('\t');
      filteredLines.add((text: line, isIndented: isIndented));
    }

    final paragraphs = <String>[];
    final currentPara = StringBuffer();

    for (int i = 0; i < filteredLines.length; i++) {
      final item = filteredLines[i];
      final line = item.text;

      if (line.isEmpty) {
        if (currentPara.isNotEmpty) {
          paragraphs.add(currentPara.toString().trim());
          currentPara.clear();
        }
        continue;
      }

      if (currentPara.isEmpty) {
        currentPara.write(line);
      } else {
        final currentStr = currentPara.toString().trim();
        final currentIsHeading = _isHeading(currentStr);
        final lineIsHeading = _isHeading(line);
        final isBullet = RegExp(r'^(?:[•\-\*]|\d+[\.\)])\s+').hasMatch(line);

        final lastChar = currentStr.isNotEmpty ? currentStr.substring(currentStr.length - 1) : '';
        final isSentenceEnd = lastChar == '.' ||
            lastChar == '!' ||
            lastChar == '?' ||
            lastChar == '।' || // Odia/Hindi Purna Viram
            lastChar == '॥' ||
            lastChar == '"' ||
            lastChar == '”' ||
            lastChar == "'";

        // Break into new paragraph if previous was heading, current is heading/bullet, or current is indented after sentence end
        if (currentIsHeading || lineIsHeading || isBullet || (isSentenceEnd && item.isIndented)) {
          paragraphs.add(currentStr);
          currentPara.clear();
          currentPara.write(line);
          continue;
        }

        // Hyphenation: join broken words across lines (e.g. extraor-\ndinary -> extraordinary)
        if (currentStr.endsWith('-') || currentStr.endsWith('—') || currentStr.endsWith('\u00AD')) {
          final stripped = currentStr.substring(0, currentStr.length - 1);
          currentPara.clear();
          currentPara.write(stripped);
          currentPara.write(line);
        } else {
          currentPara.write(' ');
          currentPara.write(line);
        }
      }
    }

    if (currentPara.isNotEmpty) {
      paragraphs.add(currentPara.toString().trim());
    }

    return paragraphs.where((p) => p.trim().isNotEmpty).toList();
  }

  Future<Directory> _getImportDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDocDir.path}/imported_novels');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    // Clean up any stray temporary files left over from prior aborted downloads
    try {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final name = entity.uri.pathSegments.last;
          if (name.startsWith('temp_dl_') || name.endsWith('.tmp')) {
            await entity.delete();
          }
        }
      }
    } catch (_) {}
    return dir;
  }
}

/// Lightweight, pure-Dart PDF text stream parser and cover image extractor
class PdfBookParser {
  static List<String> extractPages(List<int> bytes) {
    final pages = <String>[];
    int searchIdx = 0;
    final streamMarker = [115, 116, 114, 101, 97, 109]; // 'stream'
    final endStreamMarker = [101, 110, 100, 115, 116, 114, 101, 97, 109]; // 'endstream'

    while (searchIdx < bytes.length) {
      final streamPos = _indexOf(bytes, streamMarker, searchIdx);
      if (streamPos == -1) break;

      int lookBackStart = streamPos > 250 ? streamPos - 250 : 0;
      final headerStr = String.fromCharCodes(bytes.sublist(lookBackStart, streamPos));
      final isFlate = headerStr.contains('/FlateDecode');
      final isImage = headerStr.contains('/Image') || headerStr.contains('/DCTDecode');

      int dataStart = streamPos + streamMarker.length;
      if (dataStart < bytes.length && bytes[dataStart] == 13) dataStart++;
      if (dataStart < bytes.length && bytes[dataStart] == 10) dataStart++;

      final endPos = _indexOf(bytes, endStreamMarker, dataStart);
      if (endPos == -1) break;

      int dataEnd = endPos;
      if (dataEnd > dataStart && bytes[dataEnd - 1] == 10) dataEnd--;
      if (dataEnd > dataStart && bytes[dataEnd - 1] == 13) dataEnd--;

      final streamData = bytes.sublist(dataStart, dataEnd);
      searchIdx = endPos + endStreamMarker.length;

      if (isImage) continue;

      List<int>? decompressed;
      if (isFlate) {
        try {
          decompressed = zlib.decode(streamData);
        } catch (_) {}
      } else {
        decompressed = streamData;
      }

      if (decompressed != null && decompressed.isNotEmpty) {
        final text = _extractTextFromDecompressed(decompressed);
        if (text.trim().isNotEmpty) {
          pages.add(text.trim());
        }
      }
    }
    return pages;
  }

  static List<int>? extractFirstImage(List<int> bytes) {
    int searchIdx = 0;
    final streamMarker = [115, 116, 114, 101, 97, 109];
    final endStreamMarker = [101, 110, 100, 115, 116, 114, 101, 97, 109];

    while (searchIdx < bytes.length) {
      final streamPos = _indexOf(bytes, streamMarker, searchIdx);
      if (streamPos == -1) break;

      int lookBackStart = streamPos > 300 ? streamPos - 300 : 0;
      final headerStr = String.fromCharCodes(bytes.sublist(lookBackStart, streamPos));
      final isJpeg = headerStr.contains('/DCTDecode') || (headerStr.contains('/Subtype') && headerStr.contains('/Image'));

      int dataStart = streamPos + streamMarker.length;
      if (dataStart < bytes.length && bytes[dataStart] == 13) dataStart++;
      if (dataStart < bytes.length && bytes[dataStart] == 10) dataStart++;

      final endPos = _indexOf(bytes, endStreamMarker, dataStart);
      if (endPos == -1) break;

      int dataEnd = endPos;
      if (dataEnd > dataStart && bytes[dataEnd - 1] == 10) dataEnd--;
      if (dataEnd > dataStart && bytes[dataEnd - 1] == 13) dataEnd--;

      final streamData = bytes.sublist(dataStart, dataEnd);
      searchIdx = endPos + endStreamMarker.length;

      if (isJpeg && streamData.length > 5000) {
        if (streamData.length > 3 && streamData[0] == 0xFF && streamData[1] == 0xD8 && streamData[2] == 0xFF) {
          return streamData;
        }
      }
    }
    return null;
  }

  static List<List<int>> extractAllImages(List<int> bytes, {int maxImages = 500}) {
    final images = <List<int>>[];
    int searchIdx = 0;
    final streamMarker = [115, 116, 114, 101, 97, 109];
    final endStreamMarker = [101, 110, 100, 115, 116, 114, 101, 97, 109];

    while (searchIdx < bytes.length && images.length < maxImages) {
      final streamPos = _indexOf(bytes, streamMarker, searchIdx);
      if (streamPos == -1) break;

      int lookBackStart = streamPos > 300 ? streamPos - 300 : 0;
      final headerStr = String.fromCharCodes(bytes.sublist(lookBackStart, streamPos));
      final isJpeg = headerStr.contains('/DCTDecode') ||
          (headerStr.contains('/Subtype') && headerStr.contains('/Image'));
      final isJpx = headerStr.contains('/JPXDecode');

      int dataStart = streamPos + streamMarker.length;
      if (dataStart < bytes.length && bytes[dataStart] == 13) dataStart++;
      if (dataStart < bytes.length && bytes[dataStart] == 10) dataStart++;

      final endPos = _indexOf(bytes, endStreamMarker, dataStart);
      if (endPos == -1) break;

      int dataEnd = endPos;
      if (dataEnd > dataStart && bytes[dataEnd - 1] == 10) dataEnd--;
      if (dataEnd > dataStart && bytes[dataEnd - 1] == 13) dataEnd--;

      final streamData = bytes.sublist(dataStart, dataEnd);
      searchIdx = endPos + endStreamMarker.length;

      if ((isJpeg || isJpx) && streamData.length > 5000) {
        if (streamData.length > 3 &&
            streamData[0] == 0xFF &&
            streamData[1] == 0xD8 &&
            streamData[2] == 0xFF) {
          images.add(streamData);
        } else if (isJpx &&
            streamData.length > 8 &&
            streamData[0] == 0x00 &&
            streamData[1] == 0x00 &&
            streamData[2] == 0x00 &&
            streamData[3] == 0x0C) {
          images.add(streamData);
        }
      }
    }
    return images;
  }

  static String _extractTextFromDecompressed(List<int> decompressed) {
    final streamStr = latin1.decode(decompressed);
    final sb = StringBuffer();

    // 1. Tj operators: (text) Tj and <hex> Tj
    final tjStrRegex = RegExp(r'\(([\s\S]*?)\)\s*Tj');
    for (final m in tjStrRegex.allMatches(streamStr)) {
      sb.writeln(_decodePdfString(m.group(1) ?? ''));
    }
    final hexTjRegex = RegExp(r'<([0-9a-fA-F\s]+)>\s*Tj');
    for (final m in hexTjRegex.allMatches(streamStr)) {
      sb.writeln(_decodeHexPdfString(m.group(1) ?? ''));
    }

    // 2. Next-line operators ' and ": (text) ' or <hex> '
    final nextLineStrRegex = RegExp(r'\(([\s\S]*?)\)\s*[\x27\x22]');
    for (final m in nextLineStrRegex.allMatches(streamStr)) {
      sb.writeln(_decodePdfString(m.group(1) ?? ''));
    }
    final nextLineHexRegex = RegExp(r'<([0-9a-fA-F\s]+)>\s*[\x27\x22]');
    for (final m in nextLineHexRegex.allMatches(streamStr)) {
      sb.writeln(_decodeHexPdfString(m.group(1) ?? ''));
    }

    // 3. TJ array: [(text) -100 <hex> 50] TJ
    final tjArrayRegex = RegExp(r'\[([\s\S]*?)\]\s*TJ');
    for (final m in tjArrayRegex.allMatches(streamStr)) {
      final inner = m.group(1) ?? '';
      final tokenRegex = RegExp(r'\(([\s\S]*?)\)|<([0-9a-fA-F\s]+)>');
      final lineBuf = StringBuffer();
      for (final tm in tokenRegex.allMatches(inner)) {
        if (tm.group(1) != null) {
          lineBuf.write(_decodePdfString(tm.group(1)!));
        } else if (tm.group(2) != null) {
          lineBuf.write(_decodeHexPdfString(tm.group(2)!));
        }
      }
      if (lineBuf.isNotEmpty) {
        sb.writeln(lineBuf.toString());
      }
    }

    return sb.toString();
  }

  static String _decodeBytesToText(List<int> bytes) {
    if (bytes.isEmpty) return '';

    // 1. Check for UTF-16BE BOM: FE FF
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final codeUnits = <int>[];
      for (int i = 2; i + 1 < bytes.length; i += 2) {
        codeUnits.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return String.fromCharCodes(codeUnits);
    }

    // 2. Check for UTF-16LE BOM: FF FE
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      final codeUnits = <int>[];
      for (int i = 2; i + 1 < bytes.length; i += 2) {
        codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return String.fromCharCodes(codeUnits);
    }

    // 3. Check for raw UTF-16BE without BOM (common in PDF strings where high byte is 0x00 for ASCII or 0x0B for Odia or 0x09 for Devanagari)
    if (bytes.length >= 4 && bytes.length % 2 == 0) {
      int highCount = 0;
      final pairCount = bytes.length ~/ 2;
      for (int i = 0; i < bytes.length; i += 2) {
        final high = bytes[i];
        if (high == 0x00 || high == 0x0B || high == 0x09 || high == 0x20) {
          highCount++;
        }
      }
      if (highCount >= (pairCount * 0.75).round()) {
        final codeUnits = <int>[];
        for (int i = 0; i + 1 < bytes.length; i += 2) {
          codeUnits.add((bytes[i] << 8) | bytes[i + 1]);
        }
        return String.fromCharCodes(codeUnits);
      }
    }

    // 4. Try UTF-8 decode
    try {
      return utf8.decode(bytes);
    } catch (_) {}

    // 5. Fallback to Latin-1
    return latin1.decode(bytes);
  }

  static String _decodePdfString(String raw) {
    var s = raw
        .replaceAll(r'\(', '(')
        .replaceAll(r'\)', ')')
        .replaceAll(r'\\', r'\')
        .replaceAll(r'\n', '\n')
        .replaceAll(r'\r', '\r')
        .replaceAll(r'\t', '\t');

    // Octal character escapes: \ddd
    s = s.replaceAllMapped(RegExp(r'\\([0-7]{1,3})'), (m) {
      final octalStr = m.group(1)!;
      final code = int.parse(octalStr, radix: 8);
      return String.fromCharCode(code);
    });

    // Check if literal string starts with UTF-16BE BOM (\u00FE\u00FF)
    if (s.length >= 2 && s.codeUnitAt(0) == 0xFE && s.codeUnitAt(1) == 0xFF) {
      final codeUnits = <int>[];
      for (int i = 2; i + 1 < s.length; i += 2) {
        codeUnits.add((s.codeUnitAt(i) << 8) | s.codeUnitAt(i + 1));
      }
      return String.fromCharCodes(codeUnits);
    }

    return s;
  }

  static String _decodeHexPdfString(String hex) {
    final clean = hex.replaceAll(RegExp(r'\s+'), '');
    final bytes = <int>[];
    for (int i = 0; i < clean.length; i += 2) {
      if (i + 1 < clean.length) {
        bytes.add(int.parse(clean.substring(i, i + 2), radix: 16));
      }
    }
    return _decodeBytesToText(bytes);
  }

  static int _indexOf(List<int> source, List<int> pattern, int start) {
    for (int i = start; i <= source.length - pattern.length; i++) {
      bool match = true;
      for (int j = 0; j < pattern.length; j++) {
        if (source[i + j] != pattern[j]) {
          match = false;
          break;
        }
      }
      if (match) return i;
    }
    return -1;
  }
}
