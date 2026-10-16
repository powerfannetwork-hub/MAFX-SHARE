import 'dart:io';

import 'package:flutter/material.dart';

import '../services/transfer_service.dart';
import 'qr_screen.dart';
import 'scan_qr_screen.dart';

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key});

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final TransferService _service = TransferService.instance;

  bool _loading = false;
  String _mode = 'STANDARD';

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback && address.type == InternetAddressType.IPv4) {
            return address.address;
          }
        }
      }
    } catch (_) {}

    return null;
  }

  Future<void> _showMyQr() async {
    setState(() => _loading = true);

    try {
      final port = await _service.startReceiver();
      final ip = await _getLocalIp();
      final token = _service.sessionToken;

      if (!mounted) return;

      if (ip == null || token == null) {
        _message(
          'Ba a sami IP address ba. Ka kunna Wi-Fi ko hotspot, sannan ka sake gwadawa.',
        );
        return;
      }

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => QrScreen(
            ipAddress: ip,
            port: port,
            token: token,
            mode: _mode,
          ),
        ),
      );
    } catch (error) {
      if (mounted) {
        _message('An kasa fara haɗin: $error');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scanQr() async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanQrScreen(),
      ),
    );

    if (!mounted || result == null) return;

    final ip = result['ip'] as String;
    final port = result['port'] as int;
    final token = result['token'] as String;
    final url = 'http://$ip:$port';

    setState(() => _loading = true);

    try {
      final connected = await _service.checkReceiver(url);

      if (!mounted) return;

      if (!connected) {
        _message(
          'Ba a iya isa ga receiver ba. Tabbatar wayoyin suna kan Wi-Fi ko hotspot ɗaya.',
        );
        return;
      }

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Receiver Found'),
          content: SelectableText(
            'IP: $ip\n'
            'Port: $port\n'
            'Mode: ${result['mode']}\n\n'
            'Receiver ya amsa. Ana buƙatar haɗa wannan bayanin da SEND kafin a aika fayil.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );

      // Keep these values available for the next SEND integration step.
      debugPrint('MAFX receiver URL: $url');
      debugPrint('MAFX token received: ${token.isNotEmpty}');
    } catch (error) {
      if (mounted) _message('Connection check failed: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _message(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Connect Device')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 20),
          const Icon(
            Icons.devices_rounded,
            size: 80,
            color: Color(0xFF00AEEF),
          ),
          const SizedBox(height: 16),
          const Text(
            'Connect Your Devices',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 28),
          const Text(
            'Choose connection mode:',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _mode,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(
                value: 'STANDARD',
                child: Text('Standard'),
              ),
              DropdownMenuItem(
                value: '5G_PLUS',
                child: Text('5G+'),
              ),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _mode = value);
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _loading ? null : _showMyQr,
            icon: const Icon(Icons.qr_code_2),
            label: const Text('START RECEIVER & SHOW QR'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _loading ? null : _scanQr,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('SCAN RECEIVER QR'),
          ),
          if (_loading) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
          ],
          const SizedBox(height: 24),
          const Text(
            'Ka haɗa wayoyin biyu da Wi-Fi ko hotspot ɗaya kafin gwaji. '
            '5G+ sunan mode ne kawai; ba ya ƙara saurin network da kansa.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
