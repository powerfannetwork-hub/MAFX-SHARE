import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrScreen extends StatefulWidget {
  final String ipAddress;
  final int port;
  final int tcpPort;
  final String token;
  final String mode;

  const QrScreen({
    super.key,
    required this.ipAddress,
    required this.port,
    required this.tcpPort,
    required this.token,
    this.mode = 'STANDARD',
  });

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  late bool _highSpeedMode;

  static const Color _green = Color(0xFF00D18B);
  static const Color _background = Color(0xFF101820);
  static const Color _card = Color(0xFF192832);

  @override
  void initState() {
    super.initState();
    _highSpeedMode = widget.mode == '5G_PLUS';
  }

  String get _currentMode =>
      _highSpeedMode ? '5G_PLUS' : 'STANDARD';

  String get _modeLabel =>
      _highSpeedMode ? '5G+ High-Speed Mode' : 'Standard Mode';

  String get _connectionData {
    return jsonEncode({
      'app': 'MAFX_SHARE',
      'version': 1,
      'mode': _currentMode,
      'ip': widget.ipAddress,
      'port': widget.port,
      'tcpPort': widget.tcpPort,
      'token': widget.token,
    });
  }

  void _toggleHighSpeed(bool value) {
    setState(() {
      _highSpeedMode = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final modeColor =
        _highSpeedMode ? Colors.lightBlueAccent : _green;

    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text('Connect Device'),
        backgroundColor: _green,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 12),
              const Icon(
                Icons.devices_rounded,
                size: 58,
                color: _green,
              ),
              const SizedBox(height: 12),
              const Text(
                'MAFX SHARE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 27,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Connect both phones before transferring files.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: _highSpeedMode
                        ? Colors.lightBlueAccent
                        : Colors.white12,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 48,
                          height: 48,
                          decoration: BoxDecoration(
                            color: modeColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            Icons.speed_rounded,
                            color: modeColor,
                            size: 29,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                '5G+ High-Speed Mode',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              SizedBox(height: 5),
                              Text(
                                'Optimized local file transfer',
                                style: TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch.adaptive(
                          value: _highSpeedMode,
                          activeTrackColor:
                              Colors.lightBlueAccent,
                          onChanged: _toggleHighSpeed,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _highSpeedMode
                          ? 'High-speed mode selected. Scan the updated QR code with the sending phone.'
                          : 'Standard transfer mode selected.',
                      style: TextStyle(
                        color: modeColor,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(
                    color: modeColor,
                    width: 3,
                  ),
                ),
                child: QrImageView(
                  key: ValueKey(_connectionData),
                  data: _connectionData,
                  version: QrVersions.auto,
                  size: 250,
                  backgroundColor: Colors.white,
                  eyeStyle: QrEyeStyle(
                    eyeShape: QrEyeShape.square,
                    color: _highSpeedMode
                        ? Colors.blue
                        : Colors.black,
                  ),
                  dataModuleStyle: QrDataModuleStyle(
                    dataModuleShape: QrDataModuleShape.square,
                    color: _highSpeedMode
                        ? Colors.blue
                        : Colors.black,
                  ),
                ),
              ),

              const SizedBox(height: 20),

              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(15),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.wifi_tethering_rounded,
                      color: modeColor,
                      size: 30,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _modeLabel,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: modeColor,
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Receiver address',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 5),
                    SelectableText(
                      '${widget.ipAddress}:${widget.port}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'High-Speed TCP Port',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      '${widget.tcpPort}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 18),

              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Colors.white60,
                    size: 20,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Keep this screen open. On the other phone, open Send and scan this QR code. Select the same transfer mode on both devices.',
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 22),

              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _green,
                    side: const BorderSide(color: _green),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
