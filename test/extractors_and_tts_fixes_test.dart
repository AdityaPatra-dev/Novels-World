import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novels_world/extractors/bespoke/hindisamay_extractor.dart';
import 'package:novels_world/extractors/bespoke/odiabibhaba_extractor.dart';
import 'package:novels_world/extractors/bespoke/or_wikisource_extractor.dart';
import 'package:novels_world/tts/voice_calibration.dart';

void main() {
  group('HindiSamayExtractor Fixes', () {
    test('parses contentDetail.aspx with title, author, and chapters correctly', () async {
      final mockHtml = '''
        <html>
          <head><title>Hindi Samay</title></head>
          <body>
            <span id="ContentPlaceHolder1_lblTitle">गोदान</span>
            <span id="ContentPlaceHolder1_lblAuthor">प्रेमचंद</span>
            <span id="ContentPlaceHolder1_lblContentType">उपन्यास</span>
            <div id="ContentPlaceHolder1_lblToc">
              <a href="https://hindisamay.com/content/244/1/premchand-godan.cspx">अध्याय 1</a>
              <a href="https://hindisamay.com/content/244/2/premchand-godan.cspx">भाग 2</a>
            </div>
            <div id="ContentPlaceHolder1_lblContentText">
              होरी बेलारी में रहता था।<br>वह एक किसान था।
            </div>
          </body>
        </html>
      ''';

      final client = MockClient((request) async {
        return http.Response(mockHtml, 200, headers: {'content-type': 'text/html; charset=utf-8'});
      });

      final extractor = HindiSamayExtractor(client: client);
      final novel = await extractor.getNovelDetails('http://www.hindisamay.com/content/244/1/godan.cspx');

      expect(novel.title, 'गोदान');
      expect(novel.author, 'प्रेमचंद');
      expect(novel.genres, contains('उपन्यास'));
      expect(novel.description, contains('होरी बेलारी में रहता था।'));

      final chapters = await extractor.getChapterList('http://www.hindisamay.com/content/244/1/godan.cspx');
      expect(chapters.length, 2);
      expect(chapters[0].title, 'अध्याय 1');
      expect(chapters[0].url, contains('id=244&pageno=1'));
      expect(chapters[1].title, 'भाग 2');
      expect(chapters[1].url, contains('id=244&pageno=2'));

      final content = await extractor.getChapterContent('https://www.hindisamay.com/contentDetail.aspx?id=244&pageno=1&lang=hi');
      expect(content.title, 'गोदान');
      expect(content.paragraphs, contains('होरी बेलारी में रहता था।'));
      expect(content.paragraphs, contains('वह एक किसान था।'));
    });
  });

  group('OdiaBibhabaExtractor Fixes', () {
    test('fetches single book details from /api/books/\$slug directly', () async {
      final mockJson = jsonEncode({
        'book': {
          'id': 3524,
          'slug': '1-tharu-10-bahaghara-jatra',
          'title_or': '1 ଠାରୁ 10 ବାହାଘର ଯାତ୍ରା',
          'title_en': '1 Tharu 10 Bahaghara Jatra',
          'author_or': 'ମିକି ପଟେଲ',
          'author_en': 'Micky Patel',
          'year_or': '୧୯୮୯',
          'year_en': '1989',
          'category_or': 'ଚିତ୍ର, ସଂଖ୍ୟା, ଶିଶୁ, ଏନବିଟି',
          'cover_url': 'https://files.odiabibhaba.in/images/books/1-tharu-10-bahaghara-jatra.jpg',
          'pdf_url': '/api/books/1-tharu-10-bahaghara-jatra/stream',
        }
      });

      final client = MockClient((request) async {
        if (request.url.path == '/api/books/1-tharu-10-bahaghara-jatra') {
          return http.Response(mockJson, 200, headers: {'content-type': 'application/json'});
        }
        return http.Response('{"error": "Not found"}', 404);
      });

      final extractor = OdiaBibhabaExtractor(client: client);
      final novel = await extractor.getNovelDetails('https://odiabibhaba.in/or/books/1-tharu-10-bahaghara-jatra');

      expect(novel.title, '1 ଠାରୁ 10 ବାହାଘର ଯାତ୍ରା');
      expect(novel.author, 'ମିକି ପଟେଲ');
      expect(novel.coverUrl, 'https://files.odiabibhaba.in/images/books/1-tharu-10-bahaghara-jatra.jpg');
      expect(novel.bookDownloadUrl, 'https://odiabibhaba.in/api/books/1-tharu-10-bahaghara-jatra/stream');
      expect(novel.isFullBook, isTrue);
    });
  });

  group('OdiaWikisourceExtractor Fixes', () {
    test('parses header title, author, and subpage chapters properly', () async {
      final mockApiJson = jsonEncode({
        'parse': {
          'title': 'ଛମାଣ ଆଠଗୁଣ୍ଠ',
          'pageid': 3955,
          'text': {
            '*': '''
              <div id="header_title_text">ଛମାଣ ଆଠଗୁଣ୍ଠ</div>
              <div id="header_author_text">ଫକୀର ମୋହନ ସେନାପତି</div>
              <img src="//thumb.wikimedia.org/fakir_mohan.png" />
              <div class="mw-parser-output">
                <a href="/wiki/%E0%AC%9B%E0%AC%AE%E0%AC%BE%E0%AC%A3_%E0%AC%86%E0%AC%A0%E0%AC%97%E0%AD%81%E0%AC%A3%E0%AD%8D%E0%AC%A0/%E0%AC%B0%E0%AC%BE%E0%AC%AE%E0%AC%9A%E0%AC%A8%E0%AD%8D%E0%AC%A6%E0%AD%8D%E0%AC%B0_%E0%AC%AE%E0%AC%99%E0%AD%8D%E0%AC%97%E0%AC%B0%E0%AC%BE%E0%AC%9C">ରାମଚନ୍ଦ୍ର ମଙ୍ଗରାଜ</a>
                <a href="/wiki/%E0%AC%9B%E0%AC%AE%E0%AC%BE%E0%AC%A3_%E0%AC%86%E0%AC%A0%E0%AC%97%E0%AD%81%E0%AC%A3%E0%AD%8D%E0%AC%A0/%E0%AC%9A%E0%AC%AE%E0%AD%8D%E0%AC%AA%E0%AC%BE">ଚମ୍ପା</a>
              </div>
            '''
          }
        }
      });

      final client = MockClient((request) async {
        return http.Response(mockApiJson, 200, headers: {'content-type': 'application/json'});
      });

      final extractor = OdiaWikisourceExtractor(client: client);
      final novel = await extractor.getNovelDetails('https://or.wikisource.org/?curid=3955');

      expect(novel.title, 'ଛମାଣ ଆଠଗୁଣ୍ଠ');
      expect(novel.author, 'ଫକୀର ମୋହନ ସେନାପତି');
      expect(novel.coverUrl, contains('fakir_mohan.png'));

      final chapters = await extractor.getChapterList('https://or.wikisource.org/?curid=3955');
      expect(chapters.length, 2);
      expect(chapters[0].title, 'ରାମଚନ୍ଦ୍ର ମଙ୍ଗରାଜ');
      expect(chapters[1].title, 'ଚମ୍ପା');
    });
  });

  group('TTS Voice Calibration for Odia and Other Languages', () {
    test('getProfile correctly looks up Odia voice profile and retains Odia locale', () {
      final profile = VoiceCalibration.getProfile('or-IN-SubhasiniNeural');
      expect(profile.id, 'or-IN-SubhasiniNeural');
      expect(profile.gender, 'Female');
      expect(profile.locale, 'or_IN');
      expect(profile.targetVoiceKeywords, contains('ory'));
      expect(profile.targetVoiceKeywords, contains('odia'));
      expect(profile.targetVoiceKeywords, contains('or-in'));
    });

    test('getProfile correctly looks up Hindi voice profile and retains Hindi locale', () {
      final profile = VoiceCalibration.getProfile('hi-IN-SwaraNeural');
      expect(profile.id, 'hi-IN-SwaraNeural');
      expect(profile.locale, 'hi_IN');
      expect(profile.targetVoiceKeywords, contains('hi-in'));
    });
  });
}
