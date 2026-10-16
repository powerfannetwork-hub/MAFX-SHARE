import 'dart:io';

import 'package:flutter/material.dart';

import '../services/transfer_service.dart';
import 'qr_screen.dart';
import 'scan_qr_screen.dart';
import 'send_screen.dart';

class ConnectScreen extends StatefulWidget {
  final String? category;

  const ConnectScreen({
    super.key,
    this.category,
  });

  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  final TransferService _service = TransferService.instance;

  bool _loading = false;
  bool _receiverStarted = false;
  bool _connected = false;

  String _mode = 'STANDARD';
  String _status = 'Start the receiver to begin connecting.';

  String? _peerIp;
  String? _peerUrl;
  String? _peerToken;

  int? _localPort;

  String? get _localToken => _service.sessionToken;

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

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _startReceiver() async {
    if (_loading || _receiverStarted) return;

    setState(() {
      _loading = true;
      _status = 'Starting receiver...';
    });

    try {
      final port = await _service.startReceiver();
      final ip = await _getLocalIp();

      if (!mounted) return;

      if (ip == null || _localToken == null) {
        setState(() {
          _status =
              'Could not find your local IP address or receiver token.';
        });

        _showMessage(
          'Connect this phone to Wi-Fi or a hotspot, then try again.',
        );
        return;
      }

      setState(() {
        _receiverStarted = true;
        _localPort = port;
        _status =
            'Receiver is ready. Now connect to the other phone.';
      });

      _showMessage('Receiver started successfully.');
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _status = 'Could not start receiver.';
      });

      _showMessage('Unable to start receiver: $error');
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
      _showMessage('Start the receiver first.');
      return;
    }

    final ip = await _getLocalIp();

    if (!mounted) return;

    if (ip == null) {
      _showMessage(
        'Could not find the phone IP address. Check your network.',
      );
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => QrScreen(
          ipAddress: ip,
          port: _localPort!,
          token: _localToken!,
          mode: _mode,
        ),
      ),
    );
  }

  Future<void> _scanPeerQr() async {
    if (!_receiverStarted) {
      _showMessage('Start your receiver before scanning.');
      return;
    }

    if (_loading) return;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute<Map<String, dynamic>>(
        builder: (_) => const ScanQrScreen(),
      ),
    );

    if (!mounted || result == null) return;

    final app = result['app'];
    final version = result['version'];
    final ip = result['ip'];
    final port = result['port'];
    final token = result['token'];

    if (app != 'MAFX_SHARE' ||
        version != 1 ||
        ip is! String ||
        ip.trim().isEmpty ||
        port is! int ||
        port < 1 ||
        port > 65535 ||
        token is! String ||
        token.trim().isEmpty) {
      _showMessage('The QR code is invalid.');
      return;
    }

    final peerUrl = 'http://$ip:$port';

    setState(() {
      _loading = true;
      _connected = false;
      _status = 'Checking the other phone...';
    });

    try {
      final isReachable = await _service.checkReceiver(peerUrl);

      if (!mounted) return;

      if (!isReachable) {
        setState(() {
          _status = 'Connection failed. Try again.';
        });

        _showMessage(
          'Cannot reach the other phone. Make sure both phones '
          'are connected to the same Wi-Fi or hotspot and that '
          'the other receiver is running.',
        );
        return;
      }

      setState(() {
        _connected = true;
        _peerIp = ip;
        _peerUrl = peerUrl;
        _peerToken = token;
        _status =
            'Connection verified. You can now choose files to send.';
      });

      _showMessage('Connection successful!');
    } catch (error) {
      if (!mounted) return;

      setState(() {
        _connected = false;
        _status = 'Unable to connect to the other phone.';
      });

      _showMessage('Connection error: $error');
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
      _showMessage('Connect to the other phone first.');
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

  Future<void> _stopConnection() async {
    if (_loading) return;

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

    _showMessage('Receiver stopped.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Devices'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 12),
          const Icon(
            Icons.devices_rounded,
            size: 82,
            color: Color(0xFF00AEEF),
          ),
          const SizedBox(height: 16),
          const Text(
            'MAFX SHARE',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 27,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Connect first. Choose files after connection.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Connection mode',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                    ),
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
                    onChanged: _loading || _receiverStarted
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() {
                                _mode = value;
                              });
                            }
                          },
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Step 1: Start your receiver',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Both phones must start their receivers. '
                    'This allows each phone to send and receive files.',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _loading || _receiverStarted
                          ? null
                          : _startReceiver,
                      icon: const Icon(Icons.wifi_tethering),
                      label: Text(
                        _receiverStarted
                            ? 'Receiver Started'
                            : 'Start Receiver',
                      ),
                    ),
                  ),
                  if (_receiverStarted) ...[
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _showMyQr,
                        icon: const Icon(Icons.qr_code_2),
                        label: const Text('Show My QR Code'),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Step 2: Scan the other phone',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'On both phones, scan the QR code displayed '
                    'by the other phone. Each phone needs the '
                    'other phone connection details.',
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _loading || !_receiverStarted
                          ? null
                          : _scanPeerQr,
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan Other Phone QR'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          Card(
            color: _connected
                ? Colors.green.withValues(alpha: 0.08)
                : null,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Icon(
                    _connected
                        ? Icons.check_circle
                        : Icons.info_outline,
                    size: 36,
                    color: _connected
                        ? Colors.green
                        : Colors.blueGrey,
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                  ),
                  if (_peerIp != null) ...[
                    const SizedBox(height: 8),
                    Text('Other phone: $_peerIp'),
                  ],
                  if (_loading) ...[
                    const SizedBox(height: 14),
                    const CircularProgressIndicator(),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton.icon(
              onPressed:
                  _connected && !_loading ? _chooseFiles : null,
              icon: const Icon(Icons.folder_open),
              label: const Text('Choose Files to Send'),
            ),
          ),

          const SizedBox(height: 12),

          if (_receiverStarted)
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: _loading ? null : _stopConnection,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop Receiver'),
              ),
            ),

          const SizedBox(height: 12),

          const Text(
            'Connect both phones to the same Wi-Fi or hotspot. '
            'The 5G+ option is only a mode label and does not '
            'increase network speed by itself.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
    );
  }
}
