library;

/// Stub implementation for non-web platforms (Android, iOS, Desktop).
/// Guarantees that dart:js_interop is never loaded or referenced on native mobile.

void playWebSpeech(
  String text, {
  String? voice,
  double rate = 1.0,
  double pitch = 1.0,
  bool isSequential = false,
  required void Function() onDone,
}) {
  onDone();
}

void stopWebSpeech() {}

void queueNextWebSpeech(
  String text, {
  String? voice,
  double rate = 1.0,
  double pitch = 1.0,
  required void Function() onStarted,
  required void Function() onDone,
}) {}

void pauseWebSpeech() {}

void resumeWebSpeech() {}

List<Map<String, String>> getWebVoices() => const [];
