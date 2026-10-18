import 'dart:io';

/// Supported file types in MAFX SHARE.
enum MediaFileType {
  video,
  photo,
  music,
  document,
  app,
  archive,
  other,
}

/// Represents a single file in MAFX SHARE.
class MediaFileModel {
  final String id;
  final String name;
  final String path;
  final int sizeBytes;
  final MediaFileType type;
  final DateTime? modifiedAt;
  final String? mimeType;

  const MediaFileModel({
    required this.id,
    required this.name,
    required this.path,
    required this.sizeBytes,
    required this.type,
    this.modifiedAt,
    this.mimeType,
  });

  /// Creates a MediaFileModel from a file.
  static Future<MediaFileModel> fromFile(File file) async {
    final stat = await file.stat();

    final name = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : file.path;

    return MediaFileModel(
      id: file.absolute.path,
      name: name,
      path: file.path,
      sizeBytes: stat.size,
      type: typeFromName(name),
      modifiedAt: stat.modified,
      mimeType: mimeTypeFromName(name),
    );
  }

  /// Determines the file type from its extension.
  static MediaFileType typeFromName(String name) {
    final lowerName = name.toLowerCase();
    final dotIndex = lowerName.lastIndexOf('.');

    if (dotIndex < 0 || dotIndex == lowerName.length - 1) {
      return MediaFileType.other;
    }

    final extension = lowerName.substring(dotIndex + 1);

    if (_videoExtensions.contains(extension)) {
      return MediaFileType.video;
    }

    if (_photoExtensions.contains(extension)) {
      return MediaFileType.photo;
    }

    if (_musicExtensions.contains(extension)) {
      return MediaFileType.music;
    }

    if (_documentExtensions.contains(extension)) {
      return MediaFileType.document;
    }

    if (_appExtensions.contains(extension)) {
      return MediaFileType.app;
    }

    if (_archiveExtensions.contains(extension)) {
      return MediaFileType.archive;
    }

    return MediaFileType.other;
  }

  /// Returns the MIME type for a file.
  static String mimeTypeFromName(String name) {
    final lowerName = name.toLowerCase();
    final dotIndex = lowerName.lastIndexOf('.');

    if (dotIndex < 0 || dotIndex == lowerName.length - 1) {
      return 'application/octet-stream';
    }

    final extension = lowerName.substring(dotIndex + 1);

    const mimeTypes = <String, String>{
      // Videos
      'mp4': 'video/mp4',
      'm4v': 'video/x-m4v',
      'mov': 'video/quicktime',
      'mkv': 'video/x-matroska',
      'webm': 'video/webm',
      'avi': 'video/x-msvideo',
      '3gp': 'video/3gpp',
      'ts': 'video/mp2t',
      'mpg': 'video/mpeg',
      'mpeg': 'video/mpeg',
      'wmv': 'video/x-ms-wmv',
      'flv': 'video/x-flv',
      'm2ts': 'video/mp2t',
      'mts': 'video/mp2t',

      // Photos
      'jpg': 'image/jpeg',
      'jpeg': 'image/jpeg',
      'png': 'image/png',
      'gif': 'image/gif',
      'webp': 'image/webp',
      'bmp': 'image/bmp',
      'heic': 'image/heic',
      'heif': 'image/heif',
      'tif': 'image/tiff',
      'tiff': 'image/tiff',
      'svg': 'image/svg+xml',
      'dng': 'image/x-adobe-dng',
      'raw': 'image/x-raw',

      // Music
      'mp3': 'audio/mpeg',
      'm4a': 'audio/mp4',
      'aac': 'audio/aac',
      'wav': 'audio/wav',
      'ogg': 'audio/ogg',
      'oga': 'audio/ogg',
      'opus': 'audio/opus',
      'flac': 'audio/flac',
      'wma': 'audio/x-ms-wma',
      'mid': 'audio/midi',
      'midi': 'audio/midi',
      'aiff': 'audio/aiff',
      'aif': 'audio/aiff',
      'amr': 'audio/amr',

      // Documents
      'pdf': 'application/pdf',
      'txt': 'text/plain',
      'csv': 'text/csv',
      'json': 'application/json',
      'xml': 'application/xml',
      'html': 'text/html',
      'htm': 'text/html',
      'doc': 'application/msword',
      'docx':
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'xls': 'application/vnd.ms-excel',
      'xlsx':
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      'ppt': 'application/vnd.ms-powerpoint',
      'pptx':
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'rtf': 'application/rtf',
      'odt': 'application/vnd.oasis.opendocument.text',
      'ods': 'application/vnd.oasis.opendocument.spreadsheet',
      'odp': 'application/vnd.oasis.opendocument.presentation',

      // Apps and archives
      'apk': 'application/vnd.android.package-archive',
      'xapk': 'application/xapk',
      'apks': 'application/vnd.android.package-archive',
      'zip': 'application/zip',
      'rar': 'application/vnd.rar',
      '7z': 'application/x-7z-compressed',
      'tar': 'application/x-tar',
      'gz': 'application/gzip',
      'bz2': 'application/x-bzip2',
      'xz': 'application/x-xz',
    };

    return mimeTypes[extension] ?? 'application/octet-stream';
  }

