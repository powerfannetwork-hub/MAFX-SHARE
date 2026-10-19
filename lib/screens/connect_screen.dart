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

  List<String> _localIps = <String>[];

  Timer? _connectionPollTimer;

  bool get _isSender => widget.role == TransferRole.send;

  String? get _localToken => _service.sessionToken;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addObserver(this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_disposed) {
        unawaited(_initializeConnection());
      }
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

  // ------------------------------------------------------------
  // IP ADDRESS VALIDATION
  // ------------------------------------------------------------

  bool _isValidIpv4(String ip) {
    final address = InternetAddress.tryParse(ip);

    return address != null &&
        address.type == InternetAddressType.IPv4 &&
        !address.isLoopback &&
        !address.isMulticast;
  }

  bool _isPrivateIpv4(String ip) {
    final address = InternetAddress.tryParse(ip);

    if (address == null ||
        address.type != InternetAddressType.IPv4) {
      return false;
    }

    final parts = ip.split('.');

    if (parts.length != 4) return false;

    final octets = parts.map(int.tryParse).toList();

    if (octets.any((value) => value == null)) {
      return false;
    }

    final first = octets[0]!;
    final second = octets[1]!;

    return first == 10 ||
        (first == 172 && second >= 16 && second <= 31) ||
        (first == 192 && second == 168);
  }

  // ------------------------------------------------------------
  // NETWORK INTERFACE CLASSIFICATION
  // ------------------------------------------------------------

  bool _isClearlyMobileOrVpnInterface(String interfaceName) {
    final name = interfaceName.toLowerCase();

    return name.contains('rmnet') ||
        name.contains('cell') ||
        name.contains('mobile') ||
        name.contains('tun') ||
        name.contains('vpn') ||
        name.contains('ppp') ||
        name.contains('clat') ||
        name.contains('ccmni') ||
        name.contains('wwan');
  }

  bool _isWifiOrHotspotInterface(String interfaceName) {
    final name = interfaceName.toLowerCase();

    return name.contains('wlan') ||
        name.contains('wifi') ||
        name.contains('swlan') ||
        name.contains('softap') ||
        name.contains('ap0') ||
        name.contains('p2p') ||
        name.contains('bridge') ||
        name.startsWith('br');
  }

  int _interfacePriority(String interfaceName) {
    final name = interfaceName.toLowerCase();

    // Ordinary Wi-Fi interfaces are usually the best candidates.
    if (name.contains('wlan') || name.contains('wifi')) {
      return 300;
    }

    // Common Android hotspot interfaces.
    if (name.contains('softap') ||
        name.contains('swlan') ||
        name.contains('ap0')) {
      return 250;
    }

    // Wi-Fi Direct and bridge interfaces can also be useful.
    if (name.contains('p2p') ||
        name.contains('bridge') ||
        name.startsWith('br')) {
      return 200;
    }

    // Unknown interfaces are retained as lower-priority candidates.
    return 100;
  }

  // ------------------------------------------------------------
  // DISCOVER LOCAL WI-FI / HOTSPOT IP ADDRESSES
  // ------------------------------------------------------------

  Future<List<String>> _getLocalIps() async {
    try {
      final interfaces = await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      );

      final candidates = <MapEntry<int, String>>[];

      for (final interface in interfaces) {
        final interfaceName = interface.name;

        // Do not advertise addresses belonging to known mobile/VPN
        // interfaces. Unknown interface names are not rejected
        // automatically because Android manufacturers use different
        // names for Wi-Fi and hotspot interfaces.
        if (_isClearlyMobileOrVpnInterface(interfaceName)) {
          debugPrint(
            'MAFX SHARE skipped non-Wi-Fi interface: '
            '$interfaceName',
          );
          continue;
        }

        final recognizedWifi =
            _isWifiOrHotspotInterface(interfaceName);

        for (final address in interface.addresses) {
          final ip = address.address;

          if (address.isLoopback ||
              address.type != InternetAddressType.IPv4 ||
              ip.startsWith('169.254.') ||
              !_isPrivateIpv4(ip)) {
            continue;
          }

          var score = _interfacePriority(interfaceName);

          if (recognizedWifi) {
            score += 100;
          }

          candidates.add(MapEntry(score, ip));

          debugPrint(
            'MAFX SHARE IP candidate: '
            'interface=$interfaceName, '
            'ip=$ip, '
            'priority=$score',
          );
        }
      }

      // Put likely Wi-Fi/hotspot addresses first, while retaining
      // other private IPv4 candidates as fallbacks.
      candidates.sort(
        (a, b) => b.key.compareTo(a.key),
      );

      final result = <String>[];

      for (final candidate in candidates) {
        if (!result.contains(candidate.value)) {
          result.add(candidate.value);
        }
      }

      debugPrint('MAFX SHARE discovered private IPv4 addresses: $result');

      return result;
    } catch (error, stackTrace) {
      debugPrint('Could not discover local IP addresses: $error');
      debugPrintStack(stackTrace: stackTrace);

      return <String>[];
    }
  }

  // Select the local address that appears to share the same /24
  // subnet as the peer. If no match is found, use the highest-ranked
  // available local address.
  String? _getLocalIpForPeer(
    List<String> localIps,
    String peerIp,
  ) {
    if (localIps.isEmpty) return null;

    final peerParts = peerIp.split('.');

    if (peerParts.length == 4) {
      for (final localIp in localIps) {
        final localParts = localIp.split('.');

        if (localParts.length == 4 &&
            localParts[0] == peerParts[0] &&
            localParts[1] == peerParts[1] &&
            localParts[2] == peerParts[2]) {
          return localIp;
        }
      }
    }

    return localIps.first;
  }

  // ------------------------------------------------------------
  // INITIALIZE CONNECTION
  // ------------------------------------------------------------

  Future<void> _initializeConnection() async {
    if (_loading || _disposed || !mounted) return;

    setState(() {
      _loading = true;
      _connected = false;
      _status = 'Preparing file transfer connection...';
    });

    try {
      await _service.startReceiver();

      final port = _service.port;
      final tcpPort = _service.tcpPort;
      final token = _service.sessionToken;
      final ips = await _getLocalIps();

      if (!mounted || _disposed) return;

      if (port == null ||
          tcpPort == null ||
          token == null ||
          ips.isEmpty) {
        setState(() {
          _localIps = ips;
          _localIp = ips.isNotEmpty ? ips.first : null;
          _localPort = port;
          _status = ips.isEmpty
              ? 'No usable private IPv4 address found. '
                  'Enable Wi-Fi or a phone hotspot, then try again.'
              : 'The receiver could not be prepared. Please try again.';
        });

        return;
      }

      setState(() {
        _localIps = ips;
        _localIp = ips.first;
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

  // ------------------------------------------------------------
  // SHOW QR CODE ON SENDER DEVICE
  // ------------------------------------------------------------

  Future<void> _showMyQr() async {
    if (_disposed || !mounted || _showingQr) return;

    final token = _localToken;
    final port = _service.port;
    final tcpPort = _service.tcpPort;
    final ips = await _getLocalIps();

    if (!mounted || _disposed) return;

    if (!_service.isServerRunning ||
        token == null ||
        port == null ||
        tcpPort == null ||
        ips.isEmpty) {
      setState(() {
        _status =
            'QR code is not ready. Check your Wi-Fi or hotspot connection.';
      });

      _message(
        'Please enable Wi-Fi or a phone hotspot before continuing.',
      );

      return;
    }

    final ip = ips.first;

    setState(() {
      _localIps = ips;
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
            ipAddresses: ips,
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

  // ------------------------------------------------------------
  // WATCH FOR PAIRING ON THE QR-HOSTING DEVICE
  // ------------------------------------------------------------

  void _startPairingMonitor() {
    _connectionPollTimer?.cancel();

    _connectionPollTimer = Timer.periodic(
      const Duration(milliseconds: 500),
      (_) {
        if (!mounted || _disposed || !_service.isPaired) {
          return;
        }

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
          debugPrint('Pairing data is incomplete: $peer');
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

  // ------------------------------------------------------------
  // SCAN QR CODE ON RECEIVING DEVICE
  // ------------------------------------------------------------

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

  // ------------------------------------------------------------
  // VERIFY QR AND CONNECT TO PEER
  // ------------------------------------------------------------

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

    final token = tokenValue.trim();
    final mode = modeValue as String;

    // Accept both newer QR codes containing "ips" and older QR codes
    // containing only "ip".
    final peerIps = <String>[];

    final rawIps = result['ips'];

    if (rawIps is List) {
      for (final value in rawIps) {
        if (value is! String) continue;

        final candidate = value.trim();

        if (_isValidIpv4(candidate) &&
            _isPrivateIpv4(candidate) &&
            !peerIps.contains(candidate)) {
          peerIps.add(candidate);
        }
      }
    }

    final originalIp = ipValue.trim();

    if (_isValidIpv4(originalIp) &&
        _isPrivateIpv4(originalIp) &&
        !peerIps.contains(originalIp)) {
      peerIps.insert(0, originalIp);
    }

    if (peerIps.isEmpty) {
      _message(
        'The QR code does not contain a usable private Wi-Fi/hotspot IP.',
      );

      return;
    }

    setState(() {
      _loading = true;
      _connected = false;
      _status = 'Searching for the other device...';
    });

    try {
      String? connectedIp;
      String? connectedPeerUrl;

      // Try every advertised IP until the HTTP receiver responds
      // and validates the session token and transfer mode.
      for (final candidateIp in peerIps) {
        if (!mounted || _disposed) return;

        final candidateUrl = 'http://$candidateIp:$portValue';

        setState(() {
          _status = 'Trying connection to $candidateIp...';
        });

        debugPrint('MAFX SHARE trying peer address: $candidateUrl');

        final connected = await _service.connectToReceiver(
          receiverUrl: candidateUrl,
          token: token,
          mode: mode,
        );

        if (connected) {
          connectedIp = candidateIp;
          connectedPeerUrl = candidateUrl;
          break;
        }
      }

      if (!mounted || _disposed) return;

      if (connectedIp == null || connectedPeerUrl == null) {
        setState(() {
          _connected = false;
          _status = 'Connection verification failed.';
        });

        _message(
          'Could not connect. Make sure both devices use the same '
          'Wi-Fi network or hotspot and try scanning again.',
        );

        return;
      }

      // Find this phone's address for the return pairing connection.
      final ips = await _getLocalIps();

      final localIp = _getLocalIpForPeer(
        ips,
        connectedIp,
      );

      final localPort = _service.port;
      final localTcpPort = _service.tcpPort;
      final localToken = _service.sessionToken;

      if (localIp == null ||
          localPort == null ||
          localTcpPort == null ||
          localToken == null) {
        setState(() {
          _status =
              'Could not retrieve this device connection details.';
        });

        _message(
          'Pairing could not be completed. Check Wi-Fi or hotspot.',
        );

        return;
      }

      final paired = await _service.announcePairing(
        receiverUrl: connectedPeerUrl,
        receiverToken: token,
        mode: mode,
        peerIp: localIp,
        peerPort: localPort,
        peerTcpPort: localTcpPort,
        peerToken: localToken,
        receiverTcpPort: tcpPortValue,
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
        _localIps = ips;
        _localIp = localIp;
        _localPort = localPort;
        _connected = true;
        _peerIp = connectedIp;
        _peerUrl = connectedPeerUrl;
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

  // ------------------------------------------------------------
  // OPEN FILE SENDER
  // ------------------------------------------------------------

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

  // ------------------------------------------------------------
  // DISCONNECT
  // ------------------------------------------------------------

  Future<void> _stopReceiver() async {
    if (_loading || _disposed) return;

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
        _localIps = <String>[];
        _localPort = null;
        _peerIp = null;
        _peerUrl = null;
        _peerToken = null;
        _peerTcpPort = null;
        _transferMode = TransferService.standardMode;
        _status = 'Connection stopped.';
      });

      _message('Connection stopped.');
    } catch (error, stackTrace) {
      debugPrint('Stop receiver failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (mounted && !_disposed) {
        _message('Could not stop the connection.');
      }
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  // ------------------------------------------------------------
  // APP LIFECYCLE
  // ------------------------------------------------------------

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
    _connectionPollTimer = null;

    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  // ------------------------------------------------------------
  // USER INTERFACE
  // ------------------------------------------------------------

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
                  if (_localIps.length > 1) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Available Wi-Fi/hotspot addresses:',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    ..._localIps.map(
                      (ip) => SelectableText(
                        ip,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                        ),
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
                    side: const BorderSide(
                      color: Colors.redAccent,
                    ),
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
                  side: const BorderSide(
                    color: brightGreen,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 18),
            const Text(
              'Both devices must use the same Wi-Fi network or phone '
              'hotspot. If Android requests network permissions, allow '
              'them. Some hotspots prevent connected devices from '
              'communicating with each other.',
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
