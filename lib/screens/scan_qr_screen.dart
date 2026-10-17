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

        final ip = decoded['ip'];
        final port = decoded['port'];
        final token = decoded['token'];
        final mode = decoded['mode'];

        final valid = decoded['app'] == 'MAFX_SHARE' &&
            decoded['version'] == 1 &&
            ip is String &&
            _isValidIpv4(ip) &&
            port is int &&
            port >= 1 &&
            port <= 65535 &&
            token is String &&
            token.trim().isNotEmpty &&
            ['STANDARD', '5G_PLUS'].contains(mode);

        if (!valid) continue;

        _hasScanned = true;
        _controller.stop();

        if (!mounted) return;

        Navigator.of(context).pop<Map<String, dynamic>>(
          Map<String, dynamic>.from(decoded),
        );
        return;
      } catch (_) {
        // Continue scanning when the QR code is invalid.
      }
    }

    if (mounted && !_hasScanned) {
      setState(() {
        _errorMessage =
            'Wannan ba ingantaccen QR code na MAFX SHARE ba ne.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan MAFX QR'),
        actions: [
          IconButton(
            tooltip: 'Canza camera',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
          IconButton(
            tooltip: 'Hasken camera',
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
                    'Ka nuna camera kan QR code na na\'urar da za a karɓa.',
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
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                const Text(
                  'Duba QR code na MAFX SHARE domin haɗa na\'urori.',
                  textAlign: TextAlign.center,
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
