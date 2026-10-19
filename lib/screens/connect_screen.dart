import 'dart:async';
import 'dart:convert';
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

String _status = 'Ana shirya haɗin wayoyi...';
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
            (first == 172 &&
                second >= 16 &&
                second <= 31) ||
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
  _status = 'Ana kunna hanyar haɗin fayiloli...';
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
          'Ba a samu hanyar sadarwa ba. Kunna Wi-Fi ko hotspot.';
    });
    return;
  }

  setState(() {
    _localIp = ip;
    _localPort = port;
    _status = 'An shirya haɗin. Ana jiran ɗayan wayar.';
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
      _status = 'An kasa shirya haɗin. Gwada sake farawa.';
    });

    _message('Kuskuren fara haɗin: $error');
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
    _status = 'Ba a shirya QR ba. Duba Wi-Fi ko hotspot.';
  });

  _message('Da fatan za a kunna haɗin wayar tukuna.');
  return;
}

setState(() {
  _localIp = ip;
  _localPort = port;
  _showingQr = true;
});

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
  _showingQr = false;
}

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
    _message('An samu matsala wajen buɗe scanner.');
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
  _message('QR code ɗin ba na MAFX SHARE ba ne ko bai cika ba.');
  return;
}

final ip = ipValue.trim();
final token = tokenValue.trim();
final peerUrl = 'http://$ip:$portValue';
final mode = modeValue as String;

setState(() {
  _loading = true;
  _connected = false;
  _status = 'Ana tabbatar da haɗi da $ip...';
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
      _status = 'An kasa tabbatar da haɗin.';
    });

    _message(
      'An kasa haɗuwa. Tabbatar wayoyin suna kan Wi-Fi '
      'ko hotspot ɗaya, sannan ka sake scan QR.',
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
    _status = 'Connection Successful';
  });

  _message('Connection Successful');

  // Wannan wayar yanzu tana iya aikawa zuwa wayar da aka scan.
  // Wayar da ta nuna QR za ta iya karɓar fayiloli.
} catch (error, stackTrace) {
  debugPrint('Peer connection failed: $error');
  debugPrintStack(stackTrace: stackTrace);

  if (!mounted || _disposed) return;

  setState(() {
    _connected = false;
    _status = 'Haɗin ya gaza.';
  });

  _message('An kasa haɗuwa. Sake gwadawa.');
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
_message('Ka fara haɗa wayoyin kafin zaɓar fayiloli.');
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

void _selectTransferMode(String? mode) {
if (mode == null ||
(mode != TransferService.standardMode &&
mode != TransferService.highSpeedMode)) {
return;
}

setState(() {
  _transferMode = mode;
  _status = mode == TransferService.highSpeedMode
      ? 'An zaɓi 5G Mode.'
      : 'An zaɓi Standard Mode.';
});

}

Future<void> _stopReceiver() async {
if (_loading) return;

setState(() {
  _loading = true;
  _status = 'Ana dakatar da haɗin...';
});

try {
  await _service.stopReceiver();

  if (!mounted || _disposed) return;

  _connectionPollTimer?.cancel();

  setState(() {
    _connected = false;
    _localIp = null;
    _localPort = null;
    _peerIp = null;
    _peerUrl = null;
    _peerToken = null;
    _peerTcpPort = null;
    _status = 'An dakatar da haɗin.';
  });

  _message('An dakatar da haɗin.');
} catch (error) {
  debugPrint('Stop receiver failed: $error');
  _message('An kasa dakatar da haɗin.');
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
      _isSender
          ? 'MAFX SHARE — Send'
          : 'MAFX SHARE — Receive',
    ),
    actions: [
      IconButton(
        tooltip: 'Nuna QR code na wannan waya',
        onPressed: _loading ? null : _showMyQr,
        icon: const Icon(Icons.qr_code_2_rounded),
      ),
      IconButton(
        tooltip: 'Scan QR code',
        onPressed: _loading ? null : _scanQr,
        icon: const Icon(Icons.qr_code_scanner_rounded),
      ),
    ],
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
          'Haɗa wayoyi biyu kafin aikawa ko karɓar fayiloli. '
          'Wayoyin biyu za su iya aikawa da karɓa idan '
          'kowannensu ya haɗu da ɗayan.',
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
                  'Wannan waya: $_localIp:$_localPort',
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
                  'An haɗa da: $_peerIp',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Text(
          'Transfer Mode',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _transferMode,
          dropdownColor: dark,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white.withValues(alpha: 0.06),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          items: const [
            DropdownMenuItem(
              value: TransferService.standardMode,
              child: Text('Standard Mode'),
            ),
            DropdownMenuItem(
              value: TransferService.highSpeedMode,
              child: Text('5G Mode'),
            ),
          ],
          onChanged: _connected ? null : _selectTransferMode,
        ),
        const SizedBox(height: 24),
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
              backgroundColor:
                  _connected ? brightGreen : Colors.white24,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _loading ? null : _showMyQr,
            icon: const Icon(Icons.qr_code_2_rounded),
            label: const Text('Show My QR Code'),
            style: OutlinedButton.styleFrom(
              foregroundColor: brightGreen,
              side: const BorderSide(color: brightGreen),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _loading ? null : _scanQr,
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Scan Other Phone'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white30),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 50,
          child: OutlinedButton.icon(
            onPressed: _loading ? null : _stopReceiver,
            icon: const Icon(Icons.stop_circle_outlined),
            label: const Text('Stop Connection'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.redAccent,
              side: const BorderSide(color: Colors.redAccent),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    ),
  ),
);

}
}
