import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<Map<String, dynamic>> history = [];
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    loadHistory();
  }

  Future<void> loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? data = prefs.getString('mafx_transfer_history');

    List<Map<String, dynamic>> items = [];

    if (data != null) {
      try {
        final decoded = jsonDecode(data);

        if (decoded is List) {
          items = decoded
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList();
        }
      } catch (_) {
        items = [];
      }
    }

    if (!mounted) return;

    setState(() {
      history = items;
      isLoading = false;
    });
  }

  Future<void> clearHistory() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History'),
        content: const Text(
          'Are you sure you want to clear all transfer history?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('mafx_transfer_history');

    if (!mounted) return;

    setState(() {
      history.clear();
    });
  }

  String formatBytes(dynamic value) {
    final bytes = (value is num) ? value.toDouble() : 0.0;

    if (bytes < 1024) {
      return '${bytes.toInt()} B';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfer History'),
        actions: [
          IconButton(
            onPressed: loadHistory,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          if (history.isNotEmpty)
            IconButton(
              onPressed: clearHistory,
              icon: const Icon(Icons.delete_outline),
              tooltip: 'Clear history',
            ),
        ],
      ),
      body: isLoading
          ? const Center(
              child: CircularProgressIndicator(),
            )
          : history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.history,
                        size: 80,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No transfer history yet',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Your completed transfers will appear here.',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: loadHistory,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: history.length,
                    itemBuilder: (context, index) {
                      final item = history[index];

                      final fileName =
                          item['fileName']?.toString() ?? 'Unknown file';

                      final direction =
                          item['direction']?.toString() ?? 'unknown';

                      final isSent = direction.toLowerCase() == 'sent';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
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
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isSent ? 'Sent' : 'Received',
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  formatBytes(item['bytes']),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  formatDate(item['completedAt']),
                                ),
                              ],
                            ),
                          ),
                          isThreeLine: true,
                        ),
                      );
                    },
                  ),
                ),
    );
  }
}
