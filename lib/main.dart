import 'dart:io';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:provider/provider.dart';
import 'core/services/auth_service.dart';
import 'core/services/cloud_sync_service.dart';
import 'core/services/webview_session_manager.dart';
import 'core/theme/app_theme.dart';
import 'data/storage_service.dart';
import 'data/download_service.dart';
import 'firebase_options.dart';
import 'providers/library_provider.dart';
import 'providers/reader_provider.dart';
import 'providers/settings_provider.dart';
import 'ui/home_screen.dart';

class AppHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)
      ..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = AppHttpOverrides();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('[FIREBASE] Initialization info/fallback: $e');
  }

  final storageService = StorageService();
  await storageService.init();
  await WebViewSessionManager.instance.init();

  // If user is already authenticated from a previous session, do a silent background sync
  try {
    if (AuthService.instance.isAuthenticated) {
      CloudSyncService.instance.syncFull(storageService);
    }
  } catch (_) {}

  runApp(
    MultiProvider(
      providers: [
        Provider<StorageService>.value(value: storageService),
        ChangeNotifierProvider.value(value: AuthService.instance),
        ChangeNotifierProvider.value(value: CloudSyncService.instance),
        ChangeNotifierProvider(create: (_) => SettingsProvider(storageService)),
        ChangeNotifierProvider(create: (_) => LibraryProvider(storageService)),
        ChangeNotifierProvider(create: (_) => ReaderProvider(storageService)),
        ChangeNotifierProvider(create: (_) => DownloadService(storageService)),
      ],
      child: const NovelsWorldApp(),
    ),
  );
}

class NovelsWorldApp extends StatelessWidget {
  const NovelsWorldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Novels-World',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const NonStretchingScrollBehavior(),
      theme: AppTheme.darkTheme,
      home: const HomeScreen(),
    );
  }
}
