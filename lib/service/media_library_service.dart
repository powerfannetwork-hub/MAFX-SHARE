import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:photo_manager/photo_manager.dart';

import '../models/media_file_model.dart';

/// Service for accessing media and files on the device.
class MediaLibraryService {
  static const int _pageSize = 200;

  /// Request permission to access the device media library.
  ///
  /// Returns true when permission is granted.
  Future<bool> requestPermission() async {
    final permission = await PhotoManager.requestPermissionExtend();
    return permission.isAuth || permission.hasAccess;
  }

  /// Open device settings if the user needs to grant permission manually.
  Future<void> openPermissionSettings() async {
    await PhotoManager.openSetting();
  }

  /// Load media files from the device.
  ///
  /// If [type] is null, videos, photos, and music are loaded.
  /// Documents and other arbitrary files should be selected using [pickFiles].
  Future<List<MediaFileModel>> loadMedia({
    MediaFileType? type,
  }) async {
    final hasPermission = await requestPermission();

    if (!hasPermission) {
      return <MediaFileModel>[];
    }

    final requestedTypes = _getRequestTypes(type);
    final List<MediaFileModel> results = [];

    for (final requestType in requestedTypes) {
      final assets = await _loadAssets(requestType);
      results.addAll(assets);
    }

    // Remove duplicate paths and sort newest first.
    final Map<String, MediaFileModel> uniqueFiles = {};

    for (final item in results) {
      uniqueFiles[item.path] = item;
    }

    final files = uniqueFiles.values.toList();

    files.sort((a, b) {
      final aDate = a.modifiedAt;
      final bDate = b.modifiedAt;

      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;

      return bDate.compareTo(aDate);
    });

    return files;
  }

  List<RequestType> _getRequestTypes(MediaFileType? type) {
    switch (type) {
      case MediaFileType.photo:
        return [RequestType.image];

      case MediaFileType.video:
        return [RequestType.video];

      case MediaFileType.music:
        return [RequestType.audio];

      case MediaFileType.document:
      case MediaFileType.app:
      case MediaFileType.archive:
      case MediaFileType.other:
        return [];

      case null:
        return [
          RequestType.image,
          RequestType.video,
          RequestType.audio,
        ];
    }
  }

  /// Read all available assets for one media category.
  Future<List<MediaFileModel>> _loadAssets(
    RequestType requestType,
  ) async {
    final List<MediaFileModel> files = [];

    final albums = await PhotoManager.getAssetPathList(
      type: requestType,
      onlyAll: true,
    );

    if (albums.isEmpty) {
      return files;
    }

    final allMediaAlbum = albums.first;
    int page = 0;

    while (true) {
      final assets = await allMediaAlbum.getAssetListPaged(
        page: page,
        size: _pageSize,
      );

      if (assets.isEmpty) {
        break;
      }

      for (final asset in assets) {
        try {
          final file = await asset.file;

          if (file == null || !await file.exists()) {
            continue;
          }

          final stat = await file.stat();

          MediaFileType? mediaType;

          switch (asset.type) {
            case AssetType.image:
              mediaType = MediaFileType.photo;
              break;
            case AssetType.video:
              mediaType = MediaFileType.video;
              break;
            case AssetType.audio:
              mediaType = MediaFileType.music;
              break;
            default:
              continue;
          }

          files.add(
            MediaFileModel(
              id: asset.id,
              name: asset.title ?? file.uri.pathSegments.last,
              path: file.path,
              sizeBytes: stat.size,
              type: mediaType,
              modifiedAt: stat.modified,
              mimeType: _mimeTypeFor(mediaType),
            ),
          );
        } catch (_) {
          // Skip assets that cannot be accessed.
          continue;
        }
      }

      if (assets.length < _pageSize) {
        break;
      }

      page++;
    }

    return files;
  }

  String? _mimeTypeFor(MediaFileType type) {
    switch (type) {
      case MediaFileType.photo:
        return 'image/*';
      case MediaFileType.video:
        return 'video/*';
      case MediaFileType.music:
        return 'audio/*';
      default:
        return null;
    }
  }

  /// Let the user select files using the system file picker.
  ///
  /// This is useful for documents, archives, and files outside the
  /// indexed media library.
  Future<List<MediaFileModel>> pickFiles({
    bool allowMultiple = true,
    MediaFileType? type,
  }) async {
    FileType pickerType = FileType.any;

    switch (type) {
      case MediaFileType.photo:
        pickerType = FileType.image;
        break;
      case MediaFileType.video:
        pickerType = FileType.video;
        break;
      case MediaFileType.music:
        pickerType = FileType.audio;
        break;
      case MediaFileType.document:
        pickerType = FileType.custom;
        break;
      default:
        pickerType = FileType.any;
    }

    final result = await FilePicker.platform.pickFiles(
      type: pickerType,
      allowMultiple: allowMultiple,
      withData: false,
      allowedExtensions:
          type == MediaFileType.document
              ? ['pdf', 'txt', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx']
              : null,
    );

    if (result == null) {
      return <MediaFileModel>[];
    }

    final List<MediaFileModel> files = [];

    for (final pickedFile in result.files) {
      final path = pickedFile.path;

      if (path == null) {
        continue;
      }

      final file = File(path);

      if (!await file.exists()) {
        continue;
      }

      try {
        files.add(await MediaFileModel.fromFile(file));
      } catch (_) {
        // Ignore files that cannot be read.
      }
    }

    return files;
  }

  /// Load files received and saved inside the app's documents directory.
  ///
  /// This finds files whose names start with "mafx_received_".
  Future<List<MediaFileModel>> loadReceivedFiles() async {
    final directory = await getApplicationDocumentsDirectory();

    if (!await directory.exists()) {
      return <MediaFileModel>[];
    }

    final List<MediaFileModel> files = [];

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }

      final filename = entity.uri.pathSegments.isNotEmpty
          ? entity.uri.pathSegments.last
          : '';

      if (!filename.startsWith('mafx_received_')) {
        continue;
      }

      try {
        files.add(await MediaFileModel.fromFile(entity));
      } catch (_) {
        // Ignore files that cannot be read.
      }
    }

    files.sort((a, b) {
      final aDate = a.modifiedAt;
      final bDate = b.modifiedAt;

      if (aDate == null && bDate == null) return 0;
      if (aDate == null) return 1;
      if (bDate == null) return -1;

      return bDate.compareTo(aDate);
    });

    return files;
  }

  /// Refresh the device media index after files are added or removed.
  Future<void> refreshMediaLibrary() async {
    await PhotoManager.clearFileCache();
  }
}
