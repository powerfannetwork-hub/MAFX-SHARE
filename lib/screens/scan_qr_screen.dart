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
  late final MobileScannerController _controller;

  bool _hasScanned = false;
  bool _torchEnabled = false;
  bool _cameraSwitching = false;
  String? _errorMessage;

  static const Color _green = Color(0xFF43E8A0);
  static const Color _background = Color(0xFF101820);
  static const Color _card = Color(0xFF192832);

  @override
  void initState() {
    super.initState();

    _controller = MobileScannerController(
      autoStart: true,
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: CameraFacing.back,
      torchEnabled: false,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isValidIpv4(String value) {
    final address = InternetAddress.tryParse(value);

    return address != null &&
        address.type == InternetAddressType.IPv4 &&
        !address.isLoopback &&
        !address.isMulticast;
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

    if (ip is! String || !_isValidIpv4(ip.trim())) {
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
          if (mounted) {
            setState(() {
              _errorMessage =
                  'QR code ɗin ba na MAFX SHARE ba ne. '
                  'Ka duba QR code ɗin ɗayar wayar.';
            });
          }

          continue;
        }

        _hasScanned = true;

        if (mounted) {
          setState(() {
            _errorMessage = null;
          });
        }

        _controller.stop();

        if (!mounted) return;

        Navigator.of(context).pop<Map<String, dynamic>>(
          Map<String, dynamic>.from(decoded),
        );

        return;
      } on FormatException {
        // Ci gaba da scan idan QR code ba ingantaccen JSON ba ne.
      } catch (error) {
        debugPrint('QR processing error: $error');
      }
    }
  }

  Future<void> _switchCamera() async {
    if (_cameraSwitching || _hasScanned) return;

    setState(() {
      _cameraSwitching = true;
      _errorMessage = null;
    });

    try {
      await _controller.switchCamera();
    } catch (error) {
      debugPrint('Camera switch failed: $error');

      if (mounted) {
        setState(() {
          _errorMessage = 'An kasa sauya kyamara.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _cameraSwitching = false;
        });
      }
    }
  }

  Future<void> _toggleTorch() async {
    if (_hasScanned) return;

    try {
      await _controller.toggleTorch();

      if (!mounted) return;

      setState(() {
        _torchEnabled = !_torchEnabled;
        _errorMessage = null;
      });
    } catch (error) {
      debugPrint('Torch toggle failed: $error');

      if (mounted) {
        setState(() {
          _errorMessage =
              'Ba a iya kunna ko kashe hasken kyamara ba.';
        });
      }
    }
  }

  Future<void> _restartCamera() async {
    try {
      await _controller.start();

      if (mounted) {
        setState(() {
          _errorMessage = null;
        });
      }
    } catch (error) {
      debugPrint('Camera restart failed: $error');

      if (mounted) {
        setState(() {
          _errorMessage =
              'An kasa buɗe kyamara. Duba izinin kyamara a Settings.';
        });
      }
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
            onPressed: _cameraSwitching ? null : _switchCamera,
          ),
          IconButton(
            tooltip: 'Toggle flashlight',
            icon: Icon(
              _torchEnabled
                  ? Icons.flash_on_rounded
                  : Icons.flash_off_rounded,
            ),
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

                    // GYARAN BUILD ERROR:
                    // mobile_scanner 6.x yana buƙatar arguments uku.
                    errorBuilder: (
                      BuildContext context,
                      MobileScannerException error,
                      Widget? child,
                    ) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.no_photography_rounded,
                                color: Colors.redAccent,
                                size: 52,
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                'Ba a iya buɗe kyamara ba.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                error.errorDetails?.message ??
                                    'Duba izinin kyamara a Settings '
                                        'na wayarka.',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: Colors.white70,
                                  height: 1.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              FilledButton.icon(
                                onPressed: _restartCamera,
                                icon: const Icon(
                                  Icons.refresh_rounded,
                                ),
                                label: const Text('Try Again'),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
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
                        'Nuna kyamara ga QR code da MAFX SHARE '
                        'ya nuna a ɗayar wayar.',
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
                    'Tabbatar wayoyin suna kan Wi-Fi ko hotspot '
                    'ɗaya. Bayan scan, app zai tabbatar da haɗin.',
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
                        height: 1.4,
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
