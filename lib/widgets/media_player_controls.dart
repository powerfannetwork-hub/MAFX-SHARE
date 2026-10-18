import 'package:flutter/material.dart';

class MediaPlayerControls extends StatelessWidget {
  final bool isPlaying;
  final Duration position;
  final Duration duration;
  final VoidCallback onPlayPause;
  final ValueChanged<Duration> onSeek;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final bool showSkipButtons;

  const MediaPlayerControls({
    super.key,
    required this.isPlaying,
    required this.position,
    required this.duration,
    required this.onPlayPause,
    required this.onSeek,
    this.onPrevious,
    this.onNext,
    this.showSkipButtons = true,
  });

  String _formatDuration(Duration duration) {
    final totalSeconds = duration.inSeconds < 0
        ? 0
        : duration.inSeconds;

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    String twoDigits(int value) => value.toString().padLeft(2, '0');

    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }

    return '$minutes:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final safeDuration =
        duration.inMilliseconds > 0 ? duration : Duration.zero;

    final safePosition = position.inMilliseconds < 0
        ? Duration.zero
        : position > safeDuration
            ? safeDuration
            : position;

    final maxMilliseconds = safeDuration.inMilliseconds.toDouble();
    final currentMilliseconds =
        safePosition.inMilliseconds.toDouble();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Slider(
          value: maxMilliseconds > 0 ? currentMilliseconds : 0,
          min: 0,
          max: maxMilliseconds > 0 ? maxMilliseconds : 1,
          onChanged: maxMilliseconds > 0
              ? (value) {
                  onSeek(
                    Duration(milliseconds: value.round()),
                  );
                }
              : null,
          activeColor: const Color(0xFF00D09C),
          inactiveColor: Colors.white24,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(safePosition),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              Text(
                _formatDuration(safeDuration),
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (showSkipButtons)
              IconButton(
                onPressed: onPrevious,
                tooltip: 'Na baya',
                icon: const Icon(
                  Icons.skip_previous_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
            const SizedBox(width: 12),
            Container(
              decoration: const BoxDecoration(
                color: Color(0xFF00D09C),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                onPressed: onPlayPause,
                tooltip: isPlaying ? 'Dakatar' : 'Kunna',
                icon: Icon(
                  isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                  color: Colors.black,
                  size: 36,
                ),
              ),
            ),
            const SizedBox(width: 12),
            if (showSkipButtons)
              IconButton(
                onPressed: onNext,
                tooltip: 'Na gaba',
                icon: const Icon(
                  Icons.skip_next_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
          ],
        ),
      ],
    );
  }
}
