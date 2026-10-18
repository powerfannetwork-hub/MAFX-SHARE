import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/media_file_model.dart';
import '../services/media_library_service.dart';

class PhotoGalleryScreen extends StatefulWidget {
  const PhotoGalleryScreen({super.key});

  @override
  State<PhotoGalleryScreen> createState() =>
      _PhotoGalleryScreenState();
}

class _PhotoGalleryScreenState extends State<PhotoGalleryScreen> {
  final MediaLibraryService _mediaService = MediaLibraryService();
  final TextEditingController _searchController =
      TextEditingController();

  List<MediaFileModel> _photos = [];
  bool _isLoading = true;
  bool _hasPermission = true;
  String _searchQuery = '';

  static const Color _backgroundColor = Color(0xFF101010);
  static const Color _greenColor = Color(0xFF00C853);

  @override
  void initState() {
    super.initState();
    _loadPhotos();
  }

  Future<void> _loadPhotos() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final hasPermission =
          await _mediaService.requestPermission();

      if (!hasPermission) {
        if (!mounted) return;

        setState(() {
          _hasPermission = false;
          _photos = [];
          _isLoading = false;
        });
        return;
      }

      final photos = await _mediaService.loadMedia(
        type: MediaFileType.photo,
      );

      if (!mounted) return;

      setState(() {
        _photos = photos;
        _hasPermission = true;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An samu matsala wajen loda hotuna.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  List<MediaFileModel> get _filteredPhotos {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return _photos;
    }

    return _photos.where((photo) {
      return photo.name.toLowerCase().contains(query);
    }).toList();
  }

  Future<void> _openPhoto(
    BuildContext context,
    MediaFileModel photo,
  ) async {
    final index = _photos.indexWhere(
      (item) => item.path == photo.path,
    );

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _PhotoViewerScreen(
          photos: _photos,
          initialIndex: index < 0 ? 0 : index,
        ),
      ),
    );
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
          hintText: 'Bincika hotuna...',
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

  Widget _buildEmptyState() {
    final searching = _searchQuery.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching
                  ? Icons.search_off
                  : Icons.photo_library_outlined,
              size: 76,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            Text(
              searching ? 'Ba a sami hoton ba' : 'Babu hotuna',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              searching
                  ? 'Gwada wani suna daban.'
                  : 'Hotunan wayarka za su bayyana a nan '
                      'idan an ba app izinin shiga su.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                height: 1.5,
              ),
            ),
            if (!searching) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _loadPhotos,
                icon: const Icon(Icons.refresh),
                label: const Text('Sake loda'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _greenColor,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.lock_outline,
              size: 72,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            const Text(
              'Ana buƙatar izini',
              style: TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ba MAFX SHARE izinin shiga hotuna domin '
              'ya nuna hotunan wayarka.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton.icon(
              onPressed: _loadPhotos,
              icon: const Icon(Icons.lock_open),
              label: const Text('Sake neman izini'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _greenColor,
                foregroundColor: Colors.black,
              ),
            ),
            TextButton(
              onPressed: _mediaService.openPermissionSettings,
              child: const Text(
                'Buɗe saitunan izini',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photos = _filteredPhotos;

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        foregroundColor: Colors.white,
        title: const Text(
          'MAFX Gallery',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _loadPhotos,
            tooltip: 'Sake loda hotuna',
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
                  Icons.photo_library,
                  color: _greenColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  '${photos.length} hotuna',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
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
                    ? _buildPermissionState()
                    : photos.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            color: _greenColor,
                            onRefresh: _loadPhotos,
                            child: GridView.builder(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                8,
                                0,
                                8,
                                20,
                              ),
                              gridDelegate:
                                  const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 5,
                                mainAxisSpacing: 5,
                                childAspectRatio: 0.82,
                              ),
                              itemCount: photos.length,
                              itemBuilder: (context, index) {
                                final photo = photos[index];

                                return GestureDetector(
                                  onTap: () =>
                                      _openPhoto(context, photo),
                                  child: ClipRRect(
                                    borderRadius:
                                        BorderRadius.circular(10),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        Image.file(
                                          File(photo.path),
                                          fit: BoxFit.cover,
                                          errorBuilder: (
                                            context,
                                            error,
                                            stackTrace,
                                          ) {
                                            return Container(
                                              color: const Color(
                                                0xFF242424,
                                              ),
                                              child: const Icon(
                                                Icons.broken_image,
                                                color: Colors.white38,
                                                size: 32,
                                              ),
                                            );
                                          },
                                        ),
                                        Positioned(
                                          left: 0,
                                          right: 0,
                                          bottom: 0,
                                          child: Container(
                                            padding:
                                                const EdgeInsets.all(6),
                                            decoration: const BoxDecoration(
                                              gradient: LinearGradient(
                                                begin:
                                                    Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Colors.transparent,
                                                  Colors.black87,
                                                ],
                                              ),
                                            ),
                                            child: Text(
                                              photo.name,
                                              maxLines: 1,
                                              overflow:
                                                  TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 10,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
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

class _PhotoViewerScreen extends StatefulWidget {
  final List<MediaFileModel> photos;
  final int initialIndex;

  const _PhotoViewerScreen({
    required this.photos,
    required this.initialIndex,
  });

  @override
  State<_PhotoViewerScreen> createState() =>
      _PhotoViewerScreenState();
}

class _PhotoViewerScreenState extends State<_PhotoViewerScreen> {
  late final PageController _pageController;
  late int _currentIndex;

  static const Color _greenColor = Color(0xFF00C853);

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialIndex;

    _pageController = PageController(
      initialPage: widget.initialIndex,
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photos[_currentIndex];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          photo.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${_currentIndex + 1}/${widget.photos.length}',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ),
          ),
        ],
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.photos.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          final item = widget.photos[index];

          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 5,
            child: Center(
              child: Image.file(
                File(item.path),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.broken_image_outlined,
                    size: 80,
                    color: Colors.white54,
                  );
                },
              ),
            ),
          );
        },
      ),
      bottomNavigationBar: Container(
        color: Colors.black,
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              onPressed: _currentIndex > 0
                  ? () {
                      _pageController.previousPage(
                        duration:
                            const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      );
                    }
                  : null,
              icon: const Icon(Icons.chevron_left),
              color: _greenColor,
              iconSize: 36,
            ),
            const SizedBox(width: 30),
            IconButton(
              onPressed: _currentIndex < widget.photos.length - 1
                  ? () {
                      _pageController.nextPage(
                        duration:
                            const Duration(milliseconds: 250),
                        curve: Curves.easeInOut,
                      );
                    }
                  : null,
              icon: const Icon(Icons.chevron_right),
              color: _greenColor,
              iconSize: 36,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }
}
