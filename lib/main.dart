import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:network_info_plus/network_info_plus.dart';

void main() => runApp(MaterialApp(home: FlashApp(), debugShowCheckedModeBanner: false));

class FlashApp extends StatefulWidget { @override _FlashAppState createState() => _FlashAppState(); }

class _FlashAppState extends State<FlashApp> {
  String ip = "Ana neman IP...";
  String log = "Flash - Yafi Xender sauri x3";
  double progress = 0;
  ServerSocket? server;

  @override
  void initState() {
    super.initState();
    getIp();
    startServer();
  }

  getIp() async {
    final info = NetworkInfo();
    var wifiIP = await info.getWifiIP();
    setState(() => ip = wifiIP ?? "Kunna Hotspot da farko");
  }

  startServer() async {
    try {
      server = await ServerSocket.bind(InternetAddress.anyIPv4, 8888);
      setState(() => log = "A shirye don karba akan port 8888");
      server!.listen((client) async {
        setState(() => log = "Ana karba daga ${client.remoteAddress.address}...");
        // Karba file name
        var file = File('/storage/emulated/0/Download/flash_received_file');
        var sink = file.openWrite();
        int total = 0;
        client.listen((data) {
          sink.add(data);
          total += data.length;
          setState(() {
            log = "Ana karba: ${(total/1024/1024).toStringAsFixed(2)} MB";
          });
        }, onDone: () {
          sink.close();
          setState(() => log = "An gama karba! An ajiye a Download");
        });
      });
    } catch (e) {
      setState(() => log = "Error Server: $e");
    }
  }

  sendFile() async {
    var result = await FilePicker.platform.pickFiles();
    if (result == null) return;
    var file = File(result.files.single.path!);
    var fileName = result.files.single.name;
    var size = await file.length();

    // Nemi IP na mai karba
    TextEditingController ipController = TextEditingController(text: "192.168.43.1");
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text("Saka IP na mai karba"),
      content: TextField(controller: ipController, decoration: InputDecoration(hintText: "192.168.43.1")),
      actions: [
        TextButton(onPressed: () async {
          Navigator.pop(context);
          try {
            setState(() => log = "Ana hadawa da ${ipController.text}...");
            var socket = await Socket.connect(ipController.text, 8888, timeout: Duration(seconds: 5));
            setState(() => log = "An hada! Ana tura $fileName...");
            var stream = file.openRead();
            int sent = 0;
            await for (var chunk in stream) {
              socket.add(chunk);
              sent += chunk.length;
              setState(() {
                progress = sent / size;
                log = "Ana tura: ${(progress*100).toStringAsFixed(1)}%";
              });
            }
            await socket.flush();
            await socket.close();
            setState(() => log = "An gama tura $fileName!");
          } catch (e) {
            setState(() => log = "Ba a hada ba: $e - Tabbatar kun hada da hotspot dinsa");
          }
        }, child: Text("TURA"))
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFF12121A),
      appBar: AppBar(title: Text("FLASH - $ip"), backgroundColor: Colors.deepPurple),
      body: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          children: [
            Container(padding: EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(20)),
              child: Column(children: [
                Icon(Icons.bolt, size: 60, color: Colors.yellow),
                SizedBox(height: 10),
                Text(ip, style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 10),
                Text(log, style: TextStyle(color: Colors.white70), textAlign: TextAlign.center),
                SizedBox(height: 10),
                LinearProgressIndicator(value: progress, backgroundColor: Colors.white12),
              ])
            ),
            SizedBox(height: 30),
            Row(children: [
              Expanded(child: ElevatedButton.icon(onPressed: sendFile, icon: Icon(Icons.send), label: Text("TURA FILE"), style: ElevatedButton.styleFrom(padding: EdgeInsets.all(20), backgroundColor: Colors.deepPurple))),
              SizedBox(width: 15),
              Expanded(child: ElevatedButton.icon(onPressed: getIp, icon: Icon(Icons.wifi), label: Text("SABUNTA IP"), style: ElevatedButton.styleFrom(padding: EdgeInsets.all(20), backgroundColor: Colors.white10))),
            ]),
            SizedBox(height: 20),
            Text("Yadda ake amfani:\n1. Wayar mai KARBA ta kunna Hotspot\n2. Wayar mai TURA ta hada da hotspot din\n3. Mai tura ya danna TURA FILE ya saka IP: 192.168.43.1", style: TextStyle(color: Colors.white54))
          ],
        ),
      ),
    );
  }
}
