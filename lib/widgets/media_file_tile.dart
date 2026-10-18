import 'package:flutter/material.dart';

import '../models/media_file_model.dart';

class MediaFileTile extends StatelessWidget {
  final MediaFileModel media;
  final VoidCallback? onTap;
  final VoidCallback? onMoreTap;
  final Widget? trailing;

  const MediaFileTile({
    super.key,
    required this.media,
    this.onTap,
    this.onMoreTap,
    this.trailing,
  });

  IconData _getIcon() {
    switch (media.type) {
      case MediaFileType.video:
        return Icons.play_circle_fill_rounded;
      case MediaFileType.photo:
        return Icons.image_rounded;
      case MediaFileType.music:
        return Icons.music_note_rounded;
      case MediaFileType.document:
        return Icons.description_rounded;
      case MediaFileType.app:
        return Icons.android_rounded;
      case MediaFileType.archive:
        return Icons.folder_zip_rounded;
      case MediaFileType.other:
        return Icons.insert_drive_file_rounded;
    }
  }

  Color _getColor() {
    switch (media.type) {
      case MediaFileType.video:
        return const Color(0xFF00C853);
      case MediaFileType.photo:
        return const Color(0xFF40C4FF);
      case MediaFileType.music:
        return const Color(0xFFFFAB40);
      case MediaFileType.document:
        return const Color(0xFF448AFF);
      case MediaFileType.app:
        return const Color(0xFF69F0AE);
      case MediaFileType.archive:
        return const Color(0xFFB388FF);
      case MediaFileType.other:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _getColor();

    return Card(
      color: const Color(0xFF1B1B1B),
      margin: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 5,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 5,
        ),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            _getIcon(),
            color: color,
            size: 28,
          ),
        ),
        title: Text(
          media.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(
            '${media.typeLabel} • ${media.formattedSize}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white60,
              fontSize: 12,
            ),
          ),
        ),
        trailing: trailing ??
            (onMoreTap == null
                ? null
                : IconButton(
                    onPressed: onMoreTap,
                    icon: const Icon(
                      Icons.more_vert,
                      color: Colors.white70,
                    ),
                  )),
        onTap: onTap,
      ),
    );
  }
}
