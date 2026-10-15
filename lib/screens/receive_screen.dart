import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'connect_screen.dart';

class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Receive Files'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            const SizedBox(height: 35),
            const Icon(
              Icons.phonelink_ring_rounded,
              size: 90,
              color: AppTheme.green,
            ),
            const SizedBox(height: 20),
            const Text(
              'Ready to receive',
              style: TextStyle(
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Connect to another device to receive photos, '
              'videos, music and other files without mobile data.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.blueGrey,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 25),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
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
                        Icons.phone_android,
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
                        Icons.wifi,
                        color: AppTheme.green,
                      ),
                      SizedBox(width: 10),
                      Text('Connection'),
                      Spacer(),
                      Text('Not connected'),
                    ],
                  ),
                ],
              ),
            ),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ConnectScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.qr_code_2_rounded),
                label: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('CONNECT DEVICE'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
