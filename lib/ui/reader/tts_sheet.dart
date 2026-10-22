import 'package:flutter/material.dart';
import '../../tts/sleep_timer_service.dart';
import '../../tts/ring_buffer_manager.dart';
import '../../tts/tts_model_registry.dart';
import '../../providers/settings_provider.dart';

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
    SettingsProvider settingsProvider,
  ) {
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
              const Text(
                'Select Neural TTS Engine',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
              ),
              const SizedBox(height: 6),
              Text(
                'Switch instantly between the 3 specialized novel narrator models:',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 16),
              ...TtsModelRegistry.models.map((model) {
                final isSelected = ttsManager.activeEngine.id == model.id;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFF8B5CF6).withValues(alpha: 0.15)
                        : const Color(0xFF1E1E28),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected ? const Color(0xFF8B5CF6) : Colors.white12,
                      width: isSelected ? 1.5 : 1.0,
                    ),
                  ),
                  child: ListTile(
                    title: Text(
                      model.name,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          model.category,
                          style: const TextStyle(fontSize: 11, color: Color(0xFF8B5CF6)),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          model.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle, color: Color(0xFF8B5CF6))
                        : const Icon(Icons.circle_outlined, color: Colors.white24),
                    onTap: () {
                      ttsManager.switchEngine(model.id);
                      ttsManager.setVoice(model.defaultVoice);
                      settingsProvider.updateTtsVoice(model.id, model.defaultVoice);
                      Navigator.pop(context);
                    },
                  ),
                );
              }),
            ],
          ),
        );
      },
    );
  }
}

