import 'dart:io';

import 'package:flutter/material.dart';

import '../services/transfer_service.dart';
import 'qr_screen.dart';
import 'scan_qr_screen.dart';
import 'send_screen.dart';

enum TransferRole {
  send,
  receive,
}

class ConnectScreen extends StatefulWidget {
  final String? category;
  final TransferRole role;

  const ConnectScreen({
    super.key,
    this.category,
    this.role = TransferRole.receive,
  });

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final TransferService _service = TransferService.instance;

  bool _loading = false;
  bool _receiverStarted = false;
  bool _connected = false;

  String _status = 'Ready to connect';

  String? _peerIp;
  String? _peerUrl;
  String? _peerToken;

  int? _localPort;

  String? get _localToken => _service.sessionToken;

  bool get _isSender => widget.role == TransferRole.send;

  @override
  void initState() {
    super.initState();

    _status = _isSender
        ? 'Scan the receiver QR code to connect.'
        : 'Prepare this phone to receive files.';
  }

  void _message(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  bool _isPrivateIpv4(String ip) {
    final parts = ip.split('.');

    if (parts.length != 4) return false;

    final octets = parts.map(int.tryParse).toList();

    if (octets.any((value) => value == null)) {
      return false;
    }

    final a = octets[0]!;
    final b = octets[1]!;

    if (a == 10) return true;

    if (a == 172 && b >= 16 && b <= 31) {
      return true;
    }

    if (a == 192 && b == 168) {
      return true;
    }

    return false;
  }

  Future<String?> _getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      String? fallbackIp;

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.isLoopback ||
              address.type != InternetAddressType.IPv4) {
            continue;
          }

          final ip = address.address;

          if (ip.startsWith('169.254.')) {
            continue;
          }

          fallbackIp ??= ip;

