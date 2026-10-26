import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:io';
import 'dart:typed_data';
import 'edge_drm.dart';

/// Direct high-performance WebSocket client for Microsoft Edge Neural TTS.
/// Provides pristine, studio-quality MP3 audio without third-party package issues,
/// eliminating 403 Forbidden handshake errors and raw byte corruption.
class EdgeTtsClient {
  static const String _baseUrl = 'speech.platform.bing.com/consumer/speech/synthesize/readaloud';
  static const String _wssUrl = 'wss://$_baseUrl/edge/v1';
  static const String _voiceListUrl = 'https://$_baseUrl/voices/list';

  static bool _clockCalibrated = false;

  /// Calibrates clock skew against Microsoft server Date header to prevent 403s.
  static Future<void> calibrateClock({bool force = false}) async {
    if (_clockCalibrated && !force) return;
    final client = HttpClient()..userAgent = null;
    try {
      final url = Uri.parse(
        '$_voiceListUrl?trustedclienttoken=${EdgeDrm.trustedClientToken}'
        '&Sec-MS-GEC=${EdgeDrm.generateSecMsGecV2()}'
        '&Sec-MS-GEC-Version=${EdgeDrm.secMsGecVersion}',
      );
      final request = await client.getUrl(url).timeout(const Duration(seconds: 5));
      request.headers.set('User-Agent',
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.3650.75 Safari/537.36 Edg/143.0.3650.75');
      request.headers.set('Authority', 'speech.platform.bing.com');
      final response = await request.close().timeout(const Duration(seconds: 5));
      final serverDate = response.headers.value('date');
      if (serverDate != null) {
        EdgeDrm.updateClockSkew(serverDate);
      }
      await response.drain<void>();
      _clockCalibrated = true;
    } catch (_) {
      // Best-effort clock calibration
    } finally {
      client.close();
    }
  }

  /// Synthesizes text into high-fidelity MP3 bytes via WebSocket.
  static Future<Uint8List?> synthesizeToBytes(
    String text, {
    required String voice,
    String rate = '+0%',
    String pitch = '+0Hz',
    String volume = '+0%',
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (text.trim().isEmpty) return null;

    for (int attempt = 0; attempt < 2; attempt++) {
      try {
        final bytes = await _performSynthesis(
          text,
          voice: voice,
          rate: rate,
          pitch: pitch,
          volume: volume,
        ).timeout(timeout);

        if (bytes != null && bytes.isNotEmpty) {
          return bytes;
        }
      } catch (e) {
        dev.log('Synthesis attempt $attempt failed: $e', name: 'EdgeTtsClient');
        if (attempt == 0) {
          await calibrateClock(force: true);
        }
      }
    }
    return null;
  }

  static Future<Uint8List?> _performSynthesis(
    String text, {
    required String voice,
    required String rate,
    required String pitch,
    required String volume,
  }) async {
    final gec = EdgeDrm.generateSecMsGecV2();
    final connectionId = EdgeDrm.generateUuidHex();
    final requestId = EdgeDrm.generateUuidHex();
    final muid = EdgeDrm.generateMuid();

    final wsUrlString = '$_wssUrl?TrustedClientToken=${EdgeDrm.trustedClientToken}'
        '&ConnectionId=$connectionId'
        '&Sec-MS-GEC=$gec'
        '&Sec-MS-GEC-Version=${EdgeDrm.secMsGecVersion}';

    final httpClient = HttpClient()..userAgent = null;
    WebSocket? ws;
    try {
      ws = await WebSocket.connect(
        wsUrlString,
        headers: {
          'Pragma': 'no-cache',
          'Cache-Control': 'no-cache',
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/143.0.3650.75 Safari/537.36 Edg/143.0.3650.75',
          'Origin': 'chrome-extension://jdiccldimpdaibmpdkjnbmckianbfold',
          'Accept-Encoding': 'gzip, deflate, br, zstd',
          'Accept-Language': 'en-US,en;q=0.9',
          'Cookie': 'muid=$muid;',
        },
        compression: CompressionOptions.compressionDefault,
        customClient: httpClient,
      );

      final timestamp = EdgeDrm.generateTimestamp();

      // 1. Send speech.config
      final configMsg = 'X-Timestamp:$timestamp\r\n'
          'Content-Type:application/json; charset=utf-8\r\n'
          'Path:speech.config\r\n\r\n'
          '{"context":{"synthesis":{"audio":{"metadataoptions":'
          '{"sentenceBoundaryEnabled":"false","wordBoundaryEnabled":"false"}'
          ',"outputFormat":"audio-24khz-48kbitrate-mono-mp3"}}}}\r\n';
      ws.add(configMsg);

      // 2. Send SSML payload
      final longVoice = _voiceShortToLong(voice);
      final escapedText = _xmlEscape(text);
      final ssml = "<speak version='1.0' xmlns='http://www.w3.org/2001/10/synthesis' xml:lang='en-US'>"
          "<voice name='$longVoice'>"
          "<prosody pitch='$pitch' rate='$rate' volume='$volume'>"
          "$escapedText"
          "</prosody></voice></speak>";

      final ssmlMsg = 'X-RequestId:$requestId\r\n'
          'Content-Type:application/ssml+xml\r\n'
          'X-Timestamp:${timestamp}Z\r\n'
          'Path:ssml\r\n\r\n'
          '$ssml';
      ws.add(ssmlMsg);

      // 3. Receive binary MP3 stream
      final audioBytes = BytesBuilder(copy: false);
      await for (final message in ws) {
        if (message is String) {
          if (message.contains('Path:turn.end')) {
            break;
          }
        } else if (message is List<int>) {
          final data = message is Uint8List ? message : Uint8List.fromList(message);
          if (data.length > 2) {
            final headerLen = (data[0] << 8) | data[1];
            if (headerLen < data.length) {
              final headerText = ascii.decode(data.sublist(2, 2 + headerLen), allowInvalid: true);
              if (headerText.contains('Path:audio')) {
                audioBytes.add(data.sublist(2 + headerLen));
              }
            }
          }
        }
      }

      final result = audioBytes.toBytes();
      return result.isNotEmpty ? result : null;
    } finally {
      try {
        await ws?.close();
      } catch (_) {}
      httpClient.close();
    }
  }

  static String _voiceShortToLong(String shortName) {
    final match = RegExp(r'^([a-z]{2,})-([A-Z]{2,})-(.+Neural)$').firstMatch(shortName);
    if (match != null) {
      final locale = '${match.group(1)}-${match.group(2)}';
      final name = match.group(3);
      return 'Microsoft Server Speech Text to Speech Voice ($locale, $name)';
    }
    return shortName;
  }

  static String _xmlEscape(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&apos;');
  }
}
