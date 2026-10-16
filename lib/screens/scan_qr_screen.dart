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

        if (decoded is! Map<String, dynamic>) {
          continue;
        }

        if (decoded['app'] != 'MAFX_SHARE' ||
            decoded['version'] != 1 ||
            decoded['session'] is! String ||
            !['STANDARD', '5G_PLUS'].contains(decoded['mode'])) {
          continue;
        }

        _hasScanned = true;
        _controller.stop();

        if (!mounted) return;

        Navigator.of(context).pop<Map<String, dynamic>>(
          decoded,
        );
        return;
      } catch (_) {
        // Ignore QR codes that do not contain valid MAFX SHARE data.
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
            icon: const Icon(Icons.cameraswitch_rounded),
            onPressed: () => _controller.switchCamera(),
          ),
          IconButton(
            tooltip: 'Toggle flashlight',
            icon: const Icon(Icons.flash_on_rounded),
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
                Positioned(
                  bottom: 30,
                  left: 24,
                  right: 24,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Text(
                      'Point your camera at the QR code '
                      'displayed on the sending phone.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        height: 1.4,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'Only valid MAFX SHARE QR codes are accepted.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.blueGrey,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
