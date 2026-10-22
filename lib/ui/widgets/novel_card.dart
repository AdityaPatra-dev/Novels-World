import 'dart:io';
import 'package:flutter/material.dart';
import '../../core/models/novel.dart';
import '../../core/services/webview_session_manager.dart';

import 'package:flutter/services.dart';
import 'source_webview_screen.dart';
import 'novel_storage_modal.dart';

class NovelCard extends StatelessWidget {
  final Novel novel;
  final VoidCallback onTap;

  const NovelCard({
    super.key,
    required this.novel,
    required this.onTap,
  });

  String get _sanitizedCoverUrl {
    var url = novel.coverUrl.trim();
    if (url.isEmpty) return '';
    if (url.startsWith('//')) {
      url = 'https:$url';
    }
    if (url.startsWith('/')) {
      final origin = Uri.tryParse(novel.sourceUrl)?.origin;
      if (origin != null && origin.isNotEmpty) {
        url = '$origin$url';
      }
    }
    url = url.replaceAll(RegExp(r'render_js.*$'), '');
    if (url.contains('dflazy.jpg') || url.contains('placeholder') || url.startsWith('data:')) {
      return '';
    }
    try {
      final uri = Uri.parse(url);
      url = uri.toString();
    } catch (_) {
      url = Uri.encodeFull(url);
    }
    return url;
  }

  Map<String, String> get _imageHeaders {
    final headers = <String, String>{
      'User-Agent': WebViewSessionManager.defaultUserAgent,
      'Accept': 'image/avif,image/webp,image/apng,image/svg+xml,image/*,*/*;q=0.8',
    };
    if (novel.sourceUrl.isNotEmpty) {
      final origin = Uri.tryParse(novel.sourceUrl)?.origin;
      if (origin != null && origin.isNotEmpty) {
        headers['Referer'] = '$origin/';
      }
    }
    final cookie = WebViewSessionManager.instance.getCookieHeader(novel.sourceUrl);
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }
    return headers;
  }

  @override
  Widget build(BuildContext context) {
    final cleanUrl = _sanitizedCoverUrl;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    color: const Color(0xFF1E1E28),
                    width: double.infinity,
                    height: double.infinity,
                    child: cleanUrl.isNotEmpty
                        ? (cleanUrl.startsWith('file://')
                            ? Image.file(
                                File(Uri.parse(cleanUrl).toFilePath()),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                              )
                            : Image.network(
                                cleanUrl,
                                headers: _imageHeaders,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                              ))
                        : _buildPlaceholder(),
                  ),
                ),
                // Top-Left: Novel Storage Folder Inspector
                Positioned(
                  top: 6,
                  left: 6,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.70),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: novel.sourceId == 'local_epub'
                            ? const Color(0xFF10B981).withValues(alpha: 0.5)
                            : const Color(0xFF8B5CF6).withValues(alpha: 0.5),
                        width: 0.6,
                      ),
                    ),
                    child: InkWell(
                      onTap: () => NovelStorageModal.show(context, novel),
                      borderRadius: BorderRadius.circular(6),
                      child: Tooltip(
                        message: 'View Storage Folder & Chapters',
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            novel.sourceId == 'local_epub'
                                ? Icons.folder_special_rounded
                                : Icons.folder_outlined,
                            size: 14,
                            color: novel.sourceId == 'local_epub'
                                ? const Color(0xFF34D399)
                                : const Color(0xFFA78BFA),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (novel.sourceUrl.isNotEmpty)
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: Colors.white24, width: 0.5),
                      ),
                      child: InkWell(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: novel.sourceUrl));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Copied novel link: ${novel.sourceUrl}'),
                              duration: const Duration(seconds: 2),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(6),
                        child: const Padding(
                          padding: EdgeInsets.all(4),
                          child: Icon(
                            Icons.link_rounded,
                            size: 14,
                            color: Color(0xFFA78BFA),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Text(
            novel.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              height: 1.15,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            novel.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
          if (novel.sourceUrl.isNotEmpty) ...[
            const SizedBox(height: 4),
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => SourceWebViewScreen(
                      initialUrl: novel.sourceUrl,
                      sourceName: novel.title,
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2.5),
                decoration: BoxDecoration(
                  color: const Color(0xFF262638),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                    width: 0.8,
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.link_rounded,
                      size: 11,
                      color: Color(0xFFA78BFA),
                    ),
                    const SizedBox(width: 3),
                    Expanded(
                      child: Text(
                        novel.sourceUrl,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 9.5,
                          color: Color(0xFFA78BFA),
                          decoration: TextDecoration.underline,
                          decorationColor: Color(0xFFA78BFA),
                        ),
                      ),
                    ),
                    const SizedBox(width: 3),
                    GestureDetector(
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: novel.sourceUrl));
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Copied link: ${novel.sourceUrl}'),
                            duration: const Duration(seconds: 2),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: const Tooltip(
                        message: 'Copy Link',
                        child: Icon(
                          Icons.copy_rounded,
                          size: 10,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                    GestureDetector(
                      onTap: () => NovelStorageModal.show(context, novel),
                      child: const Tooltip(
                        message: 'Storage Folder',
                        child: Icon(
                          Icons.folder_open_rounded,
                          size: 11,
                          color: Color(0xFFA78BFA),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlaceholder() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF242436),
            const Color(0xFF14141E),
          ],
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: 32,
            color: const Color(0xFF8B5CF6).withValues(alpha: 0.7),
          ),
          const SizedBox(height: 8),
          Text(
            novel.title,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: Colors.white70,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
