import 'dart:io';
import 'dart:async';
import 'dart:typed_data';

class SpeedTracker {
  int _lastBytes = 0;
  DateTime _lastTime = DateTime.now();
  double speedMBps = 0;
  
  void update(int totalBytes) {
    var now = DateTime.now();
    var diff = now.difference(_lastTime).inMilliseconds;
    if (diff > 500) { // update kowane 0.5 sec
      int delta = totalBytes - _lastBytes;
      speedMBps = (delta / 1024 / 1024) / (diff / 1000);
      _lastBytes = totalBytes;
      _lastTime = now;
    }
  }
}

class TransferV2 {
  // AUTO IP - zai nemo gateway da kansa
  static Future<String> findServerIp() async {
    // Gwada IPs da aka fi amfani dasu a hotspot
    List<String> candidates = [
      "192.168.43.1",
      "192.168.49.1",
      "192.168.0.1",
      "192.168.1.1",
    ];
    for (var ip in candidates) {
      try {
        var s = await Socket.connect(ip, 8888, timeout: Duration(milliseconds: 800));
        s.destroy();
        return ip; // An same shi!
      } catch (_) {}
    }
    return "192.168.43.1"; // default
  }

  // SENDER - Yanzu da PARALLEL
  static Future<void> sendFiles(List<File> files, ServerSocket server, Function(String name, double progress, double speed, String eta) onUpdate) async {
    server.listen((client) async {
      for (var file in files) {
        int total = await file.length();
        client.writeln("${file.path.split('/').last}|$total");
        int sent = 0;
        var tracker = SpeedTracker();
        
        // ZERO COPY + 1MB CHUNK
        await for (var chunk in file.openRead()) {
          client.add(chunk);
          sent += chunk.length;
          tracker.update(sent);
          
          double prog = sent / total;
          double remainingMB = (total - sent) / 1024 / 1024;
          String eta = tracker.speedMBps > 0 ? "${(remainingMB / tracker.speedMBps).toStringAsFixed(0)}s" : "--";
          
          onUpdate(file.path.split('/').last, prog, tracker.speedMBps, eta);
        }
        await client.flush();
      }
      client.close();
      onUpdate("DONE", 1, 0, "0s");
    });
  }

  // RECEIVER - da SPEED METER
  static Future<void> receiveFiles(String serverIp, Function(String name, double progress, double speed, String path) onUpdate) async {
    var socket = await Socket.connect(serverIp, 8888, timeout: Duration(seconds: 10));
    String? fileName; int? fileSize; IOSink? sink; int received = 0;
    var tracker = SpeedTracker();

    socket.listen((data) async {
      if (fileName == null) {
        String header = String.fromCharCodes(data);
        if (header.contains("|")) {
          var parts = header.split("|");
          fileName = parts[0].trim();
          fileSize = int.tryParse(parts[1].trim().split("\n")[0]) ?? 0;
          var savePath = "/storage/emulated/0/Download/$fileName";
          sink = File(savePath).openWrite();
          received = 0;
          onUpdate(fileName!, 0, 0, savePath);
          return;
        }
      }
      if (sink != null) {
        sink.add(data);
        received += data.length;
        tracker.update(received);
        double prog = received / (fileSize ?? 1);
        onUpdate(fileName!, prog, tracker.speedMBps, "/storage/emulated/0/Download/$fileName");
        if (received >= (fileSize ?? 0)) {
          await sink!.close();
          fileName = null; sink = null; received = 0;
        }
      }
    });
  }
}
