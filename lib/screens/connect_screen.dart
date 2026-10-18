import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../services/device_discovery_service.dart';
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

class _ConnectScreenState extends State<ConnectScreen>
    with WidgetsBindingObserver {
  final TransferService _service = TransferService.instance;
  final DeviceDiscoveryService _discovery = DeviceDiscoveryService();

  StreamSubscription<Map<String, dynamic>>? _discoverySubscription;

  bool _loading = false;
  bool _receiverStarted = false;
  bool _connected = false;
  bool _checkingReceiver = false;
  bool _discoveryStarted = false;

  String _status = 'Ready to connect';
  String _transferMode = 'STANDARD';

  String? _peerIp;
  String? _peerUrl;
  String? _peerToken;
  String? _localIp;

  int? _localPort;
  int? _peerTcpPort;

  Timer? _receiverMonitor;

  final Map<String, Map<String, dynamic>> _nearbyDevices = {};

  String? get _localToken => _service.sessionToken;

  bool get _isSender => widget.role == TransferRole.send;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _status = _isSender
        ? 'Scan the receiver QR code or select a discovered device.'
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
    if (octets.any((value) => value == null)) return false;

    final a = octets[0]!;
    final b = octets[1]!;

    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }

  bool _isValidIpv4(String ip) {
    final address = InternetAddress.tryParse(ip);

    return address != null &&
        address.type == InternetAddressType.IPv4 &&
        !address.isLoopback &&
        !address.isMulticast;
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

          if (ip.startsWith('169.254.')) continue;

          fallbackIp ??= ip;

          if (_isPrivateIpv4(ip)) return ip;
        }
      }

      return fallbackIp;
    } catch (error, stackTrace) {
      debugPrint('IP lookup failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return null;
    }
  }

  Future<void> _startDiscovery() async {
    if (_discoveryStarted || !_isSender || _disposed) return;

    final ip = await _getLocalIp();

    if (!mounted || _disposed) return;

    if (ip == null) {
      setState(() {
        _status = 'Network unavailable. Check Wi-Fi or hotspot.';
      });
      return;
    }

    try {
      final discoveryToken =
          _localToken ?? 'discovery-${DateTime.now().millisecondsSinceEpoch}';

      await _discovery.startListening(
        deviceName: 'MAFX-ANDROID',
        sessionToken: discoveryToken,
        httpPort: _service.httpPort,
        tcpPort: _service.tcpPort ?? _service.httpPort,
      );

      if (!mounted || _disposed) {
        await _discovery.stop();
        return;
      }

      _discoveryStarted = true;

      _discoverySubscription ??= _discovery.devices.listen(
        (device) {
          if (!mounted) return;

          final ipValue = device['ip'];
          final portValue = device['httpPort'];

          if (ipValue is! String || portValue is! int) return;

          final key = '$ipValue:$portValue';

          setState(() {
            if (device['unavailable'] == true) {
              _nearbyDevices.remove(key);
            } else {
              _nearbyDevices[key] = device;
            }
          });
        },
        onError: (Object error) {
          debugPrint('Discovery stream error: $error');
        },
      );

      if (mounted) {
        setState(() {
          _status = _nearbyDevices.isEmpty
              ? 'Searching for nearby MAFX SHARE devices...'
              : 'Nearby devices found.';
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Device discovery failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _status =
            'Automatic discovery unavailable. You can still scan a QR code.';
      });
    }
  }

  bool _disposed = false;

  void _startReceiverMonitor() {
    _receiverMonitor?.cancel();
    _receiverMonitor = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _checkReceiverStatus(),
    );
  }

  void _stopReceiverMonitor() {
    _receiverMonitor?.cancel();
    _receiverMonitor = null;
  }

  Future<void> _checkReceiverStatus() async {
    if (!mounted ||
        !_receiverStarted ||
        _checkingReceiver ||
        _loading) {
      return;
    }

    _checkingReceiver = true;

    try {
      if (!_service.isServerRunning) {
        if (!mounted) return;

        setState(() {
          _receiverStarted = false;
          _localPort = null;
          _localIp = null;
          _connected = false;
          _peerIp = null;
          _peerUrl = null;
          _peerToken = null;
          _peerTcpPort = null;
          _status = 'Receiver stopped. Prepare it again.';
        });

        _stopReceiverMonitor();
        return;
      }

      final currentIp = await _getLocalIp();
      if (!mounted) return;

      if (currentIp == null) {
        setState(() {
          _status = 'Network unavailable. Check Wi-Fi.';
          _connected = false;
        });
        return;
      }

      if (currentIp != _localIp) {
        setState(() {
          _localIp = currentIp;
          _status = 'Network changed. Show the updated QR code.';
          _connected = false;
          _peerIp = null;
          _peerUrl = null;
          _peerToken = null;
          _peerTcpPort = null;
        });
      }
    } catch (error, stackTrace) {
      debugPrint('Receiver status check failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _checkingReceiver = false;
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
      final token = _localToken;
      final tcpPort = _service.tcpPort;

      if (!mounted) return;

      if (ip == null || token == null || tcpPort == null) {
        await _service.stopReceiver();
        if (!mounted) return;

        setState(() {
          _receiverStarted = false;
          _localPort = null;
          _localIp = null;
          _status = 'Network or TCP receiver is not ready.';
        });

        _message(
          'Check Wi-Fi or hotspot, then prepare the receiver again.',
        );
        return;
      }

      setState(() {
        _receiverStarted = true;
        _localPort = port;
        _localIp = ip;
        _status = 'Receiver ready. Waiting for the other phone.';
      });

      _startReceiverMonitor();
      _message('Receiver is ready.');
    } catch (error, stackTrace) {
      debugPrint('Receiver startup failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _receiverStarted = false;
        _localPort = null;
        _localIp = null;
        _status = 'Could not prepare receiver.';
      });

      _message('Receiver error: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _showMyQr() async {
    if (_loading) return;

    final tcpPort = _service.tcpPort;

    if (!_receiverStarted ||
        _localPort == null ||
        _localToken == null ||
        tcpPort == null ||
        !_service.isServerRunning) {
      setState(() {
        _receiverStarted = false;
        _localPort = null;
        _localIp = null;
        _status = 'Receiver is not running. Prepare it again.';
      });

      _message('Prepare the receiver first.');
      return;
    }

    setState(() {
      _loading = true;
      _status = 'Checking network...';
    });

    try {
      final ip = await _getLocalIp();
      if (!mounted) return;

      if (ip == null) {
        setState(() => _status = 'Network unavailable. Check Wi-Fi.');
        _message('Could not find the phone IP address.');
        return;
      }

      setState(() {
        _localIp = ip;
        _status = 'Receiver ready. Show this QR code to connect.';
      });

      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => QrScreen(
            ipAddress: ip,
            port: _localPort!,
            tcpPort: tcpPort,
            token: _localToken!,
            mode: 'STANDARD',
          ),
        ),
      );

      if (!mounted) return;
      await _checkReceiverStatus();
    } catch (error, stackTrace) {
      debugPrint('Could not show QR code: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;
      _message('Could not display the QR code.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _scanQr() async {
    if (_loading || !_isSender) return;

    await _startDiscovery();

    if (!mounted) return;

    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute<Map<String, dynamic>>(
        builder: (_) => const ScanQrScreen(),
      ),
    );

    if (!mounted || result == null) return;

    await _connectToPeer(result);
  }

  Future<void> _connectToDiscoveredDevice(
    Map<String, dynamic> device,
  ) async {
    final ip = device['ip'];
    final port = device['httpPort'];
    final tcpPort = device['tcpPort'];

    if (ip is! String || port is! int || tcpPort is! int) {
      _message('Invalid discovered device.');
      return;
    }

    _message(
      'Automatic device discovery does not provide the secure session token. '
      'Scan the receiver QR code to connect safely.',
    );
  }

  Future<void> _connectToPeer(Map<String, dynamic> result) async {
    final ipValue = result['ip'];
    final portValue = result['port'];
    final tcpPortValue = result['tcpPort'];
    final tokenValue = result['token'];
    final modeValue = result['mode'];

    if (result['app'] != 'MAFX_SHARE' ||
        result['version'] != 1 ||
        ipValue is! String ||
        !_isValidIpv4(ipValue.trim()) ||
        portValue is! int ||
        portValue < 1 ||
        portValue > 65535 ||
        tcpPortValue is! int ||
        tcpPortValue < 1 ||
        tcpPortValue > 65535 ||
        tokenValue is! String ||
        tokenValue.trim().isEmpty ||
        (modeValue != 'STANDARD' && modeValue != '5G_PLUS')) {
      _message('Invalid MAFX SHARE QR code. Update both phones first.');
      return;
    }

    final ip = ipValue.trim();
    final token = tokenValue.trim();
    final peerUrl = 'http://$ip:$portValue';
    final mode = modeValue as String;

    setState(() {
      _loading = true;
      _connected = false;
      _peerIp = null;
      _peerUrl = null;
      _peerToken = null;
      _peerTcpPort = null;
      _transferMode = 'STANDARD';
      _status = 'Authenticating connection to $ip...';
    });

    try {
      final connected = await _service.connectToReceiver(
        receiverUrl: peerUrl,
        token: token,
        mode: mode,
      );

      if (!mounted) return;

      if (!connected) {
        setState(() {
          _connected = false;
          _peerIp = null;
          _peerUrl = null;
          _peerToken = null;
          _peerTcpPort = null;
          _transferMode = 'STANDARD';
          _status = 'Connection authentication failed.';
        });

        _message(
          'Could not authenticate the receiver. '
          'Make sure both phones are on the same Wi-Fi or hotspot '
          'and the receiver is running.',
        );
        return;
      }

      setState(() {
        _connected = true;
        _peerIp = ip;
        _peerUrl = peerUrl;
        _peerToken = token;
        _peerTcpPort = tcpPortValue;
        _transferMode = mode;
        _status = mode == '5G_PLUS'
            ? 'Connected. 5G+ High-Speed Mode selected.'
            : 'Connected successfully to $ip';
      });

      _message(
        mode == '5G_PLUS'
            ? 'Connected. 5G+ High-Speed Mode selected.'
            : 'Connection authenticated successfully.',
      );

      await _chooseFiles();
    } catch (error, stackTrace) {
      debugPrint('Connection failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _connected = false;
        _peerIp = null;
        _peerUrl = null;
        _peerToken = null;
        _peerTcpPort = null;
        _transferMode = 'STANDARD';
        _status = 'Connection failed.';
      });

      _message('Connection error. Please try again.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _chooseFiles() async {
    if (!_isSender ||
        !_connected ||
        _peerUrl == null ||
        _peerToken == null) {
      _message('Connect to the receiving phone first.');
      return;
    }

    final receiverUrl = _peerUrl!;
    final receiverToken = _peerToken!;
    final transferMode = _transferMode;
    final receiverTcpPort = _peerTcpPort;

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SendScreen(
          receiverUrl: receiverUrl,
          receiverToken: receiverToken,
          category: widget.category,
          transferMode: transferMode,
          receiverTcpPort: receiverTcpPort,
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

    _stopReceiverMonitor();

    try {
      await _service.stopReceiver();
      if (!mounted) return;

      setState(() {
        _receiverStarted = false;
        _connected = false;
        _localPort = null;
        _localIp = null;
        _peerIp = null;
        _peerUrl = null;
        _peerToken = null;
        _peerTcpPort = null;
        _transferMode = 'STANDARD';
        _status = 'Receiver stopped.';
      });

      _message('Receiver stopped.');
    } catch (error, stackTrace) {
      debugPrint('Could not stop receiver: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;
      _message('Could not stop receiver.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _receiverStarted) {
      _checkReceiverStatus();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _stopReceiverMonitor();
    WidgetsBinding.instance.removeObserver(this);

    unawaited(_discoverySubscription?.cancel());
    unawaited(_discovery.dispose());

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
          if (!_isSender)
            IconButton(
              tooltip: 'Show my QR',
              onPressed: _receiverStarted && !_loading ? _showMyQr : null,
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
              _isSender ? Icons.send_rounded : Icons.download_rounded,
              size: 76,
              color: const Color(0xFF00D18B),
            ),
            const SizedBox(height: 20),
            Text(
              _isSender ? 'Connect Before Sending' : 'Receive Files',
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
                  ? 'Scan the receiver QR code to connect securely.'
                  : 'Prepare this phone, then show its QR code to the sending phone.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),
            if (!_isSender) ...[
              _ActionButton(
                icon: Icons.wifi_rounded,
                title:
                    _receiverStarted ? 'Receiver Ready' : 'Prepare to Receive',
                onPressed:
                    _loading || _receiverStarted ? null : _prepareReceiver,
              ),
              const SizedBox(height: 14),
              _ActionButton(
                icon: Icons.qr_code_2_rounded,
                title: 'Show My QR Code',
                onPressed:
                    _loading || !_receiverStarted ? null : _showMyQr,
              ),
              if (_localIp != null) ...[
                const SizedBox(height: 12),
                SelectableText(
                  'Local IP: $_localIp',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ],
            if (_isSender) ...[
              _ActionButton(
                icon: Icons.qr_code_scanner_rounded,
                title: _loading
                    ? 'Authenticating Connection...'
                    : 'Scan Receiver QR Code',
                onPressed: _loading ? null : _scanQr,
              ),
              const SizedBox(height: 12),
              const Text(
                'Both phones must be on the same Wi-Fi network or hotspot.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, height: 1.5),
              ),
              const SizedBox(height: 20),
              const Text(
                'Nearby devices',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              if (_nearbyDevices.isEmpty)
                const Text(
                  'Device discovery runs while you open the QR scanner. '
                  'If no devices appear, use the receiver QR code.',
                  style: TextStyle(color: Colors.white60, height: 1.4),
                )
              else
                ..._nearbyDevices.values.map(
                  (device) => Card(
                    color: Colors.white10,
                    child: ListTile(
                      leading: const Icon(
                        Icons.phone_android_rounded,
                        color: Color(0xFF00D18B),
                      ),
                      title: Text(
                        device['deviceName']?.toString() ?? 'MAFX device',
                        style: const TextStyle(color: Colors.white),
                      ),
                      subtitle: Text(
                        '${device['ip']}:${device['httpPort']}',
                        style: const TextStyle(color: Colors.white60),
                      ),
                      onTap: _loading
                          ? null
                          : () => _connectToDiscoveredDevice(device),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _connected
                      ? const Color(0xFF00D18B)
                      : Colors.white12,
                ),
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
                  if (_connected) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Transfer mode: $_transferMode',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                  if (_peerIp != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Connected device: $_peerIp',
                      style: const TextStyle(color: Colors.white70),
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
            if (_receiverStarted) ...[
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: _loading ? null : _stopReceiver,
                icon: const Icon(Icons.stop_circle_outlined),
                label: const Text('Stop Receiver'),
                style: TextButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                ),
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
          textAlign: TextAlign.center,
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
