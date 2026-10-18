import 'dart:io';

import 'package:flutter/material.dart';

import '../models/media_file_model.dart';

class PhotoGrid extends StatelessWidget {
  final List<MediaFileModel> photos;
  final ValueChanged<MediaFileModel>? onPhotoTap;
  final bool showNames;
  final int crossAxisCount;
  final double spacing;

  const PhotoGrid({
    super.key,
    required this.photos,
    this.onPhotoTap,
    this.showNames = false,
    this.crossAxisCount = 3,
    this.spacing = 4,
  });

  @override
  Widget build(BuildContext context) {
    if (photos.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.photo_library_outlined,
              size: 56,
              color: Colors.white38,
            ),
            SizedBox(height: 12),
            Text(
              'Babu hotuna a nan tukuna.',
              style: TextStyle(
                color: Colors.white60,
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: EdgeInsets.all(spacing),
      itemCount: photos.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount < 1 ? 1 : crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: showNames ? 0.82 : 1,
      ),
      itemBuilder: (context, index) {
        final photo = photos[index];
        final file = File(photo.path);

        return Material(
          color: const Color(0xFF17231E),
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onPhotoTap == null
                ? null
                : () => onPhotoTap!(photo),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: file.existsSync()
                      ? Image.file(
                          file,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return const _PhotoPlaceholder();
                          },
                        )
                      : const _PhotoPlaceholder(),
                ),
                if (showNames)
                  Padding(
                    padding: const EdgeInsets.all(7),
                    child: Text(
                      photo.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PhotoPlaceholder extends StatelessWidget {
  const _PhotoPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF22332B),
      alignment: Alignment.center,
      child: const Icon(
        Icons.image_not_supported_outlined,
        color: Colors.white38,
        size: 34,
      ),
    );
  }
}
