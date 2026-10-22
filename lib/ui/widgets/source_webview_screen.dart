import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../core/services/epub_service.dart';
import '../../core/services/webview_session_manager.dart';
import '../../providers/library_provider.dart';
import '../novel/novel_detail_screen.dart';

/// In-App WebView screen for resolving Cloudflare / bot-protection challenges,
/// logging into novel sources, or inspecting the live website directly.
/// Automatically captures clearance cookies and synchronizes them with native HTTP extractors.
class SourceWebViewScreen extends StatefulWidget {
  final String initialUrl;
  final String sourceName;

  const SourceWebViewScreen({
    super.key,
    required this.initialUrl,
    required this.sourceName,
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

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent(WebViewSessionManager.defaultUserAgent)
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
          },
          onWebResourceError: (error) {
            // Silently handle non-fatal web resource errors
          },
          onNavigationRequest: (NavigationRequest request) {
            final urlLower = request.url.toLowerCase();
            if (urlLower.endsWith('.epub') ||
                urlLower.contains('.epub?') ||
                urlLower.contains('/download/epub')) {
              _handleEpubDownload(request.url);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.initialUrl));
  }

  Future<void> _handleEpubDownload(String url) async {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Streaming & importing EPUB book...'),
          ],
        ),
        duration: Duration(seconds: 15),
      ),
    );

    try {
      final headers = <String, String>{
        'User-Agent': WebViewSessionManager.defaultUserAgent,
      };
      final cookies = WebViewSessionManager.instance.getCookieHeader(url);
      if (cookies != null && cookies.isNotEmpty) {
        headers['Cookie'] = cookies;
      }

      final novel = await EpubService().importEpubFromUrl(url, headers: headers);
      if (mounted) {
        await context.read<LibraryProvider>().saveToLibrary(novel);
        scaffold.hideCurrentSnackBar();
        scaffold.showSnackBar(
          SnackBar(
            content: Text('Successfully imported "${novel.title}"!'),
            backgroundColor: const Color(0xFF10B981),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Read Now',
              textColor: Colors.white,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => NovelDetailScreen(novel: novel)),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        scaffold.hideCurrentSnackBar();
        scaffold.showSnackBar(
          SnackBar(
            content: Text('Failed to import EPUB: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
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

