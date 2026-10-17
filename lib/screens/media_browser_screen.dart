import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

class MediaBrowserScreen extends StatefulWidget {
  final String category;
  final bool allowMultiple;

  const MediaBrowserScreen({
    super.key,
    required this.category,
    this.allowMultiple = true,
  });

  @override
  State<MediaBrowserScreen> createState() =>
      _MediaBrowserScreenState();
}

class _MediaBrowserScreenState extends State<MediaBrowserScreen> {
  static const Color green = Color(0xFF008D5A);
  static const Color accent = Color(0xFF00D18B);
  static const Color background = Color(0xFF19191D);
  static const Color surface = Color(0xFF29292F);

  List<AssetEntity> _assets = [];
  final Set<AssetEntity> _selected = {};

  bool _loading = true;
  bool _permissionDenied = false;

  int _page = 0;
  bool _hasMore = true;

  String get _category =>
      widget.category.toLowerCase().trim();

  String get _title {
    switch (_category) {
      case 'photos':
        return 'Photos';
      case 'videos':
        return 'Videos';
      case 'music':
        return 'Music';
      default:
        return 'Media';
    }
  }

  RequestType get _requestType {
    switch (_category) {
      case 'photos':
        return RequestType.image;
      case 'videos':
        return RequestType.video;
      case 'music':
        return RequestType.audio;
      default:
        return RequestType.common;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMedia();
  }

  Future<void> _loadMedia() async {
    if (_page == 0 && mounted) {
      setState(() {
        _loading = true;
        _permissionDenied = false;
      });
    }

    try {
      final permission = await PhotoManager.requestPermissionExtend();

      if (!permission.isAuth && !permission.hasAccess) {
        if (!mounted) return;

        setState(() {
          _permissionDenied = true;
          _loading = false;
        });

        return;
      }

      final paths = await PhotoManager.getAssetPathList(
        type: _requestType,
        hasAll: true,
      );

      if (paths.isEmpty) {
        if (!mounted) return;

        setState(() {
          _assets = [];
          _loading = false;
          _hasMore = false;
        });

        return;
      }

      final album = paths.first;

      const pageSize = 80;

      final result = await album.getAssetListPaged(
        page: _page,
        size: pageSize,
      );

      if (!mounted) return;

      setState(() {
        if (_page == 0) {
          _assets = result;
        } else {
          _assets.addAll(result);
        }

        _hasMore = result.length == pageSize;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Media loading error: $error');

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _showMessage('Unable to load media: $error');
    }
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;

    _page++;

    await _loadMedia();
  }

  void _toggleSelection(AssetEntity asset) {
    setState(() {
      if (_selected.contains(asset)) {
        _selected.remove(asset);
      } else {
        if (!widget.allowMultiple) {
          _selected.clear();
        }

        _selected.add(asset);
      }
    });
  }

  Future<void> _openSettings() async {
    await PhotoManager.openSetting();
  }

  void _finishSelection() {
    Navigator.pop<List<AssetEntity>>(
      context,
      _selected.toList(),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _formatDuration(Duration? duration) {
    if (duration == null) return '';

    final minutes = duration.inMinutes;
    final seconds =
        (duration.inSeconds % 60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  Widget _buildPermissionMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.photo_library_outlined,
              color: accent,
              size: 72,
            ),
            const SizedBox(height: 20),
            const Text(
              'Media permission required',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Allow MAFX SHARE to access the media you '
              'want to select.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 22),
            FilledButton(
              onPressed: _openSettings,
              style: FilledButton.styleFrom(
                backgroundColor: green,
              ),
              child: const Text('Open Settings'),
            ),
            TextButton(
              onPressed: () {
                setState(() {
                  _page = 0;
                  _loading = true;
                });

                _loadMedia();
              },
              child: const Text(
                'Try Again',
                style: TextStyle(color: accent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _category == 'videos'
                  ? Icons.video_library_outlined
                  : _category == 'music'
                      ? Icons.music_note_rounded
                      : Icons.photo_library_outlined,
              color: accent,
              size: 68,
            ),
            const SizedBox(height: 18),
            Text(
              'No $_title found',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'There are no matching items available '
              'to display on this phone.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGridItem(AssetEntity asset) {
    final selected = _selected.contains(asset);

    return GestureDetector(
      onTap: () => _toggleSelection(asset),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: surface,
            child: FutureBuilder<Widget?>(
              future: _thumbnail(asset),
              builder: (context, snapshot) {
                if (snapshot.hasData && snapshot.data != null) {
                  return snapshot.data!;
                }

                return const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: accent,
                  ),
                );
              },
            ),
          ),
          if (asset.type == AssetType.video)
            Positioned(
              bottom: 6,
              left: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  _formatDuration(asset.videoDuration),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
          Positioned(
            top: 7,
            right: 7,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: selected ? green : Colors.black54,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white,
                  width: 1.3,
                ),
              ),
              child: selected
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 18,
                    )
                  : null,
            ),
          ),
          if (selected)
            Container(
              decoration: BoxDecoration(
                border: Border.all(
                  color: accent,
                  width: 3,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<Widget?> _thumbnail(AssetEntity asset) async {
    final file = await asset.file;

    if (file == null || !await file.exists()) {
      return null;
    }

    return Image.file(
      file,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        return const Icon(
          Icons.broken_image_outlined,
          color: Colors.white54,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: green,
        foregroundColor: Colors.white,
        title: Text(_title),
        actions: [
          if (_selected.isNotEmpty)
            TextButton(
              onPressed: () {
                setState(() {
                  _selected.clear();
                });
              },
              child: const Text(
                'Clear',
                style: TextStyle(color: Colors.white),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading && _assets.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: accent),
              )
            : _permissionDenied
                ? _buildPermissionMessage()
                : _assets.isEmpty
                    ? _buildEmptyMessage()
                    : Column(
                        children: [
                          Container(
                            color: surface,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '${_assets.length} items • '
                                    '${_selected.length} selected',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Text(
                                  _selected.isEmpty
                                      ? 'Tap to select'
                                      : '${_selected.length} chosen',
                                  style: const TextStyle(
                                    color: accent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: NotificationListener<
                                ScrollNotification>(
                              onNotification: (notification) {
                                if (notification.metrics.pixels >=
                                    notification.metrics.maxScrollExtent -
                                        300) {
                                  _loadMore();
                                }

                                return false;
                              },
                              child: GridView.builder(
                                padding: const EdgeInsets.all(3),
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 3,
                                  crossAxisSpacing: 3,
                                  mainAxisSpacing: 3,
                                ),
                                itemCount: _assets.length,
                                itemBuilder: (context, index) {
                                  return _buildGridItem(
                                    _assets[index],
                                  );
                                },
                              ),
                            ),
                          ),
                          SafeArea(
                            top: false,
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: SizedBox(
                                width: double.infinity,
                                height: 52,
                                child: FilledButton.icon(
                                  onPressed: _selected.isEmpty
                                      ? null
                                      : _finishSelection,
                                  icon: const Icon(
                                    Icons.check_circle_rounded,
                                  ),
                                  label: Text(
                                    'Done (${_selected.length})',
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: green,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
      ),
    );
  }
}
