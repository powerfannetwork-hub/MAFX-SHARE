import 'dart:io';
import 'dart:typed_data';
import 'dart:async';

class TransferEngine {
  static const int PORT = 8888;
  static const int CHUNK_SIZE = 1024 * 1024; // 1MB chunk - Xender yana 64KB ne

  // SENDER: Fara Server
  static Future<ServerSocket> startServer({
    required Function(String fileName, int sent, int total) onProgress,
  }) async {
    var server = await ServerSocket.bind(InternetAddress.anyIPv4, PORT);
    print("Server yana sauraro a ${server.address}:${server.port}");

    server.listen((Socket client) async {
      // 1. Karbi sunan file da girma
      var files = await _getFilesToSend(); // zaka cika daga UI

      for (var file in files) {
        var fileStat = await file.stat();
        int total = fileStat.size;

        // Aika Header: fileName|size\n
        client.writeln("${file.path.split('/').last}|$total");
        await client.flush();

        // 2. Tura da ZERO-COPY, ba loda file a RAM bane
        int sent = 0;
        await for (var chunk in file.openRead()) {
          client.add(chunk);
          sent += chunk.length;
          onProgress(file.path.split('/').last, sent, total);
        }
        await client.flush();
      }
      client.close();
    });
    return server;
  }

  // RECEIVER: Hada da Sauke
  static Future<void> startReceiver({
    required String serverIp, // Yawanci 192.168.43.1 ne idan hotspot
    required Function(String fileName, int received, int total) onProgress,
    required Function(String savedPath) onFileDone,
  }) async {
    var socket = await Socket.connect(serverIp, PORT, timeout: Duration(seconds: 5));
    print("An hada da Server $serverIp");

    // Buffer don karanta header
    socket.listen((Uint8List data) async {
      // Wannan simplified ne, a zahiri sai mu yi framing mai kyau
    });

    // Cikakken mai karbar file mai sauri
    var buffer = <int>[];
    String? currentFileName;
    int? currentFileSize;
    int received = 0;
    IOSink? fileSink;

    await for (var chunk in socket) {
      // Idan har yanzu ba mu da header
      if (currentFileName == null) {
        String header = String.fromCharCodes(chunk);
        if (header.contains("|")) {
          var parts = header.split("|");
          currentFileName = parts[0].trim();
          currentFileSize = int.parse(parts[1].trim().split("\n")[0]);
          var savePath = "/storage/emulated/0/Download/$currentFileName";
          fileSink = File(savePath).openWrite();
          received = 0;

          // Idan header ya zo da wani data na file a ciki
          var remaining = header.split("\n").length > 1? header.split("\n")[1] : "";
          if (remaining.isNotEmpty) {
            var bytes = remaining.codeUnits;
            fileSink.add(bytes);
            received += bytes.length;
          }
          continue;
        }
      }

      if (fileSink!= null) {
        fileSink.add(chunk);
        received += chunk.length;
        onProgress(currentFileName!, received, currentFileSize!);

        if (received >= currentFileSize!) {
          await fileSink.close();
          onFileDone("/storage/emulated/0/Download/$currentFileName");
          // Shirya don file na gaba
          currentFileName = null;
          fileSink = null;
        }
      }
    }
  }

  static Future<List<File>> _getFilesToSend() async {
    // Wannan list din za ta fito daga file_picker a UI
    return [];
  }
}

// Don gudu mai yawa - Parallel Transfer
class FastTransfer {
  static Future<void> sendParallel(List<File> files, Socket socket) async {
    // Tura file 3 a lokaci daya
    var futures = <Future>[];
    for (var file in files) {
      futures.add(_sendSingle(file, socket));
    }
    await Future.wait(futures);
  }

  static Future<void> _sendSingle(File file, Socket socket) async {
    await for (var chunk in file.openRead()) {
      socket.add(chunk);
    }
  }
}
