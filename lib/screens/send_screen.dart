import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:photo_manager/photo_manager.dart';

import '../services/transfer_service.dart';
import 'media_browser_screen.dart';

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

  final List<_SelectedFile> _selectedFiles = [];

  bool _sending = false;
  double _progress = 0;
  String _status = '';

  final List<String> _failedFiles = [];

  String get _category => (widget.category ?? 'files').toLowerCase();

  Future<void> _pickFiles() async {
    if (_sending) return;

    if (_category == 'photos' ||
        _category == 'videos' ||
        _category == 'music') {
      await _pickMedia();
    } else {
      await _pickDocuments();
    }
  }

  Future<void> _pickMedia() async {
    final String category;

    if (_category == 'photos') {
      category = 'Photos';
    } else if (_category == 'videos') {
      category = 'Videos';
    } else {
      category = 'Music';
    }

    try {
      final assets = await Navigator.of(context).push<List<AssetEntity>>(
        MaterialPageRoute<List<AssetEntity>>(
          builder: (_) => MediaBrowserScreen(
            category: category,
            allowMultiple: true,
          ),
        ),
      );

      if (assets == null || assets.isEmpty) return;

      final newFiles = <_SelectedFile>[];

      for (final asset in assets) {
        final file = await asset.file;

        if (file == null || !await file.exists()) {
          continue;
        }

        final name = asset.title?.trim().isNotEmpty == true
            ? asset.title!
            : 'media_${asset.id}';

        newFiles.add(
          _SelectedFile(
            name: name,
            path: file.path,
            size: await file.length(),
          ),
        );
      }

      if (!mounted) return;

      _addFiles(newFiles);
    } catch (error, stackTrace) {
      debugPrint('Media selection failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      _showMessage('An kasa buɗe media browser: $error');
    }
  }

  Future<void> _pickDocuments() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
        withData: false,
      );

      if (result == null) return;

      final newFiles = <_SelectedFile>[];

      for (final file in result.files) {
        final path = file.path;

        if (path == null) {
          debugPrint('No accessible path for ${file.name}');
          continue;
        }

        newFiles.add(
          _SelectedFile(
            name: file.name,
            path: path,
            size: file.size,
          ),
        );
      }

      if (!mounted) return;

      _addFiles(newFiles);
    } catch (error, stackTrace) {
      debugPrint('File selection failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      _showMessage('An kasa zaɓar fayiloli: $error');
    }
  }

  void _addFiles(List<_SelectedFile> files) {
    var added = 0;

    setState(() {
      for (final file in files) {
        final alreadyAdded = _selectedFiles.any(
          (item) => item.path == file.path,
        );

        if (!alreadyAdded) {
          _selectedFiles.add(file);
          added++;
        }
      }

      _status = added == 0
          ? 'Babu sabon fayil da aka ƙara.'
          : 'An ƙara fayiloli $added.';
    });
  }

  void _removeFile(_SelectedFile file) {
    if (_sending) return;

    setState(() {
      _selectedFiles.remove(file);
    });
  }

  Future<void> _sendFiles() async {
    if (_sending || _selectedFiles.isEmpty) return;

    final filesToSend = List<_SelectedFile>.from(_selectedFiles);

    setState(() {
      _sending = true;
      _progress = 0;
      _status = 'Ana fara aikawa...';
      _failedFiles.clear();
    });

    var sent = 0;
    final total = filesToSend.length;

    for (var index = 0; index < total; index++) {
      if (!mounted) return;

      final selected = filesToSend[index];

      setState(() {
        _status = 'Ana aikawa: ${selected.name}';
        _progress = index / total;
      });

      try {
        final file = File(selected.path);

        if (!await file.exists()) {
          throw Exception('Ba a sami fayil ɗin a wayar ba.');
        }

        await _transferService.sendFile(
          receiverUrl: widget.receiverUrl,
          token: widget.receiverToken,
          filePath: selected.path,
          fileName: selected.name,
        );

        sent++;
      } catch (error, stackTrace) {
        debugPrint('Failed to send ${selected.name}: $error');
        debugPrintStack(stackTrace: stackTrace);

        _failedFiles.add(selected.name);
      }

      if (!mounted) return;

      setState(() {
        _progress = (index + 1) / total;
      });
    }

    if (!mounted) return;

    setState(() {
      if (_failedFiles.isEmpty) {
        _status = 'An aika duk fayiloli cikin nasara!';
      } else {
        _status = 'An aika $sent daga $total. '
            'Fayilolin da suka gaza: ${_failedFiles.length}.';
      }

      _sending = false;
    });

    if (_failedFiles.isEmpty) {
      setState(() {
        _selectedFiles.clear();
      });

      _showMessage('An aika duk fayiloli cikin nasara!');
    } else {
      _showMessage(
        'An aika $sent daga $total fayiloli. '
        'Duba jerin fayilolin da suka gaza.',
      );
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

  IconData _fileIcon(String name) {
    final extension = name.contains('.')
        ? name.split('.').last.toLowerCase()
        : '';

    switch (extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
      case 'gif':
        return Icons.image_rounded;

      case 'mp4':
      case 'mkv':
      case 'mov':
      case 'avi':
      case 'webm':
        return Icons.video_file_rounded;

      case 'mp3':
      case 'm4a':
      case 'wav':
      case 'aac':
      case 'flac':
        return Icons.audio_file_rounded;

      case 'apk':
        return Icons.android_rounded;

      case 'pdf':
        return Icons.picture_as_pdf_rounded;

      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF00D084);

    return Scaffold(
      backgroundColor: const Color(0xFF101820),
      appBar: AppBar(
        title: const Text('Send Files'),
        backgroundColor: const Color(0xFF101820),
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF192832),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.devices, color: green),
                      SizedBox(width: 8),
                      Text(
                        'MAFX SHARE',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Receiver: ${widget.receiverUrl}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Category: ${widget.category ?? 'Files'}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_selectedFiles.length} file(s) selected',
                    style: const TextStyle(color: green),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _sending ? null : _pickFiles,
                      icon: const Icon(Icons.add),
                      label: const Text('Add Files'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: green,
                        side: const BorderSide(color: green),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _sending || _selectedFiles.isEmpty
                          ? null
                          : _sendFiles,
                      icon: const Icon(Icons.send),
                      label: const Text('Send Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: green,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (_sending || _progress > 0) ...[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(
                  value: _progress.clamp(0.0, 1.0),
                  color: green,
                  backgroundColor: Colors.white12,
                ),
              ),
              const SizedBox(height: 8),
            ],
            if (_status.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _status,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            if (_failedFiles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Failed files',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 6),
                      for (final name in _failedFiles)
                        Text(
                          name,
                          style: const TextStyle(color: Colors.white70),
                        ),
                    ],
                  ),
                ),
              ),
            const Divider(color: Colors.white12),
            Expanded(
              child: _selectedFiles.isEmpty
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.folder_open,
                            color: Colors.white38,
                            size: 64,
                          ),
                          SizedBox(height: 12),
                          Text(
                            'No files selected',
                            style: TextStyle(color: Colors.white70),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Tap Add Files to choose files to send.',
                            style: TextStyle(color: Colors.white38),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: _selectedFiles.length,
                      itemBuilder: (context, index) {
                        final file = _selectedFiles[index];

                        return ListTile(
                          leading: Icon(
                            _fileIcon(file.name),
                            color: green,
                            size: 32,
                          ),
                          title: Text(
                            file.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white),
                          ),
                          subtitle: Text(
                            _formatSize(file.size),
                            style: const TextStyle(color: Colors.white54),
                          ),
                          trailing: IconButton(
                            onPressed: _sending
                                ? null
                                : () => _removeFile(file),
                            icon: const Icon(
                              Icons.close,
                              color: Colors.redAccent,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SelectedFile {
  final String name;
  final String path;
  final int size;

  const _SelectedFile({
    required this.name,
    required this.path,
    required this.size,
  });
}
