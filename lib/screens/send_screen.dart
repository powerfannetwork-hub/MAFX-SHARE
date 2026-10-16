import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'connect_screen.dart';

class SendScreen extends StatefulWidget {
  final String? category;

  const SendScreen({
    super.key,
    this.category,
  });

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  List<PlatformFile> _files = [];

  bool _isPicking = false;

  String get _category =>
      widget.category?.trim().toLowerCase() ?? 'files';

  String get _screenTitle {
    if (widget.category == null) {
      return 'Send Files';
    }

    return 'Send ${widget.category}';
  }

  IconData get _categoryIcon {
    switch (_category) {
      case 'photos':
        return Icons.photo_library_rounded;
      case 'videos':
        return Icons.video_library_rounded;
      case 'music':
        return Icons.music_note_rounded;
      case 'apps':
        return Icons.apps_rounded;
      default:
        return Icons.folder_rounded;
    }
  }

  List<String> get _allowedExtensions {
    switch (_category) {
      case 'photos':
        return [
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
        ];

      case 'videos':
        return [
          'mp4',
          'm4v',
          'mov',
          'avi',
          'mkv',
          'webm',
          '3gp',
          'mpeg',
          'mpg',
        ];

      case 'music':
        return [
          'mp3',
          'm4a',
          'aac',
          'wav',
          'ogg',
          'flac',
          'wma',
          'opus',
          'amr',
        ];

      case 'apps':
        return [
          'apk',
          'xapk',
          'apks',
        ];

      default:
        return [];
    }
  }

  String get _selectionMessage {
    switch (_category) {
      case 'photos':
        return 'Select photos to share.';
      case 'videos':
        return 'Select videos to share.';
      case 'music':
        return 'Select music files to share.';
      case 'apps':
        return 'Select APK or supported app package files.';
      default:
        return 'Select files to share.';
    }
  }

  Future<void> _pickFiles() async {
    if (_isPicking) return;

    setState(() {
      _isPicking = true;
    });

    try {
      final extensions = _allowedExtensions;

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: extensions.isEmpty
            ? FileType.any
            : FileType.custom,
        allowedExtensions:
            extensions.isEmpty ? null : extensions,
        withData: false,
      );

      if (!mounted) return;

      if (result == null) {
        return;
      }

      final existingPaths = _files
          .map((file) => file.path)
          .whereType<String>()
          .toSet();

      final newFiles = result.files.where((file) {
        final path = file.path;

        if (path == null || path.isEmpty) {
          return true;
        }

        return !existingPaths.contains(path);
      }).toList();

      setState(() {
        _files.addAll(newFiles);
      });

      if (newFiles.isEmpty && result.files.isNotEmpty) {
        _showMessage('These files have already been selected.');
      }
    } catch (error) {
      if (mounted) {
        _showMessage('Unable to select files: $error');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
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

  void _removeFile(int index) {
    setState(() {
      _files.removeAt(index);
    });
  }

  void _clearFiles() {
    setState(() {
      _files.clear();
    });
  }

  String _formatSize(int bytes) {
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

  int get _totalSize {
    return _files.fold<int>(
      0,
      (total, file) => total + file.size,
    );
  }

  Future<void> _continueToConnect() async {
    if (_files.isEmpty) {
      _showMessage('Select at least one file first.');
      return;
    }

    final invalidFiles = _files.where((file) {
      final path = file.path;
      return path == null || path.isEmpty;
    }).toList();

    if (invalidFiles.isNotEmpty) {
      _showMessage(
        'Some files cannot be accessed. Remove them and select them again.',
      );
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ConnectScreen(
          files: List<PlatformFile>.from(_files),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _categoryIcon,
              size: 82,
              color: const Color(0xFF00AEEF),
            ),
            const SizedBox(height: 18),
            Text(
              _selectionMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isPicking ? null : _pickFiles,
              icon: const Icon(Icons.add),
              label: Text(
                _isPicking ? 'Opening...' : 'Choose Files',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${_files.length} file(s) selected',
          style: const TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Total size: ${_formatSize(_totalSize)}',
          style: TextStyle(
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 14),
        ...List.generate(_files.length, (index) {
          final file = _files[index];

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            child: ListTile(
              leading: Icon(_categoryIcon),
              title: Text(
                file.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(_formatSize(file.size)),
              trailing: IconButton(
                onPressed: () => _removeFile(index),
                icon: const Icon(
                  Icons.close,
                  color: Colors.red,
                ),
                tooltip: 'Remove file',
              ),
            ),
          );
        }),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _isPicking ? null : _pickFiles,
          icon: const Icon(Icons.add),
          label: const Text('Add More Files'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _files.isEmpty ? null : _clearFiles,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear Selection'),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_screenTitle),
      ),
      body: Column(
        children: [
          Expanded(
            child: _files.isEmpty
                ? _buildEmptyState()
                : _buildFileList(),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _files.isEmpty
                      ? null
                      : _continueToConnect,
                  icon: const Icon(Icons.devices),
                  label: const Text('Continue to Connect'),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
