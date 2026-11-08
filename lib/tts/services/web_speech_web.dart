library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:flutter/foundation.dart';

/// Web implementation utilizing the browser native Web Speech API
/// via window.novelsWorldTts bridge.

void playWebSpeech(
  String text, {
  String? voice,
  double rate = 1.0,
  double pitch = 1.0,
  bool isSequential = false,
  required void Function() onDone,
}) {
  try {
    final win = globalContext;
    final tts = win.getProperty('novelsWorldTts'.toJS) as JSObject?;
    if (tts != null) {
      final jsCallback = (() {
        onDone();
      }).toJS;

      tts.callMethodVarArgs(
        'speak'.toJS,
        [
          text.toJS,
          (voice ?? '').toJS,
          rate.toJS,
          pitch.toJS,
          jsCallback,
          isSequential.toJS,
        ],
      );
    } else {
      debugPrint('[WebSpeech] window.novelsWorldTts not found, calling onDone');
      onDone();
    }
  } catch (e) {
    debugPrint('[WebSpeech] playWebSpeech error: $e');
    onDone();
  }
}

void stopWebSpeech() {
  try {
    final win = globalContext;
    final tts = win.getProperty('novelsWorldTts'.toJS) as JSObject?;
    tts?.callMethod('stop'.toJS);
  } catch (_) {}
}

void queueNextWebSpeech(
  String text, {
  String? voice,
  double rate = 1.0,
  double pitch = 1.0,
  required void Function() onStarted,
  required void Function() onDone,
}) {
  try {
    final win = globalContext;
    final tts = win.getProperty('novelsWorldTts'.toJS) as JSObject?;
    if (tts != null) {
      final jsOnStarted = (() {
        onStarted();
      }).toJS;
      final jsOnDone = (() {
        onDone();
      }).toJS;

      tts.callMethodVarArgs(
        'queueNext'.toJS,
        [
          text.toJS,
          (voice ?? '').toJS,
          rate.toJS,
          pitch.toJS,
          jsOnStarted,
          jsOnDone,
        ],
      );
    }
  } catch (e) {
    debugPrint('[WebSpeech] queueNextWebSpeech error: $e');
  }
}

void pauseWebSpeech() {
  try {
    final win = globalContext;
    final tts = win.getProperty('novelsWorldTts'.toJS) as JSObject?;
    tts?.callMethod('pause'.toJS);
  } catch (_) {}
}

void resumeWebSpeech() {
  try {
    final win = globalContext;
    final tts = win.getProperty('novelsWorldTts'.toJS) as JSObject?;
    tts?.callMethod('resume'.toJS);
  } catch (_) {}
}

List<Map<String, String>> getWebVoices() {
  try {
    final win = globalContext;
    final tts = win.getProperty('novelsWorldTts'.toJS) as JSObject?;
    if (tts != null) {
      final jsStr = tts.callMethod('getVoicesJson'.toJS) as JSString?;
      if (jsStr != null) {
        final raw = jsonDecode(jsStr.toDart) as List<dynamic>;
        return raw.map((item) {
          final map = item as Map<String, dynamic>;
          return {
            'name': map['name']?.toString() ?? '',
            'lang': map['lang']?.toString() ?? 'en-US',
            'gender': map['gender']?.toString() ?? 'Neutral',
          };
        }).where((v) => v['name']!.isNotEmpty).toList();
      }
    }
  } catch (e) {
    debugPrint('[WebSpeech] getWebVoices error: $e');
  }
  return const [];
}
