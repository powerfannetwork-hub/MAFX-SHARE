import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'connect_screen.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});

  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
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

      if (result != null && result.files.isNotEmpty) {
        setState(() {
          for (final file in result.files) {
            final alreadyAdded = _files.any(
              (item) =>
                  item.name == file.name &&
                  item.path == file.path,
            );

            if (!alreadyAdded) {
              _files.add(file);
            }
          }
        });
      }
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An kasa zaɓar fayil: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isPicking = false);
      }
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Da farko, zaɓi fayilolin da za ka aika.'),
        ),
      );
      return;
    }

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ConnectScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Files'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: _files.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.folder_open_rounded,
                            size: 76,
                            color: Color(0xFF00AEEF),
                          ),
                          const SizedBox(height: 18),
                          const Text(
                            'Select Files to Share',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'Choose documents, videos, photos, '
                            'or other files from your device.',
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          FilledButton.icon(
                            onPressed: _isPicking ? null : _pickFiles,
                            icon: const Icon(Icons.add_rounded),
                            label: Text(
                              _isPicking ? 'Opening...' : 'Choose Files',
                            ),
                          ),
                        ],
                      ),
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
                      const SizedBox(height: 6),
                      Text('Total size: ${_formatSize(_totalSize)}'),
                      const SizedBox(height: 16),
                      ...List.generate(_files.length, (index) {
                        final file = _files[index];

                        return Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.insert_drive_file_rounded),
                            ),
                            title: Text(
                              file.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: Text(_formatSize(file.size)),
                            trailing: IconButton(
                              tooltip: 'Remove file',
                              icon: const Icon(
                                Icons.close_rounded,
                                color: Colors.red,
                              ),
                              onPressed: () => _removeFile(index),
                            ),
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _isPicking ? null : _pickFiles,
                        icon: const Icon(Icons.add_rounded),
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
                  icon: const Icon(Icons.devices_rounded),
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
