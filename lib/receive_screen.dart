import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'hotspot_controller.dart';

class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});
  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}

class _ReceiveScreenState extends State<ReceiveScreen> {
  bool isConnecting = false;

  void _onQr(String code) async {
    if (isConnecting) return;
    setState(() => isConnecting = true);
    var info = HotspotController.parseWifiQr(code);
    if (info.isNotEmpty) {
      bool ok = await HotspotController.connectToHotspot(info["ssid"]!, info["password"]!);
      if (ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("An hada da ${info["ssid"]}")));
        // ANAN ZAMU KAI SHI FILE LIST SCREEN
        Navigator.push(context, MaterialPageRoute(builder: (_) => const FileListScreen()));
      }
    }
    setState(() => isConnecting = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        MobileScanner(onDetect: (c) => _onQr(c.barcodes.first.rawValue?? "")),
        if (isConnecting) const Center(child: CircularProgressIndicator()),
      ]),
    );
  }
}

class FileListScreen extends StatelessWidget {
  const FileListScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text("An hada! Yanzu za a fara tura file da sauri...")));
  }
}