  static const Set<String> _videoExtensions = {
    'mp4', 'm4v', 'mov', 'mkv', 'webm', 'avi', '3gp', 'ts',
    'mpg', 'mpeg', 'wmv', 'flv', 'm2ts', 'mts',
  };

  static const Set<String> _photoExtensions = {
    'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif',
    'tif', 'tiff', 'svg', 'dng', 'raw',
  };

  static const Set<String> _musicExtensions = {
    'mp3', 'm4a', 'aac', 'wav', 'ogg', 'oga', 'opus', 'flac',
    'wma', 'mid', 'midi', 'aiff', 'aif', 'amr',
  };

  static const Set<String> _documentExtensions = {
    'pdf', 'txt', 'csv', 'json', 'xml', 'html', 'htm', 'doc',
    'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'rtf', 'odt', 'ods', 'odp',
  };

  static const Set<String> _appExtensions = {
    'apk', 'xapk', 'apks',
  };

  static const Set<String> _archiveExtensions = {
    'zip', 'rar', '7z', 'tar', 'gz', 'bz2', 'xz',
  };

  /// Formats a file size in bytes, KB, MB, or GB.
  static String formatBytes(int bytes) {
    if (bytes < 0) {
      return 'Unknown size';
    }

    if (bytes < 1024) {
      return '$bytes B';
    }

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Returns the formatted file size.
  String get formattedSize => formatBytes(sizeBytes);

  /// Returns a display label for the file type.
  String get typeLabel {
    switch (type) {
      case MediaFileType.video:
        return 'Video';
      case MediaFileType.photo:
        return 'Photo';
      case MediaFileType.music:
        return 'Music';
      case MediaFileType.document:
        return 'Document';
      case MediaFileType.app:
        return 'App';
      case MediaFileType.archive:
        return 'Archive';
      case MediaFileType.other:
        return 'Other';
    }
  }

  /// Checks whether the file exists at its path.
  Future<bool> get exists => File(path).exists();

  /// Converts the model to JSON.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'path': path,
      'sizeBytes': sizeBytes,
      'type': type.name,
      'modifiedAt': modifiedAt?.toIso8601String(),
      'mimeType': mimeType,
    };
  }

  /// Creates a model from JSON.
  factory MediaFileModel.fromJson(Map<String, dynamic> json) {
    final typeName = json['type'] as String? ?? 'other';

    final type = MediaFileType.values.firstWhere(
      (value) => value.name == typeName,
      orElse: () => MediaFileType.other,
    );

    return MediaFileModel(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      path: json['path'] as String? ?? '',
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      type: type,
      modifiedAt: DateTime.tryParse(
        json['modifiedAt'] as String? ?? '',
      ),
      mimeType: json['mimeType'] as String?,
    );
  }

  /// Creates a copy of the model with updated values.
  MediaFileModel copyWith({
    String? id,
    String? name,
    String? path,
    int? sizeBytes,
    MediaFileType? type,
    DateTime? modifiedAt,
    String? mimeType,
  }) {
    return MediaFileModel(
      id: id ?? this.id,
      name: name ?? this.name,
      path: path ?? this.path,
      sizeBytes: sizeBytes ?? this.sizeBytes,
      type: type ?? this.type,
      modifiedAt: modifiedAt ?? this.modifiedAt,
      mimeType: mimeType ?? this.mimeType,
    );
  }
}