          if (_isPrivateIpv4(ip)) {
            return ip;
          }
        }
      }

      return fallbackIp;
    } catch (error, stackTrace) {
      debugPrint('IP lookup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> _prepareReceiver() async {
    if (_loading || _receiverStarted) return;

    setState(() {
      _loading = true;
      _status = 'Preparing receiver...';
    });

    try {
      final port = await _service.startReceiver();
      final ip = await _getLocalIp();

      if (!mounted) return;

      if (ip == null || _localToken == null) {
        await _service.stopReceiver();

        setState(() {
          _receiverStarted = false;
          _localPort = null;
          _status = 'Network not ready. Check Wi-Fi.';
        });

        _message(
          'Connect this phone to Wi-Fi or a hotspot, '
          'then try again.',
        );

        return;
      }

      setState(() {
        _receiverStarted = true;
        _localPort = port;
        _status = 'Ready. Waiting for the other phone.';
      });

      _message('Receiver is ready.');
    } catch (error, stackTrace) {
      debugPrint('Receiver startup failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _receiverStarted = false;
        _localPort = null;
        _status = 'Could not prepare receiver.';
      });

      _message('Receiver error: $error');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _showMyQr() async {
    if (!_receiverStarted ||
        _localPort == null ||
        _localToken == null) {
      _message('Prepare the receiver first.');
      return;
    }

    final ip = await _getLocalIp();

    if (!mounted) return;

    if (ip == null) {
      _message('Could not find the phone IP address.');
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => QrScreen(
          ipAddress: ip,
          port: _localPort!,
          token: _localToken!,
          mode: 'STANDARD',
        ),
      ),
    );
  }

  Future<void> _scanQr() async {
    if (_loading) return;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute<Map<String, dynamic>>(
        builder: (_) => const ScanQrScreen(),
      ),
    );

    if (!mounted || result == null) return;

    final ip = result['ip'];
    final port = result['port'];
    final token = result['token'];

    if (result['app'] != 'MAFX_SHARE' ||
        result['version'] != 1 ||
        ip is! String ||
        ip.trim().isEmpty ||
        port is! int ||
        port < 1 ||
        port > 65535 ||
        token is! String ||
        token.trim().isEmpty) {
      _message('Invalid MAFX SHARE QR code.');
      return;
    }

    final peerUrl = 'http://$ip:$port';

    setState(() {
      _loading = true;
      _connected = false;
      _status = 'Connecting to $ip...';
    });

    try {
      final reachable = await _service.checkReceiver(peerUrl);

      if (!mounted) return;

      if (!reachable) {
        setState(() {
          _connected = false;
          _peerIp = null;
          _peerUrl = null;
          _peerToken = null;
          _status = 'Connection failed.';
        });

        _message(
          'Could not reach the other phone. '
          'Check that both phones are on the same Wi-Fi '
          'or hotspot and that the receiver is running.',
        );

        return;
      }

      setState(() {
        _connected = true;
        _peerIp = ip;
        _peerUrl = peerUrl;
        _peerToken = token;
        _status = 'Connected to $ip';
      });

      _message('Connected successfully.');

      if (_isSender) {
        await _chooseFiles();
      }
    } catch (error, stackTrace) {
      debugPrint('Connection failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _connected = false;
        _status = 'Connection failed.';
      });

      _message('Connection error: $error');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _chooseFiles() async {
    if (!_connected || _peerUrl == null || _peerToken == null) {
      _message('Connect to the other phone first.');
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SendScreen(
          receiverUrl: _peerUrl!,
          receiverToken: _peerToken!,
          category: widget.category,
        ),
      ),
    );
  }

  Future<void> _stopReceiver() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _status = 'Stopping receiver...';
    });

    try {
      await _service.stopReceiver();

      if (!mounted) return;

      setState(() {
        _receiverStarted = false;
        _connected = false;
        _localPort = null;
        _peerIp = null;
        _peerUrl = null;
        _peerToken = null;
        _status = 'Receiver stopped.';
      });
    } catch (error) {
      if (!mounted) return;

      _message('Could not stop receiver: $error');
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF008D5A);
    const dark = Color(0xFF202024);

    return Scaffold(
      backgroundColor: dark,
      appBar: AppBar(
        backgroundColor: green,
        foregroundColor: Colors.white,
        title: Text(_isSender ? 'Send' : 'Receive'),
        actions: [
          IconButton(
            tooltip: 'Show my QR',
            onPressed: _receiverStarted ? _showMyQr : null,
            icon: const Icon(Icons.qr_code_2_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const SizedBox(height: 24),
            Icon(
              _isSender
                  ? Icons.send_rounded
                  : Icons.download_rounded,
              size: 76,
              color: const Color(0xFF00D18B),
            ),
            const SizedBox(height: 20),
            Text(
              _isSender
                  ? 'Send files quickly'
                  : 'Receive files quickly',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _isSender
                  ? 'Scan the QR code shown on the receiving phone.'
                  : 'Prepare this phone and show your QR code.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 32),
            if (!_isSender) ...[
              _ActionButton(
                icon: Icons.wifi_rounded,
                title: _receiverStarted
                    ? 'Receiver Ready'
                    : 'Prepare to Receive',
                onPressed: _loading || _receiverStarted
                    ? null
                    : _prepareReceiver,
              ),
              const SizedBox(height: 14),
              _ActionButton(
                icon: Icons.qr_code_2_rounded,
                title: 'Show My QR Code',
                onPressed: _receiverStarted ? _showMyQr : null,
              ),
            ],
            if (_isSender) ...[
              _ActionButton(
                icon: Icons.qr_code_scanner_rounded,
                title: 'Scan QR Code',
                onPressed: _loading ? null : _scanQr,
              ),
              const SizedBox(height: 12),
              const Text(
                'The receiving phone must prepare its receiver '
                'and display its QR code first.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white60,
                  height: 1.5,
                ),
              ),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white12),
              ),
              child: Column(
                children: [
                  Icon(
                    _connected
                        ? Icons.check_circle_rounded
                        : Icons.info_outline_rounded,
                    color: _connected
                        ? const Color(0xFF00D18B)
                        : Colors.white70,
                    size: 34,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                    ),
                  ),
                  if (_peerIp != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Device: $_peerIp',
                      style: const TextStyle(
                        color: Colors.white70,
                      ),
                    ),
                  ],
                  if (_loading) ...[
                    const SizedBox(height: 16),
                    const CircularProgressIndicator(
                      color: Color(0xFF00D18B),
                    ),
                  ],
                ],
              ),
            ),
            if (_connected && !_isSender) ...[
              const SizedBox(height: 18),
              _ActionButton(
                icon: Icons.folder_open_rounded,
                title: 'Choose Files to Send',
                onPressed: _chooseFiles,
              ),
            ],
            if (_receiverStarted) ...[
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: _loading ? null : _stopReceiver,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop Receiver'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback? onPressed;

  const _ActionButton({
    required this.icon,
    required this.title,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 58,
      child: FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon),
        label: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: FilledButton.styleFrom(
          backgroundColor: const Color(0xFF008D5A),
          foregroundColor: Colors.white,
          disabledBackgroundColor: Colors.white12,
          disabledForegroundColor: Colors.white38,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}
