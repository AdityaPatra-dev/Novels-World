import 'dart:async';
import 'package:flutter/foundation.dart';

enum SleepTimerMode {
  off,
  minutes15,
  minutes30,
  minutes45,
  minutes60,
  endOfChapter,
}

class SleepTimerService extends ChangeNotifier {
  SleepTimerMode _mode = SleepTimerMode.off;
  int _remainingSeconds = 0;
  Timer? _timer;
  VoidCallback? onTimerExpired;
  Function(double volume)? onVolumeFade;

  SleepTimerMode get mode => _mode;
  int get remainingSeconds => _remainingSeconds;
  bool get isActive => _mode != SleepTimerMode.off && _remainingSeconds > 0;

  String get formattedRemaining {
    if (!isActive) return 'Off';
    final m = _remainingSeconds ~/ 60;
    final s = _remainingSeconds % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  void setMode(SleepTimerMode mode) {
    _timer?.cancel();
    _mode = mode;

    switch (mode) {
      case SleepTimerMode.off:
        _remainingSeconds = 0;
        onVolumeFade?.call(1.0);
        break;
      case SleepTimerMode.minutes15:
        _remainingSeconds = 15 * 60;
        break;
      case SleepTimerMode.minutes30:
        _remainingSeconds = 30 * 60;
        break;
      case SleepTimerMode.minutes45:
        _remainingSeconds = 45 * 60;
        break;
      case SleepTimerMode.minutes60:
        _remainingSeconds = 60 * 60;
        break;
      case SleepTimerMode.endOfChapter:
        // Handled dynamically when chapter completes
        _remainingSeconds = 999999;
        break;
    }

    if (mode != SleepTimerMode.off && mode != SleepTimerMode.endOfChapter) {
      _startCountdown();
    }
    notifyListeners();
  }

  void _startCountdown() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 1) {
        _remainingSeconds--;

        // Smooth volume fade-out over the final 60 seconds
        if (_remainingSeconds <= 60) {
          final volume = (_remainingSeconds / 60.0).clamp(0.0, 1.0);
          onVolumeFade?.call(volume);
        } else {
          onVolumeFade?.call(1.0);
        }

        notifyListeners();
      } else {
        _remainingSeconds = 0;
        _mode = SleepTimerMode.off;
        timer.cancel();
        onVolumeFade?.call(0.0);
        notifyListeners();
        onTimerExpired?.call();
      }
    });
  }

  void triggerEndOfChapter() {
    if (_mode == SleepTimerMode.endOfChapter) {
      _mode = SleepTimerMode.off;
      _remainingSeconds = 0;
      notifyListeners();
      onTimerExpired?.call();
    }
  }

  void cancel() {
    _timer?.cancel();
    _mode = SleepTimerMode.off;
    _remainingSeconds = 0;
    onVolumeFade?.call(1.0);
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

