import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// MAFX SHARE parallel file-transfer engine.
///
/// Protocol overview:
/// - A sender opens up to six TCP connections.
/// - Each connection sends a distinct chunk.
/// - Each chunk contains JSON metadata followed by binary data.
/// - The receiver validates CRC32 and writes chunks to temporary files.
/// - Chunks are merged in their original order.
///
/// Both sender and receiver must use this protocol.
class MafxTransferEngine {
MafxTransferEngine({
this.parallelCount = 6,
this.smallChunkSize = 1024 * 1024,
this.mediumChunkSize = 4 * 1024 * 1024,
this.largeChunkSize = 8 * 1024 * 1024,
this.parallelThreshold = 10 * 1024 * 1024,
this.largeFileThreshold = 100 * 1024 * 1024,
this.veryLargeFileThreshold = 1024 * 1024 * 1024,
}) : assert(parallelCount > 0);

final int parallelCount;
final int smallChunkSize;
final int mediumChunkSize;
final int largeChunkSize;
final int parallelThreshold;
final int largeFileThreshold;
final int veryLargeFileThreshold;

/// Selects a chunk size according to file size.
int chunkSizeFor(int fileSize) {
if (fileSize < parallelThreshold) {
return smallChunkSize;
}
if (fileSize > veryLargeFileThreshold) {
return largeChunkSize;
}
if (fileSize > largeFileThreshold) {
return largeChunkSize;
}
return mediumChunkSize;
}

/// Splits a file into metadata descriptors without loading its contents
/// into memory. Actual bytes are read only when sending each chunk.
Future<List<MafxChunk>> splitFile(File file) async {
if (!await file.exists()) {
throw FileSystemException('File does not exist', file.path);
}

final length = await file.length();
final size = chunkSizeFor(length);
final count = length == 0 ? 1 : (length + size - 1) ~/ size;
final fileId = _createFileId();

return List<MafxChunk>.generate(count, (index) {
  final offset = index * size;
  final remaining = length - offset;
  final bytes = length == 0 ? 0 : min(size, remaining);

  return MafxChunk(
    fileId: fileId,
    chunkIndex: index,
    totalChunks: count,
    offset: offset,
    length: bytes,
    fileSize: length,
  );
});

}

/// Sends a file using multiple TCP connections.
///
/// [receiverIp] may be an IP address or a host name.
/// [port] must point to a receiver implementing this engine's protocol.
///
/// The optional [onProgress] callback reports bytes sent and total bytes.
Future<void> sendFileParallel(
File file,
String receiverIp, {
required int port,
String? fileName,
String? token,
void Function(int sentBytes, int totalBytes)? onProgress,
Duration connectTimeout = const Duration(seconds: 15),
Duration transferTimeout = const Duration(minutes: 30),
}) async {
if (port < 1 || port > 65535) {
throw ArgumentError.value(port, 'port', 'Invalid TCP port');
}
if (!await file.exists()) {
throw FileSystemException('File does not exist', file.path);
}

final chunks = await splitFile(file);
final fileSize = await file.length();
final name = fileName ?? file.uri.pathSegments.last;
final actualToken = token ?? '';
final progress = _ProgressCounter(fileSize, onProgress);

// Each worker takes a different chunk index.
var nextIndex = 0;
final workers = min(parallelCount, chunks.length);

Future<void> worker() async {
  while (true) {
    final index = nextIndex++;
    if (index >= chunks.length) return;

    final chunk = chunks[index];
    await _sendOneChunk(
      file: file,
      receiverIp: receiverIp,
      port: port,
      fileName: name,
      token: actualToken,
      chunk: chunk,
      connectTimeout: connectTimeout,
      transferTimeout: transferTimeout,
      progress: progress,
    );
  }
}

await Future.wait(
  List<Future<void>>.generate(workers, (_) => worker()),
);

}

Future<void> _sendOneChunk({
required File file,
required String receiverIp,
required int port,
required String fileName,
required String token,
required MafxChunk chunk,
required Duration connectTimeout,
required Duration transferTimeout,
required _ProgressCounter progress,
}) async {
Socket? socket;
RandomAccessFile? handle;

try {
  socket = await Socket.connect(
    receiverIp,
    port,
    timeout: connectTimeout,
  );

  handle = await file.open(mode: FileMode.read);
  await handle.setPosition(chunk.offset);

  final bytes = await handle.read(chunk.length);
  if (bytes.length != chunk.length) {
    throw FileSystemException(
      'Unable to read complete chunk ${chunk.chunkIndex}',
      file.path,
    );
  }

  final checksum = MafxChecksum.crc32(bytes);

  final header = <String, dynamic>{
    'protocol': 'MAFX_CHUNK_V1',
    'fileId': chunk.fileId,
    'fileName': fileName,
    'token': token,
    'chunkIndex': chunk.chunkIndex,
    'totalChunks': chunk.totalChunks,
    'fileSize': chunk.fileSize,
    'offset': chunk.offset,
    'chunkLength': chunk.length,
    'checksum': checksum,
  };

  final headerBytes = utf8.encode(jsonEncode(header));

  // Four-byte big-endian header length, then JSON header, then data.
  final prefix = ByteData(4)
    ..setUint32(0, headerBytes.length, Endian.big);

  socket.add(prefix.buffer.asUint8List());
  socket.add(headerBytes);
  socket.add(bytes);
  await socket.flush().timeout(transferTimeout);

  // The receiver must reply with a newline-terminated JSON ACK.
  final response = await _readLine(socket)
      .timeout(transferTimeout);

  final ack = jsonDecode(response);
  if (ack is! Map<String, dynamic> ||
      ack['success'] != true ||
      ack['fileId'] != chunk.fileId ||
      ack['chunkIndex'] != chunk.chunkIndex) {
    throw const FormatException(
      'Receiver did not acknowledge the chunk.',
    );
  }

  progress.add(bytes.length);
} finally {
  await handle?.close();
  socket?.destroy();
}

}

Future<String> _readLine(Socket socket) async {
final completer = Completer<String>();
final buffer = BytesBuilder(copy: false);
late StreamSubscription<List<int>> subscription;

subscription = socket.listen(
  (data) {
    for (final byte in data) {
      if (byte == 10) {
        if (!completer.isCompleted) {
          completer.complete(utf8.decode(buffer.takeBytes()));
        }
        subscription.cancel();
        return;
      }
      buffer.addByte(byte);
    }
  },
  onError: (Object error, StackTrace stackTrace) {
    if (!completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  },
  onDone: () {
    if (!completer.isCompleted) {
      completer.completeError(
        const SocketException('Receiver closed before ACK.'),
      );
    }
  },
  cancelOnError: true,
);

return completer.future;

}

/// Starts a TCP receiver on [port].
///
/// The receiver accepts concurrent chunk connections, validates each
/// chunk's CRC32, stores it in a temporary file, and merges chunks when
/// all chunks for that file have arrived.
Future<MafxReceiver> startReceiver({
required int port,
String bindAddress = '0.0.0.0',
String? expectedToken,
String? outputDirectory,
void Function(File file)? onFileReceived,
}) async {
final server = await ServerSocket.bind(
bindAddress,
port,
shared: true,
);

final receiver = MafxReceiver._(
  server: server,
  expectedToken: expectedToken,
  outputDirectory: outputDirectory,
  onFileReceived: onFileReceived,
);

receiver._start();
return receiver;

}

String createFileId() {
final random = Random.secure();
final bytes = List<int>.generate(16, () => random.nextInt(256));
return base64UrlEncode(bytes).replaceAll('=', '');
}
}

class MafxChunk {
const MafxChunk({
required this.fileId,
required this.chunkIndex,
required this.totalChunks,
required this.offset,
required this.length,
required this.fileSize,
});

final String fileId;
final int chunkIndex;
final int totalChunks;
final int offset;
final int length;
final int fileSize;
}

class MafxChecksum {
MafxChecksum._();

static final List<int> _table = List<int>.generate(256, (index) {
var value = index;
for (var bit = 0; bit < 8; bit++) {
value = (value & 1) != 0
? (value >> 1) ^ 0xEDB88320
: value >> 1;
}
return value & 0xFFFFFFFF;
});

/// Returns an unsigned CRC32 checksum.
static int crc32(List<int> bytes) {
var crc = 0xFFFFFFFF;

for (final byte in bytes) {
  crc = _table[(crc ^ byte) & 0xFF] ^ (crc >> 8);
}

return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;

}
}

class MafxReceiver {
MafxReceiver._({
required ServerSocket server,
required this.expectedToken,
required this.outputDirectory,
required this.onFileReceived,
}) : _server = server;

final ServerSocket _server;
final String? expectedToken;
final String? outputDirectory;
final void Function(File file)? onFileReceived;

final Map<String, _IncomingFile> _incoming = {};
bool _closed = false;

int get port => _server.port;

void _start() {
_server.listen(
(socket) {
unawaited(_handleSocket(socket));
},
onError: (Object error, StackTrace stackTrace) {
stderr.writeln('MAFX receiver server error: $error');
},
);
}

Future<void> _handleSocket(Socket socket) async {
try {
final headerLengthBytes = await _readExact(socket, 4);
final headerLength = ByteData.sublistView(
Uint8List.fromList(headerLengthBytes),
).getUint32(0, Endian.big);

  if (headerLength == 0 || headerLength > 64 * 1024) {
    throw const FormatException('Invalid chunk header length.');
  }

  final headerBytes = await _readExact(socket, headerLength);
  final decoded = jsonDecode(utf8.decode(headerBytes));

  if (decoded is! Map<String, dynamic> ||
      decoded['protocol'] != 'MAFX_CHUNK_V1') {
    throw const FormatException('Invalid chunk protocol.');
  }

  final header = decoded;
  final token = header['token'];

  if (expectedToken != null && token != expectedToken) {
    throw const FormatException('Invalid session token.');
  }

  final fileId = header['fileId'];
  final fileName = header['fileName'];
  final chunkIndex = header['chunkIndex'];
  final totalChunks = header['totalChunks'];
  final fileSize = header['fileSize'];
  final offset = header['offset'];
  final chunkLength = header['chunkLength'];
  final checksum = header['checksum'];

  if (fileId is! String ||
      fileId.isEmpty ||
      fileName is! String ||
      fileName.isEmpty ||
      chunkIndex is! int ||
      totalChunks is! int ||
      fileSize is! int ||
      offset is! int ||
      chunkLength is! int ||
      checksum is! int ||
      totalChunks < 1 ||
      chunkIndex < 0 ||
      chunkIndex >= totalChunks ||
      fileSize < 0 ||
      offset < 0 ||
      chunkLength < 0 ||
      offset + chunkLength > fileSize) {
    throw const FormatException('Invalid chunk metadata.');
  }

  final data = await _readExact(socket, chunkLength);
  if (MafxChecksum.crc32(data) != checksum) {
    throw const FormatException('Chunk checksum mismatch.');
  }

  final directory = await _getTempDirectory();
  final safeName = _sanitizeName(fileName);
  final key = fileId;

  final incoming = _incoming.putIfAbsent(
    key,
    () => _IncomingFile(
      fileId: fileId,
      fileName: safeName,
      totalChunks: totalChunks,
      fileSize: fileSize,
      directory: directory,
    ),
  );

  if (incoming.fileName != safeName ||
      incoming.totalChunks != totalChunks ||
      incoming.fileSize != fileSize) {
    throw const FormatException(
      'Chunk metadata conflicts with the existing transfer.',
    );
  }

  await incoming.writeChunk(
    index: chunkIndex,
    offset: offset,
    bytes: data,
  );

  final ack = jsonEncode({
    'success': true,
    'fileId': fileId,
    'chunkIndex': chunkIndex,
  });

  socket.write('$ack\n');
  await socket.flush();

  if (incoming.isComplete) {
    final result = await incoming.merge();
    _incoming.remove(key);
    onFileReceived?.call(result);
  }
} catch (error) {
  final response = jsonEncode({
    'success': false,
    'error': error.toString(),
  });
  try {
    socket.write('$response\n');
    await socket.flush();
  } catch (_) {
    // The socket may already have closed.
  }
} finally {
  socket.destroy();
}

}

Future<List<int>> _readExact(Socket socket, int count) async {
if (count == 0) return <int>[];

final builder = BytesBuilder(copy: false);
final completer = Completer<List<int>>();
var received = 0;

late StreamSubscription<List<int>> subscription;

subscription = socket.listen(
  (data) {
    if (completer.isCompleted) return;

    final remaining = count - received;
    final take = min(remaining, data.length);

    builder.add(data.sublist(0, take));
    received += take;

    if (received == count) {
      completer.complete(builder.takeBytes());
      subscription.cancel();
    }
  },
  onError: (Object error, StackTrace stackTrace) {
    if (!completer.isCompleted) {
      completer.completeError(error, stackTrace);
    }
  },
  onDone: () {
    if (!completer.isCompleted) {
      completer.completeError(
        const SocketException('Unexpected end of chunk stream.'),
      );
    }
  },
  cancelOnError: true,
);

return completer.future;

}

Future<Directory> _getTempDirectory() async {
if (outputDirectory != null) {
final directory = Directory(outputDirectory!);
await directory.create(recursive: true);
return directory;
}

final directory = await getApplicationDocumentsDirectory();
await directory.create(recursive: true);
return directory;

}

String sanitizeName(String input) {
final name = input.replaceAll('\', '/').split('/').last.trim();
return name.replaceAll(RegExp(r'[\x00-\x1F<>:"|?*]'), '');
}

Future<void> close() async {
if (_closed) return;
_closed = true;

await _server.close();

for (final incoming in _incoming.values) {
  await incoming.cleanup();
}
_incoming.clear();

}
}

class _IncomingFile {
_IncomingFile({
required this.fileId,
required this.fileName,
required this.totalChunks,
required this.fileSize,
required this.directory,
});

final String fileId;
final String fileName;
final int totalChunks;
final int fileSize;
final Directory directory;

final Map<int, String> _chunkPaths = {};
final Set<int> _received = {};
Future<void> _writeQueue = Future<void>.value();

bool get isComplete => _received.length == totalChunks;

Future<void> writeChunk({
required int index,
required int offset,
required List<int> bytes,
}) async {
if (_received.contains(index)) {
throw const FormatException('Duplicate chunk received.');
}

final path = '${directory.path}${Platform.pathSeparator}'
    'mafx_$fileId.$index.part';

// Serialize metadata updates so simultaneous connections cannot mark
// the same chunk as complete twice.
final completer = Completer<void>();

_writeQueue = _writeQueue.then((_) async {
  final file = File(path);
  await file.writeAsBytes(bytes, flush: true);
  _chunkPaths[index] = path;
  _received.add(index);
  completer.complete();
}).catchError((Object error, StackTrace stackTrace) {
  if (!completer.isCompleted) {
    completer.completeError(error, stackTrace);
  }
});

await completer.future;

}

Future<File> merge() async {
if (!isComplete) {
throw StateError('Cannot merge an incomplete file.');
}

final outputPath = '${directory.path}${Platform.pathSeparator}'
    'mafx_received_${DateTime.now().microsecondsSinceEpoch}_$fileName';

final output = File(outputPath);
final sink = output.openWrite();

try {
  for (var index = 0; index < totalChunks; index++) {
    final path = _chunkPaths[index];
    if (path == null) {
      throw StateError('Missing chunk $index.');
    }

    await sink.addStream(File(path).openRead());
  }

  await sink.flush();
} finally {
  await sink.close();
}

final mergedLength = await output.length();
if (mergedLength != fileSize) {
  await output.delete();
  throw const FormatException(
    'Merged file size does not match expected size.',
  );
}

await cleanup();
return output;

}

Future<void> cleanup() async {
for (final path in chunkPaths.values) {
try {
final file = File(path);
if (await file.exists()) await file.delete();
} catch () {
// Best-effort cleanup.
}
}
_chunkPaths.clear();
_received.clear();
}
}

class _ProgressCounter {
_ProgressCounter(this.totalBytes, this.onProgress);

final int totalBytes;
final void Function(int sentBytes, int totalBytes)? onProgress;
int _sentBytes = 0;

void add(int bytes) {
_sentBytes += bytes;
onProgress?.call(_sentBytes, totalBytes);
}
}
