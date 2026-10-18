import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Discovers MAFX SHARE devices on the same local network using UDP.
class DeviceDiscoveryService {
  DeviceDiscoveryService({
    this.discoveryPort = 45872,
    this.discoveryInterval = const Duration(seconds: 3),
  });

  final int discoveryPort;
  final Duration discoveryInterval;

  RawDatagramSocket? _socket;
  Timer? _discoveryTimer;

  bool _running = false;
  String? _deviceName;
  String? _sessionToken;
  int? _httpPort;
  int? _tcpPort;

  final StreamController<Map<String, dynamic>> _devicesController =
      StreamController<Map<String, dynamic>>.broadcast();

  final Map<String, DateTime> _lastSeen = {};

  /// Stream of discovered MAFX SHARE devices.
  Stream<Map<String, dynamic>> get devices => _devicesController.stream;

  bool get isRunning => _running;

  /// Starts listening for nearby MAFX SHARE devices.
  Future<void> startListening({
    required String deviceName,
    required String sessionToken,
    required int httpPort,
    required int tcpPort,
  }) async {
    if (_running) return;

    if (deviceName.trim().isEmpty || sessionToken.trim().isEmpty) {
      throw ArgumentError('Device name and session token are required.');
    }

    if (httpPort < 1 ||
        httpPort > 65535 ||
        tcpPort < 1 ||
        tcpPort > 65535) {
      throw ArgumentError('Invalid receiver port.');
    }

    _deviceName = deviceName.trim();
    _sessionToken = sessionToken;
    _httpPort = httpPort;
    _tcpPort = tcpPort;

    final socket = await RawDatagramSocket.bind(
      InternetAddress.anyIPv4,
      discoveryPort,
      reuseAddress: true,
      reusePort: false,
    );

    _socket = socket;
    socket.broadcastEnabled = true;
    _running = true;

    socket.listen(
      _handleSocketEvent,
      onError: (Object error, StackTrace stackTrace) {
        stderr.writeln('MAFX discovery socket error: $error');
      },
      onDone: () {
        _running = false;
      },
      cancelOnError: false,
    );

    _discoveryTimer = Timer.periodic(
      discoveryInterval,
      (_) => _broadcastPresence(),
    );

    await _broadcastPresence();
  }

  /// Sends a UDP announcement to devices on the local network.
  Future<void> _broadcastPresence() async {
    final socket = _socket;

    if (!_running || socket == null) return;

    final message = <String, dynamic>{
      'app': 'MAFX_SHARE',
      'version': 1,
      'type': 'DISCOVER',
      'deviceName': _deviceName,
      'httpPort': _httpPort,
      'tcpPort': _tcpPort,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    final bytes = utf8.encode(jsonEncode(message));

    try {
      socket.send(
        bytes,
        InternetAddress('255.255.255.255'),
        discoveryPort,
      );
    } catch (error) {
      stderr.writeln('MAFX discovery broadcast failed: $error');
    }
  }

  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final socket = _socket;
    if (socket == null) return;

    Datagram? datagram;

    while ((datagram = socket.receive()) != null) {
      final packet = datagram!;
      _processDatagram(packet);
    }
  }

  void _processDatagram(Datagram datagram) {
    try {
      final decoded = jsonDecode(utf8.decode(datagram.data));

      if (decoded is! Map<String, dynamic>) return;
      if (decoded['app'] != 'MAFX_SHARE') return;
      if (decoded['version'] != 1) return;
      if (decoded['type'] != 'DISCOVER') return;

      final senderIp = datagram.address.address;
      final deviceName = decoded['deviceName'];
      final httpPort = decoded['httpPort'];
      final tcpPort = decoded['tcpPort'];

      if (deviceName is! String ||
          deviceName.trim().isEmpty ||
          httpPort is! int ||
          tcpPort is! int ||
          httpPort < 1 ||
          httpPort > 65535 ||
          tcpPort < 1 ||
          tcpPort > 65535) {
        return;
      }

      // Ignore our own discovery announcement.
      if (httpPort == _httpPort &&
          tcpPort == _tcpPort &&
          decoded['deviceName'] == _deviceName) {
        return;
      }

      final deviceKey = '$senderIp:$httpPort';
      _lastSeen[deviceKey] = DateTime.now();

      _devicesController.add({
        'app': 'MAFX_SHARE',
        'version': 1,
        'ip': senderIp,
        'deviceName': deviceName,
        'httpPort': httpPort,
        'tcpPort': tcpPort,
        'lastSeen': DateTime.now(),
      });
    } catch (error) {
      stderr.writeln('Ignoring invalid MAFX discovery packet: $error');
    }
  }

  /// Returns the latest time a device was discovered.
  DateTime? lastSeenAt(String ip, int port) {
    return _lastSeen['$ip:$port'];
  }

  /// Stops UDP discovery and releases the socket.
  Future<void> stop() async {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;

    _running = false;

    _socket?.close();
    _socket = null;

    _deviceName = null;
    _sessionToken = null;
    _httpPort = null;
    _tcpPort = null;

    _lastSeen.clear();
  }

  /// Releases all resources owned by this service.
  Future<void> dispose() async {
    await stop();
    await _devicesController.close();
  }
}
