import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../providers/reader_provider.dart';
import '../../providers/settings_provider.dart';
import 'reader_settings_modal.dart';
import 'tts_sheet.dart';

class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key});

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  final ScrollController _scrollController = ScrollController();
  bool _showFloatingTts = false;

  void _showSettings() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => const ReaderSettingsModal(),
    );
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reader = context.watch<ReaderProvider>();
    final settingsProvider = context.watch<SettingsProvider>();
    final settings = settingsProvider.settings;

    final chapter = reader.currentChapter;
    final content = reader.content;
    final ttsManager = reader.ttsManager;
    final sleepTimer = ttsManager.sleepTimer;

    TextStyle baseTextStyle;
    try {
      baseTextStyle = GoogleFonts.getFont(
        settings.fontFamily,
        fontSize: settings.fontSize,
        height: settings.lineHeight,
        color: settings.textColor,
      );
    } catch (_) {
      baseTextStyle = TextStyle(
        fontSize: settings.fontSize,
        height: settings.lineHeight,
        color: settings.textColor,
      );
    }

    final isTtsActive = reader.isTtsPlaying || _showFloatingTts;

    return Scaffold(
      backgroundColor: settings.backgroundColor,
      appBar: AppBar(
        backgroundColor: settings.backgroundColor.withValues(alpha: 0.95),
        elevation: 0,
        iconTheme: IconThemeData(color: settings.textColor),
        title: Text(
          chapter?.title ?? 'Reader',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: settings.textColor,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: Icon(
              reader.isTtsPlaying ? Icons.record_voice_over : Icons.record_voice_over_outlined,
              color: reader.isTtsPlaying ? const Color(0xFF8B5CF6) : settings.textColor,
            ),
            tooltip: reader.isTtsPlaying ? 'Audio Playing' : 'Listen via TTS',
            onPressed: () {
              setState(() {
                _showFloatingTts = !_showFloatingTts;
              });
              if (!_showFloatingTts && reader.isTtsPlaying) {
                reader.toggleTtsPlayback();
              } else if (_showFloatingTts && !reader.isTtsPlaying) {
                reader.toggleTtsPlayback();
              }
            },
          ),
          IconButton(
            icon: const Icon(Icons.format_size),
            tooltip: 'Reading Settings',
            onPressed: _showSettings,
          ),
        ],
      ),
      body: Stack(
        children: [
          if (reader.isLoading)
            Center(
              child: CircularProgressIndicator(color: settings.textColor),
            )
          else if (reader.errorMessage != null)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
                    const SizedBox(height: 12),
                    Text(
                      reader.errorMessage!,
                      style: TextStyle(color: settings.textColor),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => reader.loadCurrentChapter(),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              ),
            )
          else if (content != null)
            ListView(
              controller: _scrollController,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 150),
              children: [
                // Chapter Header
                Padding(
                  padding: const EdgeInsets.only(bottom: 24, top: 8),
                  child: Text(
                    content.title,
                    style: baseTextStyle.copyWith(
                      fontSize: settings.fontSize + 6,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Interactive Paragraphs & Sentences (Tap to play from sentence)
                ..._buildInteractiveParagraphs(reader, settings, baseTextStyle),

                const SizedBox(height: 30),
                const Divider(color: Colors.white24),
                const SizedBox(height: 16),

                // Chapter Navigation Footer
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    ElevatedButton.icon(
                      onPressed: reader.hasPreviousChapter
                          ? () {
                              _scrollController.jumpTo(0);
                              reader.previousChapter();
                            }
                          : null,
                      icon: const Icon(Icons.arrow_back),
                      label: const Text('Previous'),
                    ),
                    ElevatedButton.icon(
                      onPressed: reader.hasNextChapter
                          ? () {
                              _scrollController.jumpTo(0);
                              reader.nextChapter();
                            }
                          : null,
                      icon: const Icon(Icons.arrow_forward),
                      label: const Text('Next Chapter'),
                    ),
                  ],
                ),
              ],
            ),

          // Floating Real-Time Neural TTS Player Bar
          if (isTtsActive)
            Positioned(
              left: 14,
              right: 14,
              bottom: 16,
              child: Card(
                elevation: 12,
                color: const Color(0xFF14141E).withValues(alpha: 0.98),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                  side: const BorderSide(color: Color(0xFF8B5CF6), width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Top Row: Engine Tag & Sleep Timer
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          InkWell(
                            onTap: () => TtsSheet.showVoiceSwitcherModal(context, ttsManager, settingsProvider),
                            borderRadius: BorderRadius.circular(8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.5)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.psychology, size: 14, color: Color(0xFF8B5CF6)),
                                  const SizedBox(width: 6),
                                  Text(
                                    ttsManager.activeEngine.name.split(' ').first,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const Icon(Icons.arrow_drop_down, size: 14, color: Colors.white70),
                                ],
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              // Speed Cycle Chip
                              InkWell(
                                onTap: () {
                                  const speeds = [0.75, 1.0, 1.25, 1.5, 2.0];
                                  final idx = speeds.indexOf(ttsManager.speed);
                                  final nextSpeed = speeds[(idx + 1) % speeds.length];
                                  ttsManager.setSpeed(nextSpeed);
                                },
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${ttsManager.speed}x',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),

                              // Sleep Timer Chip
                              InkWell(
                                onTap: () => TtsSheet.showSleepTimerModal(context, sleepTimer),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: sleepTimer.isActive
                                        ? Colors.purple.withValues(alpha: 0.3)
                                        : Colors.white10,
                                    borderRadius: BorderRadius.circular(8),
                                    border: sleepTimer.isActive
                                        ? Border.all(color: Colors.purpleAccent, width: 1)
                                        : null,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.timer_outlined,
                                        size: 13,
                                        color: sleepTimer.isActive ? Colors.purpleAccent : Colors.white70,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        sleepTimer.isActive ? sleepTimer.formattedRemaining : 'Timer',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: sleepTimer.isActive ? Colors.purpleAccent : Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Bottom Row: Audio Controls & Sentence Index
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  reader.sentences.isNotEmpty
                                      ? 'Sentence ${reader.activeSentenceIndex + 1} of ${reader.sentences.length}'
                                      : 'Preparing sentences...',
                                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                                ),
                                if (ttsManager.isBuffering)
                                  const Text(
                                    'Synthesizing next sentence...',
                                    style: TextStyle(fontSize: 10, color: Color(0xFF06B6D4)),
                                  ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_previous, color: Colors.white),
                            tooltip: 'Previous Sentence',
                            onPressed: () => ttsManager.skipPrevious(),
                          ),
                          IconButton(
                            icon: Icon(
                              reader.isTtsPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                              color: const Color(0xFF8B5CF6),
                              size: 38,
                            ),
                            tooltip: reader.isTtsPlaying ? 'Pause' : 'Play',
                            onPressed: () => reader.toggleTtsPlayback(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.skip_next, color: Colors.white),
                            tooltip: 'Next Sentence',
                            onPressed: () => ttsManager.skipNext(),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, size: 18, color: Colors.white54),
                            tooltip: 'Hide Player',
                            onPressed: () {
                              reader.stopTts();
                              setState(() {
                                _showFloatingTts = false;
                              });
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _buildInteractiveParagraphs(
    ReaderProvider reader,
    dynamic settings,
    TextStyle baseTextStyle,
  ) {
    final paragraphs = reader.content?.paragraphs ?? [];
    final List<Widget> widgets = [];

    int sentenceCounter = 0;

    for (final paragraph in paragraphs) {
      final sentencesInPara = _splitIntoSentences(paragraph);

      widgets.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Wrap(
            children: sentencesInPara.map((s) {
              final sentenceIndex = sentenceCounter++;
              final isHighlighted = reader.isTtsPlaying && reader.activeSentenceIndex == sentenceIndex;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _showFloatingTts = true;
                  });
                  reader.playFromSentence(sentenceIndex);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                  decoration: BoxDecoration(
                    color: isHighlighted ? settings.highlightColor : Colors.transparent,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '$s ',
                    style: baseTextStyle.copyWith(
                      fontWeight: isHighlighted ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      );
    }

    return widgets;
  }

  List<String> _splitIntoSentences(String text) {
    final RegExp regex = RegExp(r'[^.!?]+(?:[.!?]+["' r"'\s]*)");
    final matches = regex.allMatches(text.trim());
    if (matches.isEmpty) return [text.trim()];

    final List<String> list = [];
    int lastEnd = 0;
    for (final m in matches) {
      final s = m.group(0)?.trim();
      if (s != null && s.isNotEmpty) {
        list.add(s);
      }
      lastEnd = m.end;
    }
    if (lastEnd < text.trim().length) {
      final rem = text.trim().substring(lastEnd).trim();
      if (rem.isNotEmpty) list.add(rem);
    }
    return list;
  }
}
