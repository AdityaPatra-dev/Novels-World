import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import '../services/webview_session_manager.dart';

/// Configurable Cloudflare Worker Edge Proxy URL for web clients.
/// Set to your deployed Cloudflare Worker endpoint, e.g.:
/// 'https://novels-world-proxy.`<your-subdomain>`.workers.dev'
String webProxyEndpoint = 'https://novels-world-proxy.adityapatraraj.workers.dev';

/// Configures or updates the web CORS proxy endpoint dynamically.
void setWebProxyEndpoint(String endpoint) {
  webProxyEndpoint = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
}

/// Returns the HTTP request headers for fetching cover images safely without hotlink/CORS rejection.
Map<String, String> getCoverImageHeaders(String coverUrl, [String? sourceUrl]) {
  final headers = <String, String>{
    'User-Agent': WebViewSessionManager.defaultUserAgent,
    'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
  };
  final coverUri = Uri.tryParse(coverUrl);
  if (coverUri != null && coverUri.origin.isNotEmpty && !coverUri.scheme.startsWith('file')) {
    headers['Referer'] = '${coverUri.origin}/';
  } else if (sourceUrl != null && sourceUrl.isNotEmpty) {
    final origin = Uri.tryParse(sourceUrl)?.origin;
    if (origin != null && origin.isNotEmpty) {
      headers['Referer'] = '$origin/';
    }
  }
  if (sourceUrl != null && sourceUrl.isNotEmpty) {
    final cookie = WebViewSessionManager.instance.getCookieHeader(sourceUrl);
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
  }
  return headers;
}

/// Returns the proxied URL for web image covers to avoid hotlinking/CORS blocks.
String getWebProxiedImageUrl(String originalUrl) {
  if (!kIsWeb || webProxyEndpoint.isEmpty || originalUrl.isEmpty) {
    return originalUrl;
  }
  if (!originalUrl.startsWith('http://') && !originalUrl.startsWith('https://')) {
    return originalUrl;
  }
  if (originalUrl.contains('firebase') ||
      originalUrl.contains('googleapis.com') ||
      originalUrl.contains('gstatic.com') ||
      originalUrl.startsWith(webProxyEndpoint)) {
    return originalUrl;
  }
  return '$webProxyEndpoint?url=${Uri.encodeComponent(originalUrl)}';
}

/// Creates a platform-optimized HTTP client:
/// - On Web (`kIsWeb`): Routes external scraping through Cloudflare Edge proxy with in-memory caching & deduplication
/// - On Mobile (`!kIsWeb`): Direct raw OS sockets via native IOClient (zero overhead, 100% native)
http.Client createPlatformHttpClient({Duration timeout = const Duration(seconds: 15)}) {
  if (kIsWeb) {
    return _WebCorsProxyClient(webProxyEndpoint);
  }
  final native = HttpClient();
  native.userAgent = WebViewSessionManager.defaultUserAgent;
  native.badCertificateCallback = (cert, host, port) => true;
  native.connectionTimeout = timeout;
  return IOClient(native);
}

class _CachedResponse {
  final int statusCode;
  final Map<String, String> headers;
  final List<int> bodyBytes;
  final DateTime expiresAt;

  _CachedResponse({
    required this.statusCode,
    required this.headers,
    required this.bodyBytes,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class _WebCorsProxyClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final String proxyUrl;

  // Shared in-memory cache across all extractor requests on web to minimize requests
  static final Map<String, _CachedResponse> _responseCache = {};
  static final Map<String, Future<List<int>>> _inFlightRequests = {};
  static const int _maxCacheSize = 200;

  _WebCorsProxyClient(this.proxyUrl);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final originalUri = request.url;
    final urlStr = originalUri.toString();

    // Direct fetch for Firebase, Google APIs, local assets, or if already targeted at proxy
    if (!urlStr.startsWith('http://') && !urlStr.startsWith('https://')) {
      return _inner.send(request);
    }
    if (urlStr.contains('firebase') ||
        urlStr.contains('googleapis.com') ||
        urlStr.contains('gstatic.com') ||
        (proxyUrl.isNotEmpty && urlStr.startsWith(proxyUrl)) ||
        proxyUrl.isEmpty) {
      return _inner.send(request);
    }

    // 1. Check in-memory cache for GET requests (0ms latency, 0 network requests)
    if (request.method == 'GET') {
      final cached = _responseCache[urlStr];
      if (cached != null && !cached.isExpired) {
        return http.StreamedResponse(
          Stream.value(cached.bodyBytes),
          cached.statusCode,
          headers: cached.headers,
          reasonPhrase: 'OK (Memory Cache)',
        );
      }
    }

    // 2. Proxy the external request through Cloudflare Edge
    final proxiedUri = Uri.parse('$proxyUrl?url=${Uri.encodeComponent(urlStr)}');
    final proxiedRequest = http.Request(request.method, proxiedUri);
    proxiedRequest.headers.addAll(request.headers);
    if (request is http.Request) {
      proxiedRequest.bodyBytes = request.bodyBytes;
    }

    // For non-GET requests, forward directly without caching
    if (request.method != 'GET') {
      return _inner.send(proxiedRequest);
    }

    // 3. Request deduplication: if identical URL is already in-flight, await the same future
    final existingFuture = _inFlightRequests[urlStr];
    if (existingFuture != null) {
      final bodyBytes = await existingFuture;
      final cached = _responseCache[urlStr];
      return http.StreamedResponse(
        Stream.value(bodyBytes),
        cached?.statusCode ?? 200,
        headers: cached?.headers ?? {},
        reasonPhrase: 'OK (Deduplicated)',
      );
    }

    final completer = Completer<List<int>>();
    _inFlightRequests[urlStr] = completer.future;

    try {
      final streamedResponse = await _inner.send(proxiedRequest);

      if (streamedResponse.statusCode == 200) {
        final bodyBytes = await streamedResponse.stream.toBytes();

        // Dynamic TTL: 24h for chapters, 1h for novel details, 15m for listings/searches
        final isChapter = urlStr.toLowerCase().contains('chapter');
        final isListing = urlStr.contains('page') || urlStr.contains('search') || urlStr.contains('popular');
        final ttl = isChapter
            ? const Duration(hours: 24)
            : (isListing ? const Duration(minutes: 15) : const Duration(hours: 1));

        // Evict oldest if cache limit reached
        if (_responseCache.length >= _maxCacheSize) {
          _responseCache.remove(_responseCache.keys.first);
        }

        _responseCache[urlStr] = _CachedResponse(
          statusCode: streamedResponse.statusCode,
          headers: streamedResponse.headers,
          bodyBytes: bodyBytes,
          expiresAt: DateTime.now().add(ttl),
        );

        completer.complete(bodyBytes);

        return http.StreamedResponse(
          Stream.value(bodyBytes),
          streamedResponse.statusCode,
          headers: streamedResponse.headers,
          contentLength: bodyBytes.length,
          request: streamedResponse.request,
          isRedirect: streamedResponse.isRedirect,
          reasonPhrase: streamedResponse.reasonPhrase,
        );
      } else {
        completer.complete([]);
        return streamedResponse;
      }
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _inFlightRequests.remove(urlStr);
    }
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
