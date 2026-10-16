import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/transfer_service.dart';
import 'connect_screen.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  final TransferService _service = TransferService.instance;

  List<PlatformFile> _files = [];
  bool _isPicking = false;

  Future<void> _pickFiles() async {
    if (_isPicking) return;

    setState(() => _isPicking = true);

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );

      if (!mounted) return;

      if (result != null) {
        setState(() {
          for (final file in result.files) {
            if (!_files.any((item) => item.path == file.path)) {
              _files.add(file);
            }
          }
        });
      }
    } catch (error) {
      if (mounted) _message('An kasa zaɓar fayil: $error');
    } finally {
      if (mounted) setState(() => _isPicking = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _removeFile(int index) {
    setState(() => _files.removeAt(index));
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  int get _totalSize =>
      _files.fold<int>(0, (total, file) => total + file.size);

  Future<void> _continueToConnect() async {
    if (_files.isEmpty) {
      _message('Da farko, zaɓi fayilolin da za ka aika.');
      return;
    }

    final missingPath = _files.any(
      (file) => file.path == null || file.path!.isEmpty,
    );

    if (missingPath) {
      _message('Ba a iya samun hanyar wasu fayiloli ba. Ka sake zaɓar su.');
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ConnectScreen(
          files: List<PlatformFile>.from(_files),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Send Files')),
      body: Column(
        children: [
          Expanded(
            child: _files.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.folder_open_rounded,
                          size: 76,
                          color: Color(0xFF00AEEF),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Select Files to Share',
                          style: TextStyle(
                            fontSize: 22,
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
                  )
                : ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(
                        '${_files.length} file(s) selected',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text('Total size: ${_formatSize(_totalSize)}'),
                      const SizedBox(height: 12),
                      ...List.generate(_files.length, (index) {
                        final file = _files[index];
                        return Card(
                          child: ListTile(
                            leading: const Icon(Icons.insert_drive_file),
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
                            ),
                          ),
                        );
                      }),
                      OutlinedButton.icon(
                        onPressed: _isPicking ? null : _pickFiles,
                        icon: const Icon(Icons.add),
                        label: const Text('Add More Files'),
                      ),
                    ],
                  ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton.icon(
                  onPressed: _continueToConnect,
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
