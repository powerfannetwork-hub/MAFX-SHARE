import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Discovers MAFX SHARE devices connected to the same local network.
class DeviceDiscoveryService {
  DeviceDiscoveryService({
    this.discoveryPort = 45872,
    this.discoveryInterval = const Duration(seconds: 3),
    this.deviceTimeout = const Duration(seconds: 12),
  })  : assert(discoveryPort > 0 && discoveryPort <= 65535),
        assert(discoveryInterval > Duration.zero),
        assert(deviceTimeout > Duration.zero);

  final int discoveryPort;
  final Duration discoveryInterval;
  final Duration deviceTimeout;

  RawDatagramSocket? _socket;
  Timer? _discoveryTimer;
  Timer? _cleanupTimer;

  bool _running = false;
  bool _disposed = false;

  String? _deviceName;
  int? _httpPort;
  int? _tcpPort;

  final StreamController<Map<String, dynamic>> _devicesController =
      StreamController<Map<String, dynamic>>.broadcast();

  final Map<String, Map<String, dynamic>> _knownDevices = {};
  final Map<String, DateTime> _lastSeen = {};

  /// Emits devices discovered on the local network.
  Stream<Map<String, dynamic>> get devices => _devicesController.stream;

  /// Returns true when discovery is running.
  bool get isRunning => _running;

  /// Returns the latest list of discovered devices.
  List<Map<String, dynamic>> get discoveredDevices =>
      _knownDevices.values
          .map((device) => Map<String, dynamic>.from(device))
          .toList(growable: false);

  /// Starts listening for nearby MAFX SHARE devices.
  Future<void> startListening({
    required String deviceName,
    required String sessionToken,
    required int httpPort,
    required int tcpPort,
  }) async {
    if (_disposed) {
      throw StateError('DeviceDiscoveryService has been disposed.');
    }

    if (_running) return;

    final name = deviceName.trim();
    final token = sessionToken.trim();

    if (name.isEmpty || token.isEmpty) {
      throw ArgumentError(
        'Device name and session token are required.',
      );
    }

    _validatePort(httpPort, 'httpPort');
    _validatePort(tcpPort, 'tcpPort');

    _deviceName = name;
    _httpPort = httpPort;
    _tcpPort = tcpPort;

    RawDatagramSocket? socket;

    try {
      socket = await RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        discoveryPort,
        reuseAddress: true,
        reusePort: false,
      );

      if (_disposed) {
        socket.close();
        throw StateError('DeviceDiscoveryService has been disposed.');
      }

      socket.broadcastEnabled = true;
      _socket = socket;
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

      _cleanupTimer = Timer.periodic(
        const Duration(seconds: 3),
        (_) => _removeExpiredDevices(),
      );

      await _broadcastPresence();
    } catch (_) {
      _discoveryTimer?.cancel();
      _discoveryTimer = null;

      _cleanupTimer?.cancel();
      _cleanupTimer = null;

      _running = false;

      if (identical(_socket, socket)) {
        _socket = null;
      }

      socket?.close();

      _deviceName = null;
      _httpPort = null;
      _tcpPort = null;

      rethrow;
    }
  }

  /// Validates a TCP or HTTP port.
  void _validatePort(int port, String fieldName) {
    if (port < 1 || port > 65535) {
      throw ArgumentError.value(
        port,
        fieldName,
        'Port must be between 1 and 65535.',
      );
    }
  }

  /// Announces this device to other devices on the local network.
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

  /// Handles incoming UDP events.
  void _handleSocketEvent(RawSocketEvent event) {
    if (event != RawSocketEvent.read) return;

    final socket = _socket;
    if (socket == null || !_running) return;

    Datagram? datagram;

    while ((datagram = socket.receive()) != null) {
      _processDatagram(datagram!);
    }
  }

  /// Processes an announcement from another MAFX SHARE device.
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

      // Ignore this device's own announcement.
      if (httpPort == _httpPort &&
          tcpPort == _tcpPort &&
          deviceName.trim() == _deviceName) {
        return;
      }

      final key = '$senderIp:$httpPort';
      final now = DateTime.now();

      final device = <String, dynamic>{
        'app': 'MAFX_SHARE',
        'version': 1,
        'ip': senderIp,
        'deviceName': deviceName.trim(),
        'httpPort': httpPort,
        'tcpPort': tcpPort,
        'lastSeen': now,
      };

      _lastSeen[key] = now;
      _knownDevices[key] = device;

      if (!_devicesController.isClosed) {
        _devicesController.add(
          Map<String, dynamic>.from(device),
        );
      }
    } catch (error) {
      stderr.writeln('Ignoring invalid MAFX discovery packet: $error');
    }
  }

  /// Removes devices that have stopped announcing their presence.
  void _removeExpiredDevices() {
    final now = DateTime.now();
    final expiredKeys = <String>[];

    for (final entry in _lastSeen.entries) {
      if (now.difference(entry.value) > deviceTimeout) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      _lastSeen.remove(key);

      final removed = _knownDevices.remove(key);

      if (removed != null && !_devicesController.isClosed) {
        _devicesController.add({
          ...removed,
          'unavailable': true,
        });
      }
    }
  }

  /// Returns the last time a device was discovered.
  DateTime? lastSeenAt(String ip, int port) {
    return _lastSeen['$ip:$port'];
  }

  /// Stops discovery and releases its network resources.
  Future<void> stop() async {
    _discoveryTimer?.cancel();
    _discoveryTimer = null;

    _cleanupTimer?.cancel();
    _cleanupTimer = null;

    _running = false;

    final socket = _socket;
    _socket = null;
    socket?.close();

    _deviceName = null;
    _httpPort = null;
    _tcpPort = null;

    _lastSeen.clear();
    _knownDevices.clear();
  }

  /// Disposes this service permanently.
  Future<void> dispose() async {
    if (_disposed) return;

    await stop();
    _disposed = true;

    await _devicesController.close();
  }
}
