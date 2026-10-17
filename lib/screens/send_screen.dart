import 'dart:io';

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

  String get _category =>
      (widget.category ?? 'Files').toLowerCase();

  @override
  void initState() {
    super.initState();
  }

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
      final List<AssetEntity>? assets =
          await Navigator.of(context).push<List<AssetEntity>>(
        MaterialPageRoute(
          builder: (_) => MediaBrowserScreen(
            category: category,
            allowMultiple: true,
          ),
        ),
      );

      if (assets == null || assets.isEmpty) return;

      final List<_SelectedFile> newFiles = [];

      for (final asset in assets) {
        final File? file = await asset.file;

        if (file == null || !await file.exists()) {
          continue;
        }

        final String name =
            asset.title?.trim().isNotEmpty == true
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

      setState(() {
        for (final file in newFiles) {
          final alreadyAdded = _selectedFiles.any(
            (item) => item.path == file.path,
          );

          if (!alreadyAdded) {
            _selectedFiles.add(file);
          }
        }

        _status = newFiles.isEmpty
            ? 'Ba a sami fayilolin da za a iya amfani da su ba.'
            : 'An zaɓi fayiloli ${newFiles.length}.';
      });
    } catch (e) {
      _showMessage('An kasa buɗe media browser: $e');
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

      final List<_SelectedFile> newFiles = [];

      for (final file in result.files) {
        final path = file.path;

        if (path == null) continue;

        newFiles.add(
          _SelectedFile(
            name: file.name,
            path: path,
            size: file.size,
          ),
        );
      }

      if (!mounted) return;

      setState(() {
        for (final file in newFiles) {
          final alreadyAdded = _selectedFiles.any(
            (item) => item.path == file.path,
          );

          if (!alreadyAdded) {
            _selectedFiles.add(file);
          }
        }

        _status = 'An ƙara fayiloli ${newFiles.length}.';
      });
    } catch (e) {
      _showMessage('An kasa zaɓar fayiloli: $e');
    }
  }

  void _removeFile(_SelectedFile file) {
    setState(() {
      _selectedFiles.remove(file);
    });
  }

  Future<void> _sendFiles() async {
    if (_sending || _selectedFiles.isEmpty) return;

    setState(() {
      _sending = true;
      _progress = 0;
      _status = 'Ana fara aikawa...';
    });

    int sent = 0;
    final int total = _selectedFiles.length;
    final List<String> failedFiles = [];

    try {
      for (final selected in List<_SelectedFile>.from(_selectedFiles)) {
        if (!mounted) return;

        setState(() {
          _status = 'Ana aikawa: ${selected.name}';
          _progress = sent / total;
        });

        final file = File(selected.path);

        if (!await file.exists()) {
          failedFiles.add(selected.name);
          continue;
        }

        try {
          await _transferService.sendFile(
            receiverUrl: widget.receiverUrl,
            token: widget.receiverToken,
            filePath: selected.path,
            fileName: selected.name,
          );

          sent++;
        } catch (_) {
          failedFiles.add(selected.name);
        }

        if (!mounted) return;

        setState(() {
          _progress = (sent + failedFiles.length) / total;
        });
      }

      if (!mounted) return;

      setState(() {
        _status = failedFiles.isEmpty
            ? 'An aika duk fayiloli cikin nasara!'
            : 'An aika $sent daga $total. '
                'Fayilolin da suka gaza: ${failedFiles.length}.';
      });

      if (failedFiles.isEmpty) {
        _showMessage('An aika duk fayiloli cikin nasara!');
        setState(() {
          _selectedFiles.clear();
        });
      } else {
        _showMessage(
          'An aika $sent daga $total fayiloli. '
          'Duba fayilolin da suka gaza.',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _status = 'An samu matsala yayin aikawa: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
    final extension = name.split('.').last.toLowerCase();

    switch (extension) {
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'webp':
        return Icons.image;
      case 'mp4':
      case 'mkv':
      case 'mov':
      case 'avi':
        return Icons.video_file;
      case 'mp3':
      case 'm4a':
      case 'wav':
      case 'aac':
        return Icons.audio_file;
      case 'apk':
        return Icons.android;
      case 'pdf':
        return Icons.picture_as_pdf;
      default:
        return Icons.insert_drive_file;
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      Icon(
                        Icons.devices,
                        color: Color(0xFF00D084),
                      ),
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
                    'Category: ${widget.category ?? 'Files'}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_selectedFiles.length} file(s) selected',
                    style: const TextStyle(
                      color: Color(0xFF00D084),
                    ),
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
                        foregroundColor: const Color(0xFF00D084),
                        side: const BorderSide(
                          color: Color(0xFF00D084),
                        ),
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed:
                          _sending || _selectedFiles.isEmpty
                              ? null
                              : _sendFiles,
                      icon: const Icon(Icons.send),
                      label: const Text('Send Now'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00D084),
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(
                          vertical: 14,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            if (_sending || _progress > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(
                      value: _progress.clamp(0.0, 1.0),
                      color: const Color(0xFF00D084),
                      backgroundColor: Colors.white12,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: const TextStyle(color: Colors.white70),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

            if (_status.isNotEmpty && !_sending)
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
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 16,
                            ),
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
                            color: const Color(0xFF00D084),
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
                            style: const TextStyle(
                              color: Colors.white54,
                            ),
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
