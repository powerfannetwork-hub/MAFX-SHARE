import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/transfer_service.dart';

class SendScreen extends StatefulWidget {
  final String receiverUrl;
  final String receiverToken;
  final String? category;

  const SendScreen({
    super.key,
    required this.receiverUrl,
    required this.receiverToken,
    this.category,
  });

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final TransferService _transferService = TransferService.instance;

  List<PlatformFile> _files = [];

  bool _isPicking = false;
  bool _isSending = false;

  int _sentCount = 0;
  int _failedCount = 0;

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

  Future<void> _pickFiles() async {
    if (_isPicking || _isSending) return;

    setState(() {
      _isPicking = true;
    });

    try {
      final extensions = _allowedExtensions;

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: extensions.isEmpty ? FileType.any : FileType.custom,
        allowedExtensions: extensions.isEmpty ? null : extensions,
        withData: false,
      );

      if (!mounted || result == null) return;

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

  Future<void> _sendFiles() async {
    if (_isSending) return;

    if (_files.isEmpty) {
      _showMessage('Choose at least one file first.');
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

    setState(() {
      _isSending = true;
      _sentCount = 0;
      _failedCount = 0;
    });

    for (final file in List<PlatformFile>.from(_files)) {
      if (!mounted) return;

      final path = file.path;

      if (path == null || path.isEmpty) {
        setState(() {
          _failedCount++;
        });
        continue;
      }

      try {
        await _transferService.sendFile(
          receiverUrl: widget.receiverUrl,
          token: widget.receiverToken,
          filePath: path,
          fileName: file.name,
        );

        if (!mounted) return;

        setState(() {
          _sentCount++;
        });
      } catch (error) {
        debugPrint('Failed to send ${file.name}: $error');

        if (!mounted) return;

        setState(() {
          _failedCount++;
        });
      }
    }

    if (!mounted) return;

    setState(() {
      _isSending = false;
    });

    if (_failedCount == 0) {
      _showMessage('All selected files were sent successfully.');
    } else {
      _showMessage(
        'Transfer finished: $_sentCount sent, $_failedCount failed.',
      );
    }
  }

  void _removeFile(int index) {
    if (_isSending) return;

    setState(() {
      _files.removeAt(index);
    });
  }

  void _clearFiles() {
    if (_isSending) return;

    setState(() {
      _files.clear();
    });
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

  Widget _buildEmptyState() {
    String message;

    switch (_category) {
      case 'photos':
        message = 'Select photos to share.';
        break;
      case 'videos':
        message = 'Select videos to share.';
        break;
      case 'music':
        message = 'Select music files to share.';
        break;
      case 'apps':
        message = 'Select APK or supported app package files.';
        break;
      default:
        message = 'Select files to share.';
    }

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
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _isPicking || _isSending ? null : _pickFiles,
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
        Text('Total size: ${_formatSize(_totalSize)}'),
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
                onPressed: _isSending ? null : () => _removeFile(index),
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
          onPressed: _isPicking || _isSending ? null : _pickFiles,
          icon: const Icon(Icons.add),
          label: const Text('Add More Files'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _files.isEmpty || _isSending ? null : _clearFiles,
          icon: const Icon(Icons.delete_outline),
          label: const Text('Clear Selection'),
        ),
        if (_isSending || _sentCount > 0 || _failedCount > 0) ...[
          const SizedBox(height: 18),
          Text(
            'Sent: $_sentCount    Failed: $_failedCount',
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_isSending) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              'Sending files. Please keep the app open.',
              textAlign: TextAlign.center,
            ),
          ],
        ],
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
            child: _files.isEmpty ? _buildEmptyState() : _buildFileList(),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _files.isEmpty || _isSending || _isPicking
                      ? null
                      : _sendFiles,
                  icon: _isSending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    _isSending ? 'Sending...' : 'Send Files',
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
