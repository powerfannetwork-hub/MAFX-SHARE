import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrScreen extends StatefulWidget {
  final String ipAddress;
  final List<String> ipAddresses;
  final int port;
  final int tcpPort;
  final String token;
  final String mode;

  const QrScreen({
    super.key,
    required this.ipAddress,
    this.ipAddresses = const [],
    required this.port,
    required this.tcpPort,
    required this.token,
    this.mode = 'STANDARD',
  });

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  static const Color _green = Color(0xFF008D5A);
  static const Color _brightGreen = Color(0xFF00D18B);
  static const Color _dark = Color(0xFF202024);
  static const Color _card = Color(0xFF2B2B30);

  late bool _highSpeedEnabled;

  @override
  void initState() {
    super.initState();
    _highSpeedEnabled = widget.mode == '5G_PLUS';
  }

  String get _mode =>
      _highSpeedEnabled ? '5G_PLUS' : 'STANDARD';

  bool get _isHighSpeed => _highSpeedEnabled;

  /// Returns the available IP addresses without duplicates.
  ///
  /// The original [ipAddress] is retained for compatibility
  /// with older versions of the app.
  List<String> get _availableIpAddresses {
    final addresses = <String>[];

    for (final address in [
      widget.ipAddress,
      ...widget.ipAddresses,
    ]) {
      final ip = address.trim();

      if (ip.isNotEmpty && !addresses.contains(ip)) {
        addresses.add(ip);
      }
    }

    return addresses;
  }

  String get _qrData {
    final addresses = _availableIpAddresses;

    final payload = <String, dynamic>{
      'app': 'MAFX_SHARE',
      'version': 1,

      // Backward compatibility with older app versions.
      'ip': widget.ipAddress,

      // New field allows the scanning device to try
      // multiple Wi-Fi or hotspot IP addresses.
      'ips': addresses,

      'port': widget.port,
      'tcpPort': widget.tcpPort,
      'token': widget.token,
      'mode': _mode,
    };

    return jsonEncode(payload);
  }

  @override
  Widget build(BuildContext context) {
    final modeColor =
        _isHighSpeed ? Colors.lightBlueAccent : _brightGreen;

    final addresses = _availableIpAddresses;

    return Scaffold(
      backgroundColor: _dark,
      appBar: AppBar(
        backgroundColor: _green,
        foregroundColor: Colors.white,
        title: const Text('Connect'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(22),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          children: [
                            QrImageView(
                              key: ValueKey(_qrData),
                              data: _qrData,
                              version: QrVersions.auto,
                              size: 300,
                              backgroundColor: Colors.white,
                              errorCorrectionLevel:
                                  QrErrorCorrectLevel.M,
                            ),
                            const SizedBox(height: 18),
                            Row(
                              mainAxisAlignment:
                                  MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.wifi_tethering_rounded,
                                  color: _green,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    widget.ipAddress,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _green,
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // Show the additional network addresses
                            // when the device has more than one.
                            if (addresses.length > 1) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'Available network addresses:',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.black54,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 4),
                              ...addresses.map(
                                (address) => Padding(
                                  padding:
                                      const EdgeInsets.symmetric(
                                    vertical: 2,
                                  ),
                                  child: Text(
                                    address,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _green,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],

                            const SizedBox(height: 8),
                            Text(
                              _isHighSpeed
                                  ? 'High-speed connection'
                                  : 'Standard connection',
                              style: TextStyle(
                                color: _isHighSpeed
                                    ? Colors.lightBlueAccent
                                    : _green,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 22),
                      const Text(
                        'Scan this QR code with the other device',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Keep both devices connected to the same '
                        'Wi-Fi network or phone hotspot.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white60,
                          fontSize: 13,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'If connection fails, check that both '
                        'devices are on the same network and '
                        'that the hotspot allows communication '
                        'between connected devices.',
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
              ),
            ),

            // High-speed mode switch.
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 12,
              ),
              decoration: const BoxDecoration(
                color: _card,
                border: Border(
                  top: BorderSide(color: Colors.white24),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.rocket_launch_rounded,
                    color: modeColor,
                    size: 26,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'High-speed Mode',
                      style: TextStyle(
                        color: modeColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Switch(
                    value: _highSpeedEnabled,
                    activeColor: Colors.lightBlueAccent,
                    onChanged: (enabled) {
                      setState(() {
                        _highSpeedEnabled = enabled;
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
