import 'package:flutter/material.dart';
import '../core/models/novel.dart';
import '../data/storage_service.dart';

class LibraryProvider extends ChangeNotifier {
  final StorageService _storage;
  List<Novel> _novels = [];

  LibraryProvider(this._storage) {
    loadLibrary();
  }

  List<Novel> get novels => _novels;

  void loadLibrary() {
    _novels = _storage.getLibraryNovels();
    notifyListeners();
  }

  bool isInLibrary(String novelId) {
    return _novels.any((n) => n.id == novelId);
  }

  Future<void> toggleLibrary(Novel novel) async {
    if (isInLibrary(novel.id)) {
      await _storage.removeNovelFromLibrary(novel.id);
    } else {
      await _storage.saveNovelToLibrary(novel);
    }
    loadLibrary();
  }

  Future<void> removeFromLibrary(String novelId) async {
    await _storage.removeNovelFromLibrary(novelId);
    loadLibrary();
  }
}

