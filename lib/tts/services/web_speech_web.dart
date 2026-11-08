library;

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
