import 'package:flutter/material.dart';
import '../../tts/language_voice_registry.dart';

/// Unbiased searchable global language selection modal.
///
/// Features 70+ languages with flags, native scripts, instant search,
/// and a 1-tap toggle between original text and translated text.
class LanguageSelectionModal extends StatefulWidget {
  final String? currentLanguageCode;
  final bool isTranslationActive;
  final ValueChanged<LanguageVoiceInfo> onLanguageSelected;
  final VoidCallback onDisableTranslation;

  const LanguageSelectionModal({
    super.key,
    required this.currentLanguageCode,
    required this.isTranslationActive,
    required this.onLanguageSelected,
    required this.onDisableTranslation,
  });

  static Future<void> show({
    required BuildContext context,
    required String? currentLanguageCode,
    required bool isTranslationActive,
    required ValueChanged<LanguageVoiceInfo> onLanguageSelected,
    required VoidCallback onDisableTranslation,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF14141E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (context) => LanguageSelectionModal(
        currentLanguageCode: currentLanguageCode,
        isTranslationActive: isTranslationActive,
        onLanguageSelected: onLanguageSelected,
        onDisableTranslation: onDisableTranslation,
      ),
    );
  }

  @override
  State<LanguageSelectionModal> createState() => _LanguageSelectionModalState();
}

class _LanguageSelectionModalState extends State<LanguageSelectionModal> {
  final TextEditingController _searchController = TextEditingController();
  List<LanguageVoiceInfo> _filteredLanguages = LanguageVoiceRegistry.supportedLanguages;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    setState(() {
      _filteredLanguages = LanguageVoiceRegistry.search(_searchController.text);
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeInfo = widget.currentLanguageCode != null
        ? LanguageVoiceRegistry.getByCode(widget.currentLanguageCode!)
        : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),

              // Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Translate Chapter',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  if (widget.isTranslationActive)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      icon: const Icon(Icons.close, size: 16),
                      label: const Text('View Original'),
                      onPressed: () {
                        widget.onDisableTranslation();
                        Navigator.pop(context);
                      },
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Translate chapter text into any language with native TTS speech.',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.6)),
              ),
              const SizedBox(height: 14),

              // Search Bar
              TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search language (e.g. Hindi, Spanish, 日本語)...',
                  hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                  prefixIcon: const Icon(Icons.search, color: Color(0xFF8B5CF6), size: 20),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white38, size: 18),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  filled: true,
                  fillColor: const Color(0xFF1E1E28),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Languages List
              Expanded(
                child: ListView.builder(
                  controller: scrollController,
                  itemCount: _filteredLanguages.length,
                  itemBuilder: (context, index) {
                    final lang = _filteredLanguages[index];
                    final isSelected = widget.isTranslationActive &&
                        activeInfo != null &&
                        activeInfo.code == lang.code;

                    return Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? const Color(0xFF8B5CF6).withValues(alpha: 0.15)
                            : const Color(0xFF1E1E28),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected ? const Color(0xFF8B5CF6) : Colors.white10,
                          width: isSelected ? 1.5 : 1.0,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        leading: Text(
                          lang.flag,
                          style: const TextStyle(fontSize: 24),
                        ),
                        title: Text(
                          lang.nativeName,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            color: Colors.white,
                          ),
                        ),
                        subtitle: Text(
                          lang.englishName,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withValues(alpha: 0.6),
                          ),
                        ),
                        trailing: isSelected
                            ? const Icon(Icons.check_circle, color: Color(0xFF8B5CF6), size: 20)
                            : const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 14),
                        onTap: () {
                          widget.onLanguageSelected(lang);
                          Navigator.pop(context);
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
