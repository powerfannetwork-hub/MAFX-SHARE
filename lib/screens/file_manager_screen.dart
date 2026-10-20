import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import '../models/media_file_model.dart';
import '../services/media_library_service.dart';
import '../widgets/media_file_tile.dart';

class FileManagerScreen extends StatefulWidget {
  const FileManagerScreen({super.key});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  final MediaLibraryService _mediaService = MediaLibraryService();
  final TextEditingController _searchController =
      TextEditingController();

  List<MediaFileModel> _receivedFiles = [];
  List<MediaFileModel> _selectedFiles = [];

  bool _isLoading = true;
  String _searchQuery = '';

  static const Color _backgroundColor = Color(0xFF101010);
  static const Color _cardColor = Color(0xFF1C1C1C);
  static const Color _greenColor = Color(0xFF00C853);

  @override
  void initState() {
    super.initState();
    _loadReceivedFiles();
  }

  Future<void> _loadReceivedFiles() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
    });

    try {
      final files = await _mediaService.loadReceivedFiles();

      if (!mounted) return;

      setState(() {
        _receivedFiles = files;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to load received files.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  List<MediaFileModel> get _allFiles {
    final Map<String, MediaFileModel> unique = {};

    for (final file in _receivedFiles) {
      unique[file.path] = file;
    }

    for (final file in _selectedFiles) {
      unique[file.path] = file;
    }

    return unique.values.toList();
  }

  List<MediaFileModel> get _filteredFiles {
    final query = _searchQuery.trim().toLowerCase();

    if (query.isEmpty) {
      return _allFiles;
    }

    return _allFiles.where((file) {
      return file.name.toLowerCase().contains(query) ||
          file.typeLabel.toLowerCase().contains(query);
    }).toList();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';

    const units = ['KB', 'MB', 'GB', 'TB'];
    double size = bytes / 1024;
    int index = 0;

    while (size >= 1024 && index < units.length - 1) {
      size /= 1024;
      index++;
    }

    return '${size.toStringAsFixed(1)} ${units[index]}';
  }

  Future<void> _pickFiles() async {
    try {
      final files = await _mediaService.pickFiles(
        allowMultiple: true,
      );

      if (!mounted || files.isEmpty) return;

      setState(() {
        final Map<String, MediaFileModel> unique = {
          for (final file in _selectedFiles) file.path: file,
          for (final file in files) file.path: file,
        };

        _selectedFiles = unique.values.toList();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${files.length} file(s) selected.',
          ),
          backgroundColor: _greenColor,
        ),
      );
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to select files.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Future<void> _openFile(MediaFileModel file) async {
    try {
      final result = await OpenFilex.open(file.path);

      if (!mounted) return;

      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Unable to open "${file.name}". '
              'Make sure a compatible app is installed.',
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('An error occurred while opening the file.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: TextField(
        controller: _searchController,
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
          });
        },
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: 'Search files...',
          hintStyle: const TextStyle(color: Colors.white54),
          prefixIcon: const Icon(
            Icons.search,
            color: _greenColor,
          ),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    _searchController.clear();

                    setState(() {
                      _searchQuery = '';
                    });
                  },
                  icon: const Icon(
                    Icons.close,
                    color: Colors.white70,
                  ),
                  tooltip: 'Clear search',
                ),
          filled: true,
          fillColor: _cardColor,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final searching = _searchQuery.trim().isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              searching
                  ? Icons.search_off
                  : Icons.folder_open_outlined,
              size: 76,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            Text(
              searching ? 'No Files Found' : 'No Files Available',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 19,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              searching
                  ? 'Try searching with a different name.'
                  : 'Select files from your device or view files '
                      'received through MAFX SHARE.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white60,
                height: 1.5,
              ),
            ),
            if (!searching) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: _pickFiles,
                icon: const Icon(Icons.add),
                label: const Text('Select Files'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _greenColor,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final files = _filteredFiles;

    final totalBytes = files.fold<int>(
      0,
      (total, file) => total + file.sizeBytes,
    );

    return Scaffold(
      backgroundColor: _backgroundColor,
      appBar: AppBar(
        backgroundColor: _backgroundColor,
        foregroundColor: Colors.white,
        title: const Text(
          'MAFX Files',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            onPressed: _loadReceivedFiles,
            tooltip: 'Refresh files',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _pickFiles,
        backgroundColor: _greenColor,
        foregroundColor: Colors.black,
        icon: const Icon(Icons.add),
        label: const Text('Select Files'),
      ),
      body: Column(
        children: [
          _buildSearchField(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                const Icon(
                  Icons.folder,
                  color: _greenColor,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${files.length} files • ${_formatSize(totalBytes)}',
                    style: const TextStyle(
                      color: Colors.white60,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: _greenColor,
                    ),
                  )
                : files.isEmpty
                    ? _buildEmptyState()
                    : RefreshIndicator(
                        color: _greenColor,
                        onRefresh: _loadReceivedFiles,
                        child: ListView.builder(
                          padding: const EdgeInsets.only(bottom: 100),
                          physics:
                              const AlwaysScrollableScrollPhysics(),
                          itemCount: files.length,
                          itemBuilder: (context, index) {
                            final file = files[index];

                            return MediaFileTile(
                              media: file,
                              onTap: () => _openFile(file),
                              onMoreTap: () => _showFileOptions(file),
                            );
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  void _showFileOptions(MediaFileModel file) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF202020),
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.insert_drive_file,
                    color: _greenColor,
                  ),
                  title: Text(
                    file.name,
                    style: const TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    '${file.typeLabel} • ${_formatSize(file.sizeBytes)}',
                    style: const TextStyle(color: Colors.white60),
                  ),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.open_in_new,
                    color: _greenColor,
                  ),
                  title: const Text(
                    'Open File',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _openFile(file);
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.info_outline,
                    color: _greenColor,
                  ),
                  title: const Text(
                    'File Details',
                    style: TextStyle(color: Colors.white),
                  ),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _showFileDetails(file);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFileDetails(MediaFileModel file) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF202020),
          title: const Text(
            'File Details',
            style: TextStyle(color: Colors.white),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailRow('Name', file.name),
                _detailRow('Type', file.typeLabel),
                _detailRow('Size', _formatSize(file.sizeBytes)),
                _detailRow('Path', file.path),
                if (file.mimeType != null)
                  _detailRow('MIME Type', file.mimeType!),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text(
                'Close',
                style: TextStyle(color: _greenColor),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: _greenColor,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            value,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
