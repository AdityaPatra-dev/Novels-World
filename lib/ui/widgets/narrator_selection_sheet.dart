import 'dart:io';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import '../../tts/language_voice_registry.dart';
import '../../tts/services/edge_tts_client.dart';

/// Interactive Narrator Gallery allowing users to audition and sample every voice
/// with instant [▶ Play Sample] previews before downloading audiobooks.
class NarratorSelectionSheet extends StatefulWidget {
  final LanguageVoiceInfo language;
  final String currentVoice;
  final ValueChanged<String> onVoiceSelected;

  const NarratorSelectionSheet({
    super.key,
    required this.language,
    required this.currentVoice,
    required this.onVoiceSelected,
  });

  static Future<void> show({
    required BuildContext context,
    required LanguageVoiceInfo language,
    required String currentVoice,
    required ValueChanged<String> onVoiceSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => NarratorSelectionSheet(
        language: language,
        currentVoice: currentVoice,
        onVoiceSelected: onVoiceSelected,
      ),
    );
  }

  @override
  State<NarratorSelectionSheet> createState() => _NarratorSelectionSheetState();
}

class _NarratorSelectionSheetState extends State<NarratorSelectionSheet> {
  late String _selectedVoice;
  final AudioPlayer _samplePlayer = AudioPlayer();
  String? _previewingVoice;
  bool _isLoadingSample = false;

  @override
  void initState() {
    super.initState();
    _selectedVoice = widget.currentVoice;
    _samplePlayer.playerStateStream.listen((state) {
      if (state.processingState == ProcessingState.completed) {
        if (mounted) {
          setState(() {
            _previewingVoice = null;
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _samplePlayer.dispose();
    super.dispose();
  }

  Future<void> _playSample(String voice) async {
    if (_previewingVoice == voice) {
      await _samplePlayer.stop();
      setState(() {
        _previewingVoice = null;
      });
      return;
    }

    await _samplePlayer.stop();
    setState(() {
      _previewingVoice = voice;
      _isLoadingSample = true;
    });

    try {
      final cleanVoice = voice.split(' ').first.trim();
      final phrase = widget.language.samplePhrase;
      final bytes = await EdgeTtsClient.synthesizeToBytes(
        phrase,
        voice: cleanVoice,
        rate: '+0%',
        pitch: '+0Hz',
      );

      if (bytes != null && bytes.isNotEmpty && mounted) {
        final tempFile = File('${Directory.systemTemp.path}/sample_${cleanVoice.hashCode}.mp3');
        await tempFile.writeAsBytes(bytes);
        await _samplePlayer.setFilePath(tempFile.path);
        await _samplePlayer.play();
        setState(() {
          _isLoadingSample = false;
        });
      } else {
        if (mounted) {
          setState(() {
            _previewingVoice = null;
            _isLoadingSample = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _previewingVoice = null;
          _isLoadingSample = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final voices = widget.language.voices;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Choose Narrator (${widget.language.flag} ${widget.language.englishName})',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap [▶ Play Sample] to audition any narrator before downloading.',
            style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: voices.length,
              itemBuilder: (context, index) {
                final voice = voices[index];
                final isSelected = _selectedVoice == voice ||
                    _selectedVoice.startsWith(voice.split(' ').first);
                final isPlayingThis = _previewingVoice == voice;

                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF8B5CF6).withValues(alpha: 0.15)
                        : const Color(0xFF1E1E28),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF8B5CF6) : Colors.white10,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    leading: CircleAvatar(
                      backgroundColor: isSelected
                          ? const Color(0xFF8B5CF6)
                          : const Color(0xFF2A2A38),
                      child: Icon(
                        voice.contains('Female') ? Icons.face_3 : Icons.face,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    title: Text(
                      voice,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Sample Preview Button
                        IconButton(
                          icon: isPlayingThis
                              ? (_isLoadingSample
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF8B5CF6)),
                                    )
                                  : const Icon(Icons.pause_circle_filled, color: Color(0xFF8B5CF6), size: 28))
                              : const Icon(Icons.play_circle_fill, color: Colors.white70, size: 28),
                          tooltip: 'Play Sample',
                          onPressed: () => _playSample(voice),
                        ),
                        const SizedBox(width: 4),
                        // Checkmark
                        if (isSelected)
                          const Icon(Icons.check, color: Color(0xFF8B5CF6), size: 20),
                      ],
                    ),
                    onTap: () {
                      setState(() {
                        _selectedVoice = voice;
                      });
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF8B5CF6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                widget.onVoiceSelected(_selectedVoice);
                Navigator.pop(context);
              },
              child: const Text('Confirm Narrator', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
