import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

enum TransferMode {
  standard,
  highSpeed,
}

class QrScreen extends StatefulWidget {
  final TransferMode initialMode;

  const QrScreen({
    super.key,
    this.initialMode = TransferMode.standard,
  });

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  late TransferMode _mode;
  late String _sessionId;

  @override
  void initState() {
    super.initState();
    _mode = widget.initialMode;
    _sessionId = _createSessionId();
  }

  String _createSessionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    );

    return base64UrlEncode(bytes).replaceAll('=', '');
  }

  String get _qrData {
    return jsonEncode({
      'app': 'MAFX_SHARE',
      'version': 1,
      'mode': _mode == TransferMode.highSpeed
          ? '5G_PLUS'
          : 'STANDARD',
      'session': _sessionId,
    });
  }

  Color get _modeColor {
    return _mode == TransferMode.highSpeed
        ? const Color(0xFF00AEEF)
        : Colors.black;
  }

  void _changeMode(TransferMode mode) {
    if (_mode == mode) return;

    setState(() {
      _mode = mode;
      _sessionId = _createSessionId();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isHighSpeed = _mode == TransferMode.highSpeed;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Device'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const Text(
              'Choose Transfer Mode',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Choose the mode suitable for your device.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.blueGrey),
            ),
            const SizedBox(height: 24),

            Row(
              children: [
                Expanded(
                  child: _ModeCard(
                    title: 'Standard',
                    subtitle: 'For older phones',
                    icon: Icons.phone_android_rounded,
                    color: Colors.black,
                    selected: !isHighSpeed,
                    onTap: () =>
                        _changeMode(TransferMode.standard),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ModeCard(
                    title: '5G+',
                    subtitle: 'High-speed mode',
                    icon: Icons.bolt_rounded,
                    color: const Color(0xFF00AEEF),
                    selected: isHighSpeed,
                    onTap: () =>
                        _changeMode(TransferMode.highSpeed),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 30),

            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: _modeColor.withValues(alpha: 0.25),
                  width: 2,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    isHighSpeed
                        ? 'MAFX SHARE 5G+'
                        : 'MAFX SHARE STANDARD',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: _modeColor,
                    ),
                  ),
                  const SizedBox(height: 20),

                  QrImageView(
                    data: _qrData,
                    version: QrVersions.auto,
                    size: 240,
                    backgroundColor: Colors.white,
                    eyeStyle: QrEyeStyle(
                      eyeShape: QrEyeShape.square,
                      color: _modeColor,
                    ),
                    dataModuleStyle: QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.square,
                      color: _modeColor,
                    ),
                  ),

                  const SizedBox(height: 20),

                  Text(
                    isHighSpeed
                        ? 'Blue QR • 5G+ mode'
                        : 'Black QR • Standard mode',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: _modeColor,
                    ),
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    'Let the receiving phone scan this QR code.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.blueGrey,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4D8),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFF946200),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '5G+ is the name of this transfer mode. '
                      'It does not require a 5G mobile network. '
                      'Actual transfer speed depends on the '
                      'connection and both devices.',
                      style: TextStyle(
                        height: 1.5,
                        color: Color(0xFF795500),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            OutlinedButton.icon(
              onPressed: () {
                setState(() {
                  _sessionId = _createSessionId();
                });
              },
              icon: const Icon(Icons.refresh_rounded),
              label: const Padding(
                padding: EdgeInsets.all(12),
                child: Text('GENERATE NEW QR'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final bool selected;
  final VoidCallback onTap;

  const _ModeCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: 10,
          vertical: 18,
        ),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.08)
              : Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? color
                : const Color(0xFFE5EDF4),
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: color,
                fontSize: 17,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.blueGrey,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
