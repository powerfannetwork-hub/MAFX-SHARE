import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class ReceiveScreen extends StatelessWidget {
  const ReceiveScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, title: const Text("Scan QR")),
      body: Stack(
        children: [
          MobileScanner(
            onDetect: (capture) {
              final String? code = capture.barcodes.first.rawValue;
              if (code != null) {
                // Anan ne zai karanta kuma ya hada kai tsaye
                print("QR FOUND: $code");
                // TODO: connectToHotspot(code)
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text("An hada: $code"))
                );
              }
            },
          ),
          Center(
            child: Container(
              width: 250, height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2),
                borderRadius: BorderRadius.circular(20)
              ),
            ),
          ),
          const Positioned(
            bottom: 40, left: 0, right: 0,
            child: Text("Duba QR din da ke wayar daya", textAlign: TextAlign.center, style: TextStyle(color: Colors.white)),
          )
        ],
      ),
    );
  }
}
