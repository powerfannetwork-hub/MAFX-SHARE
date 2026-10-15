import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'transfer_engine.dart';

class FileSelectScreen extends StatefulWidget {
  final bool isSender;
  final String serverIp;
  const FileSelectScreen({super.key, required this.isSender, this.serverIp = "192.168.43.1"});

  @override
  State<FileSelectScreen> createState() => _FileSelectScreenState();
}

class _FileSelectScreenState extends State<FileSelectScreen> {
  List<PlatformFile> pickedFiles = [];
  double progress = 0;
  String status = "";

  Future<void> pick() async {
    var result = await FilePicker.platform.pickFiles(allowMultiple: true);
    if (result!= null) setState(() => pickedFiles = result.files);
  }

  Future<void> startSend() async {
    var files = pickedFiles.map((p) => File(p.path!)).toList();
    // Tura ta socket mafi sauri
    var server = await TransferEngine.startServer(onProgress: (name, sent, total) {
      setState(() {
        progress = sent / total;
        status = "$name: ${(sent/1024/1024).toStringAsFixed(1)}MB / ${(total/1024/1024).toStringAsFixed(1)}MB";
      });
    });
    // A zahiri server din yana jira, yanzu receiver ya hada
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121A),
      appBar: AppBar(title: Text(widget.isSender? "Zabi abinda zaka tura" : "Ana jira")),
      body: Column(
        children: [
          ElevatedButton(onPressed: pick, child: const Text("Zabi File")),
          LinearProgressIndicator(value: progress),
          Text(status, style: const TextStyle(color: Colors.white)),
          Expanded(
            child: ListView.builder(
              itemCount: pickedFiles.length,
              itemBuilder: (_, i) => ListTile(
                title: Text(pickedFiles[i].name, style: const TextStyle(color: Colors.white)),
                subtitle: Text("${(pickedFiles[i].size/1024/1024).toStringAsFixed(2)} MB"),
              ),
            ),
          ),
          if (pickedFiles.isNotEmpty)
            ElevatedButton(
              onPressed: startSend,
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, minimumSize: Size(double.infinity, 60)),
              child: const Text("TURA YANZU - SAURI", style: TextStyle(fontSize: 20)),
            ),
        ],
      ),
    );
  }
}
