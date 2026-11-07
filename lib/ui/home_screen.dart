import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/download_service.dart';
import 'library/library_screen.dart';
import 'browse/browse_screen.dart';
import 'downloads/downloads_screen.dart';
import 'profile/profile_screen.dart';
import 'settings/settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 1; // Default to Browse tab

  @override
  Widget build(BuildContext context) {
    final downloadService = context.watch<DownloadService>();

    final List<Widget> pages = [
      LibraryScreen(onBrowseTap: () => setState(() => _currentIndex = 1)),
      const BrowseScreen(),
      DownloadsScreen(onBrowseTap: () => setState(() => _currentIndex = 1)),
      const ProfileScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.bookmark_outline),
            selectedIcon: Icon(Icons.bookmark),
            label: 'Library',
          ),
          const NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore),
            label: 'Browse',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: downloadService.isProcessing || downloadService.queue.isNotEmpty,
              label: Text(
                '${downloadService.activeQueueCount}',
                style: const TextStyle(fontSize: 10),
              ),
              child: const Icon(Icons.download_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: downloadService.isProcessing || downloadService.queue.isNotEmpty,
              label: Text(
                '${downloadService.activeQueueCount}',
                style: const TextStyle(fontSize: 10),
              ),
              child: const Icon(Icons.download),
            ),
            label: 'Downloads',
          ),
          const NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profile',
          ),
          const NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}

