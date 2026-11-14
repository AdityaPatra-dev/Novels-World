import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/utils/text_cleaner.dart';
import '../../core/services/webview_session_manager.dart';
import '../../providers/audiobook_player_provider.dart';
import '../audiobook/audiobook_player_screen.dart';

class AudiobookMiniPlayer extends StatelessWidget {
  const AudiobookMiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudiobookPlayerProvider>();

    if (!player.hasTrack) {
      return const SizedBox.shrink();
    }

    final novel = player.currentNovel!;
    final chapter = player.currentChapter!;
    final pos = player.position;
    final dur = player.duration;
    final progress = dur.inMilliseconds > 0 ? (pos.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0) : 0.0;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E2C),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.35)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top mini scrubber line
            LinearProgressIndicator(
              value: progress,
              backgroundColor: Colors.white10,
              color: const Color(0xFFA78BFA),
              minHeight: 2.5,
            ),
            InkWell(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (ctx) => AudiobookPlayerScreen(
                      novel: novel,
                      initialChapter: chapter,
                      language: player.currentLanguage,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    // Thumbnail
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 42,
                        height: 42,
                        color: const Color(0xFF14141E),
                        child: _buildThumbnail(novel.coverUrl),
                      ),
                    ),
                    const SizedBox(width: 10),

                    // Titles
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            chapter.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: Text(
                                  player.currentLanguage.toUpperCase(),
                                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Color(0xFFA78BFA)),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  TextCleaner.cleanNovelTitle(novel.title),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 11, color: Colors.white60),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // Play/Pause
                    IconButton(
                      icon: Icon(
                        player.isPlaying ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded,
                        color: const Color(0xFFA78BFA),
                        size: 32,
                      ),
                      onPressed: () => player.togglePlayPause(),
                    ),

                    // Close
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 18, color: Colors.white54),
                      onPressed: () => player.stop(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(String coverUrl) {
    if (coverUrl.isEmpty || !TextCleaner.isValidCoverUrl(coverUrl)) {
      return const Icon(Icons.headphones_rounded, size: 22, color: Color(0xFFA78BFA));
    }
    if (coverUrl.startsWith('file://')) {
      return Image.file(
        File(Uri.parse(coverUrl).toFilePath()),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.headphones_rounded, size: 22, color: Color(0xFFA78BFA)),
      );
    }
    return Image.network(
      coverUrl,
      headers: {'User-Agent': WebViewSessionManager.defaultUserAgent},
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => const Icon(Icons.headphones_rounded, size: 22, color: Color(0xFFA78BFA)),
    );
  }
}
