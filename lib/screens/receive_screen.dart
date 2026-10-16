import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'connect_screen.dart';
import 'qr_screen.dart';

class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key});

  void _openConnect(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ConnectScreen(),
      ),
    );
  }

  void _showMyQr(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const QrScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Files'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const SizedBox(height: 28),
            const Icon(
              Icons.phonelink_ring_rounded,
              size: 88,
              color: AppTheme.green,
            ),
            const SizedBox(height: 20),
            const Text(
              'Ready to Receive',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Prepare to receive photos, videos, documents '
              'and other files from another device.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.blueGrey,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 25),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFE5EDF4),
                ),
              ),
              child: const Column(
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.phone_android_rounded,
                        color: AppTheme.green,
                      ),
                      SizedBox(width: 10),
                      Text('Device name'),
                      Spacer(),
                      Text(
                        'MAFX-ANDROID',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Divider(height: 28),
                  Row(
                    children: [
                      Icon(
                        Icons.wifi_rounded,
                        color: AppTheme.green,
                      ),
                      SizedBox(width: 10),
                      Text('Connection'),
                      Spacer(),
                      Text(
                        'Not connected',
                        style: TextStyle(
                          color: Colors.orange,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 18),

            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF00AEEF).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    color: Color(0xFF00AEEF),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Zaɓi Connect Device domin bincika QR code '
                      'na wata na’ura. Dole ne a kammala haɗin '
                      'na’urori kafin a iya karɓar fayiloli.',
                    ),
                  ),
                ],
              ),
            ),

            const Spacer(),

            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => _openConnect(context),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('CONNECT DEVICE'),
                ),
              ),
            ),

            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _showMyQr(context),
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('SHOW MY QR CODE'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
