import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/models/novel.dart';
import '../../core/services/epub_service.dart';
import '../../core/services/webview_session_manager.dart';
import '../../providers/library_provider.dart';

/// In-App WebView screen for resolving Cloudflare / bot-protection challenges,
/// logging into novel sources, or inspecting the live website directly.
/// Automatically captures clearance cookies and synchronizes them with native HTTP extractors.
class SourceWebViewScreen extends StatefulWidget {
  final String initialUrl;
  final String sourceName;
  final Novel? targetNovel;

  const SourceWebViewScreen({
    super.key,
    required this.initialUrl,
    required this.sourceName,
    this.targetNovel,
  });

  @override
  State<SourceWebViewScreen> createState() => _SourceWebViewScreenState();
}

class _SourceWebViewScreenState extends State<SourceWebViewScreen> {
  late final WebViewController _controller;
  int _loadingProgress = 0;
  bool _isLoading = true;
  String _pageTitle = '';
  int _cookieCount = 0;
  bool _hasSyncedCookies = false;
  bool _isHandlingDownload = false;
  Timer? _clearancePollTimer;

  // In-flight in-browser download state
  File? _inFlightDownloadFile;
  IOSink? _inFlightDownloadSink;
  int _receivedChunks = 0;
  int _totalChunks = 0;
  String _inFlightFilename = '';

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(WebViewSessionManager.defaultUserAgent)
      ..addJavaScriptChannel(
        'NovelsWorldDownload',
        onMessageReceived: (JavaScriptMessage msg) async {
          try {
            final data = jsonDecode(msg.message) as Map<String, dynamic>;
            final type = data['type'] as String?;

            if (type == 'start') {
              _showDownloadProgressSnackBar('Connecting to book download server...');
              return;
            }

            if (type == 'meta') {
              _inFlightFilename = data['filename']?.toString() ?? 'book';
              _totalChunks = data['totalChunks'] as int? ?? 1;
              _receivedChunks = 0;

              final appDocDir = await getApplicationDocumentsDirectory();
              final baseDir = Directory('${appDocDir.path}/imported_novels');
              if (!await baseDir.exists()) {
                await baseDir.create(recursive: true);
              }
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              _inFlightDownloadFile = File('${baseDir.path}/temp_wv_$timestamp.tmp');
              _inFlightDownloadSink = _inFlightDownloadFile!.openWrite();
              _showDownloadProgressSnackBar('Downloading book via browser session...');
              return;
            }

            if (type == 'chunk') {
              final chunkB64 = data['data'] as String?;
              if (chunkB64 != null && _inFlightDownloadSink != null) {
                final bytes = base64Decode(chunkB64);
                _inFlightDownloadSink!.add(bytes);
                _receivedChunks++;
                if (_totalChunks > 0 && (_receivedChunks % 3 == 0 || _receivedChunks == _totalChunks)) {
                  final pct = ((_receivedChunks / _totalChunks) * 100).toInt();
                  _showDownloadProgressSnackBar('Downloading book: $pct%');
                }
              }
              return;
            }

            if (type == 'complete') {
              if (_inFlightDownloadSink != null) {
                await _inFlightDownloadSink!.flush();
                await _inFlightDownloadSink!.close();
                _inFlightDownloadSink = null;
              }
              if (_inFlightDownloadFile != null && await _inFlightDownloadFile!.exists()) {
                final file = _inFlightDownloadFile!;
                final filename = _inFlightFilename;
                _inFlightDownloadFile = null;
                _inFlightFilename = '';
                await _processDownloadedFile(file, filename: filename);
              }
              return;
            }

            if (type == 'html_rendered') {
              if (mounted) {
                ScaffoldMessenger.of(context).hideCurrentSnackBar();
              }
              return;
            }

            if (type == 'error') {
              final fallbackUrl = data['fallbackUrl']?.toString();
              final method = (data['fallbackMethod']?.toString() ?? 'GET').toUpperCase();
              final body = data['fallbackBody']?.toString();
              if (fallbackUrl != null && fallbackUrl.isNotEmpty) {
                _handleEpubDownload(fallbackUrl, method: method, postBody: body);
              } else {
                _showDownloadError(data['message']?.toString() ?? 'Download failed');
              }
              return;
            }

            // Legacy fallback: { action: '...', method: '...', body: '...' }
            final action = data['action']?.toString() ?? '';
            final method = data['method']?.toString().toUpperCase() ?? 'GET';
            final body = data['body']?.toString();
            if (action.isNotEmpty) {
              _startInWebViewDownload(action, method: method, postBody: body);
            }
          } catch (err) {
            _showDownloadError('$err');
          }
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (progress) {
            if (mounted) {
              setState(() {
                _loadingProgress = progress;
                _isLoading = progress < 100;
              });
            }
          },
          onPageStarted: (url) {
            if (mounted) {
              setState(() {
                _isLoading = true;
              });
            }
          },
          onPageFinished: (url) async {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
            await _syncCookies(url);
            try {
              final title = await _controller.getTitle() ?? '';
              if (mounted) {
                setState(() {
                  _pageTitle = title;
                });
              }
            } catch (_) {}

            // Inject form and download button interception for OceanofPDF and vdoc.pub
            try {
              await _controller.runJavaScript(r'''
                (function() {
                  if (window.__nw_injected) return;
                  window.__nw_injected = true;

                  window.__nw_download = async function(url, method, postBody) {
                    try {
                      NovelsWorldDownload.postMessage(JSON.stringify({ type: 'start', url: url }));

                      const fetchOptions = {
                        method: method || 'GET',
                        credentials: 'include',
                        headers: {}
                      };

                      if (method === 'POST') {
                        if (postBody) {
                          fetchOptions.headers['Content-Type'] = 'application/x-www-form-urlencoded';
                          fetchOptions.body = postBody;
                        }
                      }

                      const res = await window.fetch(url, fetchOptions);
                      if (!res.ok) {
                        throw new Error('HTTP ' + res.status + ' ' + res.statusText);
                      }

                      const cType = (res.headers.get('content-type') || '').toLowerCase();

                      if (cType.includes('text/html')) {
                        const htmlText = await res.text();
                        const m = htmlText.match(/href=["']([^"']+\.(?:epub|pdf|mobi)[^"']*)["']/i) ||
                                  htmlText.match(/href=["']([^"']*(?:download-file|\/dl\/|\/download\/file)[^"']*)["']/i);
                        if (m && m[1]) {
                          let nextUrl = m[1];
                          if (!nextUrl.startsWith('http')) {
                            nextUrl = new URL(nextUrl, window.location.origin).href;
                          }
                          return window.__nw_download(nextUrl, 'GET', null);
                        }
                        document.open();
                        document.write(htmlText);
                        document.close();
                        NovelsWorldDownload.postMessage(JSON.stringify({ type: 'html_rendered' }));
                        return;
                      }

                      const buffer = await res.arrayBuffer();
                      const bytes = new Uint8Array(buffer);
                      if (bytes.length < 50) {
                        throw new Error('Downloaded file is too small: ' + bytes.length + ' bytes');
                      }

                      let filename = '';
                      const disp = res.headers.get('content-disposition') || '';
                      const fnMatch = disp.match(/filename\*?=(?:UTF-8'')?["']?([^"';]+)["']?/i);
                      if (fnMatch && fnMatch[1]) {
                        filename = decodeURIComponent(fnMatch[1]);
                      } else {
                        const pathParts = new URL(res.url || url).pathname.split('/');
                        filename = pathParts[pathParts.length - 1] || 'book';
                      }

                      const chunkSize = 256 * 1024;
                      const totalChunks = Math.ceil(bytes.length / chunkSize);

                      NovelsWorldDownload.postMessage(JSON.stringify({
                        type: 'meta',
                        filename: filename,
                        totalBytes: bytes.length,
                        totalChunks: totalChunks,
                        contentType: cType
                      }));

                      for (let i = 0; i < totalChunks; i++) {
                        const start = i * chunkSize;
                        const end = Math.min(start + chunkSize, bytes.length);
                        const chunk = bytes.subarray(start, end);

                        let binary = '';
                        const len = chunk.byteLength;
                        for (let j = 0; j < len; j++) {
                          binary += String.fromCharCode(chunk[j]);
                        }
                        const b64 = btoa(binary);

                        NovelsWorldDownload.postMessage(JSON.stringify({
                          type: 'chunk',
                          index: i,
                          data: b64
                        }));
                      }

                      NovelsWorldDownload.postMessage(JSON.stringify({
                        type: 'complete',
                        filename: filename
                      }));
                    } catch (err) {
                      NovelsWorldDownload.postMessage(JSON.stringify({
                        type: 'error',
                        message: err.toString(),
                        fallbackUrl: url,
                        fallbackMethod: method,
                        fallbackBody: postBody
                      }));
                    }
                  };

                  function bindFormsAndButtons() {
                    document.querySelectorAll('form').forEach(function(f) {
                      if (f.__nw_bound) return;
                      f.__nw_bound = true;
                      var act = (f.getAttribute('action') || '').toLowerCase();
                      var inner = (f.innerHTML || '').toLowerCase();
                      var isDl = act.includes('download') || act.includes('epub') || act.includes('pdf') ||
                                 inner.includes('download') || inner.includes('epub') || inner.includes('pdf') ||
                                 f.querySelector('button[type="submit"], input[type="submit"], .btn-download');
                      if (isDl) {
                        f.addEventListener('submit', function(e) {
                          try {
                            e.preventDefault();
                            var submitBtn = f.querySelector('button[type="submit"], input[type="submit"], input[type="image"], .btn-download, button');
                            if (submitBtn) {
                              submitBtn.disabled = true;
                              if (submitBtn.innerText) submitBtn.innerText = 'Downloading book...';
                            }
                            var formData = (e.submitter) ? new FormData(f, e.submitter) : new FormData(f);
                            var parts = [];
                            for (var pair of formData.entries()) {
                              parts.push(encodeURIComponent(pair[0]) + '=' + encodeURIComponent(pair[1]));
                            }
                            if (e.submitter && e.submitter.name && !formData.has(e.submitter.name)) {
                              parts.push(encodeURIComponent(e.submitter.name) + '=' + encodeURIComponent(e.submitter.value || '1'));
                            }
                            var bodyStr = parts.join('&');
                            var fullAction = f.action || window.location.href;
                            window.__nw_download(fullAction, (f.method || 'POST').toUpperCase(), bodyStr);
                          } catch (err) {
                            window.__nw_download(f.action || window.location.href, (f.method || 'POST').toUpperCase(), null);
                          }
                        });
                      }
                    });

                    document.querySelectorAll('a, button, input[type="button"], input[type="submit"]').forEach(function(el) {
                      if (el.__nw_btn_bound) return;
                      el.__nw_btn_bound = true;
                      var str = (el.innerText || el.value || el.href || el.getAttribute('download') || '').toLowerCase();
                      var isDlBtn = (str.includes('download') || str.includes('epub') || str.includes('pdf')) &&
                                    !str.includes('download app') && !str.includes('download chrome');
                      if (isDlBtn) {
                        el.addEventListener('click', function(e) {
                          var form = el.closest('form');
                          if (!form && el.href && (el.href.startsWith('http') || el.href.startsWith('/'))) {
                            var targetUrl = el.href.startsWith('http') ? el.href : new URL(el.href, window.location.origin).href;
                            if (targetUrl.includes('.epub') || targetUrl.includes('.pdf') || targetUrl.includes('download')) {
                              e.preventDefault();
                              window.__nw_download(targetUrl, 'GET', null);
                            }
                          }
                        });
                      }
                    });
                  }

                  bindFormsAndButtons();
                  setInterval(bindFormsAndButtons, 1500);
                })();
              ''');
            } catch (_) {}
          },
          onWebResourceError: (error) {
            // Silently handle non-fatal web resource errors
          },
          onNavigationRequest: (NavigationRequest request) {
            final urlLower = request.url.toLowerCase();
            if (urlLower.endsWith('.epub') ||
                urlLower.endsWith('.pdf') ||
                urlLower.contains('.epub?') ||
                urlLower.contains('.pdf?') ||
                urlLower.contains('/download/epub') ||
                urlLower.contains('epub-download') ||
                urlLower.contains('/get.php?md5=') ||
                urlLower.contains('/dl/') ||
                urlLower.contains('/download/file') ||
                urlLower.contains('download_file') ||
                urlLower.contains('/download-file') ||
                urlLower.contains('download-file') ||
                urlLower.contains('?download=') ||
                urlLower.contains('&download=') ||
                urlLower.contains('attachment') ||
                (urlLower.contains('download') && (urlLower.contains('hash=') || urlLower.contains('token=')))) {
              _startInWebViewDownload(request.url, method: 'GET');
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));

    // Monitor for clearance resolution and sync cookies continuously
    _clearancePollTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      if (!mounted) return;
      try {
        final currentUrl = await _controller.currentUrl();
        if (currentUrl == null || currentUrl.isEmpty) return;
        await _syncCookies(currentUrl);

        final title = await _controller.getTitle() ?? '';
        if (mounted && title.isNotEmpty && title != _pageTitle) {
          setState(() {
            _pageTitle = title;
          });
        }
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _clearancePollTimer?.cancel();
    try {
      _inFlightDownloadSink?.close();
    } catch (_) {}
    super.dispose();
  }

  void _showDownloadProgressSnackBar(String message) {
    if (!mounted) return;
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.hideCurrentSnackBar();
    scaffold.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        duration: const Duration(seconds: 30),
      ),
    );
  }

