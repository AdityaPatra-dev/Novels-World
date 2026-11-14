import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/novel.dart';
import '../../core/models/chapter.dart';
import '../../core/utils/text_cleaner.dart';
import '../../core/services/webview_session_manager.dart';
import '../../tts/language_voice_registry.dart';
import '../../providers/audiobook_player_provider.dart';

class AudiobookPlayerScreen extends StatelessWidget {
  final Novel? novel;
  final Chapter? initialChapter;
  final String? language;

  const AudiobookPlayerScreen({
    super.key,
    this.novel,
    this.initialChapter,
    this.language,
  });

  static void open(
    BuildContext context, {
    required Novel novel,
    required Chapter chapter,
    required String language,
    List<Chapter>? allChapters,
  }) {
    final provider = context.read<AudiobookPlayerProvider>();
    provider.playAudiobook(
      novel: novel,
      chapter: chapter,
      language: language,
      allChapters: allChapters,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (ctx) => AudiobookPlayerScreen(
          novel: novel,
          initialChapter: chapter,
          language: language,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<AudiobookPlayerProvider>();
    final activeNovel = player.currentNovel ?? novel;
    final activeChapter = player.currentChapter ?? initialChapter;
    final activeLang = player.currentLanguage.isNotEmpty ? player.currentLanguage : (language ?? 'en');

    if (activeNovel == null || activeChapter == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0E0E14),
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: const Center(
          child: Text('No Audiobook Loaded', style: TextStyle(color: Colors.white70)),
        ),
      );
    }

    final langConfig = LanguageVoiceRegistry.getByCode(activeLang);

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E14),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28, color: Colors.white),
          tooltip: 'Minimize Player',
          onPressed: () => Navigator.pop(context),
        ),
        title: Column(
          children: [
            const Text(
              'PLAYING AUDIOBOOK',
              style: TextStyle(fontSize: 10, letterSpacing: 1.2, fontWeight: FontWeight.bold, color: Color(0xFFA78BFA)),
            ),
            const SizedBox(height: 2),
            Text(
              TextCleaner.cleanNovelTitle(activeNovel.title),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.queue_music_rounded, color: Colors.white),
            tooltip: 'Chapter Playlist',
            onPressed: () => _openPlaylistSheet(context, player),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // 1. Cover Artwork
              const Spacer(),
              Center(
                child: Container(
                  width: 260,
                  height: 260,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.25),
                        blurRadius: 30,
                        spreadRadius: 2,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: _buildCoverImage(activeNovel.coverUrl),
                  ),
                ),
              ),
              const Spacer(),

              // 2. Chapter Title & Metadata
              Column(
                children: [
                  Text(
                    activeChapter.title,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    activeNovel.author,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13, color: Colors.white60),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(langConfig.flag, style: const TextStyle(fontSize: 12)),
                        const SizedBox(width: 6),
                        Text(
                          '${langConfig.englishName} • Offline AI Voice',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFFA78BFA)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // 3. Scrubber Bar
              _buildScrubberBar(player),

              // 4. Primary Playback Controls
              _buildPrimaryControls(player),

              const SizedBox(height: 12),

              // 5. Secondary Utility Controls: Speed dial & Sleep timer
              _buildSecondaryControls(context, player),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCoverImage(String coverUrl) {
    if (coverUrl.isEmpty || !TextCleaner.isValidCoverUrl(coverUrl)) {
      return Container(
        color: const Color(0xFF1E1E2C),
        child: const Icon(Icons.headphones_rounded, size: 72, color: Color(0xFFA78BFA)),
      );
    }

    if (coverUrl.startsWith('file://')) {
      return Image.file(
        File(Uri.parse(coverUrl).toFilePath()),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) => Container(
          color: const Color(0xFF1E1E2C),
          child: const Icon(Icons.headphones_rounded, size: 72, color: Color(0xFFA78BFA)),
        ),
      );
    }

    return Image.network(
      coverUrl,
      headers: {'User-Agent': WebViewSessionManager.defaultUserAgent},
      fit: BoxFit.cover,
      errorBuilder: (context, error, stackTrace) => Container(
        color: const Color(0xFF1E1E2C),
        child: const Icon(Icons.headphones_rounded, size: 72, color: Color(0xFFA78BFA)),
      ),
    );
  }

  Widget _buildScrubberBar(AudiobookPlayerProvider player) {
    final pos = player.position;
    final dur = player.duration;
    final maxMs = dur.inMilliseconds > 0 ? dur.inMilliseconds.toDouble() : 1.0;
    final currentMs = pos.inMilliseconds.toDouble().clamp(0.0, maxMs);

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: const Color(0xFFA78BFA),
            inactiveTrackColor: Colors.white12,
            thumbColor: Colors.white,
            overlayColor: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
          ),
          child: Slider(
            value: currentMs,
            min: 0.0,
            max: maxMs,
            onChanged: (val) {
              player.seek(Duration(milliseconds: val.toInt()));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(_formatDuration(pos), style: const TextStyle(fontSize: 11, color: Colors.white60)),
              Text(_formatDuration(dur), style: const TextStyle(fontSize: 11, color: Colors.white60)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPrimaryControls(AudiobookPlayerProvider player) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        // Previous Chapter
        IconButton(
          icon: const Icon(Icons.skip_previous_rounded, size: 30, color: Colors.white70),
          tooltip: 'Previous Chapter',
          onPressed: () => player.playPreviousChapter(),
        ),

        // Rewind 15s
        IconButton(
          icon: const Icon(Icons.replay_10_rounded, size: 34, color: Colors.white),
          tooltip: 'Rewind 15s',
          onPressed: () => player.smartRewind(15),
        ),

        // Play/Pause Big Button
        GestureDetector(
          onTap: () => player.togglePlayPause(),
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF8B5CF6).withValues(alpha: 0.4),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                player.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                size: 38,
                color: Colors.white,
              ),
            ),
          ),
        ),

        // Forward 15s
        IconButton(
          icon: const Icon(Icons.forward_10_rounded, size: 34, color: Colors.white),
          tooltip: 'Forward 15s',
          onPressed: () => player.smartForward(15),
        ),

        // Next Chapter
        IconButton(
          icon: const Icon(Icons.skip_next_rounded, size: 30, color: Colors.white70),
          tooltip: 'Next Chapter',
          onPressed: () => player.playNextChapter(),
        ),
      ],
    );
  }

  Widget _buildSecondaryControls(BuildContext context, AudiobookPlayerProvider player) {
    final sleepRem = player.sleepTimerRemaining;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        // Speed dial
        TextButton.icon(
          onPressed: () => _openSpeedDialog(context, player),
          icon: const Icon(Icons.speed_rounded, size: 18, color: Color(0xFFA78BFA)),
          label: Text(
            '${player.speed}x',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFFA78BFA)),
          ),
          style: TextButton.styleFrom(
            backgroundColor: const Color(0xFF1B1B26),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),

        // Sleep timer with volume fade
        TextButton.icon(
          onPressed: () => _openSleepTimerSheet(context, player),
          icon: Icon(
            Icons.bedtime_rounded,
            size: 18,
            color: sleepRem != null ? const Color(0xFF34D399) : Colors.white70,
          ),
          label: Text(
            sleepRem != null ? _formatDuration(sleepRem) : 'Sleep Timer',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: sleepRem != null ? const Color(0xFF34D399) : Colors.white70,
            ),
          ),
          style: TextButton.styleFrom(
            backgroundColor: sleepRem != null
                ? const Color(0xFF10B981).withValues(alpha: 0.15)
                : const Color(0xFF1B1B26),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          ),
        ),
      ],
    );
  }

  void _openSpeedDialog(BuildContext context, AudiobookPlayerProvider player) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A26),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Playback Speed',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: speeds.map((s) {
                  final isSelected = player.speed == s;
                  return ChoiceChip(
                    label: Text('${s}x'),
                    selected: isSelected,
                    selectedColor: const Color(0xFF8B5CF6),
                    backgroundColor: const Color(0xFF14141E),
                    labelStyle: TextStyle(
                      color: isSelected ? Colors.white : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    onSelected: (_) {
                      player.setSpeed(s);
                      Navigator.pop(ctx);
                    },
                  );
                }).toList(),
              ),
            ],
          ),
        );
      },
    );
  }

  void _openSleepTimerSheet(BuildContext context, AudiobookPlayerProvider player) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A26),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final options = [
          {'label': 'Off', 'duration': null},
          {'label': '5 minutes', 'duration': const Duration(minutes: 5)},
          {'label': '15 minutes', 'duration': const Duration(minutes: 15)},
          {'label': '30 minutes', 'duration': const Duration(minutes: 30)},
          {'label': '45 minutes (with 45s volume fade)', 'duration': const Duration(minutes: 45)},
          {'label': '60 minutes', 'duration': const Duration(minutes: 60)},
        ];

        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.bedtime_rounded, color: Color(0xFFA78BFA), size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Sleep Timer (Audible Benchmark)',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                'Audio gradually fades down over the final 45 seconds before stopping.',
                style: TextStyle(fontSize: 11, color: Colors.white60),
              ),
              const SizedBox(height: 12),
              ...options.map((opt) {
                final d = opt['duration'] as Duration?;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(opt['label'] as String, style: const TextStyle(color: Colors.white, fontSize: 13.5)),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white38, size: 18),
                  onTap: () {
                    player.setSleepTimer(d);
                    Navigator.pop(ctx);
                  },
                );
              }),
            ],
          ),
        );
      },
    );
  }

  void _openPlaylistSheet(BuildContext context, AudiobookPlayerProvider player) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141E),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        final chapters = player.audioChapters;
        return Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Audiobook Chapters (${chapters.length})',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white70),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const Divider(color: Colors.white12),
              Expanded(
                child: ListView.builder(
                  itemCount: chapters.length,
                  itemBuilder: (context, idx) {
                    final ch = chapters[idx];
                    final isCurrent = player.currentChapter?.id == ch.id;

                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isCurrent ? Icons.headphones_rounded : Icons.radio_button_unchecked,
                        color: isCurrent ? const Color(0xFFA78BFA) : Colors.white38,
                        size: 20,
                      ),
                      title: Text(
                        ch.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                          color: isCurrent ? const Color(0xFFA78BFA) : Colors.white,
                        ),
                      ),
                      trailing: isCurrent && player.isPlaying
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFA78BFA)),
                            )
                          : null,
                      onTap: () {
                        player.playAudiobook(
                          novel: player.currentNovel!,
                          chapter: ch,
                          language: player.currentLanguage,
                          allChapters: chapters,
                        );
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (d.inHours > 0) {
      return '${d.inHours}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }
}
