import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import '../models/novel.dart';
import '../models/chapter.dart';
import '../models/chapter_content.dart';
import '../utils/text_cleaner.dart';

/// Service responsible for parsing, extracting, and importing local EPUB files
/// into the Novels-World offline library.
class EpubService {
  static final EpubService _instance = EpubService._internal();
  factory EpubService() => _instance;
  EpubService._internal();

  /// Imports an EPUB file, extracts its contents into app documents,
  /// parses its metadata/spine/TOC, and returns a fully initialized [Novel].
  Future<Novel> importEpub(File epubFile, {Directory? targetDir}) async {
    final bytes = await epubFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    // Compute a stable ID from file content hash
    final digest = md5.convert(bytes.sublist(0, bytes.length > 8192 ? 8192 : bytes.length)).toString().substring(0, 12);
    final novelId = 'local_epub_$digest';

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
      final coverFile = File('$opfDir/$coverHref');
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
        final tocFile = File('$opfDir/$href');
        if (await tocFile.exists()) {
          try {
            final tocXml = XmlDocument.parse(await tocFile.readAsString());
            for (final navPoint in tocXml.findAllElements('navPoint')) {
              final label = navPoint.findAllElements('text').firstOrNull?.innerText.trim();
              final src = navPoint.findAllElements('content').firstOrNull?.getAttribute('src');
              if (label != null && src != null) {
                final cleanSrc = src.split('#').first;
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
      final chFile = File('$opfDir/$relHref');
      if (!await chFile.exists()) continue;

      String chTitle = tocTitles[relHref] ?? '';
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

    final novel = Novel(
      id: novelId,
      sourceId: 'local_epub',
      title: title,
      author: author,
      description: description,
      coverUrl: coverUrl,
      sourceUrl: bookDir.uri.toString(),
      inLibrary: true,
      status: 'COMPLETED',
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

  /// Reads and parses an XHTML chapter file into cleaned paragraphs.
  Future<ChapterContent> loadChapterContent(String fileUriStr) async {
    final uri = Uri.parse(fileUriStr);
    final filePath = uri.toFilePath();
    final file = File(filePath);

    if (!await file.exists()) {
      throw Exception('Chapter file not found at $filePath');
    }

    final rawHtml = await file.readAsString();
    final doc = html_parser.parse(rawHtml);

    // Remove unwanted non-narrative tags
    doc.querySelectorAll('script, style, link, meta').forEach((el) => el.remove());

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
      // Fallback: look at divs or body text
      final bodyEl = doc.body;
      if (bodyEl != null) {
        for (final div in bodyEl.querySelectorAll('div')) {
          final text = div.text.trim();
          if (text.length > 20) {
            rawParas.add(text);
          }
        }
        if (rawParas.isEmpty) {
          rawParas.add(bodyEl.text.trim());
        }
      }
    }

    final paragraphs = TextCleaner.cleanParagraphs(rawParas);
    final rawText = TextCleaner.toCleanRawText(paragraphs);
    final title = doc.querySelector('h1, h2, title')?.text.trim() ?? 'Chapter';

    return ChapterContent(
      chapterId: filePath,
      novelId: 'local_epub',
      title: title,
      rawText: rawText,
      paragraphs: paragraphs,
    );
  }

  Future<Directory> _getImportDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDocDir.path}/imported_novels');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }
}
