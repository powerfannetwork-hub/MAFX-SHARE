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
  final List<_SelectedFile> _failedFiles = [];

  bool _sending = false;

  double _progress = 0;
  double _currentFileProgress = 0;

  String _status = '';
  String _currentFileName = '';

  int _currentFileSentBytes = 0;
  int _currentFileTotalBytes = 0;

  int _sentCount = 0;
  int _totalBytes = 0;

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

    switch (_category) {
      case 'photos':
        category = 'Photos';
        break;
      case 'videos':
        category = 'Videos';
        break;
      default:
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

      if (!mounted || assets == null || assets.isEmpty) return;

      final newFiles = <_SelectedFile>[];

      for (final asset in assets) {
        final file = await asset.file;

        if (file == null || !await file.exists()) {
          continue;
        }

        final assetName = asset.title?.trim();
        final name = assetName != null && assetName.isNotEmpty
            ? assetName
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

      if (!mounted || result == null) return;

      final newFiles = <_SelectedFile>[];

      for (final pickedFile in result.files) {
        final path = pickedFile.path;

        if (path == null || path.isEmpty) {
          debugPrint('No accessible path for ${pickedFile.name}');
          continue;
        }

        newFiles.add(
          _SelectedFile(
            name: pickedFile.name,
            path: path,
            size: pickedFile.size,
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
    if (files.isEmpty) {
      _showMessage('Ba a sami fayilolin da za a iya amfani da su ba.');
      return;
    }

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
      _status = 'An cire ${file.name}.';
    });
  }

  void _clearFiles() {
    if (_sending || _selectedFiles.isEmpty) return;

    setState(() {
      _selectedFiles.clear();
      _failedFiles.clear();

      _progress = 0;
      _currentFileProgress = 0;
      _currentFileName = '';
      _currentFileSentBytes = 0;
      _currentFileTotalBytes = 0;

      _sentCount = 0;
      _totalBytes = 0;

      _status = 'An share jerin fayilolin da aka zaɓa.';
    });
  }

  Future<void> _sendFiles() async {
    if (_sending || _selectedFiles.isEmpty) return;

    final filesToSend = List<_SelectedFile>.from(_selectedFiles);

    setState(() {
      _sending = true;

      _progress = 0;
      _currentFileProgress = 0;
      _currentFileName = '';
      _currentFileSentBytes = 0;
      _currentFileTotalBytes = 0;

      _sentCount = 0;
      _totalBytes = 0;

      _status = 'Ana shirya aika fayiloli...';
      _failedFiles.clear();
    });

    var sent = 0;
    var failed = 0;

    final total = filesToSend.length;

    for (var index = 0; index < total; index++) {
      if (!mounted) return;

      final selected = filesToSend[index];

      setState(() {
        _status = 'Ana aikawa: ${selected.name}';
        _currentFileName = selected.name;

        _progress = index / total;

        _currentFileProgress = 0;
        _currentFileSentBytes = 0;
        _currentFileTotalBytes = selected.size;
      });

      try {
        final file = File(selected.path);

        if (!await file.exists()) {
          throw Exception('Ba a sami fayil ɗin a wayar ba.');
        }

        final fileSize = await file.length();

        await _transferService.sendFile(
          receiverUrl: widget.receiverUrl,
          token: widget.receiverToken,
          filePath: selected.path,
          fileName: selected.name,
          onProgress: (sentBytes, totalBytes) {
            if (!mounted) return;

            setState(() {
              _currentFileSentBytes = sentBytes;
              _currentFileTotalBytes = totalBytes;

              _currentFileProgress = totalBytes > 0
                  ? (sentBytes / totalBytes)
                      .clamp(0.0, 1.0)
                      .toDouble()
                  : 0.0;
            });
          },
        );

        sent++;
        _totalBytes += fileSize;
      } catch (error, stackTrace) {
        failed++;

        _failedFiles.add(selected.name);

        debugPrint('Failed to send ${selected.name}: $error');
        debugPrintStack(stackTrace: stackTrace);
      }

      if (!mounted) return;

      setState(() {
        _sentCount = sent;
        _progress = (index + 1) / total;

        _status = failed == 0
            ? 'An aika $sent daga $total fayiloli...'
            : 'An aika $sent; sun gaza $failed.';
      });
    }

    if (!mounted) return;

    setState(() {
      _sending = false;
      _progress = 1;

      _currentFileProgress = 0;
      _currentFileSentBytes = 0;
      _currentFileTotalBytes = 0;

      if (_failedFiles.isEmpty) {
        _status = 'An aika duk fayiloli cikin nasara!';
        _selectedFiles.clear();
      } else {
        _status = 'An aika $sent daga $total. '
            'Fayilolin da suka gaza: ${_failedFiles.length}.';
      }
    });

    if (_failedFiles.isEmpty) {
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
      case 'heic':
        return Icons.image_rounded;

      case 'mp4':
      case 'mkv':
      case 'mov':
      case 'avi':
      case 'webm':
      case '3gp':
        return Icons.video_file_rounded;

      case 'mp3':
      case 'm4a':
      case 'wav':
      case 'aac':
      case 'flac':
      case 'ogg':
        return Icons.audio_file_rounded;

      case 'apk':
        return Icons.android_rounded;

      case 'pdf':
        return Icons.picture_as_pdf_rounded;

      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_rounded;

      case 'doc':
      case 'docx':
        return Icons.description_rounded;

      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;

      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;

      case 'txt':
        return Icons.text_snippet_rounded;

      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Widget _buildFileCard(_SelectedFile file) {
    const green = Color(0xFF00D084);

    return Container(
      key: ValueKey(file.path),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF192832),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: green.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              _fileIcon(file.name),
              color: green,
              size: 27,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  file.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  _formatSize(file.size),
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          if (!_sending)
            IconButton(
              tooltip: 'Remove file',
              onPressed: () => _removeFile(file),
              icon: const Icon(
                Icons.close_rounded,
                color: Colors.white70,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProgressPanel() {
    const green = Color(0xFF00D084);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF192832),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _sending
                    ? Icons.sync_rounded
                    : _failedFiles.isEmpty
                        ? Icons.check_circle_outline_rounded
                        : Icons.warning_amber_rounded,
                color: green,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _status,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),

          // Overall progress for all selected files.
          if (_sending || _progress > 0) ...[
            const SizedBox(height: 14),
            LinearProgressIndicator(
              value: _progress.clamp(0.0, 1.0).toDouble(),
              color: green,
              backgroundColor: Colors.white12,
              minHeight: 6,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 8),
            Text(
              '${(_progress * 100).round()}% complete',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
          ],

          // Progress for the individual file being sent.
          if (_sending) ...[
            const SizedBox(height: 14),
            Text(
              'Fayil na yanzu: $_currentFileName',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _currentFileProgress,
              color: green,
              backgroundColor: Colors.white12,
              minHeight: 5,
              borderRadius: BorderRadius.circular(10),
            ),
            const SizedBox(height: 6),
            Text(
              '${(_currentFileProgress * 100).round()}% — '
              '${_formatSize(_currentFileSentBytes)} / '
              '${_formatSize(_currentFileTotalBytes)}',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
          ],

          if (_sentCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Successful files: $_sentCount',
              style: const TextStyle(color: green),
            ),
            Text(
              'Transferred: ${_formatSize(_totalBytes)}',
              style: const TextStyle(color: Colors.white70),
            ),
          ],

          if (_failedFiles.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              'Failed files:',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 5),
            ..._failedFiles.map(
              (name) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '• $name',
                  style: const TextStyle(
                    color: Colors.redAccent,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _sending ? null : _retryFailedFiles,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry Failed Files'),
              style: OutlinedButton.styleFrom(
                foregroundColor: green,
                side: const BorderSide(color: green),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _retryFailedFiles() async {
    if (_sending || _failedFiles.isEmpty) return;

    final failedNames = List<String>.from(_failedFiles);

    final failedItems = _selectedFiles
        .where((file) => failedNames.contains(file.name))
        .toList();

    if (failedItems.isEmpty) {
      _showMessage(
        'Ba a sami fayilolin da suka gaza a jerin zaɓaɓɓun fayiloli ba.',
      );
      return;
    }

    setState(() {
      _selectedFiles
        ..clear()
        ..addAll(failedItems);

      _failedFiles.clear();

      _progress = 0;
      _currentFileProgress = 0;
      _currentFileName = '';
      _currentFileSentBytes = 0;
      _currentFileTotalBytes = 0;

      _sentCount = 0;
      _totalBytes = 0;

      _status = 'Ana sake aika fayilolin da suka gaza...';
    });

    await _sendFiles();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF00D084);
    const background = Color(0xFF101820);

    return Scaffold(
      backgroundColor: background,
      appBar: AppBar(
        title: const Text('Transfer Files'),
        backgroundColor: background,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_selectedFiles.isNotEmpty && !_sending)
            IconButton(
              tooltip: 'Clear selected files',
              onPressed: _clearFiles,
              icon: const Icon(Icons.delete_sweep_rounded),
            ),
        ],
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
                      Icon(Icons.devices_rounded, color: green),
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
                  const SizedBox(height: 12),
                  const Text(
                    'Receiver address',
                    style: TextStyle(
                      color: Colors.white60,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(
                    widget.receiverUrl,
                    style: const TextStyle(
                      color: green,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
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
                      icon: const Icon(Icons.add_rounded),
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
                      icon: Icon(
                        _sending
                            ? Icons.sync_rounded
                            : Icons.send_rounded,
                      ),
                      label: Text(_sending ? 'Sending...' : 'Send Now'),
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

            if (_selectedFiles.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Selected files',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    Text(
                      '${_selectedFiles.length} item(s)',
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 8),

            Expanded(
              child: _selectedFiles.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_open_rounded,
                              size: 76,
                              color: Colors.white.withValues(alpha: 0.25),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No files selected',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 19,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'Tap Add Files to choose photos, videos, '
                              'music, documents, or other files.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white60,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _selectedFiles.length,
                      itemBuilder: (context, index) {
                        return _buildFileCard(_selectedFiles[index]);
                      },
                    ),
            ),

            if (_status.isNotEmpty) _buildProgressPanel(),
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
