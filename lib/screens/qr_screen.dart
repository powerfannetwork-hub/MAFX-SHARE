import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class QrScreen extends StatelessWidget {
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

static const Color _green = Color(0xFF00D18B);
static const Color _background = Color(0xFF101820);
static const Color _card = Color(0xFF192832);

String get _connectionData {
return jsonEncode({
'app': 'MAFX_SHARE',
'version': 1,
'mode': mode,
'ip': ipAddress,
'port': port,
'tcpPort': tcpPort,
'token': token,
});
}

bool get _isHighSpeed => mode == '5G_PLUS';

@override
Widget build(BuildContext context) {
final modeColor =
_isHighSpeed ? Colors.lightBlueAccent : _green;

final modeLabel = _isHighSpeed
    ? '5G+ High-Speed Mode'
    : 'Standard Mode';

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
            'Scan this QR code to connect both phones.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),

          const SizedBox(height: 24),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: modeColor,
                width: 1.5,
              ),
            ),
            child: Column(
              children: [
                Icon(
                  Icons.speed_rounded,
                  color: modeColor,
                  size: 38,
                ),

                const SizedBox(height: 10),

                Text(
                  modeLabel,
                  style: TextStyle(
                    color: modeColor,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 6),

                const Text(
                  'Transfer mode',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 13,
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
              data: _connectionData,
              version: QrVersions.auto,
              size: 250,
              backgroundColor: Colors.white,
              eyeStyle: QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: _isHighSpeed
                    ? Colors.blue
                    : Colors.black,
              ),
              dataModuleStyle: QrDataModuleStyle(
                dataModuleShape:
                    QrDataModuleShape.square,
                color: _isHighSpeed
                    ? Colors.blue
                    : Colors.black,
              ),
            ),
          ),

          const SizedBox(height: 22),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                const Icon(
                  Icons.wifi_tethering_rounded,
                  color: _green,
                  size: 32,
                ),

                const SizedBox(height: 10),

                const Text(
                  'Waiting for connection',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 14),

                const Text(
                  'Phone address',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 5),

                SelectableText(
                  '$ipAddress:$port',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),

                const SizedBox(height: 12),

                const Text(
                  'TCP Port',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),

                const SizedBox(height: 5),

                SelectableText(
                  '$tcpPort',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: _green,
                  size: 22,
                ),

                SizedBox(width: 10),

                Expanded(
                  child: Text(
                    'A waya ta biyu, danna Receive domin buɗe '
                    'scanner, sannan ka scan wannan QR code. '
                    'Wayoyin biyu su kasance a Wi-Fi ko hotspot '
                    'ɗaya. Bayan an haɗa su, sai a zaɓi fayiloli.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ),
              ],
            ),
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
