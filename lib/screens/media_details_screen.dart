import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';

import '../models/media_file_model.dart';

class MediaDetailsScreen extends StatelessWidget {
  final MediaFileModel media;

  const MediaDetailsScreen({
    super.key,
    required this.media,
  });

  IconData _getIcon() {
    switch (media.type) {
      case MediaFileType.video:
        return Icons.video_file_rounded;
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

  Future<void> _copyPath(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: media.path));

    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('An kwafi hanyar fayil ɗin.'),
      ),
    );
  }

  Future<void> _openFile(BuildContext context) async {
    if (!media.exists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ba a sami wannan fayil ɗin a na’ura ba.'),
        ),
      );
      return;
    }

    try {
      await OpenFilex.open(media.path);
    } catch (error) {
      if (!context.mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An kasa buɗe fayil ɗin: $error'),
        ),
      );
    }
  }

  Widget _buildDetail({
    required IconData icon,
    required String title,
    required String value,
    bool selectable = false,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1B2522),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: const Color(0xFF00D09C),
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 5),
                SelectableText(
                  value.isEmpty ? 'Ba a sani ba' : value,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          if (selectable)
            IconButton(
              tooltip: 'Kwafi',
              onPressed: () {},
              icon: const Icon(
                Icons.copy_rounded,
                color: Colors.white54,
                size: 18,
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final modifiedAt = media.modifiedAt;

    return Scaffold(
      backgroundColor: const Color(0xFF0B1411),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101C17),
        foregroundColor: Colors.white,
        title: const Text('Bayanan Fayil'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                vertical: 28,
                horizontal: 16,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF14251E),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  Icon(
                    _getIcon(),
                    color: const Color(0xFF00D09C),
                    size: 76,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    media.name,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    media.formattedSize,
                    style: const TextStyle(
                      color: Color(0xFF00D09C),
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'Cikakken Bayani',
              style: TextStyle(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 14),
            _buildDetail(
              icon: Icons.category_rounded,
              title: 'Nau’in fayil',
              value: media.typeLabel,
            ),
            _buildDetail(
              icon: Icons.storage_rounded,
              title: 'Girman fayil',
              value: media.formattedSize,
            ),
            _buildDetail(
              icon: Icons.folder_open_rounded,
              title: 'Hanyar fayil',
              value: media.path,
            ),
            _buildDetail(
              icon: Icons.calendar_today_rounded,
              title: 'Lokacin gyara',
              value: modifiedAt == null
                  ? 'Ba a sani ba'
                  : modifiedAt.toLocal().toString(),
            ),
            _buildDetail(
              icon: Icons.description_outlined,
              title: 'Nau’in MIME',
              value: media.mimeType ?? 'Ba a sani ba',
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: ElevatedButton.icon(
                onPressed: () => _openFile(context),
                icon: const Icon(Icons.open_in_new_rounded),
                label: const Text('Buɗe Fayil'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00D09C),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () => _copyPath(context),
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Kwafi Hanyar Fayil'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF00D09C),
                  side: const BorderSide(
                    color: Color(0xFF00D09C),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
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
