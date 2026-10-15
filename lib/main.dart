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

// ================== SPEED TRACKER ==================
class SpeedTracker {
  int _lastBytes = 0;
  DateTime _lastTime = DateTime.now();
  double speedMBps = 0;
  void update(int totalBytes) {
    var now = DateTime.now();
    var diff = now.difference(_lastTime).inMilliseconds;
    if (diff > 500) {
      int delta = totalBytes - _lastBytes;
      speedMBps = (delta / 1024 / 1024) / (diff / 1000);
      _lastBytes = totalBytes;
      _lastTime = now;
    }
  }
}

// ================== HOTSPOT CONTROLLER ==================
class HotspotController {
  static Future<Map<String, String>> startHotspot() async {
    await [Permission.location, Permission.nearbyWifiDevices, Permission.storage].request();
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
  static Future<String> findServerIp() async {
    List<String> ips = ["192.168.43.1", "192.168.49.1", "192.168.0.1", "192.168.1.1"];
    for (var ip in ips) {
      try {
        var s = await Socket.connect(ip, 8888, timeout: const Duration(milliseconds: 800));
        s.destroy();
        return ip;
      } catch (_) {}
    }
    return "192.168.43.1";
  }
}

// ================== HOME ==================
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
          Icon(icon, size: 36, color: Colors.white), const SizedBox(width: 12),
          Text(text
