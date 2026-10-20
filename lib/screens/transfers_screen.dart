import 'package:flutter/material.dart';

import '../services/transfer_service.dart';
import '../theme/app_theme.dart';

class TransfersScreen extends StatefulWidget {
  const TransfersScreen({super.key});

  @override
  State<TransfersScreen> createState() => _TransfersScreenState();
}

class _TransfersScreenState extends State<TransfersScreen> {
  final TransferService _transferService = TransferService.instance;

  List<Map<String, dynamic>> _transfers = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadTransfers();
  }

  Future<void> _loadTransfers() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final transfers = await _transferService.getTransferHistory();

      if (!mounted) return;

      setState(() {
        _transfers = transfers;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Unable to load transfer history.';
      });
    }
  }

  int get _totalSent {
    return _transfers
        .where((transfer) => transfer['direction'] == 'sent')
        .length;
  }

  int get _totalReceived {
    return _transfers
        .where((transfer) => transfer['direction'] == 'received')
        .length;
  }

  int get _totalBytes {
    return _transfers.fold<int>(
      0,
      (total, transfer) {
        final bytes = transfer['bytes'];
        return total + (bytes is num ? bytes.toInt() : 0);
      },
    );
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

  String _formatDate(dynamic value) {
    if (value is! String) {
      return 'Date unavailable';
    }

    final date = DateTime.tryParse(value);

    if (date == null) {
      return 'Date unavailable';
    }

    final localDate = date.toLocal();
    final hour = localDate.hour % 12 == 0
        ? 12
        : localDate.hour % 12;
    final minute = localDate.minute.toString().padLeft(2, '0');
    final period = localDate.hour >= 12 ? 'PM' : 'AM';

    return '${localDate.day}/${localDate.month}/${localDate.year}'
        ' • $hour:$minute $period';
  }

  String _fileName(Map<String, dynamic> transfer) {
    final name = transfer['fileName'];

    if (name is String && name.trim().isNotEmpty) {
      return name;
    }

    return 'Unknown file';
  }

  bool _isReceived(Map<String, dynamic> transfer) {
    return transfer['direction'] == 'received';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8FA),
      appBar: AppBar(
        title: const Text(
          'Transfers',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            onPressed: _isLoading ? null : _loadTransfers,
            tooltip: 'Refresh transfers',
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadTransfers,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 180),
          Center(
            child: CircularProgressIndicator(
              color: AppTheme.green,
            ),
          ),
          SizedBox(height: 16),
          Center(
            child: Text('Loading transfers...'),
          ),
        ],
      );
    }

    if (_errorMessage != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
        children: [
          const SizedBox(height: 100),
          const Icon(
            Icons.error_outline_rounded,
            size: 56,
            color: Colors.redAccent,
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              _errorMessage!,
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: FilledButton.icon(
              onPressed: _loadTransfers,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(18),
      children: [
        _buildSummaryCard(),
        const SizedBox(height: 22),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Transfer History',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            Text(
              '${_transfers.length} items',
              style: const TextStyle(
                color: Colors.blueGrey,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_transfers.isEmpty)
          _buildEmptyState()
        else
          ..._transfers.map(_buildTransferTile),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _buildSummaryCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFE5EDF4),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: AppTheme.green.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(
                  Icons.swap_vert_circle_rounded,
                  color: AppTheme.green,
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Transfers',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'A summary of your file transfers',
                      style: TextStyle(
                        color: Colors.blueGrey,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(
                child: _buildStat(
                  icon: Icons.arrow_upward_rounded,
                  label: 'Sent',
                  value: '$_totalSent',
                  color: const Color(0xFF2878D0),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildStat(
                  icon: Icons.arrow_downward_rounded,
                  label: 'Received',
                  value: '$_totalReceived',
                  color: AppTheme.green,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F8FA),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.storage_rounded,
                  color: Colors.blueGrey,
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Total transfer data',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey,
                    ),
                  ),
                ),
                Text(
                  _formatBytes(_totalBytes),
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: color,
            size: 25,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.blueGrey,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTransferTile(Map<String, dynamic> transfer) {
    final received = _isReceived(transfer);
    final directionColor = received
        ? AppTheme.green
        : const Color(0xFF2878D0);

    final bytesValue = transfer['bytes'];
    final bytes = bytesValue is num ? bytesValue.toInt() : 0;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFFE5EDF4),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 10,
        ),
        leading: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: directionColor.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(
            received
                ? Icons.south_west_rounded
                : Icons.north_east_rounded,
            color: directionColor,
            size: 25,
          ),
        ),
        title: Text(
          _fileName(transfer),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                received ? 'Received' : 'Sent',
                style: TextStyle(
                  color: directionColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatDate(transfer['timestamp']),
                style: const TextStyle(
                  color: Colors.blueGrey,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
        trailing: Text(
          _formatBytes(bytes),
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 22,
        vertical: 34,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: const Color(0xFFE5EDF4),
        ),
      ),
      child: const Column(
        children: [
          Icon(
            Icons.folder_open_rounded,
            color: AppTheme.green,
            size: 56,
          ),
          SizedBox(height: 16),
          Text(
            'No transfers yet',
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
          SizedBox(height: 8),
          Text(
            'Files you send or receive will appear here after the transfer is recorded.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.blueGrey,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
