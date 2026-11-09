import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Centralized session and cookie manager for novel extractors.
/// Synchronizes cookies obtained from the In-App WebView (such as cf_clearance,
/// session tokens, and Turnstile verifications) with native background HTTP requests.
class WebViewSessionManager {
  static final WebViewSessionManager instance = WebViewSessionManager._();
  WebViewSessionManager._();

  final Map<String, String> _cookieCache = {};
  SharedPreferences? _prefs;
  bool _initialized = false;

  static const String defaultUserAgent =
      'Mozilla/5.0 (Linux; Android 14; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Mobile Safari/537.36';

  Future<void> init() async {
    if (_initialized) return;
    try {
      _prefs = await SharedPreferences.getInstance();
      final keys = _prefs?.getKeys() ?? {};
      for (final key in keys) {
        if (key.startsWith('cookie_host_')) {
          final host = key.replaceFirst('cookie_host_', '');
          final value = _prefs?.getString(key) ?? '';
          if (value.isNotEmpty) {
            _cookieCache[host] = value;
          }
        }
      }
    } catch (_) {}
    _initialized = true;
  }

  Map<String, String> _parseCookieString(String cookies) {
    final map = <String, String>{};
    for (final pair in cookies.split(';')) {
      final trimmed = pair.trim();
      if (trimmed.isEmpty) continue;
      final eq = trimmed.indexOf('=');
      if (eq > 0) {
        final name = trimmed.substring(0, eq).trim();
        final value = trimmed.substring(eq + 1).trim();
        if (name.isNotEmpty) {
          map[name] = value;
        }
      }
    }
    return map;
  }

  String? getCookieHeader(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    final host = uri.host.toLowerCase();

    // 1. Check exact host
    if (_cookieCache.containsKey(host) && _cookieCache[host]!.trim().isNotEmpty) {
      return _cookieCache[host];
    }

    // 2. Check without 'www.'
    if (host.startsWith('www.')) {
      final noWww = host.substring(4);
      if (_cookieCache.containsKey(noWww) && _cookieCache[noWww]!.trim().isNotEmpty) {
        return _cookieCache[noWww];
      }
    } else {
      // Check with 'www.'
      final withWww = 'www.$host';
      if (_cookieCache.containsKey(withWww) && _cookieCache[withWww]!.trim().isNotEmpty) {
        return _cookieCache[withWww];
      }
    }

    // 3. Check root domain (e.g. novelbin.com for api.novelbin.com)
    final parts = host.split('.');
    if (parts.length > 2) {
      final rootHost = parts.sublist(parts.length - 2).join('.');
      if (_cookieCache.containsKey(rootHost) && _cookieCache[rootHost]!.trim().isNotEmpty) {
        return _cookieCache[rootHost];
      }
    }

    return null;
  }

  bool hasClearanceCookie(String url) {
    final cookie = getCookieHeader(url);
    if (cookie == null) return false;
    return cookie.contains('cf_clearance');
  }

  Future<void> saveCookies(String url, String cookieString) async {
    final uri = Uri.tryParse(url);
    if (uri == null || cookieString.trim().isEmpty) return;
    final host = uri.host.toLowerCase();

    final existing = _cookieCache[host] ?? '';
    final existingMap = _parseCookieString(existing);
    final newMap = _parseCookieString(cookieString);

    existingMap.addAll(newMap);

    final merged = existingMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
    _cookieCache[host] = merged;

    try {
      _prefs ??= await SharedPreferences.getInstance();
      await _prefs?.setString('cookie_host_$host', merged);
    } catch (_) {}

    // Also mirror to root domain if host has subdomains (e.g. www.oceanofpdf.com -> oceanofpdf.com)
    final parts = host.split('.');
    if (parts.length > 2) {
      final rootHost = parts.sublist(parts.length - 2).join('.');
      final rootExisting = _cookieCache[rootHost] ?? '';
      final rootExistingMap = _parseCookieString(rootExisting);
      rootExistingMap.addAll(newMap);
      final rootMerged = rootExistingMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
      _cookieCache[rootHost] = rootMerged;
      try {
        await _prefs?.setString('cookie_host_$rootHost', rootMerged);
      } catch (_) {}
    }
  }

  Future<void> clearCookies(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    final host = uri.host.toLowerCase();
    _cookieCache.remove(host);
    try {
      await _prefs?.remove('cookie_host_$host');
    } catch (_) {}

    final parts = host.split('.');
    if (parts.length > 2) {
      final rootHost = parts.sublist(parts.length - 2).join('.');
      _cookieCache.remove(rootHost);
      try {
        await _prefs?.remove('cookie_host_$rootHost');
      } catch (_) {}
    }
  }

  /// Extracts cookies for the given URL directly from the WebView cookie storage
  /// and updates the in-memory cache and persistent preferences.
  Future<String?> syncCookiesFromWebView(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return null;
    try {
      final cookieManager = WebViewCookieManager();
      final cookies = await cookieManager.getCookies(domain: uri);
      final combinedMap = <String, String>{};
      for (final c in cookies) {
        combinedMap[c.name] = c.value;
      }

      final host = uri.host.toLowerCase();
      final parts = host.split('.');
      if (parts.length > 2) {
        final rootHost = parts.sublist(parts.length - 2).join('.');
        final rootUri = Uri(scheme: uri.scheme, host: rootHost);
        try {
          final rootCookies = await cookieManager.getCookies(domain: rootUri);
          for (final c in rootCookies) {
            combinedMap[c.name] = c.value;
          }
        } catch (_) {}
      }

      if (combinedMap.isNotEmpty) {
        final cookieStr = combinedMap.entries.map((e) => '${e.key}=${e.value}').join('; ');
        await saveCookies(url, cookieStr);
        return cookieStr;
      }
    } catch (_) {}
    return null;
  }

