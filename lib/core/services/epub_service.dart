import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:path_provider/path_provider.dart';
import 'package:xml/xml.dart';
import '../models/novel.dart';
import '../models/chapter.dart';
import '../models/chapter_content.dart';
import '../utils/text_cleaner.dart';
import 'webview_session_manager.dart';

/// Service responsible for parsing, extracting, and importing local EPUB files
/// into the Novels-World offline library.
class EpubService {
  static final EpubService _instance = EpubService._internal();
  factory EpubService() => _instance;
  EpubService._internal();

  /// Imports an EPUB file, extracts its contents into app documents,
  /// parses its metadata/spine/TOC, and returns a fully initialized [Novel].
  Future<Novel> importEpub(File epubFile, {Directory? targetDir, Novel? originalNovel}) async {
    final bytes = await epubFile.readAsBytes();

    // Verify magic bytes: Standard ZIP/EPUB starts with PK\x03\x04 (0x50, 0x4B, 0x03, 0x04)
    if (bytes.length < 4 ||
        bytes[0] != 0x50 ||
        bytes[1] != 0x4B ||
        bytes[2] != 0x03 ||
        bytes[3] != 0x04) {
      throw const FormatException('Corrupt or invalid EPUB archive: missing PK signature header');
    }

    final archive = ZipDecoder().decodeBytes(bytes);

    // Compute a stable ID from file content hash or use originalNovel.id
    final digest = md5.convert(bytes.sublist(0, bytes.length > 8192 ? 8192 : bytes.length)).toString().substring(0, 12);
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
      bookSizeBytes: bytes.length,
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
  /// and returns a fully initialized [Novel].
  Future<Novel> importEpubFromUrl(
    String url, {
    Map<String, String>? headers,
    void Function(double progress, String stage)? onProgress,
    Novel? originalNovel,
  }) async {
    if (kIsWeb) {
      throw 'EPUB URL import is not supported in browser environment';
    }
    final client = HttpClient();
    client.connectionTimeout = const Duration(seconds: 30);
    client.autoUncompress = true;
    File? tempFile;
    File? tempTmpFile;
    try {
      onProgress?.call(0.05, 'Connecting');

      Uri currentUri = Uri.parse(url);
      HttpClientResponse? response;

      // Handle redirects manually to preserve and forward User-Agent, Referer, and Cookies
      for (int redirect = 0; redirect < 10; redirect++) {
        final request = await client.getUrl(currentUri);
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

        // Maintain Referer across redirects
        String? referer = headers?['Referer'];
        if (redirect > 0) {
          referer = currentUri.toString();
        } else if (referer == null || referer.isEmpty) {
          if (originalNovel != null && originalNovel.sourceUrl.isNotEmpty) {
            referer = originalNovel.sourceUrl;
          } else {
            referer = '${currentUri.scheme}://${currentUri.host}/';
          }
        }
        request.headers.set(HttpHeaders.refererHeader, referer);

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
        throw HttpException('Failed to download EPUB: HTTP ${response?.statusCode ?? 500}');
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
      if (headerBytes.length < 4 ||
          headerBytes[0] != 0x50 ||
          headerBytes[1] != 0x4B ||
          headerBytes[2] != 0x03 ||
          headerBytes[3] != 0x04) {
        throw const FormatException('Downloaded file is not a valid EPUB archive (corrupted or blocked download).');
      }

      tempFile = File('${baseDir.path}/temp_dl_$timestamp.epub');
      await tempTmpFile.rename(tempFile.path);
      tempTmpFile = null;

      onProgress?.call(0.98, 'Extracting');
      final novel = await importEpub(tempFile, originalNovel: originalNovel);
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
