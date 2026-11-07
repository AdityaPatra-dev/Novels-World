import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

http.Client createPlatformHttpClient({Duration timeout = const Duration(seconds: 15)}) {
  if (kIsWeb) {
    return http.Client();
  }
  final native = HttpClient();
  native.badCertificateCallback = (cert, host, port) => true;
  native.connectionTimeout = timeout;
  return IOClient(native);
}
