import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'hotspot_controller.dart';

class SendScreen extends StatefulWidget {
  const SendScreen({super.key});
  @override
  State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
  String? qrData;
  String? ssid;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      var info = await HotspotController.startHotspot();
      setState(() {
        qrData = info["qr"];
        ssid = info["ssid"];
      });
    } catch (e) {
      setState(() => qrData = "ERROR");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121A),
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(ssid?? "Ana kunnawa...")),
      body: Center(
        child: qrData == null
       ? const CircularProgressIndicator()
        : qrData == "ERROR"
       ? const Text("Bai iya kunna Hotspot ba, ka bawa app Location permission a Setting")
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
                child: QrImageView(data: qrData!, size: 240),
              ),
              const SizedBox(height: 20),
              Text("Hotspot: $ssid", style: const TextStyle(color: Colors.white)),
              const SizedBox(height: 10),
              const Text("Bari abokinka ya scan", style: TextStyle(color: Colors.white54)),
            ],
          ),
      ),
    );
  }

  @override
  void dispose() {
    HotspotController.stopHotspot();
    super.dispose();
  }
}
