import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../tts/sleep_timer_service.dart';
import '../../tts/ring_buffer_manager.dart';
import '../../tts/tts_model_registry.dart';
import '../../tts/voice_calibration.dart';
import '../../tts/services/web_speech_interop.dart';
import '../../tts/language_voice_registry.dart';
import '../../providers/settings_provider.dart';
import 'language_selection_modal.dart';

class TtsSheet {
  static void showSleepTimerModal(BuildContext context, SleepTimerService sleepTimer) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF181822),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Sleep Timer',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  if (sleepTimer.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF8B5CF6)),
                      ),
                      child: Text(
                        sleepTimer.formattedRemaining,
                        style: const TextStyle(
                          color: Color(0xFF8B5CF6),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Audio volume smoothly fades out over the last 60 seconds.',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 16),
              _buildTimerOption(context, sleepTimer, SleepTimerMode.off, 'Off'),
              _buildTimerOption(context, sleepTimer, SleepTimerMode.minutes15, '15 Minutes'),
              _buildTimerOption(context, sleepTimer, SleepTimerMode.minutes30, '30 Minutes'),
              _buildTimerOption(context, sleepTimer, SleepTimerMode.minutes45, '45 Minutes'),
              _buildTimerOption(context, sleepTimer, SleepTimerMode.minutes60, '60 Minutes'),
              _buildTimerOption(context, sleepTimer, SleepTimerMode.endOfChapter, 'End of Current Chapter'),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  static Widget _buildTimerOption(
    BuildContext context,
    SleepTimerService timer,
    SleepTimerMode mode,
    String title,
  ) {
    final isSelected = timer.mode == mode;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        isSelected ? Icons.radio_button_checked : Icons.radio_button_off,
        color: isSelected ? const Color(0xFF8B5CF6) : Colors.white38,
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      onTap: () {
        timer.setMode(mode);
        Navigator.pop(context);
      },
    );
  }

  static void showVoiceSwitcherModal(
    BuildContext context,
    RingBufferManager ttsManager,
    SettingsProvider settingsProvider, {
    String? currentLanguage,
    void Function(String langCode)? onLanguageChanged,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) {
        String currentLang = currentLanguage ?? ttsManager.currentLanguage;

        return StatefulBuilder(
          builder: (context, setState) {
            final activeEngine = ttsManager.activeEngine;
            final activeVoice = ttsManager.activeVoice;
            final modelInfo = TtsModelRegistry.getModel(activeEngine.id);
            final langInfo = LanguageVoiceRegistry.getByCode(currentLang);
            final isEnglish = currentLang == 'en' || currentLang == 'en-us' || currentLang == 'en-gb';

            // Dynamically load voice profiles for the selected language
            final relevantProfiles = VoiceCalibration.getProfilesForLanguage(currentLang).where((p) {
              if (activeEngine.id == TtsModelRegistry.systemId) {
                return p.id.startsWith('system') || p.id == 'default';
              }
              return !p.id.startsWith('system');
            }).toList();

            final webVoices = kIsWeb ? getWebVoices() : const <Map<String, String>>[];
            final displayedWebVoices = webVoices.isNotEmpty
                ? webVoices
                : const [
                    {'name': 'Google US English', 'lang': 'en-US', 'gender': 'Female'},
                    {'name': 'Google UK English Female', 'lang': 'en-GB', 'gender': 'Female'},
                    {'name': 'Google UK English Male', 'lang': 'en-GB', 'gender': 'Male'},
                    {'name': 'Default System Voice', 'lang': 'en-US', 'gender': 'Neutral'},
                  ];

            return DraggableScrollableSheet(
              initialChildSize: 0.82,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
                  child: ListView(
                    controller: scrollController,
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
                      const Text(
                        'Audio & Voice Settings',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Choose an AI reading model and speaker calibrated for your language',
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
                      ),
                      const SizedBox(height: 14),

                      // Language Selector Bar
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1B1B28),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Text(langInfo.flag, style: const TextStyle(fontSize: 20)),
                                const SizedBox(width: 10),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Reading & Voice Language', style: TextStyle(fontSize: 10.5, color: Colors.white60)),
                                    Text(
                                      '${langInfo.englishName} (${langInfo.nativeName})',
                                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            TextButton.icon(
                              onPressed: () {
                                LanguageSelectionModal.show(
                                  context: context,
                                  currentLanguageCode: currentLang,
                                  isTranslationActive: currentLang != 'en',
                                  onLanguageSelected: (lang) {
                                    setState(() {
                                      currentLang = lang.code;
                                    });
                                    ttsManager.currentLanguage = lang.code;
                                    final defVoice = lang.defaultFemaleVoice.isNotEmpty
                                        ? lang.defaultFemaleVoice
                                        : (lang.defaultMaleVoice.isNotEmpty ? lang.defaultMaleVoice : 'en-US-JennyNeural');
                                    ttsManager.setVoice(defVoice);
                                    settingsProvider.updateTtsVoice(activeEngine.id, defVoice);
                                    onLanguageChanged?.call(lang.code);
                                  },
                                  onDisableTranslation: () {
                                    setState(() {
                                      currentLang = 'en';
                                    });
                                    ttsManager.currentLanguage = 'en';
                                    ttsManager.setVoice('en-US-ChristopherNeural');
                                    settingsProvider.updateTtsVoice(activeEngine.id, 'en-US-ChristopherNeural');
                                    onLanguageChanged?.call('en');
                                  },
                                );
                              },
                              icon: const Icon(Icons.language, size: 16, color: Color(0xFFA78BFA)),
                              label: const Text('Change', style: TextStyle(color: Color(0xFFA78BFA), fontSize: 12, fontWeight: FontWeight.bold)),
                              style: TextButton.styleFrom(
                                backgroundColor: const Color(0xFF8B5CF6).withValues(alpha: 0.15),
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Engine Section (Mobile: full engine selector; Web: browser audio banner)
                      if (!kIsWeb) ...[
                        const Text(
                          'AI Audio Model',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
                        ),
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: (isEnglish
                                ? TtsModelRegistry.models
                                : TtsModelRegistry.models.where((m) =>
                                    m.id == TtsModelRegistry.edgeNeuralId ||
                                    m.id == TtsModelRegistry.systemId)
                            ).map((m) {
                              final isSelected = activeEngine.id == m.id;
                              final modelLabel = m.id == TtsModelRegistry.edgeNeuralId
                                  ? (isEnglish ? 'Microsoft HD' : '${langInfo.englishName} Studio HD')
                                  : (m.id == TtsModelRegistry.systemId ? 'Device TTS' : m.name.split(' ').first);
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(modelLabel),
                                  selected: isSelected,
                                  selectedColor: const Color(0xFF8B5CF6),
                                  backgroundColor: const Color(0xFF1E1E28),
                                  labelStyle: TextStyle(
                                    color: isSelected ? Colors.white : Colors.white70,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 12,
                                  ),
                                  onSelected: (sel) {
                                    if (sel) {
                                      ttsManager.switchEngine(m.id);
                                      final targetVoice = m.id == TtsModelRegistry.systemId
                                          ? 'system_$currentLang'
                                          : (langInfo.defaultFemaleVoice.isNotEmpty ? langInfo.defaultFemaleVoice : m.defaultVoice);
                                      ttsManager.setVoice(targetVoice);
                                      settingsProvider.updateTtsVoice(m.id, targetVoice);
                                      setState(() {});
                                    }
                                  },
                                ),
                              );
                            }).toList(),
                          ),
                        ),

                        // Model explanation banner
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.auto_awesome, color: Color(0xFF8B5CF6), size: 18),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      isEnglish ? modelInfo.category : '${langInfo.englishName} Native Studio Model',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                        color: Color(0xFFA78BFA),
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      isEnglish
                                          ? modelInfo.description
                                          : 'High-definition neural AI speakers calibrated specifically for ${langInfo.englishName} (${langInfo.nativeName}) literature.',
                                      style: const TextStyle(fontSize: 11, color: Colors.white70, height: 1.3),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF8B5CF6).withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.3)),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.record_voice_over, color: Color(0xFF8B5CF6), size: 20),
                              const SizedBox(width: 10),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Browser AI & System Audio',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 13,
                                        color: Color(0xFFA78BFA),
                                      ),
                                    ),
                                    SizedBox(height: 3),
                                    Text(
                                      'Select from the full library of high-speed natural and system voices provided by your browser and operating system.',
                                      style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.3),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 18),

                      // Voice Profiles List
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Voice Cast & Persona',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
                          ),
                          Text(
                            kIsWeb ? '${displayedWebVoices.length} Voices' : '${relevantProfiles.length} Voices',
                            style: const TextStyle(fontSize: 11, color: Colors.white38),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (kIsWeb)
                        ...displayedWebVoices.map((v) {
                          final vName = v['name'] ?? '';
                          final vLang = v['lang'] ?? 'en-US';
                          final vGender = v['gender'] ?? 'Neutral';
                          final isSelected = activeVoice == vName ||
                              (activeVoice.isEmpty && vName == displayedWebVoices.first['name']) ||
                              (!displayedWebVoices.any((dv) => dv['name'] == activeVoice) && vName == displayedWebVoices.first['name']);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFF8B5CF6).withValues(alpha: 0.15)
                                  : const Color(0xFF1E1E28),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected ? const Color(0xFF8B5CF6) : Colors.white10,
                                width: isSelected ? 1.5 : 1.0,
                              ),
                            ),
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: vGender == 'Female'
                                    ? const Color(0xFFEC4899).withValues(alpha: 0.2)
                                    : vGender == 'Male'
                                        ? const Color(0xFF3B82F6).withValues(alpha: 0.2)
                                        : const Color(0xFF10B981).withValues(alpha: 0.2),
                                child: Icon(
                                  vGender == 'Female'
                                      ? Icons.female
                                      : vGender == 'Male'
                                          ? Icons.male
                                          : Icons.record_voice_over,
                                  size: 18,
                                  color: vGender == 'Female'
                                      ? const Color(0xFFEC4899)
                                      : vGender == 'Male'
                                          ? const Color(0xFF3B82F6)
                                          : const Color(0xFF10B981),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      vName,
                                      style: TextStyle(
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                        fontSize: 13,
                                        color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.white10,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      vLang,
                                      style: const TextStyle(fontSize: 10, color: Colors.white70),
                                    ),
                                  ),
                                ],
                              ),
                              subtitle: Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(
                                  vName.toLowerCase().contains('natural') || vName.toLowerCase().contains('online')
                                      ? 'Natural cloud voice'
                                      : 'Native system voice',
                                  style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.55)),
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(Icons.volume_up, color: Color(0xFF8B5CF6)),
                                tooltip: 'Preview Voice',
                                onPressed: () {
                                  playWebSpeech(
                                    'This is a preview of the $vName reading voice.',
                                    voice: vName,
                                    onDone: () {},
                                  );
                                },
                              ),
                              onTap: () {
                                ttsManager.setVoice(vName);
                                settingsProvider.updateTtsVoice(TtsModelRegistry.systemId, vName);
                                setState(() {});
                              },
                            ),
                          );
                        })
                      else
                        ...relevantProfiles.map((profile) {
                        final isSelected = activeVoice.contains(profile.id) ||
                            profile.displayName.contains(activeVoice) ||
                            activeVoice == profile.id;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? const Color(0xFF8B5CF6).withValues(alpha: 0.15)
                                : const Color(0xFF1E1E28),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected ? const Color(0xFF8B5CF6) : Colors.white10,
                              width: isSelected ? 1.5 : 1.0,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: profile.gender == 'Female'
                                  ? const Color(0xFFEC4899).withValues(alpha: 0.2)
                                  : profile.gender == 'Male'
                                      ? const Color(0xFF3B82F6).withValues(alpha: 0.2)
                                      : const Color(0xFF10B981).withValues(alpha: 0.2),
                              child: Icon(
                                profile.gender == 'Female'
                                    ? Icons.female
                                    : profile.gender == 'Male'
                                        ? Icons.male
                                        : Icons.record_voice_over,
                                size: 18,
                                color: profile.gender == 'Female'
                                    ? const Color(0xFFEC4899)
                                    : profile.gender == 'Male'
                                        ? const Color(0xFF3B82F6)
                                        : const Color(0xFF10B981),
                              ),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    profile.displayName,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                      fontSize: 13,
                                      color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.9),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white10,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    profile.accent,
                                    style: const TextStyle(fontSize: 10, color: Colors.white70),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                profile.description,
                                style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.55)),
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.volume_up, color: Color(0xFF8B5CF6)),
                              tooltip: 'Preview Voice',
                              onPressed: () {
                                ttsManager.previewVoice(profile.id);
                              },
                            ),
                            onTap: () {
                              ttsManager.setVoice(profile.id);
                              ttsManager.currentLanguage = currentLang;
                              settingsProvider.updateTtsVoice(activeEngine.id, profile.id);
                              setState(() {});
                            },
                          ),
                        );
                      }),

                      const SizedBox(height: 18),

                      // Natural Cadence / Inter-Sentence Pause Controls
                      const Text(
                        'Pacing & Breathing Pause',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _buildPauseChip('Seamless (0ms)', 0, ttsManager, () => setState(() {})),
                          const SizedBox(width: 8),
                          _buildPauseChip('Natural (100ms)', 100, ttsManager, () => setState(() {})),
                          const SizedBox(width: 8),
                          _buildPauseChip('Relaxed (250ms)', 250, ttsManager, () => setState(() {})),
                        ],
                      ),

                      const SizedBox(height: 18),

                      // Speech Rate Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Reading Speed', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70)),
                          Text('${ttsManager.speed.toStringAsFixed(2)}x', style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Slider(
                        value: ttsManager.speed,
                        min: 0.5,
                        max: 2.5,
                        divisions: 20,
                        activeColor: const Color(0xFF8B5CF6),
                        inactiveColor: Colors.white12,
                        onChanged: (val) {
                          ttsManager.setSpeed(val);
                          setState(() {});
                        },
                      ),

                      // Pitch Calibration Slider
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Voice Tone / Pitch', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white70)),
                          Text('${ttsManager.pitch.toStringAsFixed(2)}x', style: const TextStyle(color: Color(0xFF8B5CF6), fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Slider(
                        value: ttsManager.pitch,
                        min: 0.6,
                        max: 1.4,
                        divisions: 16,
                        activeColor: const Color(0xFF8B5CF6),
                        inactiveColor: Colors.white12,
                        onChanged: (val) {
                          ttsManager.setPitch(val);
                          setState(() {});
                        },
                      ),

                      const SizedBox(height: 16),

                      // Listen-to-Save Audiobook Toggle
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E1E28),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: ttsManager.saveTtsAsAudiobook
                                ? const Color(0xFF8B5CF6)
                                : Colors.white10,
                            width: ttsManager.saveTtsAsAudiobook ? 1.5 : 1.0,
                          ),
                        ),
                        child: SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          secondary: Icon(
                            Icons.bookmark_added,
                            color: ttsManager.saveTtsAsAudiobook
                                ? const Color(0xFF8B5CF6)
                                : Colors.white54,
                          ),
                          title: const Text(
                            'Save Listening as Offline Audiobook',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          subtitle: Text(
                            'Automatically stitches streamed audio into a permanent chapter .mp3 file for offline listening.',
                            style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
                          ),
                          activeThumbColor: const Color(0xFF8B5CF6),
                          value: ttsManager.saveTtsAsAudiobook,
                          onChanged: (val) {
                            ttsManager.saveTtsAsAudiobook = val;
                            settingsProvider.updateSaveTtsAsAudiobook(val);
                            setState(() {});
                          },
                        ),
                      ),

                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF8B5CF6),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        icon: const Icon(Icons.check),
                        label: const Text('Done & Apply Settings', style: TextStyle(fontWeight: FontWeight.bold)),
                        onPressed: () => Navigator.pop(context),
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  static Widget _buildPauseChip(
    String label,
    int ms,
    RingBufferManager manager,
    VoidCallback onUpdated,
  ) {
    final isSelected = manager.sentencePauseMs == ms;
    return Expanded(
      child: ChoiceChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: isSelected ? Colors.white : Colors.white70,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        selected: isSelected,
        selectedColor: const Color(0xFF8B5CF6),
        backgroundColor: const Color(0xFF1E1E28),
        onSelected: (sel) {
          if (sel) {
            manager.setSentencePause(ms);
            onUpdated();
          }
        },
      ),
    );
  }
}
