import 'package:flutter/material.dart';
import '../../core/models/novel.dart';
import '../../core/services/webview_session_manager.dart';

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
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                color: const Color(0xFF1E1E28),
                width: double.infinity,
                child: cleanUrl.isNotEmpty
                    ? Image.network(
                        cleanUrl,
                        headers: _imageHeaders,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
                      )
                    : _buildPlaceholder(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            novel.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            novel.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withValues(alpha: 0.6),
            ),
          ),
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