  /// Headless WebView fetcher to bypass Cloudflare TLS fingerprinting and JS challenges.
  /// When native Dart HttpClient is rejected with 403 or Cloudflare challenge,
  /// this uses the underlying Chromium engine on mobile, or curl on desktop/CI environments
  /// to retrieve the fully rendered DOM.
  Future<String?> fetchHtmlViaWebView(String url, {Duration timeout = const Duration(seconds: 12)}) async {
    if (kIsWeb) return null;
    // 1. Mobile WebViewController (Android / iOS)
    if (Platform.isAndroid || Platform.isIOS) {
      try {
        final completer = Completer<String?>();
        final controller = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setUserAgent(defaultUserAgent);

        Timer? timer;
        bool completed = false;

        void finish(String? html) {
          if (!completed) {
            completed = true;
            timer?.cancel();
            if (!completer.isCompleted) {
              completer.complete(html);
            }
          }
        }

        String decodeHtml(dynamic htmlObj) {
          var str = htmlObj.toString();
          if (str.startsWith('"') && str.endsWith('"')) {
            try {
              return jsonDecode(str).toString();
            } catch (_) {
              return str
                  .substring(1, str.length - 1)
                  .replaceAll(r'\"', '"')
                  .replaceAll(r'\n', '\n')
                  .replaceAll(r'\t', '\t')
                  .replaceAll(r'\/', '/');
            }
          }
          return str;
        }

        timer = Timer(timeout, () async {
          if (!completed) {
            try {
              final htmlObj = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
              finish(decodeHtml(htmlObj));
            } catch (_) {
              finish(null);
            }
          }
        });

        controller.setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (finishedUrl) async {
              // Give scripts and redirections a brief moment to stabilize
              await Future.delayed(const Duration(milliseconds: 1500));
              if (!completed) {
                try {
                  await syncCookiesFromWebView(finishedUrl);
                  var htmlObj = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
                  var htmlStr = decodeHtml(htmlObj);
                  // If Turnstile challenge is still active, wait for resolution
                  if (htmlStr.contains('Just a moment...') || htmlStr.contains('challenge-running')) {
                    await Future.delayed(const Duration(milliseconds: 2500));
                    await syncCookiesFromWebView(finishedUrl);
                    htmlObj = await controller.runJavaScriptReturningResult('document.documentElement.outerHTML');
                    htmlStr = decodeHtml(htmlObj);
                  }
                  finish(htmlStr);
                } catch (_) {
                  finish(null);
                }
              }
            },
            onWebResourceError: (_) {},
          ),
        );

        await controller.loadRequest(Uri.parse(url));
        final wvResult = await completer.future;
        if (wvResult != null && wvResult.isNotEmpty && !wvResult.contains('Just a moment...')) {
          return wvResult;
        }
      } catch (_) {
        // Fallback below
      }
    }

    // 2. Desktop/CLI/CI runner fallback using curl
    // This allows automated health checks and desktop environments to bypass Cloudflare TLS fingerprint blocks.
    try {
      final isFeedOrApi = url.contains('/feed') || url.contains('/wp-json') || url.contains('.xml') || url.contains('.rss');
      final acceptHeader = isFeedOrApi
          ? 'Accept: application/rss+xml,application/xml,application/json,text/xml,*/*;q=0.8'
          : 'Accept: text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8';

      final curlArgs = [
        '-s',
        '-L',
        '--http1.1',
        '--compressed',
        '--max-time',
        timeout.inSeconds.toString(),
        '-A',
        defaultUserAgent,
        '-H',
        acceptHeader,
        '-H',
        'Accept-Language: en-US,en;q=0.9',
        '-H',
        'Sec-Ch-Ua: "Chromium";v="128", "Not;A=Brand";v="24", "Google Chrome";v="128"',
        '-H',
        'Sec-Ch-Ua-Mobile: ?1',
        '-H',
        'Sec-Ch-Ua-Platform: "Android"',
      ];

      if (!isFeedOrApi) {
        curlArgs.addAll([
          '-H',
          'Sec-Fetch-Dest: document',
          '-H',
          'Sec-Fetch-Mode: navigate',
          '-H',
          'Sec-Fetch-Site: none',
          '-H',
          'Sec-Fetch-User: ?1',
          '-H',
          'Upgrade-Insecure-Requests: 1',
        ]);
      } else {
        curlArgs.addAll([
          '-H',
          'Sec-Fetch-Dest: empty',
          '-H',
          'Sec-Fetch-Mode: cors',
          '-H',
          'Sec-Fetch-Site: same-origin',
        ]);
      }

      curlArgs.add(url);

      final res = await Process.run('curl', curlArgs);
      if (res.exitCode == 0 && res.stdout is String) {
        final html = res.stdout as String;
        if (html.isNotEmpty &&
            !html.contains('Just a moment...') &&
            !html.contains('Enable JavaScript and cookies to continue')) {
          return html;
        }
      }
    } catch (_) {}

    return null;
  }
}

