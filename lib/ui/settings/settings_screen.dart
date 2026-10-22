import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/reader_settings.dart';
import '../../data/storage_service.dart';
import '../../providers/settings_provider.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  double _cacheSizeMb = 0.0;
  int _cachedChapters = 0;
  bool _isLoadingCache = true;

  @override
  void initState() {
    super.initState();
    _loadCacheInfo();
  }

  Future<void> _loadCacheInfo() async {
    final storage = StorageService();
    await storage.init();
    final size = await storage.getCacheSizeMb();
    final count = await storage.getTotalCachedChapterCount();
    if (mounted) {
      setState(() {
        _cacheSizeMb = size;
        _cachedChapters = count;
        _isLoadingCache = false;
      });
    }
  }

  Future<void> _clearCache() async {
    final storage = StorageService();
    await storage.init();
    await storage.clearAllChapterCache();
    await _loadCacheInfo();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Offline chapter cache cleared.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final settings = settingsProvider.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        children: [
          // Section 1: Neural TTS Engine
          _buildSectionHeader('Neural Text-To-Speech'),
          Card(
            color: const Color(0xFF181822),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Active TTS Engine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: settings.ttsEngine,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFF1E1E28),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    dropdownColor: const Color(0xFF1E1E28),
                    items: const [
                      DropdownMenuItem(
                        value: 'kokoro',
                        child: Text('Kokoro-82M (Expressive Storyteller)'),
                      ),
                      DropdownMenuItem(
                        value: 'piper',
                        child: Text('Piper TTS (Ultra-Fast VITS)'),
                      ),
                      DropdownMenuItem(
                        value: 'sherpa',
                        child: Text('Sherpa-Matcha (CJK Specialist)'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        String defaultVoice = 'af_bella';
                        if (val == 'piper') defaultVoice = 'en_US-lessac-high';
                        if (val == 'sherpa') defaultVoice = 'cjk_storyteller_bilingual';
                        settingsProvider.updateTtsVoice(val, defaultVoice);
                      }
                    },
                  ),
                  const SizedBox(height: 16),

                  // Reading Speed
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Default Reading Speed', style: TextStyle(fontSize: 13)),
                      Text('${settings.ttsSpeed.toStringAsFixed(2)}x', style: const TextStyle(fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Slider(
                    value: settings.ttsSpeed,
                    min: 0.5,
                    max: 2.5,
                    divisions: 8,
                    activeColor: const Color(0xFF8B5CF6),
                    onChanged: (val) => settingsProvider.updateTtsSpeed(val),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Section 2: Reader Defaults
          _buildSectionHeader('Default Typography & Theme'),
          Card(
            color: const Color(0xFF181822),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.palette_outlined, color: Color(0xFF8B5CF6)),
                  title: const Text('Default Theme'),
                  subtitle: Text(settings.theme.name.toUpperCase()),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    final next = ReaderTheme.values[(settings.theme.index + 1) % ReaderTheme.values.length];
                    settingsProvider.updateTheme(next);
                  },
                ),
                const Divider(height: 1, color: Colors.white12),
                ListTile(
                  leading: const Icon(Icons.font_download_outlined, color: Color(0xFF8B5CF6)),
                  title: const Text('Font Family'),
                  subtitle: Text(settings.fontFamily),
                  trailing: const Icon(Icons.chevron_right, size: 20),
                  onTap: () {
                    const fonts = ['Lora', 'Merriweather', 'Roboto', 'Inter'];
                    final idx = fonts.indexOf(settings.fontFamily);
                    final next = fonts[(idx + 1) % fonts.length];
                    settingsProvider.updateFontFamily(next);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Section 3: Offline Storage & Cache (Phase 3 Deliverable)
          _buildSectionHeader('Offline Storage & Chapter Cache'),
          Card(
            color: const Color(0xFF181822),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Cached Offline Chapters', style: TextStyle(fontSize: 14)),
                      Text(
                        _isLoadingCache ? '...' : '$_cachedChapters chapters',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Storage Space Used', style: TextStyle(fontSize: 14)),
                      Text(
                        _isLoadingCache ? '...' : '${_cacheSizeMb.toStringAsFixed(2)} MB',
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF8B5CF6), fontSize: 14),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: _cachedChapters > 0 ? _clearCache : null,
                    icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                    label: const Text('Clear All Chapter Cache', style: TextStyle(color: Colors.redAccent)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Section 4: App Information
          _buildSectionHeader('About Novels-World'),
          Card(
            color: const Color(0xFF181822),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Novels-World v1.3.0 (Phase 3 Build)', style: TextStyle(fontWeight: FontWeight.bold)),
                  SizedBox(height: 6),
                  Text(
                    'High-performance offline-first novel reader with Universal Madara extractor, 3 neural TTS engines, and batch chapter downloader.',
                    style: TextStyle(fontSize: 12, color: Colors.white70, height: 1.4),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: Color(0xFF8B5CF6),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
