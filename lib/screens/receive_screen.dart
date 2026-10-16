import 'package:flutter/material.dart';
import '../services/transfer_service.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});

  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  final TransferService _transferService = TransferService.instance;

  bool _starting = false;
  String _status = 'Ready to receive files';
  int? _port;

  Future<void> _startReceiving() async {
    setState(() {
      _starting = true;
      _status = 'Starting receiver...';
    });

    try {
      final port = await _transferService.startReceiver();

      if (!mounted) return;

      setState(() {
        _port = port;
        _status = 'Receiver is running on port $port';
      });

      _showMessage(
        'Receiver started. Connect both devices to the same local network.',
      );
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _status = 'Could not start receiver: $error';
      });
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  Future<void> _stopReceiving() async {
    await _transferService.stopReceiver();

    if (!mounted) return;

    setState(() {
      _port = null;
      _status = 'Receiver stopped';
    });
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Files'),
        backgroundColor: Colors.green,
        foregroundColor: Colors.white,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.download_for_offline,
                size: 100,
                color: Colors.green,
              ),
              const SizedBox(height: 20),
              const Text(
                'MAFX SHARE',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                _status,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              if (_port == null)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _starting ? null : _startReceiving,
                    icon: const Icon(Icons.wifi),
                    label: Text(
                      _starting ? 'Starting...' : 'START RECEIVING',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.all(16),
                    ),
                  ),
                )
              else ...[
                SelectableText('Port: $_port'),
                const SizedBox(height: 12),
                const Text(
                  'Keep this screen available while preparing the connection.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _stopReceiving,
                    icon: const Icon(Icons.stop),
                    label: const Text('STOP RECEIVING'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
