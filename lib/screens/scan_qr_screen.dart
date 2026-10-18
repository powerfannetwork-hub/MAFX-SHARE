import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  final MobileScannerController _controller =
      MobileScannerController();

  bool _hasScanned = false;
  String? _errorMessage;

  static const Color _green = Color(0xFF43E8A0);
  static const Color _background = Color(0xFF101820);
  static const Color _card = Color(0xFF192832);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isValidIpv4(String value) {
    final address = InternetAddress.tryParse(value);

    return address != null &&
        address.type == InternetAddressType.IPv4;
  }

  bool _isValidPort(Object? value) {
    return value is int && value >= 1 && value <= 65535;
  }

  bool _isValidQrData(Map<String, dynamic> data) {
    final ip = data['ip'];
    final port = data['port'];
    final tcpPort = data['tcpPort'];
    final token = data['token'];
    final mode = data['mode'];

    if (data['app'] != 'MAFX_SHARE' || data['version'] != 1) {
      return false;
    }

    if (ip is! String || !_isValidIpv4(ip)) {
      return false;
    }

    if (!_isValidPort(port) || !_isValidPort(tcpPort)) {
      return false;
    }

    if (token is! String || token.trim().isEmpty) {
      return false;
    }

    if (mode != 'STANDARD' && mode != '5G_PLUS') {
      return false;
    }

    return true;
  }

  void _handleDetection(BarcodeCapture capture) {
    if (_hasScanned) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;

      if (value == null || value.trim().isEmpty) {
        continue;
      }

      try {
        final decoded = jsonDecode(value);

        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        if (!_isValidQrData(decoded)) {
          continue;
        }

        _hasScanned = true;
        _controller.stop();

        if (!mounted) return;

        Navigator.of(context).pop<Map<String, dynamic>>(
          Map<String, dynamic>.from(decoded),
        );

        return;
      } on FormatException {
        // Ignore malformed QR data and continue scanning.
      } catch (_) {
        // Ignore invalid QR data and continue scanning.
      }
    }

    if (mounted && !_hasScanned) {
      setState(() {
        _errorMessage =
            'This is not a valid MAFX SHARE QR code. '
            'Please scan the receiver device QR code.';
      });
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _controller.switchCamera();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Unable to switch camera.';
      });
    }
  }

  Future<void> _toggleTorch() async {
    try {
      await _controller.toggleTorch();
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _errorMessage = 'Unable to change camera flash.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text('Scan MAFX QR'),
        backgroundColor: _green,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.cameraswitch_rounded),
            onPressed: _switchCamera,
          ),
          IconButton(
            tooltip: 'Toggle flashlight',
            icon: const Icon(Icons.flash_on_rounded),
            onPressed: _toggleTorch,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  MobileScanner(
                    controller: _controller,
                    onDetect: _handleDetection,
                  ),
                  IgnorePointer(
                    child: Container(
                      width: 250,
                      height: 250,
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: _green,
                          width: 4,
                        ),
                        borderRadius: BorderRadius.circular(24),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 24,
                    left: 24,
                    right: 24,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Point the camera at the QR code '
                        'displayed on the receiving device.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          height: 1.5,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              color: _card,
              child: Column(
                children: [
                  const Icon(
                    Icons.qr_code_scanner_rounded,
                    color: _green,
                    size: 36,
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    'Connect to another device',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Make sure the receiving device is running '
                    'MAFX SHARE and displaying its connection QR code.',
                    style: TextStyle(
                      color: Colors.white70,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