  void _showDownloadError(String message) {
    if (!mounted) return;
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.hideCurrentSnackBar();
    scaffold.showSnackBar(
      SnackBar(
        content: Text('Failed to import book: $message'),
        backgroundColor: Colors.redAccent,
        duration: const Duration(seconds: 6),
      ),
    );
    setState(() {
      _isHandlingDownload = false;
    });
  }

  Future<void> _startInWebViewDownload(String url, {String method = 'GET', String? postBody}) async {
    if (_isHandlingDownload) return;
    _isHandlingDownload = true;
    _showDownloadProgressSnackBar('Connecting to book server via browser session...');

    final escapedUrl = jsonEncode(url);
    final escapedMethod = jsonEncode(method);
    final escapedBody = postBody != null ? jsonEncode(postBody) : 'null';

    try {
      await _controller.runJavaScript('window.__nw_download($escapedUrl, $escapedMethod, $escapedBody);');
    } catch (_) {
      // If JS execution failed, fallback to native HTTP client
      _handleEpubDownload(url, method: method, postBody: postBody);
    }
  }

  Future<void> _processDownloadedFile(File file, {String? filename}) async {
    final scaffold = ScaffoldMessenger.of(context);
    try {
      _showDownloadProgressSnackBar('Extracting & importing novel into library...');
      final novel = await EpubService().importBook(
        file,
        originalNovel: widget.targetNovel,
      );
      if (mounted) {
        await context.read<LibraryProvider>().saveToLibrary(novel);
        if (!mounted) return;
        scaffold.hideCurrentSnackBar();
        scaffold.showSnackBar(
          SnackBar(
            content: Text('Successfully imported "${novel.title}"!'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showDownloadError('$e');
    } finally {
      if (mounted) {
        setState(() {
          _isHandlingDownload = false;
        });
      }
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {}
    }
  }

  Future<void> _handleEpubDownload(String url, {String method = 'GET', String? postBody}) async {
    if (_isHandlingDownload) return;
    _isHandlingDownload = true;
    _showDownloadProgressSnackBar('Streaming & importing book...');

    final scaffold = ScaffoldMessenger.of(context);
    try {
      final headers = <String, String>{
        'User-Agent': WebViewSessionManager.defaultUserAgent,
      };
      final cookies = WebViewSessionManager.instance.getCookieHeader(url);
      if (cookies != null && cookies.isNotEmpty) {
        headers['Cookie'] = cookies;
      }

      final novel = await EpubService().importEpubFromUrl(
        url,
        method: method,
        body: postBody,
        headers: headers,
        originalNovel: widget.targetNovel,
      );
      if (mounted) {
        await context.read<LibraryProvider>().saveToLibrary(novel);
        if (!mounted) return;
        scaffold.hideCurrentSnackBar();
        scaffold.showSnackBar(
          SnackBar(
            content: Text('Successfully imported "${novel.title}"!'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 4),
          ),
        );
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showDownloadError('$e');
    } finally {
      if (mounted) {
        setState(() {
          _isHandlingDownload = false;
        });
      }
    }
  }

  Future<void> _syncCookies(String url) async {
    try {
      await WebViewSessionManager.instance.syncCookiesFromWebView(url);

      // Also try reading non-HttpOnly cookies via JavaScript
      try {
        final jsCookie = await _controller.runJavaScriptReturningResult('document.cookie');
        if (jsCookie is String && jsCookie.isNotEmpty && jsCookie != '""') {
          final clean = jsCookie.replaceAll(RegExp(r'^"|"$'), '').trim();
          if (clean.isNotEmpty) {
            await WebViewSessionManager.instance.saveCookies(url, clean);
          }
        }
      } catch (_) {}

      final header = WebViewSessionManager.instance.getCookieHeader(url);
      if (header != null && header.isNotEmpty && mounted) {
        final count = header.split(';').length;
        setState(() {
          _cookieCount = count;
          _hasSyncedCookies = true;
        });
      }
    } catch (_) {}
  }

  Future<void> _saveAndReturn() async {
    final currentUrl = await _controller.currentUrl() ?? widget.initialUrl;
    await _syncCookies(currentUrl);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Session saved for ${widget.sourceName} ($_cookieCount cookies)'),
          duration: const Duration(seconds: 2),
          backgroundColor: const Color(0xFF10B981),
        ),
      );
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isCloudflare = _pageTitle.toLowerCase().contains('just a moment') ||
        _pageTitle.toLowerCase().contains('attention required') ||
        _pageTitle.toLowerCase().contains('cloudflare');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final currentUrl = await _controller.currentUrl() ?? widget.initialUrl;
        await _syncCookies(currentUrl);
        if (await _controller.canGoBack()) {
          await _controller.goBack();
        } else {
          if (context.mounted) {
            Navigator.pop(context, _hasSyncedCookies);
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final currentUrl = await _controller.currentUrl() ?? widget.initialUrl;
              await _syncCookies(currentUrl);
              if (context.mounted) {
                Navigator.pop(context, _hasSyncedCookies);
              }
            },
          ),
          titleSpacing: 0,
          title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.sourceName,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Text(
                isCloudflare
                    ? 'Cloudflare Challenge Detected - Please Solve'
                    : (_pageTitle.isNotEmpty ? _pageTitle : widget.initialUrl),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: isCloudflare ? Colors.amberAccent : Colors.white60,
                ),
              ),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh, size: 20),
              tooltip: 'Reload',
              onPressed: () => _controller.reload(),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilledButton.icon(
                onPressed: _saveAndReturn,
                icon: const Icon(Icons.check, size: 16),
                label: const Text('Save & Return', style: TextStyle(fontSize: 12)),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF8B5CF6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ),
          ],
          bottom: _isLoading
              ? PreferredSize(
                  preferredSize: const Size.fromHeight(2),
                  child: LinearProgressIndicator(
                    value: _loadingProgress / 100.0,
                    backgroundColor: Colors.transparent,
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF8B5CF6)),
                  ),
                )
              : null,
        ),
        body: Column(
          children: [
            if (isCloudflare)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: Colors.amber.withValues(alpha: 0.2),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline, size: 16, color: Colors.amberAccent),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Solve the verification on the page below, then tap "Save & Return".',
                        style: TextStyle(fontSize: 12, color: Colors.amberAccent),
                      ),
                    ),
                  ],
                ),
              ),
            Expanded(
              child: WebViewWidget(controller: _controller),
            ),
          ],
        ),
      ),
    );
  }
}

