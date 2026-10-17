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
    } catch (error, stackTrace) {
      debugPrint('Failed to load received files: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _error = 'Unable to load received files. Please try again.';
      });
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
        _showMessage(
          'This file no longer exists. Refresh the file list.',
        );
        await _loadReceivedFiles();
        return;
      }

      final result = await OpenFilex.open(file.path);

      if (!mounted) return;

      if (result.type != ResultType.done) {
        final message = result.message.trim();

        _showMessage(
          message.isNotEmpty
              ? 'Unable to open file: $message'
              : 'Unable to open this file. '
                  'Make sure a compatible app is installed.',
        );
      }
    } catch (error, stackTrace) {
      debugPrint('Failed to open received file: $error');
      debugPrintStack(stackTrace: stackTrace);

      _showMessage(
        'An error occurred while opening the file. Please try again.',
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

  Widget _buildHeader() {
    const green = Color(0xFF00D18B);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white10),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.shield_rounded,
                  color: green,
                  size: 24,
                ),
                SizedBox(width: 10),
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
            SizedBox(height: 10),
            Text(
              'Receive files from another device over your local network.',
              style: TextStyle(
                color: Colors.white70,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionButton() {
    const green = Color(0xFF008D5A);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
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
    );
  }

  Widget _buildFileHeading() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
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
    );
  }

  Widget _buildEmptyState() {
    return RefreshIndicator(
      onRefresh: _loadReceivedFiles,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 90),
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
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          SizedBox(height: 8),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              'Connect to another device to receive files. '
              'Your received files will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white38,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
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
              _error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _loading ? null : _loadReceivedFiles,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try Again'),
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
      return _buildErrorState();
    }

    if (_files.isEmpty) {
      return _buildEmptyState();
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
                  if (snapshot.hasError) {
                    return const Text(
                      'Unable to read file size',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                      ),
                    );
                  }

                  if (!snapshot.hasData) {
                    return const Text(
                      'Reading file size...',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 12,
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
            _buildHeader(),
            _buildConnectionButton(),
            _buildFileHeading(),
            const SizedBox(height: 12),
            Expanded(
              child: _buildFileList(),
            ),
          ],
        ),
      ),
    );
  }
}
