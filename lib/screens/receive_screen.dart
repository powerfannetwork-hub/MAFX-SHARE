import 'dart:io';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../services/transfer_service.dart';
import 'connect_screen.dart';

class ReceiveScreen extends StatefulWidget {
  final String? category;

  const ReceiveScreen({
    super.key,
    this.category,
  });

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final TransferService _service = TransferService.instance;

  List<File> _files = [];
  bool _loading = false;
  String? _error;
  String? _openingPath;

  @override
  void initState() {
    super.initState();
    _loadReceivedFiles();
  }

  Future<void> _loadReceivedFiles() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final files = await _service.getReceivedFiles();

      if (!mounted) return;

      setState(() {
        _files = files;
      });
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _error = 'An kasa loda jerin fayiloli.';
      });

      debugPrint('Load received files failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _formatBytes(int bytes) {
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

  String _displayName(File file) {
    final storedName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : file.path;

    // Received files have a timestamp prefix.
    final separator = storedName.indexOf('_');

    if (separator > 0) {
      final prefix = storedName.substring(0, separator);

      if (int.tryParse(prefix) != null) {
        return storedName.substring(separator + 1);
      }
    }

    return storedName;
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

  Future<void> _openFile(File file) async {
    if (_openingPath != null) return;

    setState(() {
      _openingPath = file.path;
    });

    try {
      if (!await file.exists()) {
        _showMessage('Ba a sami wannan fayil ɗin ba.');
        return;
      }

      final result = await OpenFilex.open(file.path);

      if (!mounted) return;

      if (result.type != ResultType.done) {
        final message = result.message.trim();

        _showMessage(
          message.isNotEmpty
              ? 'Ba a iya buɗe fayil ɗin ba: $message'
              : 'Ba a iya buɗe fayil ɗin ba. '
                  'Tabbatar kana da app da zai iya buɗe shi.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Open received file failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      _showMessage(
        'An samu matsala wajen buɗe fayil ɗin. '
        'Gwada sake buɗewa.',
      );
    } finally {
      if (mounted) {
        setState(() {
          _openingPath = null;
        });
      }
    }
  }

  Future<void> _openConnection() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ConnectScreen(
          category: widget.category,
        ),
      ),
    );

    if (mounted) {
      await _loadReceivedFiles();
    }
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF008D5A);
    const dark = Color(0xFF202024);

    return Scaffold(
      backgroundColor: dark,
      appBar: AppBar(
        title: const Text('Receive Files'),
        backgroundColor: green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Refresh files',
            onPressed: _loading ? null : _loadReceivedFiles,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: FilledButton.icon(
                  onPressed: _openConnection,
                  icon: const Icon(Icons.wifi_rounded),
                  label: const Text(
                    'Connect and Receive',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: green,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.folder_rounded,
                    color: Color(0xFF00D18B),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Received Files',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    '${_files.length} files',
                    style: const TextStyle(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _buildFileList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileList() {
    if (_loading && _files.isEmpty) {
      return const Center(
        child: CircularProgressIndicator(
          color: Color(0xFF00D18B),
        ),
      );
    }

    if (_error != null && _files.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Colors.redAccent,
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white70,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadReceivedFiles,
                child: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    if (_files.isEmpty) {
      return RefreshIndicator(
        onRefresh: _loadReceivedFiles,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(height: 100),
            Icon(
              Icons.inbox_rounded,
              size: 76,
              color: Colors.white38,
            ),
            SizedBox(height: 16),
            Center(
              child: Text(
                'No received files yet.',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
              ),
            ),
            SizedBox(height: 8),
            Center(
              child: Text(
                'Connect to another phone to receive files.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white38,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadReceivedFiles,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        itemCount: _files.length,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          final file = _files[index];
          final name = _displayName(file);
          final isOpening = _openingPath == file.path;

          return Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white10,
              ),
            ),
            child: ListTile(
              onTap: _openingPath == null
                  ? () => _openFile(file)
                  : null,
              leading: const CircleAvatar(
                backgroundColor: Color(0x2200D18B),
                child: Icon(
                  Icons.insert_drive_file_rounded,
                  color: Color(0xFF00D18B),
                ),
              ),
              title: Text(
                name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: FutureBuilder<int>(
                future: file.length(),
                builder: (context, snapshot) {
                  if (!snapshot.hasData) {
                    return const Text(
                      'Reading file size...',
                      style: TextStyle(
                        color: Colors.white54,
                      ),
                    );
                  }

                  return Text(
                    _formatBytes(snapshot.data!),
                    style: const TextStyle(
                      color: Colors.white60,
                    ),
                  );
                },
              ),
              trailing: isOpening
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Color(0xFF00D18B),
                      ),
                    )
                  : const Icon(
                      Icons.open_in_new_rounded,
                      color: Color(0xFF00D18B),
                    ),
            ),
          );
        },
      ),
    );
  }
}
