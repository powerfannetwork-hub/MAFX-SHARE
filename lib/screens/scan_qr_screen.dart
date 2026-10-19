import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/transfer_service.dart';

class ScanQrScreen extends StatefulWidget {
  const ScanQrScreen({super.key});

  @override
  State<ScanQrScreen> createState() => _ScanQrScreenState();
}

class _ScanQrScreenState extends State<ScanQrScreen> {
  static const Color _background = Color(0xFF202024);
  static const Color _green = Color(0xFF008D5A);
  static const Color _accent = Color(0xFF00D18B);

  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    facing: CameraFacing.back,
    formats: const [BarcodeFormat.qrCode],
    autoStart: true,
  );

  bool _processing = false;
  bool _flashEnabled = false;
  String? _errorMessage;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _toggleFlash() async {
    try {
      await _controller.toggleTorch();

      if (!mounted) return;

      setState(() {
        _flashEnabled = !_flashEnabled;
      });
    } catch (error) {
      debugPrint('Flashlight error: $error');
      _showMessage('Unable to change the flashlight setting.');
    }
  }

  Future<void> _switchCamera() async {
    try {
      await _controller.switchCamera();
    } catch (error) {
      debugPrint('Camera switch error: $error');
      _showMessage('Unable to switch camera.');
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);

    return null;
  }

  Map<String, dynamic>? _decodeQr(String rawValue) {
    try {
      final dynamic decoded = jsonDecode(rawValue);

      if (decoded is! Map) {
        _errorMessage =
            'Invalid QR code. Please scan a MAFX SHARE QR code.';
        return null;
      }

      final data = Map<String, dynamic>.from(decoded);

      if (data['app']?.toString() != 'MAFX_SHARE') {
        _errorMessage = 'This QR code does not belong to MAFX SHARE.';
        return null;
      }

      final ip = data['ip']?.toString().trim() ?? '';
      final token = data['token']?.toString().trim() ?? '';

      final mode =
          data['mode']?.toString() ?? TransferService.standardMode;

      final port = _parseInt(data['port']);
      final tcpPort = _parseInt(data['tcpPort']);

      if (ip.isEmpty) {
        _errorMessage =
            'The QR code does not contain a receiver IP address.';
        return null;
      }

      if (token.isEmpty) {
        _errorMessage =
            'The QR code does not contain a connection token.';
        return null;
      }

      if (port == null || port < 1 || port > 65535) {
        _errorMessage = 'The QR code contains an invalid receiver port.';
        return null;
      }

      if (mode != TransferService.standardMode &&
          mode != TransferService.highSpeedMode) {
        _errorMessage = 'The QR code contains an unsupported transfer mode.';
        return null;
      }

      if (mode == TransferService.highSpeedMode &&
          (tcpPort == null || tcpPort < 1 || tcpPort > 65535)) {
        _errorMessage =
            'The QR code is missing a valid high-speed TCP port.';
        return null;
      }

      return <String, dynamic>{
        'app': 'MAFX_SHARE',
        'version': _parseInt(data['version']) ?? 1,
        'ip': ip,
        'port': port,
        'tcpPort': tcpPort,
        'token': token,
        'mode': mode,
      };
    } on FormatException catch (error) {
      debugPrint('QR format error: $error');
      _errorMessage = 'Unable to read this QR code. Please try again.';
      return null;
    } catch (error, stackTrace) {
      debugPrint('QR parsing error: $error');
      debugPrintStack(stackTrace: stackTrace);

      _errorMessage = 'The QR code contains invalid connection data.';
      return null;
    }
  }

  Future<void> _handleDetection(BarcodeCapture capture) async {
    if (_processing || !mounted) return;

    for (final barcode in capture.barcodes) {
      final rawValue = barcode.rawValue;

      if (rawValue == null || rawValue.trim().isEmpty) {
        continue;
      }

      setState(() {
        _processing = true;
        _errorMessage = null;
      });

      final data = _decodeQr(rawValue.trim());

      if (data == null) {
        if (!mounted) return;

        final message = _errorMessage ?? 'Invalid QR code.';

        setState(() {
          _processing = false;
        });

        _showMessage(message);
        return;
      }

      try {
        await _controller.stop();

        if (!mounted) return;

        Navigator.of(context).pop<Map<String, dynamic>>(data);
      } catch (error, stackTrace) {
        debugPrint('Failed to finish QR scanning: $error');
        debugPrintStack(stackTrace: stackTrace);

        if (!mounted) return;

        setState(() {
          _processing = false;
          _errorMessage =
              'Unable to process the QR code. Please try again.';
        });

        try {
          await _controller.start();
        } catch (startError) {
          debugPrint('Failed to restart scanner: $startError');
          _showMessage(
            'Unable to restart the camera. Check camera permissions.',
          );
        }
      }

      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text('Scan MAFX QR'),
        backgroundColor: _green,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Switch camera',
            onPressed: _switchCamera,
            icon: const Icon(Icons.cameraswitch_rounded),
          ),
          IconButton(
            tooltip:
                _flashEnabled ? 'Turn flashlight off' : 'Turn flashlight on',
            onPressed: _toggleFlash,
            icon: Icon(
              _flashEnabled
                  ? Icons.flash_on_rounded
                  : Icons.flash_off_rounded,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                children: [
                  Icon(
                    Icons.qr_code_scanner_rounded,
                    color: _accent,
                    size: 48,
                  ),
                  SizedBox(height: 12),
                  Text(
                    'Connect to Another Device',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 21,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Point your camera at the QR code displayed on the other device.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _controller,
                        onDetect: _handleDetection,
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 245,
                            height: 245,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: _accent,
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(22),
                            ),
                          ),
                        ),
                      ),
                      if (_processing)
                        Container(
                          color: Colors.black54,
                          child: const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                CircularProgressIndicator(
                                  color: _accent,
                                ),
                                SizedBox(height: 16),
                                Text(
                                  'Processing QR code...',
                                  style: TextStyle(
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            if (_errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.redAccent,
                    height: 1.4,
                  ),
                ),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: _accent,
                    size: 22,
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Keep both devices connected to the same local Wi-Fi network or hotspot. The sending device must keep the transfer screen open.',
                      style: TextStyle(
                        color: Colors.white70,
                        height: 1.5,
                      ),
                    ),
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
