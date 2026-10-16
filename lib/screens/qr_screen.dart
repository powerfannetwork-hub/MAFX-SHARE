import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrScreen extends StatelessWidget {
  final String ipAddress;
  final int port;
  final String token;
  final String mode;

  const QrScreen({
    super.key,
    required this.ipAddress,
    required this.port,
    required this.token,
    this.mode = 'STANDARD',
  });

  @override
  Widget build(BuildContext context) {
    final connectionData = jsonEncode({
      'app': 'MAFX_SHARE',
      'version': 1,
      'mode': mode,
      'ip': ipAddress,
      'port': port,
      'token': token,
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Device'),
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.qr_code_2,
                size: 56,
                color: Colors.green,
              ),
              const SizedBox(height: 16),
              const Text(
                'MAFX SHARE',
                style: TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text('Connection mode: $mode'),
              const SizedBox(height: 24),
              QrImageView(
                data: connectionData,
                version: QrVersions.auto,
                size: 260,
                backgroundColor: Colors.white,
                eyeStyle: QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: mode == '5G_PLUS'
                      ? Colors.blue
                      : Colors.black,
                ),
                dataModuleStyle: QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: mode == '5G_PLUS'
                      ? Colors.blue
                      : Colors.black,
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Scan this QR code from the receiving device.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              SelectableText('$ipAddress:$port'),
              const SizedBox(height: 8),
              Text(
                mode == '5G_PLUS'
                    ? '5G+ mode'
                    : 'Standard mode',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
