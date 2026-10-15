import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:wifi_iot/wifi_iot.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:file_picker/file_picker.dart';
import 'package:google_fonts/google_fonts.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: const Color(0xFF12121A)),
      home: const HomeScreen(),
    );
  }
}

// ============= CONTROLLER - HOTSPOT =============
class HotspotController {
  static Future<Map<String, String>> startHotspot() async {
    await [Permission.location, Permission.nearbyWifiDevices].request();
    String ssid = "Flash-${Random().nextInt(9000) + 1000}";
    String password = "${Random().nextInt(90000000) + 10000000}";
    try {
      await WiFiForIoTPlugin.setWiFiAPSSID(ssid);
      await WiFiForIoTPlugin.setWiFiAPPreSharedKey(password);
      await WiFiForIoTPlugin.setWiFiAPBand(WiFiAPBand.BAND_5GHZ);
      await WiFiForIoTPlugin.setWiFiAPState(true);
    } catch (e) {
      await WiFiForIoTPlugin.setWiFiAPBand(WiFiAPBand.BAND_2GHZ);
      await WiFiForIoTPlugin.setWiFiAPState(true);
    }
    return {"ssid": ssid, "password": password, "qr": "WIFI:S:$ssid;T:WPA;P:$password;;"};
  }
  static Future<void> stopHotspot() async => await WiFiForIoTPlugin.setWiFiAPState(false);
  static Future<bool> connectToHotspot(String ssid, String password) async {
    await Permission.location.request();
    return await WiFiForIoTPlugin.connect(ssid, password: password, security: NetworkSecurity.WPA, joinOnce: true);
  }
  static Map<String, String> parseQr(String qr) {
    try {
      String ssid = qr.split("S:")[1].split(";")[0];
      String pass = qr.split("P:")[1].split(";")[0];
      return {"ssid": ssid, "password": pass};
    } catch (_) { return {}; }
  }
}

// ============= HOME SCREEN =============
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 80),
            Text("Transfer Files Instantly", style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold)),
            Text("Babu internet, babu talla, yafi Xender sauri", style: GoogleFonts.poppins(fontSize: 12, color: Colors.white54)),
            const Spacer(),
            _Btn(text: "SEND", color: const Color(0xFF3A7BFF), icon: Icons.send_rounded, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SendScreen()))),
            const SizedBox(height: 20),
            _Btn(text: "RECEIVED", color: const Color(0xFF00C876), icon: Icons.download_rounded, onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ReceiveScreen()))),
            const Spacer(),
            const Text("✓ Fast Transfer • No Internet • 5GHz", style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _Btn extends StatelessWidget {
  final String text; final Color color; final IconData icon; final VoidCallback onTap;
  const _Btn({required this.text, required this.color, required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85, height: 90,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, size: 36), const SizedBox(width: 12),
          Text(text, style: GoogleFonts.poppins(fontSize: 30, fontWeight: FontWeight.bold)),
        ]),
      ),
    );
  }
}

// ============= SEND SCREEN =============
class SendScreen extends StatefulWidget {
  const SendScreen({super.key});
  @override
  State<SendScreen> createState() => _SendScreenState();
}
class _SendScreenState extends State<SendScreen> {
  Map<String, String>? info;
  @override
  void initState() { super.initState(); _init(); }
  Future<void> _init() async { var i = await HotspotController.startHotspot(); setState(() => info = i); }
  @override
  void dispose() { HotspotController.stopHotspot(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(info?["ssid"]?? "Ana kunnawa...")),
      body: Center(
        child: info == null? const CircularProgressIndicator() : Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: QrImageView(data: info!["qr"]!, size: 240)),
            const SizedBox(height: 20),
            Text("Hotspot: ${info!["ssid"]}", style: const TextStyle(color: Colors.white)),
            const SizedBox(height: 30),
            ElevatedButton(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => FileTransferScreen(isSender: true, ssid: info!["ssid"]!))),
              child: const Text("ZABI FILE DA ZAKA TURA"),
            ),
          ],
        ),
      ),
    );
  }
}

// ============= RECEIVE SCREEN =============
class ReceiveScreen extends StatefulWidget {
  const ReceiveScreen({super.key});
  @override
  State<ReceiveScreen> createState() => _ReceiveScreenState();
}
class _ReceiveScreenState extends State<ReceiveScreen> {
  bool busy = false;
  void _onDetect(String code) async {
    if (busy) return; setState(() => busy = true);
    var p = HotspotController.parseQr(code);
    if (p.isNotEmpty) {
      bool ok = await HotspotController.connectToHotspot(p["ssid"]!, p["password"]!);
      if (ok && mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => FileTransferScreen(isSender: false, ssid: p["ssid"]!)));
      }
    }
    setState(() => busy = false);
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(children: [
        MobileScanner(onDetect: (c) => _onDetect(c.barcodes.first.rawValue?? "")),
        Center(child: Container(width: 250, height: 250, decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 2), borderRadius: BorderRadius.circular(20)))),
        if (busy) const Center(child: CircularProgressIndicator()),
        const Positioned(bottom: 40, left: 0, right: 0, child: Text("Duba QR din da ke wayar daya", textAlign: TextAlign.center)),
      ]),
    );
  }
}

// ============= FILE TRANSFER SCREEN - INJIN GUDU =============
class FileTransferScreen extends StatefulWidget {
  final bool isSender; final String ssid;
  const FileTransferScreen({super.key, required this.isSender, required this.ssid});
  @override
  State<FileTransferScreen> createState() => _FileTransferScreenState();
}
class _FileTransferScreenState extends State<FileTransferScreen> {
  List<File> files = [];
  double progress = 0; String log = "";
  ServerSocket? server;

  Future<void> pickFiles() async {
    var res = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (res!= null) setState(() => files = res.paths.map((p) => File(p!)).toList());
  }

  Future<void> startSending() async {
    server = await ServerSocket.bind(InternetAddress.anyIPv4, 8888);
    setState(() => log = "Ana jira mai karba ya hada... IP: ${server!.address.address}:8888");
    server!.listen((client) async {
      for (var file
