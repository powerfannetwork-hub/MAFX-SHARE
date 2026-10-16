import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  static const String _historyKey = 'mafx_transfer_history';

  List<Map<String, dynamic>> history = [];

  bool isLoading = true;
  bool isClearing = false;

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    if (mounted) {
      setState(() {
        isLoading = true;
      });
    }

    try {
      final prefs = await SharedPreferences.getInstance();

      final entries = prefs.getStringList(_historyKey) ?? [];

      final List<Map<String, dynamic>> items = [];

      for (final entry in entries) {
        try {
          final decoded = jsonDecode(entry);

          if (decoded is Map) {
            items.add(
              Map<String, dynamic>.from(decoded),
            );
          }
        } catch (error) {
          debugPrint(
            'Failed to decode transfer history entry: $error',
          );
        }
      }

      if (!mounted) return;

      setState(() {
        history = items;
        isLoading = false;
      });
    } catch (error) {
      debugPrint('Failed to load transfer history: $error');

      if (!mounted) return;

      setState(() {
        isLoading = false;
      });

      _showMessage(
        'An kasa loda tarihin transfers. Ka sake gwadawa.',
      );
    }
  }

  Future<void> clearHistory() async {
    if (isClearing || history.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Clear Transfer History'),
          content: const Text(
            'Are you sure you want to delete all transfer history?',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(false);
              },
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop(true);
              },
              child: const Text('Clear'),
            ),
          ],
        );
      },
    );

    if (confirm != true || !mounted) return;

    setState(() {
      isClearing = true;
    });

    try {
      final prefs = await SharedPreferences.getInstance();

      await prefs.remove(_historyKey);

      if (!mounted) return;

      setState(() {
        history.clear();
        isClearing = false;
      });

      _showMessage('Transfer history cleared successfully.');
    } catch (error) {
      debugPrint('Failed to clear transfer history: $error');

      if (!mounted) return;

      setState(() {
        isClearing = false;
      });

      _showMessage(
        'An kasa share tarihin transfers. Ka sake gwadawa.',
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

  String formatBytes(dynamic value) {
    final int bytes;

    if (value is num && value >= 0) {
      bytes = value.toInt();
    } else {
      bytes = 0;
    }

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

  String formatDate(dynamic value) {
    if (value == null) {
      return 'Unknown date';
    }

    try {
      final date = DateTime.parse(
        value.toString(),
      ).toLocal();

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

  bool _wasSent(Map<String, dynamic> item) {
    final direction = item['direction']?.toString().toLowerCase();

    return direction == 'sent';
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history_rounded,
              size: 84,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 18),
            const Text(
              'No Transfer History',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your sent and received files will appear here after a transfer.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: loadHistory,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHistoryItem(
    Map<String, dynamic> item,
  ) {
    final fileName =
        item['fileName']?.toString() ?? 'Unknown file';

    final isSent = _wasSent(item);

    final bytes = item['bytes'];

    final completedAt = item['completedAt'];

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        leading: CircleAvatar(
          child: Icon(
            isSent
                ? Icons.upload_rounded
                : Icons.download_rounded,
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
                    size: 15,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    isSent ? 'Sent' : 'Received',
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(
                    Icons.storage_rounded,
                    size: 15,
                  ),
                  const SizedBox(width: 5),
                  Text(formatBytes(bytes)),
                ],
              ),
              const SizedBox(height: 5),
              Row(
                children: [
                  const Icon(
                    Icons.access_time_rounded,
                    size: 15,
                  ),
                  const SizedBox(width: 5),
                  Expanded(
                    child: Text(
                      formatDate(completedAt),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        isThreeLine: true,
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
            onPressed: isLoading ? null : loadHistory,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh history',
          ),
          if (history.isNotEmpty)
            IconButton(
              onPressed: isLoading || isClearing
                  ? null
                  : clearHistory,
              icon: isClearing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(Icons.delete_outline),
              tooltip: 'Clear history',
            ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : history.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: loadHistory,
                  child: ListView.builder(
                    physics:
                        const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(12),
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      return _buildHistoryItem(
                        history[index],
                      );
                    },
                  ),
                ),
    );
  }
}
