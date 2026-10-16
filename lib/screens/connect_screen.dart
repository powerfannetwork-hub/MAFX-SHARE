import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../services/transfer_service.dart';
import 'qr_screen.dart';
import 'scan_qr_screen.dart';

class ConnectScreen extends StatefulWidget {
  final List<PlatformFile> files;

  const ConnectScreen({
    super.key,
    this.files = const [],
  });

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final TransferService _service = TransferService.instance;

  bool _loading = false;
  String _mode = 'STANDARD';
  String _status = '';

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (!address.isLoopback &&
              address.type == InternetAddressType.IPv4) {
            return address.address;
          }
        }
      }
    } catch (error) {
      debugPrint('IP lookup failed: $error');
    }

    return null;
  }

  Future<void> _showMyQr() async {
    setState(() {
      _loading = true;
      _status = 'Ana fara receiver...';
    });

    try {
      final port = await _service.startReceiver();
      final ip = await _getLocalIp();
      final token = _service.sessionToken;

      if (!mounted) return;

      if (ip == null || token == null) {
        _message(
          'Ba a sami IP ba. Ka haɗa wayar da Wi-Fi ko hotspot, sannan ka sake gwadawa.',
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
      if (mounted) _message('An kasa fara receiver: $error');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _status = '';
        });
      }
    }
  }

  Future<void> _scanQr() async {
    if (widget.files.isEmpty) {
      _message('Da farko ka buɗe SEND ka zaɓi fayiloli.');
      return;
    }

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanQrScreen(),
      ),
    );

    if (!mounted || result == null) return;

    final ip = result['ip'] as String?;
    final port = result['port'] as int?;
    final token = result['token'] as String?;

    if (ip == null ||
        port == null ||
        token == null ||
        ip.isEmpty ||
        token.isEmpty ||
        port < 1 ||
        port > 65535) {
      _message('QR code ɗin ba shi da cikakken bayani.');
      return;
    }

    final url = 'http://$ip:$port';

    setState(() {
      _loading = true;
      _status = 'Ana duba receiver...';
    });

    try {
      final connected = await _service.checkReceiver(url);

      if (!mounted) return;

      if (!connected) {
        _message(
          'Ba a samu receiver ba. Tabbatar wayoyin suna kan Wi-Fi ko hotspot ɗaya, kuma receiver yana kunne.',
        );
        return;
      }

      final approved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('An Samu Receiver'),
          content: Text(
            'Fayiloli: ${widget.files.length}\n'
            'Na’urar: $ip\n'
            'Mode: ${result['mode'] ?? 'STANDARD'}\n\n'
            'Kana son fara aika fayilolin?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Soke'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Aika Yanzu'),
            ),
          ],
        ),
      );

      if (!mounted || approved != true) return;

      int completed = 0;
      final failed = <String>[];

      for (final file in widget.files) {
        final path = file.path;

        if (path == null || path.isEmpty) {
          failed.add(file.name);
          continue;
        }

        if (!mounted) return;

        setState(() {
          _status = 'Ana aika ${completed + failed.length + 1}'
              ' cikin ${widget.files.length}: ${file.name}';
        });

        try {
          await _service.sendFile(
            receiverUrl: url,
            token: token,
            filePath: path,
            fileName: file.name,
          );
          completed++;
        } catch (error) {
          debugPrint('Failed to send ${file.name}: $error');
          failed.add(file.name);
        }
      }

      if (!mounted) return;

      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('An Kammala Aika Fayiloli'),
          content: Text(
            'An aika: $completed\n'
            'Ba a iya aika ba: ${failed.length}'
            '${failed.isEmpty ? '' : '\n\n' + failed.join('\n')}',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (mounted) _message('An samu matsala wajen aika fayiloli: $error');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
          _status = '';
        });
      }
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
          const SizedBox(height: 16),
          const Icon(
            Icons.devices_rounded,
            size: 76,
            color: Color(0xFF00AEEF),
          ),
          const SizedBox(height: 16),
          const Text(
            'Connect Your Devices',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Fayilolin da aka zaɓa: ${widget.files.length}',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          const Text(
            'Zaɓi yanayin haɗi:',
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
            onChanged: _loading
                ? null
                : (value) {
                    if (value != null) {
                      setState(() => _mode = value);
                    }
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
            label: const Text('SCAN QR & SEND FILES'),
          ),
          if (_loading) ...[
            const SizedBox(height: 20),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 8),
            Text(_status, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 24),
          const Text(
            'Muhimmi: Haɗa wayoyin biyu da Wi-Fi ko hotspot ɗaya. '
            '5G+ suna ne kawai na mode; ba ya ƙara saurin network da kansa.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
