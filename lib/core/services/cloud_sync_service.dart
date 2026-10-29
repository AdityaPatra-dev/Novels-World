import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../../core/models/novel.dart';
import '../../core/models/reading_progress.dart';
import '../../data/storage_service.dart';

class CloudSyncService extends ChangeNotifier {
  static final CloudSyncService _instance = CloudSyncService._internal();
  static CloudSyncService get instance => _instance;

  FirebaseFirestore? get _firestore {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseFirestore.instance;
      }
    } catch (_) {}
    return null;
  }

  FirebaseAuth? get _auth {
    try {
      if (Firebase.apps.isNotEmpty) {
        return FirebaseAuth.instance;
      }
    } catch (_) {}
    return null;
  }

  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  String? _syncError;

  CloudSyncService._internal();

  bool get isSyncing => _isSyncing;
  DateTime? get lastSyncTime => _lastSyncTime;
  String? get syncError => _syncError;

  User? get _currentUser => _auth?.currentUser;

  /// Full bi-directional sync between local storage and Firestore cloud
  Future<void> syncFull(StorageService storage) async {
    final firestore = _firestore;
    final user = _currentUser;
    if (firestore == null || user == null) {
      _syncError = 'Not signed in';
      notifyListeners();
      return;
    }

    _isSyncing = true;
    _syncError = null;
    notifyListeners();

    try {
      final userDoc = firestore.collection('users').doc(user.uid);

      // Update user profile metadata
      await userDoc.set({
        'uid': user.uid,
        'email': user.email,
        'displayName': user.displayName ?? user.email?.split('@').first,
        'photoUrl': user.photoURL,
        'lastActiveAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // 1. Sync Library
      await _syncLibrary(userDoc, storage);

      // 2. Sync Reading Progress
      await _syncReadingProgress(userDoc, storage);

      // 3. Sync Chapter Read History
      await _syncReadHistory(userDoc, storage);

      _lastSyncTime = DateTime.now();
      _isSyncing = false;
      notifyListeners();
      debugPrint('[CLOUD_SYNC] Full sync completed successfully.');
    } catch (e, st) {
      debugPrint('[CLOUD_SYNC] Error during full sync: $e\n$st');
      _syncError = e.toString();
      _isSyncing = false;
      notifyListeners();
    }
  }

  Future<void> _syncLibrary(DocumentReference userDoc, StorageService storage) async {
    final libraryCol = userDoc.collection('library');
    final cloudSnapshot = await libraryCol.get();

    final localNovels = storage.getLibraryNovels();
    final localMap = {for (final n in localNovels) n.id: n};

    // Pull from cloud -> local
    for (final doc in cloudSnapshot.docs) {
      final data = doc.data();
      try {
        final cloudNovel = Novel.fromJson(data);
        final local = localMap[cloudNovel.id];

        if (local == null) {
          // Cloud has a novel not present locally -> add to local
          await storage.saveNovelToLibrary(cloudNovel);
        } else {
          // Both have it -> check which has newer lastReadAt
          final cloudTime = cloudNovel.lastReadAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final localTime = local.lastReadAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          if (cloudTime.isAfter(localTime)) {
            await storage.saveNovelToLibrary(cloudNovel);
          }
        }
      } catch (e) {
        debugPrint('[CLOUD_SYNC] Error restoring novel from cloud doc ${doc.id}: $e');
      }
    }

    // Push local -> cloud
    final refreshedLocal = storage.getLibraryNovels();
    for (final novel in refreshedLocal) {
      await libraryCol.doc(novel.id).set(novel.toJson(), SetOptions(merge: true));
    }
  }

  Future<void> _syncReadingProgress(DocumentReference userDoc, StorageService storage) async {
    final progressCol = userDoc.collection('progress');
    final cloudSnapshot = await progressCol.get();

    // Pull from cloud -> local
    for (final doc in cloudSnapshot.docs) {
      final data = doc.data();
      try {
        final cloudProgress = ReadingProgress.fromJson(data);
        final localProgress = storage.getProgress(cloudProgress.novelId);

        if (localProgress == null || cloudProgress.lastReadAt.isAfter(localProgress.lastReadAt)) {
          await storage.saveProgress(cloudProgress);
        }
      } catch (e) {
        debugPrint('[CLOUD_SYNC] Error restoring progress from cloud doc ${doc.id}: $e');
      }
    }

    // Push local -> cloud
    final allLibrary = storage.getLibraryNovels();
    for (final novel in allLibrary) {
      final progress = storage.getProgress(novel.id);
      if (progress != null) {
        await progressCol.doc(novel.id).set(progress.toJson(), SetOptions(merge: true));
      }
    }
  }

  Future<void> _syncReadHistory(DocumentReference userDoc, StorageService storage) async {
    final historyCol = userDoc.collection('history');
    final cloudSnapshot = await historyCol.get();

    // Pull from cloud -> local
    for (final doc in cloudSnapshot.docs) {
      final data = doc.data();
      try {
        final novelId = doc.id;
        final rawList = data['readChapterIds'] as List<dynamic>? ?? [];
        final cloudIds = rawList.map((e) => e.toString()).toSet();

        if (cloudIds.isNotEmpty) {
          await storage.markChaptersAsRead(novelId, cloudIds);
        }
      } catch (e) {
        debugPrint('[CLOUD_SYNC] Error restoring history doc ${doc.id}: $e');
      }
    }

    // Push local -> cloud
    final allLibrary = storage.getLibraryNovels();
    for (final novel in allLibrary) {
      final localReadIds = storage.getReadChapterIds(novel.id);
      if (localReadIds.isNotEmpty) {
        await historyCol.doc(novel.id).set({
          'novelId': novel.id,
          'readChapterIds': localReadIds.toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
    }
  }

  // --- Incremental background triggers ---

  Future<void> syncNovel(Novel novel) async {
    final firestore = _firestore;
    final user = _currentUser;
    if (firestore == null || user == null) return;
    try {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('library')
          .doc(novel.id)
          .set(novel.toJson(), SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> deleteNovel(String novelId) async {
    final firestore = _firestore;
    final user = _currentUser;
    if (firestore == null || user == null) return;
    try {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('library')
          .doc(novelId)
          .delete();
    } catch (_) {}
  }

  Future<void> syncProgress(ReadingProgress progress) async {
    final firestore = _firestore;
    final user = _currentUser;
    if (firestore == null || user == null) return;
    try {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('progress')
          .doc(progress.novelId)
          .set(progress.toJson(), SetOptions(merge: true));
    } catch (_) {}
  }

  Future<void> syncReadChapters(String novelId, Iterable<String> chapterIds) async {
    final firestore = _firestore;
    final user = _currentUser;
    if (firestore == null || user == null) return;
    try {
      await firestore
          .collection('users')
          .doc(user.uid)
          .collection('history')
          .doc(novelId)
          .set({
        'novelId': novelId,
        'readChapterIds': chapterIds.toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }
}
