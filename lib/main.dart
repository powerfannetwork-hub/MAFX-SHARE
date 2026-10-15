import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
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

class ReceivePage extends StatefulWidget { @override _ReceivePageState createState() => _ReceivePageState(); }

class _ReceivePageState extends State<ReceivePage> {
  String myIp = "Ana loding...";
  String log = "1. Kunna Hotspot\n2. Bude wannan shafin\n3. Bari abokinka ya scan QR";
  ServerSocket? server;

  @override void initState() {
    super.initState();
    Future.delayed(Duration(milliseconds: 800), () async {
      await [Permission.camera, Permission.storage, Permission.location].request();
      getIp();
      startServer();
    });
  }

  getIp() async {
    var info = NetworkInfo();
    var ip = await info.getWifiIP();
    if (mounted) setState(() => myIp = ip ?? "192.168.43.1");
  }

  startServer() async {
    try {
      server = await ServerSocket.bind(InternetAddress.anyIPv4, 8888);
      if (mounted) setState(() => log = "A shirye! Nuna QR ga mai tura");
      server!.listen((client) {
        if (mounted) setState(() => log = "Ana karba...");
        var file = File('/storage/emulated/0/Download/FLASH_${DateTime.now().millisecondsSinceEpoch}');
        var sink = file.openWrite();
        int total = 0;
        client.listen((data) {
          sink.add(data);
          total += data.length;
          if (mounted) setState(() => log = "Ana karba: ${(total/1024/1024).toStringAsFixed(2)} MB");
        }, onDone: () {
          sink.close();
          if (mounted) setState(() => log = "An gama! File a Download folder");
        });
      });
    } catch (e) { if (mounted) setState(() => log = "Error: $e"); }
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

class SendPage extends StatefulWidget { @override _SendPageState createState() => _SendPageState(); }

class _SendPageState extends State<SendPage> {
  String log = "Danna SCAN QR don hadawa";
  double progress = 0;
  bool scanning = true;

  sendFileToIp(String ip) async {
   
