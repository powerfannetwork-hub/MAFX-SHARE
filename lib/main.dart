import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await [Permission.camera, Permission.location, Permission.storage].request();
  runApp(MaterialApp(home: FlashHome(), debugShowCheckedModeBanner: false));
}

class FlashHome extends StatefulWidget { @override _FlashHomeState createState() => _FlashHomeState(); }

class _FlashHomeState extends State<FlashHome> with SingleTickerProviderStateMixin {
  late TabController tab;
  @override void initState() { tab = TabController(length: 2, vsync: this); super.initState(); }
  @override Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF12121A),
      appBar: AppBar(title: Text("FLASH - Kamar Xender"), backgroundColor: Colors.deepPurple,
        bottom: TabBar(controller: tab, tabs: [Tab(icon: Icon(Icons.call_received), text: "KARBA"), Tab(icon: Icon(Icons.send), text: "TURA")])
      ),
      body: TabBarView(controller: tab, children: [ReceivePage(), SendPage()]),
    );
  }
}

// ========== KARBA ==========
class ReceivePage extends StatefulWidget { @override _ReceivePageState createState() => _ReceivePageState(); }
class _ReceivePageState extends State<ReceivePage> {
  String myIp = "Ana loding...";
  String log = "1. Kunna Hotspot\n2. Bude wannan shafin\n3. Bari abokinka ya scan QR";
  ServerSocket? server;

  @override void initState() { super.initState(); getIp(); startServer(); }

  getIp() async {
    var info = NetworkInfo();
    var ip = await info.getWifiIP();
    setState(() => myIp = ip ?? "192.168.43.1");
  }

  startServer() async {
    try {
      server = await ServerSocket.bind(InternetAddress.anyIPv4, 8888);
      setState(() => log = "A shirye! Nuna QR ga mai tura");
      server!.listen((client) {
        setState(() => log = "Ana karba daga ${client.remoteAddress.address}...");
        var file = File('/storage/emulated/0/Download/FLASH_${DateTime.now().millisecondsSinceEpoch}');
        var sink = file.openWrite();
        int total = 0;
        client.listen((data) {
          sink.add(data);
          total += data.length;
          setState(() => log = "Ana karba: ${(total/1024/1024).toStringAsFixed(2)} MB");
        }, onDone: () {
          sink.close();
          setState(() => log = "An gama! File a Download folder");
        });
      });
    } catch (e) { setState(() => log = "Error: $e"); }
  }

  @override Widget build(BuildContext context) {
    return Padding(padding: EdgeInsets.all(20), child: Column(children: [
      Container(padding: EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
        child: QrImageView(data: myIp, size: 250, backgroundColor: Colors.white)),
      SizedBox(height: 20),
      Text(myIp, style: TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
      SizedBox(height: 15),
      Text(log, style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
    ]));
  }
}

// ========== TURA ==========
class SendPage extends StatefulWidget { @override _SendPageState createState() => _SendPageState(); }
class _SendPageState extends State<SendPage> {
  String log = "Danna SCAN QR don hadawa";
  double progress = 0;
  bool scanning = true;

  sendFileToIp(String ip) async {
    var result = await FilePicker.platform.pickFiles();
    if (result == null) return;
    var file = File(result.files.single.path!);
    var size = await file.length();
    try {
      setState(() { log = "Ana hadawa da $ip..."; scanning = false; });
      var socket = await Socket.connect(ip, 8888, timeout: Duration(seconds: 5));
      setState(() => log = "An hada! Ana tura ${result.files.single.name}...");
      int sent = 0;
      await for (var chunk in file.openRead()) {
        socket.add(chunk);
        sent += chunk.length;
        setState(() { progress = sent / size; log = "Ana tura: ${(progress*100).toStringAsFixed(1)}%"; });
      }
      await socket.flush(); await socket.close();
      setState(() => log = "An gama tura!");
    } catch (e) { setState(() => log = "Ba a hada ba: $e"); }
  }

  @override Widget build(BuildContext context) {
    return Column(children: [
      Expanded(child: scanning ? MobileScanner(onDetect: (capture) {
        final ip = capture.barcodes.first.rawValue;
        if (ip != null && ip.contains(".")) {
          sendFileToIp(ip);
        }
      }) : Icon(Icons.check_circle, size: 100, color: Colors.green)),
      Padding(padding: EdgeInsets.all(20), child: Column(children: [
        LinearProgressIndicator(value: progress),
        SizedBox(height: 10),
        Text(log, style: TextStyle(color: Colors.white)),
        SizedBox(height: 10),
        ElevatedButton(onPressed: () => setState(() { scanning = true; progress = 0; }), child: Text("SAKE SCAN"), style: ElevatedButton.styleFrom(backgroundColor: Colors.deepPurple))
      ]))
    ]);
  }
}
