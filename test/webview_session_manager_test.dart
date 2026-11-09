import 'package:flutter_test/flutter_test.dart';
import 'package:novels_world/core/services/webview_session_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('WebViewSessionManager Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('Initializes cleanly and returns null for unknown hosts', () async {
      final manager = WebViewSessionManager.instance;
      await manager.init();
      expect(manager.getCookieHeader('https://unknown-domain-test.com'), isNull);
    });

    test('Stores and retrieves cookies for exact host and root domain', () async {
      final manager = WebViewSessionManager.instance;
      await manager.init();

      await manager.saveCookies(
        'https://novelbin.me/novel-list',
        'cf_clearance=abc123token; session=xyz987',
      );

      final exact = manager.getCookieHeader('https://novelbin.me/chapter-1');
      expect(exact, contains('cf_clearance=abc123token'));

      // Root domain matching for subdomains
      final sub = manager.getCookieHeader('https://api.novelbin.me/v1');
      expect(sub, contains('cf_clearance=abc123token'));
    });

    test('Clears cookies correctly', () async {
      final manager = WebViewSessionManager.instance;
      await manager.init();

      await manager.saveCookies('https://temp-test-site.org', 'test_cookie=123');
      expect(manager.getCookieHeader('https://temp-test-site.org'), equals('test_cookie=123'));

      await manager.clearCookies('https://temp-test-site.org');
      expect(manager.getCookieHeader('https://temp-test-site.org'), isNull);
    });

    test('Merges cookies without erasing cf_clearance or existing cookies', () async {
      final manager = WebViewSessionManager.instance;
      await manager.init();

      // Step 1: WebView saves HttpOnly cf_clearance
      await manager.saveCookies(
        'https://oceanofpdf.com/book',
        'cf_clearance=secret_token_123',
      );
      expect(manager.hasClearanceCookie('https://oceanofpdf.com'), isTrue);

      // Step 2: Later JavaScript document.cookie saves standard cookies
      await manager.saveCookies(
        'https://oceanofpdf.com/book',
        '_ga=analytics_token; session=user_session',
      );

      final combined = manager.getCookieHeader('https://oceanofpdf.com/search');
      expect(combined, contains('cf_clearance=secret_token_123'));
      expect(combined, contains('_ga=analytics_token'));
      expect(combined, contains('session=user_session'));
      expect(manager.hasClearanceCookie('https://oceanofpdf.com'), isTrue);
    });

    test('Matches across www and non-www variants', () async {
      final manager = WebViewSessionManager.instance;
      await manager.init();

      await manager.saveCookies(
        'https://www.oceanofpdf.com',
        'cf_clearance=www_token_456',
      );

      // Querying root domain without www should match
      expect(manager.getCookieHeader('https://oceanofpdf.com/catalog'), contains('cf_clearance=www_token_456'));
    });

    test('Default User-Agent is modern Android Mobile User-Agent', () {
      expect(WebViewSessionManager.defaultUserAgent, contains('Android'));
      expect(WebViewSessionManager.defaultUserAgent, contains('Chrome'));
      expect(WebViewSessionManager.defaultUserAgent, contains('Mobile'));
    });
  });
}

