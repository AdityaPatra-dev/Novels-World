import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/models/reader_settings.dart';
import '../../providers/settings_provider.dart';

class ReaderSettingsModal extends StatelessWidget {
  const ReaderSettingsModal({super.key});

  @override
  Widget build(BuildContext context) {
    final settingsProvider = context.watch<SettingsProvider>();
    final settings = settingsProvider.settings;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      decoration: const BoxDecoration(
        color: Color(0xFF181822),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Reading Preferences',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Theme Selector
          const Text('Theme', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildThemeButton(context, settingsProvider, ReaderTheme.light, 'Light', const Color(0xFFFAF9F6), Colors.black),
              _buildThemeButton(context, settingsProvider, ReaderTheme.sepia, 'Sepia', const Color(0xFFF4ECD8), const Color(0xFF433422)),
              _buildThemeButton(context, settingsProvider, ReaderTheme.dark, 'Dark', const Color(0xFF1E1E24), Colors.white),
              _buildThemeButton(context, settingsProvider, ReaderTheme.amoled, 'OLED', Colors.black, Colors.white),
            ],
          ),
          const SizedBox(height: 24),

          // Font Size Slider
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Font Size', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text('${settings.fontSize.toInt()} px', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.text_fields, size: 16),
                onPressed: () => settingsProvider.updateFontSize(settings.fontSize - 1),
              ),
              Expanded(
                child: Slider(
                  value: settings.fontSize,
                  min: 12.0,
                  max: 32.0,
                  divisions: 20,
                  activeColor: const Color(0xFF8B5CF6),
                  onChanged: (val) => settingsProvider.updateFontSize(val),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.text_fields, size: 24),
                onPressed: () => settingsProvider.updateFontSize(settings.fontSize + 1),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Line Height
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Line Spacing', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              Text('${settings.lineHeight.toStringAsFixed(1)}x', style: const TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          Slider(
            value: settings.lineHeight,
            min: 1.2,
            max: 2.2,
            divisions: 10,
            activeColor: const Color(0xFF8B5CF6),
            onChanged: (val) => settingsProvider.updateLineHeight(val),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildThemeButton(
    BuildContext context,
    SettingsProvider provider,
    ReaderTheme theme,
    String label,
    Color bg,
    Color fg,
  ) {
    final isSelected = provider.settings.theme == theme;
    return GestureDetector(
      onTap: () => provider.updateTheme(theme),
      child: Column(
        children: [
          Container(
            width: 56,
            height: 40,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? const Color(0xFF8B5CF6) : Colors.white24,
                width: isSelected ? 2.5 : 1.0,
              ),
            ),
            child: Center(
              child: Text('Aa', style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 4),
          Text(label, style: const TextStyle(fontSize: 11)),
        ],
      ),
    );
  }
}

