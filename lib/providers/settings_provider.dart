import 'package:flutter/material.dart';
import '../core/models/reader_settings.dart';
import '../data/storage_service.dart';

class SettingsProvider extends ChangeNotifier {
  final StorageService _storage;
  late ReaderSettings _settings;

  SettingsProvider(this._storage) {
    _settings = _storage.getSettings();
  }

  ReaderSettings get settings => _settings;

  Future<void> updateTheme(ReaderTheme theme) async {
    _settings = _settings.copyWith(theme: theme);
    notifyListeners();
    await _storage.saveSettings(_settings);
  }

  Future<void> updateFontSize(double size) async {
    final clamped = size.clamp(12.0, 36.0);
    _settings = _settings.copyWith(fontSize: clamped);
    notifyListeners();
    await _storage.saveSettings(_settings);
  }

  Future<void> updateLineHeight(double height) async {
    final clamped = height.clamp(1.2, 2.5);
    _settings = _settings.copyWith(lineHeight: clamped);
    notifyListeners();
    await _storage.saveSettings(_settings);
  }

  Future<void> updateFontFamily(String family) async {
    _settings = _settings.copyWith(fontFamily: family);
    notifyListeners();
    await _storage.saveSettings(_settings);
  }

  Future<void> updateTtsVoice(String engine, String voice) async {
    _settings = _settings.copyWith(ttsEngine: engine, ttsVoice: voice);
    notifyListeners();
    await _storage.saveSettings(_settings);
  }

  Future<void> updateTtsSpeed(double speed) async {
    _settings = _settings.copyWith(ttsSpeed: speed.clamp(0.5, 3.0));
    notifyListeners();
    await _storage.saveSettings(_settings);
  }
}

