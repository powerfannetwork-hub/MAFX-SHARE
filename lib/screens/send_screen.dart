import 'dart:io';

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
  static const Color green = Color(0xFF008D5A);
  static const Color accent = Color(0xFF00D18B);
  static const Color background = Color(0xFF19191D);
  static const Color surface = Color(0xFF29292F);

  final TransferService _transferService = TransferService.instance;

  final List<PlatformFile> _files = [];

  bool _picking = false;
  bool _sending = false;

  int _currentIndex = 0;
  int _sentCount = 0;
  int _failedCount = 0;

  String get _category =>
      widget.category?.toLowerCase().trim() ?? 'files';

  String get _title {
    switch (_category) {
      case 'apps':
        return 'Send Apps';
      case 'photos':
        return 'Send Photos';
      case 'videos':
        return 'Send Videos';
      case 'music':
        return 'Send Music';
      default:
        return 'Send Files';
    }
  }

  IconData get _categoryIcon {
    switch (_category) {
      case 'apps':
        return Icons.apps_rounded;
      case 'photos':
        return Icons.photo_library_rounded;
      case 'videos':
        return Icons.video_library_rounded;
      case 'music':
        return Icons.music_note_rounded;
      default:
        return Icons.folder_rounded;
    }
  }

  List<String>? get _extensions {
    switch (_category) {
      case 'photos':
        return [
          'jpg', 'jpeg', 'png', 'gif', 'webp',
          'bmp', 'heic', 'heif',
        ];
      case 'videos':
        return [
          'mp4', 'm4v', 'mov', 'avi', 'mkv',
          'webm', '3gp', 'mpeg', 'mpg',
        ];
      case 'music':
        return [
          'mp3', 'm4a', 'aac', 'wav', 'ogg',
          'flac', 'wma', 'opus', 'amr',
        ];
      case 'apps':
        return ['apk', 'xapk', 'apks'];
      default:
        return null;
    }
  }

  int get _totalBytes =>
      _files.fold(0, (total, file) => total + file.size);

  double get _progress {
    if (_files.isEmpty) return 0;

    return (_sentCount + _failedCount) / _files.length;
  }

  Future<void> _pickFiles() async {
    if (_picking || _sending) return;

    setState(() => _picking = true);

    try {
      final extensions = _extensions;

      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: extensions == null ? FileType.any : FileType.custom,
        allowedExtensions: extensions,
        withData: false,
      );

      if (!mounted || result == null) return;

      final knownPaths = _files
          .map((file) => file.path)
          .whereType<String>()
          .toSet();

      final knownNames = _files.map((file) => file.name).toSet();

      final additions = result.files.where((file) {
        final path = file.path;

        if (path != null && path.isNotEmpty) {
          return !knownPaths.contains(path);
        }

        return !knownNames.contains(file.name);
      }).toList();

      setState(() {
        _files.addAll(additions);
      });

      if (additions.isEmpty) {
        _showMessage('No new files were added.');
      }
    } catch (error) {
      _showMessage('Unable to open file picker: $error');
    } finally {
      if (mounted) {
        setState(() => _picking = false);
      }
    }
  }

  Future<void> _sendFiles() async {
    if (_sending || _files.isEmpty) return;

    final missingPaths = _files.any(
      (file) => file.path == null || file.path!.isEmpty,
    );

    if (missingPaths) {
      _showMessage(
        'Some files cannot be accessed. Select them again.',
      );
      return;
    }

    setState(() {
      _sending = true;
      _currentIndex = 0;
      _sentCount = 0;
      _failedCount = 0;
    });

    final selectedFiles = List<PlatformFile>.from(_files);

    for (var index = 0; index < selectedFiles.length; index++) {
      if (!mounted) return;

      final file = selectedFiles[index];
      final path = file.path;

      setState(() => _currentIndex = index);

      if (path == null || path.isEmpty) {
        setState(() => _failedCount++);
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

        setState(() => _sentCount++);
      } catch (error) {
        debugPrint('Failed to send ${file.name}: $error');

        if (!mounted) return;

        setState(() => _failedCount++);
      }
    }

    if (!mounted) return;

    setState(() => _sending = false);

    if (_failedCount == 0) {
      _showMessage('All files sent successfully.');
    } else {
      _showMessage(
        'Finished: $_sentCount sent, $_failedCount failed.',
      );
    }
  }

  void _removeFile(int index) {
    if (_sending) return;

    setState(() => _files.removeAt(index));
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

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';

    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }

    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }

    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                color: green.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _categoryIcon,
                size: 58,
                color: accent,
              ),
            ),
            const SizedBox(height: 22),
            Text(
              _title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Choose the items you want to share '
              'with the connected phone.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white60,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 26),
            FilledButton.icon(
              onPressed: _picking ? null : _pickFiles,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                _picking ? 'Opening...' : 'Choose Files',
              ),
              style: FilledButton.styleFrom(
                backgroundColor: green,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 26,
                  vertical: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelectedFiles() {
    return Column(
      children: [
        Container(
          color: surface,
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(
                Icons.check_circle_rounded,
                color: accent,
                size: 30,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${_files.length} selected',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Total size: ${_formatBytes(_totalBytes)}',
                      style: const TextStyle(
                        color: Colors.white60,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _sending
                    ? null
                    : () => setState(() => _files.clear()),
                icon: const Icon(
                  Icons.delete_outline_rounded,
                  color: Colors.white70,
                ),
                tooltip: 'Clear selection',
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(14),
            itemCount: _files.length,
            separatorBuilder: (_, __) =>
                const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final file = _files[index];

              return Container(
                decoration: BoxDecoration(
                  color: surface,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: ListTile(
                  leading: Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: green.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      _categoryIcon,
                      color: accent,
                    ),
                  ),
                  title: Text(
                    file.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    _formatBytes(file.size),
                    style: const TextStyle(
                      color: Colors.white60,
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Remove file',
                    onPressed: _sending
                        ? null
                        : () => _removeFile(index),
                    icon: const Icon(
                      Icons.close_rounded,
                      color: Colors.white70,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: OutlinedButton.icon(
            onPressed: _picking || _sending ? null : _pickFiles,
            icon: const Icon(Icons.add_rounded),
            label: const Text('Add More Files'),
            style: OutlinedButton.styleFrom(
              foregroundColor: accent,
              side: const BorderSide(color: accent),
              minimumSize: const Size(double.infinity, 48),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildProgress() {
    if (!_sending && _sentCount == 0 && _failedCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Transfer progress',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              Text(
                '${(_progress * 100).round()}%',
                style: const TextStyle(
                  color: accent,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          LinearProgressIndicator(
            value: _sending ? _progress : 1,
            backgroundColor: Colors.white12,
            color: accent,
          ),
          const SizedBox(height: 10),
          Text(
            'Sent: $_sentCount   Failed: $_failedCount',
            style: const TextStyle(color: Colors.white70),
          ),
          if (_sending && _currentIndex < _files.length)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'Sending: ${_files[_currentIndex].name}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white60),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        backgroundColor: green,
        foregroundColor: Colors.white,
        title: Text(_title),
        actions: [
          IconButton(
            tooltip: 'Choose files',
            onPressed: _picking || _sending ? null : _pickFiles,
            icon: const Icon(Icons.add_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: _files.isEmpty
                  ? _buildEmptyState()
                  : _buildSelectedFiles(),
            ),
            _buildProgress(),
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.icon(
                  onPressed: _files.isEmpty || _sending || _picking
                      ? null
                      : _sendFiles,
                  icon: _sending
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(
                    _sending
                        ? 'Sending files...'
                        : 'SEND ${_files.isEmpty ? '' : '(${_files.length})'}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: Colors.white12,
                    disabledForegroundColor: Colors.white38,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(30),
                    ),
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
