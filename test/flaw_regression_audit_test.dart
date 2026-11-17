import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/models/novel.dart';
import 'package:novels_world/core/utils/http_client_factory.dart';
import 'package:novels_world/core/utils/text_cleaner.dart';
import 'package:novels_world/data/storage_service.dart';
import 'package:novels_world/extractors/bespoke/hindisamay_extractor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('Audit & Flaw Regression Verification Tests', () {
    test('Hindi Samay extractor filters out category links like content.aspx?id=1', () async {
      final extractor = HindiSamayExtractor();
      final popular = await extractor.getPopular(page: 1);
      expect(popular.isNotEmpty, isTrue);

      // Verify no novel card has category names like 'उपन्यास' or 'Hindi Novel'
      for (final n in popular) {
        expect(n.title, isNot(equals('उपन्यास')));
        expect(n.title.toLowerCase(), isNot(equals('hindi novel')));
        expect(n.sourceUrl.contains('content.aspx'), isFalse);
      }
    });

    test('StorageService deleteNovelStorage safely removes downloaded novel without throwing on web URLs', () async {
      SharedPreferences.setMockInitialValues({});
      final tempDir = await Directory.systemTemp.createTemp('storage_test');
      final storage = StorageService();
      await storage.init(appDir: tempDir);

      final novel = Novel(
        id: 'hindisamay_test_novel',
        sourceId: 'hindisamay',
        title: 'गोदान',
        author: 'प्रेमचंद',
        description: 'प्रसिद्ध उपन्यास',
        coverUrl: 'https://www.hindisamay.com/images/logo.png',
        sourceUrl: 'https://www.hindisamay.com/contentDetail.aspx?id=244&pageno=1&lang=hi',
        status: 'COMPLETED',
        isFullBook: false,
      );

      // Record novel as downloaded
      await storage.recordDownloadedNovel(novel, 'ch_1');
      var downloaded = await storage.getDownloadedNovels();
      expect(downloaded.any((n) => n.id == novel.id), isTrue);

      // Delete novel storage
      await storage.deleteNovelStorage(novel);
      downloaded = await storage.getDownloadedNovels();
      expect(downloaded.any((n) => n.id == novel.id), isFalse);

      await tempDir.delete(recursive: true);
    });

    test('TextCleaner and getCoverImageHeaders support valid covers across sources including Wikimedia', () {
      expect(TextCleaner.isValidCoverUrl('https://or.wikisource.org/static/images/project-logos/orwikisource.png'), isTrue);
      expect(TextCleaner.isValidCoverUrl('https://www.hindisamay.com/images/logo.png'), isTrue);
      expect(TextCleaner.isValidCoverUrl('https://gadyakosh.org/gk/otherapps/images/Gadya-Kosh-Logo.png'), isTrue);
      expect(TextCleaner.isValidCoverUrl('https://kavitakosh.org/kk/otherapps/images/KK-18-Years-Logo-small.png'), isTrue);

      final wikiHeaders = getCoverImageHeaders('https://or.wikisource.org/static/images/project-logos/orwikisource.png');
      expect(wikiHeaders['User-Agent'], contains('NovelsWorldApp'));
      expect(wikiHeaders['Referer'], contains('or.wikisource.org'));
    });
  });
}
