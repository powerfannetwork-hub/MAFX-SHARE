import 'package:flutter/material.dart';

import 'connect_screen.dart';
import 'file_manager_screen.dart';
import 'music_library_screen.dart';
import 'photo_gallery_screen.dart';
import 'history_screen.dart';
import 'video_library_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Color _green = Color(0xFF008D5A);
  static const Color _background = Color(0xFF19191D);
  static const Color _surface = Color(0xFF29292F);
  static const Color _muted = Color(0xFF929299);

  int _selectedTab = 0;

  final List<_TransferCategory> _categories = const [
    _TransferCategory(
      title: 'Apps',
      icon: Icons.apps_rounded,
      category: 'apps',
    ),
    _TransferCategory(
      title: 'Photos',
      icon: Icons.photo_library_rounded,
      category: 'photos',
    ),
    _TransferCategory(
      title: 'Videos',
      icon: Icons.video_library_rounded,
      category: 'videos',
    ),
    _TransferCategory(
      title: 'Music',
      icon: Icons.music_note_rounded,
      category: 'music',
    ),
    _TransferCategory(
      title: 'Files',
      icon: Icons.folder_rounded,
      category: 'files',
    ),
  ];

  void _openConnection({
    required TransferRole role,
    String? category,
  }) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ConnectScreen(
          role: role,
          category: category,
        ),
      ),
    );
  }

  void _openSend({String? category}) {
    _openConnection(
      role: TransferRole.send,
      category: category,
    );
  }

  void _openReceive() {
    _openConnection(
      role: TransferRole.receive,
    );
  }

  void _openLibrary(String category) {
  final Widget screen;

  switch (category) {
    case 'photos':
      screen = const PhotoGalleryScreen();
      break;

    case 'videos':
      screen = const VideoLibraryScreen();
      break;

    case 'music':
      screen = const MusicLibraryScreen();
      break;

    case 'files':
      screen = const FileManagerScreen();
      break;

    default:
      _openSend(category: category);
      return;
  }

  Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => screen,
    ),
  );
}
  
  void _openTransferHistory() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const TransferHistoryScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 8,
        title: const Text(
          'MAFX SHARE',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 21,
            letterSpacing: 0.5,
          ),
        ),
        leading: IconButton(
          tooltip: 'Menu',
          onPressed: _showMenu,
          icon: const Icon(Icons.menu_rounded),
        ),
        actions: [
          IconButton(
            tooltip: 'Transfer history',
            onPressed: _openTransferHistory,
            icon: const Icon(Icons.history_rounded),
          ),
          IconButton(
            tooltip: 'More options',
            onPressed: _showMoreOptions,
            icon: const Icon(Icons.more_vert_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildCategoryBar(),
            Expanded(
              child: IndexedStack(
                index: _selectedTab,
                children: [
                  _buildAppsPage(),
                  _buildCategoryPage(
                    title: 'Photos',
                    subtitle: 'Choose photos to share.',
                    icon: Icons.photo_library_rounded,
                    category: 'photos',
                  ),
                  _buildCategoryPage(
                    title: 'Videos',
                    subtitle: 'Choose videos to share.',
                    icon: Icons.video_library_rounded,
                    category: 'videos',
                  ),
                  _buildCategoryPage(
                    title: 'Music',
                    subtitle: 'Choose music to share.',
                    icon: Icons.music_note_rounded,
                    category: 'music',
                  ),
                  _buildCategoryPage(
                    title: 'Files',
                    subtitle: 'Choose files to share.',
                    icon: Icons.folder_rounded,
                    category: 'files',
                  ),
                ],
              ),
            ),
            _buildTransferButtons(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  Widget _buildCategoryBar() {
    return Container(
      height: 65,
      color: _green,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: _categories.length,
        itemBuilder: (context, index) {
          final category = _categories[index];
          final selected = _selectedTab == index;

          return InkWell(
            onTap: () {
              setState(() {
                _selectedTab = index;
              });
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 19),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    category.icon,
                    color: selected
                        ? Colors.white
                        : Colors.white70,
                    size: 25,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    category.title,
                    style: TextStyle(
                      color: selected
                          ? Colors.white
                          : Colors.white70,
                      fontWeight: selected
                          ? FontWeight.bold
                          : FontWeight.normal,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Container(
                    height: 3,
                    width: 35,
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.white
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildAppsPage() {
    return Column(
      children: [
        _buildSectionHeader(
          title: 'Apps on this phone',
          trailing: 'Browse',
          onTrailingTap: () => _openSend(category: 'apps'),
        ),
        Expanded(
          child: _buildEmptyCategory(
            icon: Icons.apps_rounded,
            title: 'Your apps will appear here',
            message:
                'Open Send to choose apps or files available '
                'on this device.',
            buttonText: 'Choose apps to send',
            onPressed: () => _openSend(category: 'apps'),
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryPage({
    required String title,
    required String subtitle,
    required IconData icon,
    required String category,
  }) {
    return Column(
      children: [
        _buildSectionHeader(
          title: title,
          trailing: 'Select',
          onTrailingTap: () => _openSend(category: category),
        ),
        Expanded(
          child: _buildEmptyCategory(
            icon: icon,
            title: 'No $title selected',
            message: subtitle,
            buttonText: 'Open $title library',
            onPressed: () => _openLibrary(category),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader({
    required String title,
    required String trailing,
    required VoidCallback onTrailingTap,
  }) {
    return Container(
      color: _surface,
      padding: const EdgeInsets.symmetric(
        horizontal: 18,
        vertical: 15,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
          ),
          TextButton(
            onPressed: onTrailingTap,
            child: Text(
              trailing,
              style: const TextStyle(
                color: Color(0xFF00D18B),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCategory({
    required IconData icon,
    required String title,
    required String message,
    required String buttonText,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 105,
              height: 105,
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 54,
                color: const Color(0xFF00D18B),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _muted,
                height: 1.5,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: onPressed,
              icon: const Icon(Icons.send_rounded),
              label: Text(buttonText),
              style: FilledButton.styleFrom(
                backgroundColor: _green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 14,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransferButtons() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 18),
      decoration: const BoxDecoration(
        color: _background,
        border: Border(
          top: BorderSide(color: Colors.white10),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _TransferButton(
              title: 'SEND',
              icon: Icons.send_rounded,
              onPressed: () {
                final category =
                    _categories[_selectedTab].category;
                _openSend(category: category);
              },
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: _TransferButton(
              title: 'RECEIVE',
              icon: Icons.download_rounded,
              onPressed: _openReceive,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return BottomNavigationBar(
      currentIndex: _selectedTab,
      onTap: (index) {
        setState(() {
          _selectedTab = index;
        });
      },
      type: BottomNavigationBarType.fixed,
      backgroundColor: const Color(0xFF242429),
      selectedItemColor: const Color(0xFF00D18B),
      unselectedItemColor: Colors.white54,
      selectedFontSize: 11,
      unselectedFontSize: 10,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.apps_rounded),
          label: 'Apps',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.photo_rounded),
          label: 'Photos',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.video_library_rounded),
          label: 'Videos',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.music_note_rounded),
          label: 'Music',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.folder_rounded),
          label: 'Files',
        ),
      ],
    );
  }

  void _showMenu() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const ListTile(
                leading: Icon(
                  Icons.share_rounded,
                  color: Color(0xFF00D18B),
                ),
                title: Text(
                  'MAFX SHARE',
                  style: TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  'Local file sharing',
                  style: TextStyle(color: _muted),
                ),
              ),
              ListTile(
                leading: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'Send files',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openSend();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.download_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'Receive files',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openReceive();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.history_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'Transfer history',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openTransferHistory();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'About',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showAbout();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showMoreOptions() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      builder: (context) {
        return SafeArea(
          child: Wrap(
            children: [
              ListTile(
                leading: const Icon(
                  Icons.history_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'Transfer history',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _openTransferHistory();
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.info_outline_rounded,
                  color: Colors.white,
                ),
                title: const Text(
                  'About MAFX SHARE',
                  style: TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _showAbout();
                },
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAbout() {
    showAboutDialog(
      context: context,
      applicationName: 'MAFX SHARE',
      applicationVersion: '1.0.0',
      applicationLegalese: 'Local file sharing application.',
    );
  }
}

class _TransferCategory {
  final String title;
  final IconData icon;
  final String category;

  const _TransferCategory({
    required this.title,
    required this.icon,
    required this.category,
  });
}

class _TransferButton extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onPressed;

  const _TransferButton({
    required this.title,
    required this.icon,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 21),
        label: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 15,
            letterSpacing: 0.6,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF008D5A),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
            side: const BorderSide(
              color: Colors.white,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }
}
