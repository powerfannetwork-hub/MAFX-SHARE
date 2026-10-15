import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

class SendScreen extends StatelessWidget {
  const SendScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Wannan ne bayanan da zasu hada wayoyin direct
    // Daga baya zamu mayar da shi da hotspot na zahiri
    String qrData = "WIFI:S:FLASH-${DateTime.now().millisecond};T:WPA;P:12345678;;";

    return Scaffold(
      backgroundColor: const Color(0xFF12121A),
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text("Send")),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text("Bari abokinka ya scan wannan", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: QrImageView(data: qrData, version: QrVersions.auto, size: 220),
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(color: Colors.blue),
            const SizedBox(height: 10),
            const Text("Ana kunna Hotspot 5GHz...", style: TextStyle(color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}
