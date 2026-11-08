import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Configurable Cloudflare Worker Edge Proxy URL for web clients.
/// Set to your deployed Cloudflare Worker endpoint, e.g.:
/// 'https://novels-world-proxy.`<your-subdomain>`.workers.dev'
String webProxyEndpoint = 'https://novels-world-proxy.adityapatraraj.workers.dev';

/// Configures or updates the web CORS proxy endpoint dynamically.
void setWebProxyEndpoint(String endpoint) {
  webProxyEndpoint = endpoint.trim().replaceAll(RegExp(r'/+$'), '');
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
/// - On Web (`kIsWeb`): Routes external scraping through Cloudflare Edge proxy
/// - On Mobile (`!kIsWeb`): Direct raw OS sockets via native IOClient (zero overhead, 100% native)
http.Client createPlatformHttpClient({Duration timeout = const Duration(seconds: 15)}) {
  if (kIsWeb) {
    return _WebCorsProxyClient(webProxyEndpoint);
  }
  final native = HttpClient();
  native.badCertificateCallback = (cert, host, port) => true;
  native.connectionTimeout = timeout;
  return IOClient(native);
}

class _WebCorsProxyClient extends http.BaseClient {
  final http.Client _inner = http.Client();
  final String proxyUrl;

  _WebCorsProxyClient(this.proxyUrl);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
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

    // Proxy the external request through Cloudflare Edge
    final proxiedUri = Uri.parse('$proxyUrl?url=${Uri.encodeComponent(urlStr)}');
    final proxiedRequest = http.Request(request.method, proxiedUri);
    proxiedRequest.headers.addAll(request.headers);
    if (request is http.Request) {
      proxiedRequest.bodyBytes = request.bodyBytes;
    }
    return _inner.send(proxiedRequest);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
