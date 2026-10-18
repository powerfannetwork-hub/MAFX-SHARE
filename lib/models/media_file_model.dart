import 'dart:io';

/// Nau'ikan fayilolin da MAFX SHARE zai iya sarrafawa.
enum MediaFileType {
  video,
  photo,
  music,
  document,
  app,
  archive,
  other,
}

/// Bayanan fayil guda ɗaya a cikin MAFX SHARE.
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

  /// Ƙirƙirar MediaFileModel daga fayil da ke cikin wayar.
  factory MediaFileModel.fromFile(File file) {
    final stat = file.statSync();
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

  /// Gane nau'in fayil ta extension.
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

  /// MIME type na fayil.
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

      // Apps and archives
      'apk': 'application/vnd.android.package-archive',
      'xapk': 'application/xapk',
      'zip': 'application/zip',
      'rar': 'application/vnd.rar',
      '7z': 'application/x-7z-compressed',
      'tar': 'application/x-tar',
      'gz': 'application/gzip',
    };

    return mimeTypes[extension] ?? 'application/octet-stream';
  }

  static const Set<String> _videoExtensions = {
    'mp4',
    'm4v',
    'mov',
    'mkv',
    'webm',
    'avi',
    '3gp',
    'ts',
    'mpg',
    'mpeg',
    'wmv',
    'flv',
    'm2ts',
    'mts',
  };

  static const Set<String> _photoExtensions = {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'bmp',
    'heic',
    'heif',
    'tif',
    'tiff',
    'svg',
    'dng',
    'raw',
  };

  static const Set<String> _musicExtensions = {
    'mp3',
    'm4a',
    'aac',
    'wav',
    'ogg',
    'oga',
    'opus',
    'flac',
    'wma',
    'mid',
    'midi',
    'aiff',
    'aif',
    'amr',
  };

  static const Set<String> _documentExtensions = {
    'pdf',
    'txt',
    'csv',
    'json',
    'xml',
    'html',
    'htm',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'rtf',
    'odt',
    'ods',
    'odp',
  };

  static const Set<String> _appExtensions = {
    'apk',
    'xapk',
    'apks',
  };

  static const Set<String> _archiveExtensions = {
    'zip',
    'rar',
    '7z',
    'tar',
    'gz',
    'bz2',
    'xz',
  };

  /// Girman fayil cikin KB, MB ko GB.
  String get formattedSize {
    if (sizeBytes < 1024) {
      return '$sizeBytes B';
    }

    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    }

    if (sizeBytes < 1024 * 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return '${(sizeBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Sunan nau'in fayil don nunawa a UI.
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

  /// Ko fayil ɗin yana nan a wurin da aka ajiye shi.
  Future<bool> get exists async {
    return File(path).exists();
  }

  /// Bayanan da za a iya adanawa a JSON.
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

  /// Mayar da JSON zuwa MediaFileModel.
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

  /// Samar da sabon model idan ana son sabunta wasu bayanai.
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
