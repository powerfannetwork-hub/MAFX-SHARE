import 'dart:convert';

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

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleDetection(BarcodeCapture capture) {
    if (_hasScanned) return;

    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value == null || value.isEmpty) continue;

      try {
        final decoded = jsonDecode(value);

        if (decoded is! Map<String, dynamic>) continue;

        final valid = decoded['app'] == 'MAFX_SHARE' &&
            decoded['version'] == 1 &&
            decoded['ip'] is String &&
            decoded['ip'].toString().isNotEmpty &&
            decoded['port'] is int &&
            decoded['token'] is String &&
            decoded['token'].toString().isNotEmpty &&
            ['STANDARD', '5G_PLUS'].contains(decoded['mode']);

        if (!valid) continue;

        _hasScanned = true;
        _controller.stop();

        if (!mounted) return;

        Navigator.of(context).pop<Map<String, dynamic>>(decoded);
        return;
      } catch (_) {
        // Ignore invalid QR codes.
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan MAFX QR'),
        actions: [
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
          IconButton(
            tooltip: 'Flashlight',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Column(
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
                        color: const Color(0xFF43E8A0),
                        width: 4,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                  ),
                ),
                const Positioned(
                  bottom: 30,
                  left: 24,
                  right: 24,
                  child: Text(
                    'Point the camera at the receiver QR code.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      backgroundColor: Colors.black54,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'Scan a valid MAFX SHARE connection QR code.',
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
