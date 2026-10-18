import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class PlayerScreen extends StatefulWidget {
  final String videoPath;
  final String? title;

  const PlayerScreen({
    super.key,
    required this.videoPath,
    this.title,
  });

  @override
  State<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends State<PlayerScreen> {
  VideoPlayerController? _controller;

  bool _isInitialized = false;
  bool _hasError = false;
  bool _showControls = true;
  bool _isFullScreen = false;
  bool _isMuted = false;
  bool _isLoading = true;

  double _volume = 1.0;

  @override
  void initState() {
    super.initState();
    _initializePlayer();
  }

  Future<void> _initializePlayer() async {
    final oldController = _controller;
    _controller = null;

    if (oldController != null) {
      await oldController.dispose();
    }

    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _isInitialized = false;
      _hasError = false;
    });

    VideoPlayerController? controller;

    try {
      final file = File(widget.videoPath);

      if (!await file.exists()) {
        throw FileSystemException(
          'Ba a sami fayil ɗin bidiyon ba.',
          widget.videoPath,
        );
      }

      controller = VideoPlayerController.file(file);
      _controller = controller;

      await controller.initialize();
      await controller.setVolume(_isMuted ? 0 : _volume);
      await controller.setLooping(false);

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _isInitialized = true;
        _hasError = false;
        _isLoading = false;
      });

      await controller.play();
    } catch (error) {
      if (controller != null) {
        await controller.dispose();

        if (identical(_controller, controller)) {
          _controller = null;
        }
      }

      if (!mounted) return;

      setState(() {
        _hasError = true;
        _isInitialized = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _togglePlayPause() async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    if (controller.value.isPlaying) {
      await controller.pause();
    } else {
      await controller.play();
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleMute() async {
    final controller = _controller;

    if (controller == null) return;

    final mute = !_isMuted;

    await controller.setVolume(mute ? 0 : _volume);

    if (!mounted) return;

    setState(() {
      _isMuted = mute;
    });
  }

  Future<void> _changeVolume(double value) async {
    final controller = _controller;

    if (controller == null) return;

    await controller.setVolume(value);

    if (!mounted) return;

    setState(() {
      _volume = value;
      _isMuted = value == 0;
    });
  }

  Future<void> _seekRelative(int seconds) async {
    final controller = _controller;

    if (controller == null || !controller.value.isInitialized) {
      return;
    }

    final position = controller.value.position;
    final duration = controller.value.duration;

    var newPosition = position + Duration(seconds: seconds);

    if (newPosition < Duration.zero) {
      newPosition = Duration.zero;
    }

    if (newPosition > duration) {
      newPosition = duration;
    }

    await controller.seekTo(newPosition);

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _toggleFullScreen() async {
    if (_isFullScreen) {
      await SystemChrome.setPreferredOrientations(
        const [
          DeviceOrientation.portraitUp,
          DeviceOrientation.portraitDown,
        ],
      );

      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.edgeToEdge,
      );
    } else {
      await SystemChrome.setPreferredOrientations(
        const [
          DeviceOrientation.landscapeLeft,
          DeviceOrientation.landscapeRight,
        ],
      );

      await SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
      );
    }

    if (!mounted) return;

    setState(() {
      _isFullScreen = !_isFullScreen;
      _showControls = true;
    });
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:'
          '${minutes.toString().padLeft(2, '0')}:'
          '${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  Widget _buildErrorView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.video_library_outlined,
              size: 72,
              color: Colors.white54,
            ),
            const SizedBox(height: 16),
            const Text(
              'An kasa buɗe bidiyon',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ka tabbatar cewa bidiyon yana nan, '
              'kuma wayarka tana iya kunna tsarin bidiyon.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _initializePlayer,
              icon: const Icon(Icons.refresh),
              label: const Text('Sake gwadawa'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoControls() {
    final controller = _controller;

    if (controller == null || !_isInitialized) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: AnimatedOpacity(
        opacity: _showControls ? 1 : 0,
        duration: const Duration(milliseconds: 200),
        child: IgnorePointer(
          ignoring: !_showControls,
          child: Container(
            color: Colors.black26,
            child: Column(
              children: [
                Row(
                  children: [
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(
                        Icons.arrow_back,
                        color: Colors.white,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        widget.title ?? 'MAFX Player',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: _toggleMute,
                      icon: Icon(
                        _isMuted
                            ? Icons.volume_off
                            : Icons.volume_up,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      onPressed: () => _seekRelative(-10),
                      iconSize: 38,
                      icon: const Icon(
                        Icons.replay_10,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 18),
                    IconButton(
                      onPressed: _togglePlayPause,
                      iconSize: 64,
                      icon: Icon(
                        controller.value.isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_filled,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(width: 18),
                    IconButton(
                      onPressed: () => _seekRelative(10),
                      iconSize: 38,
                      icon: const Icon(
                        Icons.forward_10,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Column(
                    children: [
                      VideoProgressIndicator(
                        controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Color(0xFF00C853),
                          bufferedColor: Colors.white38,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            _formatDuration(controller.value.position),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                            ),
                          ),
                          const Text(
                            ' / ',
                            style: TextStyle(color: Colors.white70),
                          ),
                          Text(
                            _formatDuration(controller.value.duration),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 12,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _toggleFullScreen,
                            tooltip: 'Full screen',
                            icon: Icon(
                              _isFullScreen
                                  ? Icons.fullscreen_exit
                                  : Icons.fullscreen,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      Row(
                        children: [
                          const Icon(
                            Icons.volume_down,
                            color: Colors.white70,
                            size: 18,
                          ),
                          Expanded(
                            child: Slider(
                              value: _volume,
                              min: 0,
                              max: 1,
                              onChanged: _changeVolume,
                              activeColor: const Color(0xFF00C853),
                              inactiveColor: Colors.white24,
                            ),
                          ),
                          const Icon(
                            Icons.volume_up,
                            color: Colors.white70,
                            size: 18,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        top: !_isFullScreen,
        bottom: !_isFullScreen,
        child: _hasError
            ? _buildErrorView()
            : _isLoading || !_isInitialized || controller == null
                ? const Center(
                    child: CircularProgressIndicator(
                      color: Color(0xFF00C853),
                    ),
                  )
                : GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _showControls = !_showControls;
                      });
                    },
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Center(
                          child: AspectRatio(
                            aspectRatio: controller.value.aspectRatio > 0
                                ? controller.value.aspectRatio
                                : 16 / 9,
                            child: VideoPlayer(controller),
                          ),
                        ),
                        _buildVideoControls(),
                      ],
                    ),
                  ),
      ),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();

    SystemChrome.setPreferredOrientations(
      const [
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ],
    );

    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.edgeToEdge,
    );

    super.dispose();
  }
}
