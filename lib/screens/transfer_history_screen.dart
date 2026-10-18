import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TransferHistoryScreen extends StatefulWidget {
  const TransferHistoryScreen({super.key});

  @override
  State<TransferHistoryScreen> createState() =>
      _TransferHistoryScreenState();
}

class _TransferHistoryScreenState
    extends State<TransferHistoryScreen> {
  static const String _storageKey = 'mafx_transfer_history';

  List<Map<String, dynamic>> _history = [];

  bool _loading = true;
  bool _clearing = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() {
      _loading = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      final entries = prefs.getStringList(_storageKey) ?? [];

      final records = <Map<String, dynamic>>[];

      for (final entry in entries) {
        try {
          final decoded = jsonDecode(entry);

          if (decoded is Map) {
            records.add(Map<String, dynamic>.from(decoded));
          }
        } catch (error) {
          debugPrint('Invalid history entry: $error');
        }
      }

      if (!mounted) return;

      setState(() {
        _history = records;
        _loading = false;
      });
    } catch (error) {
      debugPrint('Could not load transfer history: $error');

      if (!mounted) return;

      setState(() {
        _loading = false;
      });

      _showMessage('An kasa loda tarihin transfer.');
    }
  }

  Future<void> _clearHistory() async {
    if (_clearing || _history.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear Transfer History?'),
        content: const Text(
          'Wannan zai goge tarihin transfers kawai. '
          'Ba zai goge fayilolin da aka adana ba.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext, false);
            },
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(dialogContext, true);
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() {
      _clearing = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);

      if (!mounted) return;

      setState(() {
        _history.clear();
        _clearing = false;
      });

      _showMessage('An share tarihin transfer.');
    } catch (error) {
      debugPrint('Could not clear history: $error');

      if (!mounted) return;

      setState(() {
        _clearing = false;
      });

      _showMessage('An kasa share tarihin transfer.');
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

  String _formatBytes(dynamic value) {
    final bytes = value is num && value >= 0
        ? value.toInt()
        : 0;

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

  String _formatDate(dynamic value) {
    if (value == null) return 'Unknown date';

    try {
      final date = DateTime.parse(value.toString()).toLocal();

      final day = date.day.toString().padLeft(2, '0');
      final month = date.month.toString().padLeft(2, '0');
      final year = date.year;
      final hour = date.hour.toString().padLeft(2, '0');
      final minute = date.minute.toString().padLeft(2, '0');

      return '$day/$month/$year  $hour:$minute';
    } catch (_) {
      return 'Unknown date';
    }
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final fileName = item['fileName']?.toString() ?? 'Unknown file';
    final direction = item['direction']?.toString().toLowerCase();
    final isSent = direction == 'sent';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        leading: CircleAvatar(
          backgroundColor: isSent
              ? const Color(0x2200AEEF)
              : const Color(0x2200D18B),
          child: Icon(
            isSent
                ? Icons.upload_rounded
                : Icons.download_rounded,
            color: isSent
                ? const Color(0xFF00AEEF)
                : const Color(0xFF008D5A),
          ),
        ),
        title: Text(
          fileName,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isSent
                        ? Icons.arrow_upward_rounded
                        : Icons.arrow_downward_rounded,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(isSent ? 'Sent' : 'Received'),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(
                    Icons.storage_rounded,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(_formatBytes(item['bytes'])),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _formatDate(item['completedAt'] ?? item['timestamp'])
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer History'),
        actions: [
          IconButton(
            tooltip: 'Refresh history',
            onPressed: _loading ? null : _loadHistory,
            icon: const Icon(Icons.refresh_rounded),
          ),
          if (_history.isNotEmpty)
            IconButton(
              tooltip: 'Clear history',
              onPressed: _loading || _clearing
                  ? null
                  : _clearHistory,
              icon: _clearing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.delete_outline_rounded),
            ),
        ],
      ),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : _history.isEmpty
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.history_rounded,
                          size: 76,
                          color: Color(0xFF00AEEF),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'No Transfer History',
                          style: TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Completed transfers will appear here.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        OutlinedButton.icon(
                          onPressed: _loadHistory,
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Refresh'),
                        ),
                      ],
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadHistory,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: _history.length,
                    itemBuilder: (context, index) {
                      return _buildHistoryItem(_history[index]);
                    },
                  ),
                ),
    );
  }
}
