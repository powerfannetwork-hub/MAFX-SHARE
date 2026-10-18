import 'package:flutter/material.dart';

import '../models/media_file_model.dart';
import '../services/media_library_service.dart';
import '../widgets/media_file_tile.dart';
import 'player_screen.dart';

class VideoLibraryScreen extends StatefulWidget {
  const VideoLibraryScreen({super.key});

  @override
  State<VideoLibraryScreen> createState() =>
      _VideoLibraryScreenState();
}

class _VideoLibraryScreenState extends State<VideoLibraryScreen> {
  final MediaLibraryService _mediaService = MediaLibraryService();
  final TextEditingController _searchController =
      TextEditingController();

  List<MediaFileModel> _videos = [];
  bool _isLoading = true;
  bool _hasPermission = true;
  String _searchQuery = '';

  static const Color _backgroundColor = Color(0xFF101010);
  static const Color _greenColor = Color(0xFF00C853);

  @override
  void initState() {
    super.initState();
    _loadVideos();
  }

  Future<void> _loadVideos() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
      });
    }

    try {
      final hasPermission =
          await _mediaService.requestPermission();

      if (!hasPermission) {
        if (!mounted) return;

        setState(() {
          _hasPermission = false;
          _videos = [];
          _isLoading = false;
        });
        return;
      }

      final videos = await _mediaService.loadMedia(
        type: MediaFileType.video,
      );

      if (!mounted) return;

      setState(() {
        _hasPermission = true;
        _videos = videos;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An samu matsala wajen loda bidiyoyi.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  List<MediaFileModel> get _filteredVideos {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return _videos;
    }

    return _videos.where((video) {
      return video.name.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openVideo(MediaFileModel video) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlayerScreen(
          videoPath: video.path,
          title: video.name,
        ),
      ),
    );

    if (mounted) {
      setState(() {});
    }
  }

  Widget _buildSearchBox() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Bincika bidiyo...',
          hintStyle: const TextStyle(color: Colors.white54),
          prefixIcon: const Icon(
            Icons.search,
            color: _greenColor,
          ),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white70,
                  ),
                ),
          filled: true,
          fillColor: const Color(0xFF1C1C1C),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 76,
              color: Colors.white24,
            ),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                height: 1.5,
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              action,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildVideoList() {
    final videos = _filteredVideos;

    if (videos.isEmpty) {
      return _buildEmptyState(
        icon: Icons.video_library_outlined,
        title: _searchQuery.isEmpty
            ? 'Babu bidiyo'
            : 'Ba a sami bidiyon ba',
        message: _searchQuery.isEmpty
            ? 'Bidiyoyin da ke cikin media library na wayarka '
                'za su bayyana a nan.'
            : 'Gwada wani suna ko kalma daban.',
        action: _searchQuery.isEmpty
            ? OutlinedButton.icon(
                onPressed: _loadVideos,
                icon: const Icon(Icons.refresh),
                label: const Text('Sake loda'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _greenColor,
                ),
              )
            : null,
      );
    }

    return RefreshIndicator(
      color: _greenColor,
      onRefresh: _loadVideos,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 24),
        itemCount: videos.length,
        itemBuilder: (context, index) {
          final video = videos[index];

          return MediaFileTile(
            media: video,
            onTap: () => _openVideo(video),
            trailing: const Icon(
              Icons.play_arrow_rounded,
              color: _greenColor,
              size: 30,
            ),
          );
        },
      ),
    );
  }

  Widget _buildPermissionMessage() {
    return _buildEmptyState(
      icon: Icons.folder_off_outlined,
      title: 'Ana buƙatar izini',
      message:
          'MAFX SHARE yana buƙatar izinin shiga hotuna da bidiyoyi '
          'domin ya nuna bidiyoyin wayarka.',
      action: Column(
        children: [
          ElevatedButton.icon(
            onPressed: _loadVideos,
            icon: const Icon(Icons.lock_open),
            label: const Text('Sake neman izini'),
            style: ElevatedButton.styleFrom(
              backgroundColor: _greenColor,
              foregroundColor: Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _mediaService.openPermissionSettings,
            child: const Text(
              'Buɗe saitunan izini',
              style: TextStyle(color: Colors.white70),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final totalSize = _videos.fold<int>(
      0,
      (total, video) => total + video.sizeBytes,
    );

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        foregroundColor: Colors.white,
        title: const Text(
          'MAFX Videos',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _loadVideos,
            tooltip: 'Sake loda bidiyoyi',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          _buildSearchBox(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.video_library,
                  color: _greenColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_videos.length} bidiyo'
                    ' • ${MediaFileModel.formatBytes(totalSize)}',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: _greenColor,
                    ),
                  )
                : !_hasPermission
                    ? _buildPermissionMessage()
                    : _buildVideoList(),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
