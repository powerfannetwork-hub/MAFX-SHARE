import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../models/media_file_model.dart';
import '../services/media_library_service.dart';
import '../widgets/media_file_tile.dart';

class MusicLibraryScreen extends StatefulWidget {
  const MusicLibraryScreen({super.key});

  @override
  State<MusicLibraryScreen> createState() =>
      _MusicLibraryScreenState();
}

class _MusicLibraryScreenState extends State<MusicLibraryScreen> {
  final MediaLibraryService _mediaService = MediaLibraryService();
  final AudioPlayer _audioPlayer = AudioPlayer();
  final TextEditingController _searchController =
      TextEditingController();

  List<MediaFileModel> _songs = [];

  int? _currentIndex;
  bool _isLoading = true;
  bool _hasPermission = true;
  bool _isChangingSong = false;

  String _searchQuery = '';

  static const Color _backgroundColor = Color(0xFF101010);
  static const Color _cardColor = Color(0xFF1B1B1B);
  static const Color _greenColor = Color(0xFF00C853);

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
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
          _songs = [];
          _isLoading = false;
        });

        return;
      }

      final songs = await _mediaService.loadMedia(
        type: MediaFileType.music,
      );

      if (!mounted) return;

      setState(() {
        _songs = songs;
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
          content: Text('An samu matsala wajen loda kiɗa.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  List<MediaFileModel> get _filteredSongs {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return _songs;
    }

    return _songs.where((song) {
      return song.name.toLowerCase().contains(query);
    }).toList();
  }

  bool _isCurrentSong(MediaFileModel song) {
    if (_currentIndex == null) return false;
    if (_currentIndex! >= _songs.length) return false;

    return _songs[_currentIndex!].path == song.path;
  }

  Future<void> _playSong(MediaFileModel song) async {
    final index = _songs.indexWhere(
      (item) => item.path == song.path,
    );

    if (index < 0 || _isChangingSong) return;

    setState(() {
      _isChangingSong = true;
      _currentIndex = index;
    });

    try {
      await _audioPlayer.setFilePath(song.path);
      await _audioPlayer.play();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'An kasa kunna kiɗan: ${song.name}',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isChangingSong = false;
        });
      }
    }
  }

  Future<void> _togglePlayPause() async {
    if (_currentIndex == null || _songs.isEmpty) {
      if (_filteredSongs.isNotEmpty) {
        await _playSong(_filteredSongs.first);
      }
      return;
    }

    if (_audioPlayer.playing) {
      await _audioPlayer.pause();
    } else {
      await _audioPlayer.play();
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _playNext() async {
    if (_songs.isEmpty) return;

    final current = _currentIndex ?? -1;
    final next = current + 1;

    if (next < _songs.length) {
      await _playSong(_songs[next]);
    } else {
      await _playSong(_songs.first);
    }
  }

  Future<void> _playPrevious() async {
    if (_songs.isEmpty) return;

    final current = _currentIndex ?? 0;
    final previous = current - 1;

    if (previous >= 0) {
      await _playSong(_songs[previous]);
    } else {
      await _playSong(_songs.last);
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);

    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }

  String _formatTotalSize(int bytes) {
    if (bytes < 1024) return '$bytes B';

    const units = ['KB', 'MB', 'GB', 'TB'];
    double size = bytes / 1024;
    int unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
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
          hintText: 'Bincika kiɗa...',
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
          fillColor: _cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildPermissionMessage() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.folder_off_outlined,
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
              'Ka ba MAFX SHARE izinin shiga media library '
              'domin ya nuna kiɗan wayarka.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              onPressed: _loadSongs,
              style: ElevatedButton.styleFrom(
                backgroundColor: _greenColor,
                foregroundColor: Colors.black,
              ),
              child: const Text('Sake neman izini'),
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

  Widget _buildEmptyState() {
    final searching = _searchQuery.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching
                  ? Icons.search_off
                  : Icons.music_off_outlined,
              size: 72,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            Text(
              searching ? 'Ba a sami kiɗan ba' : 'Babu kiɗa',
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
                  : 'Kiɗan da ke cikin media library na wayarka '
                      'za su bayyana a nan.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                height: 1.5,
              ),
            ),
            if (!searching) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _loadSongs,
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

  Widget _buildNowPlaying() {
    if (_currentIndex == null ||
        _currentIndex! >= _songs.length) {
      return const SizedBox.shrink();
    }

    final song = _songs[_currentIndex!];

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _greenColor.withValues(alpha: 0.4),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _greenColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.music_note_rounded,
                  color: _greenColor,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'NOW PLAYING',
                      style: TextStyle(
                        color: _greenColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      song.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      song.formattedSize,
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<Duration>(
            stream: _audioPlayer.positionStream,
            builder: (context, snapshot) {
              final position = snapshot.data ?? Duration.zero;
              final duration =
                  _audioPlayer.duration ?? Duration.zero;

              final maxMs = duration.inMilliseconds;
              final positionMs = position.inMilliseconds;

              final sliderMax = maxMs > 0 ? maxMs.toDouble() : 1.0;

              final sliderValue = positionMs
                  .clamp(0, maxMs > 0 ? maxMs : 1)
                  .toDouble();

              return Column(
                children: [
                  Slider(
                    value: sliderValue,
                    min: 0,
                    max: sliderMax,
                    onChanged: maxMs <= 0
                        ? null
                        : (value) {
                            _audioPlayer.seek(
                              Duration(
                                milliseconds: value.round(),
                              ),
                            );
                          },
                    activeColor: _greenColor,
                    inactiveColor: Colors.white24,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                    ),
                    child: Row(
                      children: [
                        Text(
                          _formatDuration(position),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          _formatDuration(duration),
                          style: const TextStyle(
                            color: Colors.white60,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              IconButton(
                onPressed: _playPrevious,
                iconSize: 30,
                color: Colors.white,
                tooltip: 'Kiɗa na baya',
                icon: const Icon(Icons.skip_previous_rounded),
              ),
              const SizedBox(width: 18),
              StreamBuilder<PlayerState>(
                stream: _audioPlayer.playerStateStream,
                builder: (context, snapshot) {
                  final state = snapshot.data;
                  final playing = state?.playing ?? false;
                  final processing = state?.processingState;

                  final loading = _isChangingSong ||
                      processing == ProcessingState.loading ||
                      processing == ProcessingState.buffering;

                  return IconButton(
                    onPressed: loading ? null : _togglePlayPause,
                    iconSize: 54,
                    color: _greenColor,
                    tooltip: playing ? 'Dakatar' : 'Kunna',
                    icon: loading
                        ? const SizedBox(
                            width: 30,
                            height: 30,
                            child: CircularProgressIndicator(
                              strokeWidth: 3,
                              color: _greenColor,
                            ),
                          )
                        : Icon(
                            playing
                                ? Icons.pause_circle_filled_rounded
                                : Icons.play_circle_fill_rounded,
                          ),
                  );
                },
              ),
              const SizedBox(width: 18),
              IconButton(
                onPressed: _playNext,
                iconSize: 30,
                color: Colors.white,
                tooltip: 'Kiɗa na gaba',
                icon: const Icon(Icons.skip_next_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final songs = _filteredSongs;

    final totalSize = _songs.fold<int>(
      0,
      (total, song) => total + song.sizeBytes,
    );

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        foregroundColor: Colors.white,
        title: const Text(
          'MAFX Music',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _loadSongs,
            tooltip: 'Sake loda kiɗa',
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
                  Icons.library_music_rounded,
                  color: _greenColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_songs.length} waƙa • '
                    '${_formatTotalSize(totalSize)}',
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
                    : songs.isEmpty
                        ? _buildEmptyState()
                        : RefreshIndicator(
                            color: _greenColor,
                            onRefresh: _loadSongs,
                            child: ListView.builder(
                              physics:
                                  const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.only(
                                bottom: 12,
                              ),
                              itemCount: songs.length,
                              itemBuilder: (context, index) {
                                final song = songs[index];
                                final isCurrent =
                                    _isCurrentSong(song);

                                return MediaFileTile(
                                  media: song,
                                  onTap: () => _playSong(song),
                                  trailing: Icon(
                                    isCurrent
                                        ? Icons.graphic_eq_rounded
                                        : Icons.play_arrow_rounded,
                                    color: isCurrent
                                        ? _greenColor
                                        : Colors.white70,
                                    size: 28,
                                  ),
                                );
                              },
                            ),
                          ),
          ),
          if (!_isLoading && _hasPermission && _songs.isNotEmpty)
            _buildNowPlaying(),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    _audioPlayer.dispose();
    super.dispose();
  }
}
