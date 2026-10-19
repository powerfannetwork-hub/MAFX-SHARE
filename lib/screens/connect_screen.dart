import 'dart:async';
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

class _ConnectScreenState extends State<ConnectScreen>
    with WidgetsBindingObserver {
  final TransferService _service = TransferService.instance;

  bool _loading = false;
  bool _connected = false;
  bool _disposed = false;
  bool _openingScanner = false;
  bool _showingQr = false;

  String _status = 'Preparing device connection...';
  String _transferMode = TransferService.standardMode;

  String? _localIp;
  String? _peerIp;
  String? _peerUrl;
  String? _peerToken;

  int? _localPort;
  int? _peerTcpPort;

  Timer? _connectionPollTimer;

  bool get _isSender => widget.role == TransferRole.send;

  String? get _localToken => _service.sessionToken;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeConnection();
    });
  }

  void _message(String message) {
    if (!mounted || _disposed) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
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

      String? fallback;

      for (final interface in interfaces) {
        for (final address in interface.addresses) {
          if (address.isLoopback ||
              address.type != InternetAddressType.IPv4) {
            continue;
          }

          final ip = address.address;

          if (ip.startsWith('169.254.')) continue;

          fallback ??= ip;

          final parts = ip.split('.');

          if (parts.length == 4) {
            final first = int.tryParse(parts[0]) ?? -1;
            final second = int.tryParse(parts[1]) ?? -1;

            if (first == 10 ||
                (first == 172 && second >= 16 && second <= 31) ||
                (first == 192 && second == 168)) {
              return ip;
            }
          }
        }
      }

      return fallback;
    } catch (error) {
      debugPrint('Could not get local IP: $error');
      return null;
    }
  }

  Future<void> _initializeConnection() async {
    if (_loading || _disposed) return;

    setState(() {
      _loading = true;
      _status = 'Preparing file transfer connection...';
    });

    try {
      final port = await _service.startReceiver();
      final ip = await _getLocalIp();

      if (!mounted || _disposed) return;

      if (ip == null ||
          _service.sessionToken == null ||
          _service.tcpPort == null) {
        setState(() {
          _status =
              'No network connection found. Enable Wi-Fi or a hotspot.';
        });
        return;
      }

      setState(() {
        _localIp = ip;
        _localPort = port;
        _status = 'Ready to connect. Waiting for the other device.';
      });

      if (_isSender) {
        await _showMyQr();
      } else {
        await _scanQr();
      }
    } catch (error, stackTrace) {
      debugPrint('Connection initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted && !_disposed) {
        setState(() {
          _status = 'Could not prepare the connection. Please try again.';
        });

        _message('Connection startup failed: $error');
      }
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _showMyQr() async {
    if (_disposed || !mounted || _showingQr) return;

    final token = _localToken;
    final port = _service.port;
    final tcpPort = _service.tcpPort;
    final ip = await _getLocalIp();

    if (!mounted || _disposed) return;

    if (!_service.isServerRunning ||
        token == null ||
        port == null ||
        tcpPort == null ||
        ip == null) {
      setState(() {
        _status =
            'QR code is not ready. Check your Wi-Fi or hotspot connection.';
      });

      _message('Please enable a network connection first.');
      return;
    }

    setState(() {
      _localIp = ip;
      _localPort = port;
      _showingQr = true;
      _status = 'Waiting for the other device to scan the QR code...';
    });

    _startPairingMonitor();

    try {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => QrScreen(
            ipAddress: ip,
            port: port,
            tcpPort: tcpPort,
            token: token,
            mode: _transferMode,
          ),
        ),
      );
    } finally {
      _connectionPollTimer?.cancel();
      _connectionPollTimer = null;
      _showingQr = false;
    }
  }

  void _startPairingMonitor() {
    _connectionPollTimer?.cancel();

    _connectionPollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) {
        if (!mounted || _disposed || !_service.isPaired) return;

        final peer = _service.pairedPeer;

        if (peer == null) return;

        final ip = peer['ip'];
        final port = peer['port'];
        final tcpPort = peer['tcpPort'];
        final token = peer['token'];
        final mode = peer['mode'];

        if (ip is! String ||
            port is! int ||
            tcpPort is! int ||
            token is! String ||
            mode is! String) {
          return;
        }

        _connectionPollTimer?.cancel();
        _connectionPollTimer = null;

        setState(() {
          _connected = true;
          _peerIp = ip;
          _peerUrl = 'http://$ip:$port';
          _peerToken = token;
          _peerTcpPort = tcpPort;
          _transferMode = mode;
          _status = 'Connection Successful';
        });

        _message('Connection Successful');

        if (_showingQr && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
    );
  }

  Future<void> _scanQr() async {
    if (_openingScanner || _disposed || !mounted) return;

    _openingScanner = true;

    try {
      final result = await Navigator.push<Map<String, dynamic>>(
        context,
        MaterialPageRoute<Map<String, dynamic>>(
          builder: (_) => const ScanQrScreen(),
        ),
      );

      if (!mounted || _disposed || result == null) return;

      await _connectToPeer(result);
    } catch (error, stackTrace) {
      debugPrint('QR scanner failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted && !_disposed) {
        _message('Could not open the QR scanner.');
      }
    } finally {
      _openingScanner = false;
    }
  }

  Future<void> _connectToPeer(
    Map<String, dynamic> result,
  ) async {
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
        (modeValue != TransferService.standardMode &&
            modeValue != TransferService.highSpeedMode)) {
      _message(
        'This QR code is invalid or does not belong to MAFX SHARE.',
      );
      return;
    }

    final ip = ipValue.trim();
    final token = tokenValue.trim();
    final peerUrl = 'http://$ip:$portValue';
    final mode = modeValue as String;

    setState(() {
      _loading = true;
      _connected = false;
      _status = 'Verifying connection to $ip...';
    });

    try {
      final connected = await _service.connectToReceiver(
        receiverUrl: peerUrl,
        token: token,
        mode: mode,
      );

      if (!mounted || _disposed) return;

      if (!connected) {
        setState(() {
          _connected = false;
          _status = 'Connection verification failed.';
        });

        _message(
          'Could not connect. Make sure both devices use the same '
          'Wi-Fi network or hotspot, then scan the QR code again.',
        );
        return;
      }

      final localIp = await _getLocalIp();
      final localPort = _service.port;
      final localTcpPort = _service.tcpPort;
      final localToken = _service.sessionToken;

      if (localIp == null ||
          localPort == null ||
          localTcpPort == null ||
          localToken == null) {
        setState(() {
          _status = 'Could not retrieve this device connection details.';
        });

        _message('Pairing could not be completed. Please try again.');
        return;
      }

      final paired = await _service.announcePairing(
        receiverUrl: peerUrl,
        receiverToken: token,
        mode: mode,
        peerIp: localIp,
        peerPort: localPort,
        peerTcpPort: localTcpPort,
        peerToken: localToken,
      );

      if (!mounted || _disposed) return;

      if (!paired) {
        setState(() {
          _connected = false;
          _status = 'QR verified, but pairing could not be completed.';
        });

        _message(
          'Pairing failed. Check your Wi-Fi connection and try again.',
        );
        return;
      }

      setState(() {
        _connected = true;
        _localIp = localIp;
        _localPort = localPort;
        _peerIp = ip;
        _peerUrl = peerUrl;
        _peerToken = token;
        _peerTcpPort = tcpPortValue;
        _transferMode = mode;
        _status = 'Connection Successful';
      });

      _message('Connection Successful');
    } catch (error, stackTrace) {
      debugPrint('Peer connection failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted || _disposed) return;

      setState(() {
        _connected = false;
        _status = 'Connection failed.';
      });

      _message('Could not connect. Please try again.');
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _chooseFiles() async {
    if (!_connected ||
        _peerIp == null ||
        _peerUrl == null ||
        _peerToken == null) {
      _message('Connect the devices before selecting files.');
      return;
    }

    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SendScreen(
          receiverUrl: _peerUrl!,
          receiverToken: _peerToken!,
          category: widget.category,
          transferMode: _transferMode,
          receiverTcpPort: _peerTcpPort,
        ),
      ),
    );
  }

  Future<void> _stopReceiver() async {
    if (_loading) return;

    setState(() {
      _loading = true;
      _status = 'Stopping connection...';
    });

    try {
      _connectionPollTimer?.cancel();
      _connectionPollTimer = null;

      await _service.stopReceiver();

      if (!mounted || _disposed) return;

      setState(() {
        _connected = false;
        _localIp = null;
        _localPort = null;
        _peerIp = null;
        _peerUrl = null;
        _peerToken = null;
        _peerTcpPort = null;
        _status = 'Connection stopped.';
      });

      _message('Connection stopped.');
    } catch (error) {
      debugPrint('Stop receiver failed: $error');
      _message('Could not stop the connection.');
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        !_service.isServerRunning &&
        !_loading &&
        !_disposed) {
      unawaited(_initializeConnection());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _connectionPollTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const green = Color(0xFF008D5A);
    const dark = Color(0xFF202024);
    const brightGreen = Color(0xFF00D18B);

    return Scaffold(
      backgroundColor: dark,
      appBar: AppBar(
        backgroundColor: green,
        foregroundColor: Colors.white,
        title: Text(
          _isSender ? 'MAFX SHARE — Send' : 'MAFX SHARE — Receive',
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const SizedBox(height: 12),
            const Icon(
              Icons.devices_rounded,
              size: 78,
              color: brightGreen,
            ),
            const SizedBox(height: 16),
            const Text(
              'Connect Your Devices',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Connect both devices before sending or receiving files.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 15,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 26),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: _connected ? brightGreen : Colors.white12,
                ),
              ),
              child: Column(
                children: [
                  Icon(
                    _connected
                        ? Icons.check_circle_rounded
                        : _loading
                            ? Icons.sync_rounded
                            : Icons.wifi_tethering_rounded,
                    color: _connected ? brightGreen : Colors.white70,
                    size: 42,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _connected ? brightGreen : Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_localIp != null && _localPort != null) ...[
                    const SizedBox(height: 12),
                    SelectableText(
                      'This device: $_localIp:$_localPort',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                  ],
                  if (_peerIp != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Connected to: $_peerIp',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            if (_connected)
              SizedBox(
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: _loading ? null : _chooseFiles,
                  icon: const Icon(Icons.folder_open_rounded),
                  label: const Text(
                    'Select Files',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: brightGreen,
                    foregroundColor: Colors.black,
                  ),
                ),
              ),
            if (_connected) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 50,
                child: OutlinedButton.icon(
                  onPressed: _loading ? null : _stopReceiver,
                  icon: const Icon(Icons.link_off_rounded),
                  label: const Text('Disconnect'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.redAccent,
                    side: const BorderSide(color: Colors.redAccent),
                  ),
                ),
              ),
            ],
            if (!_connected && _loading) ...[
              const SizedBox(height: 18),
              const Center(
                child: CircularProgressIndicator(
                  color: brightGreen,
                ),
              ),
            ],
            if (!_connected && !_loading) ...[
              const SizedBox(height: 18),
              OutlinedButton.icon(
                onPressed: _initializeConnection,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Try Again'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: brightGreen,
                  side: const BorderSide(color: brightGreen),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'Both devices must be connected to the same Wi-Fi network '
              'or hotspot. If Android requests network permissions, '
              'allow them and enable Wi-Fi or the hotspot in Settings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white54,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
