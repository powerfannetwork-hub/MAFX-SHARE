import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// MAFX SHARE parallel TCP file-transfer engine.
///
/// Protocol:
/// - Opens multiple TCP connections for parallel chunk transfer.
/// - Sends a 4-byte big-endian JSON-header length.
/// - Sends JSON metadata followed by the binary chunk.
/// - Validates each chunk using CRC32.
/// - Stores chunks separately and merges them in order.
///
/// Sender and receiver must use this same protocol.
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

  /// Selects chunk size based on file size.
  int chunkSizeFor(int fileSize) {
    if (fileSize > veryLargeFileThreshold) {
      return largeChunkSize;
    }

    if (fileSize > largeFileThreshold) {
      return mediumChunkSize;
    }

    return smallChunkSize;
  }

  /// Creates chunk descriptors without loading the whole file into memory.
  Future<List<MafxChunk>> splitFile(File file) async {
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', file.path);
    }

    final fileSize = await file.length();
    final size = chunkSizeFor(fileSize);
    final count = fileSize == 0 ? 1 : (fileSize + size - 1) ~/ size;
    final fileId = createFileId();

    return List<MafxChunk>.generate(count, (index) {
      final offset = index * size;
      final remaining = fileSize - offset;
      final length = fileSize == 0 ? 0 : min(size, remaining);

      return MafxChunk(
        fileId: fileId,
        chunkIndex: index,
        totalChunks: count,
        offset: offset,
        length: length,
        fileSize: fileSize,
      );
    });
  }

  /// Sends a file over multiple TCP connections.
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

    final defaultName = file.uri.pathSegments.isEmpty
        ? 'received_file'
        : file.uri.pathSegments.last;

    final actualName = _sanitizeName(fileName ?? defaultName);

    if (actualName.isEmpty) {
      throw const FormatException('Invalid file name.');
    }

    final progress = _ProgressCounter(fileSize, onProgress);

    var nextIndex = 0;
    final workerCount = min(parallelCount, chunks.length);

    Future<void> worker() async {
      while (true) {
        final index = nextIndex++;

        if (index >= chunks.length) {
          return;
        }

        await _sendOneChunk(
          file: file,
          receiverIp: receiverIp,
          port: port,
          fileName: actualName,
          token: token ?? '',
          chunk: chunks[index],
          connectTimeout: connectTimeout,
          transferTimeout: transferTimeout,
          progress: progress,
        );
      }
    }

    await Future.wait(
      List<Future<void>>.generate(
        workerCount,
        (_) => worker(),
      ),
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
    _SocketReader? reader;

    try {
      socket = await Socket.connect(
        receiverIp,
        port,
        timeout: connectTimeout,
      );

      reader = _SocketReader(socket);

      handle = await file.open(mode: FileMode.read);
      await handle.setPosition(chunk.offset);

      // Only this chunk is loaded into memory.
      final bytes = await handle.read(chunk.length);

      if (bytes.length != chunk.length) {
        throw FileSystemException(
          'Unable to read complete chunk ${chunk.chunkIndex}',
          file.path,
        );
      }

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
        'checksum': MafxChecksum.crc32(bytes),
      };

      final headerBytes = utf8.encode(jsonEncode(header));

      if (headerBytes.length > 64 * 1024) {
        throw const FormatException('Chunk header is too large.');
      }

      final prefix = ByteData(4)
        ..setUint32(0, headerBytes.length, Endian.big);

      socket.add(prefix.buffer.asUint8List());
      socket.add(headerBytes);
      socket.add(bytes);

      await socket.flush().timeout(transferTimeout);

      final response = await reader
          .readLine(maxLength: 64 * 1024)
          .timeout(transferTimeout);

      final decoded = jsonDecode(response);

      if (decoded is! Map<String, dynamic> ||
          decoded['success'] != true ||
          decoded['fileId'] != chunk.fileId ||
          decoded['chunkIndex'] != chunk.chunkIndex) {
        final message = decoded is Map
            ? decoded['error']?.toString()
            : null;

        throw FormatException(
          message ?? 'Receiver did not acknowledge the chunk.',
        );
      }

      progress.add(bytes.length);
    } finally {
      await handle?.close();
      await reader?.close();
      socket?.destroy();
    }
  }

  /// Starts a receiver. Use port 0 to request an available port.
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
    final bytes = List<int>.generate(
      16,
      (_) => random.nextInt(256),
    );

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
    final reader = _SocketReader(socket);

    try {
      final prefix = await reader.readExact(4);
      final headerLength = ByteData.sublistView(
        Uint8List.fromList(prefix),
      ).getUint32(0, Endian.big);

      if (headerLength == 0 || headerLength > 64 * 1024) {
        throw const FormatException('Invalid chunk header length.');
      }

      final headerBytes = await reader.readExact(headerLength);
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
          offset + chunkLength > fileSize ||
          chunkLength > 8 * 1024 * 1024) {
        throw const FormatException('Invalid chunk metadata.');
      }

      final data = await reader.readExact(chunkLength);

      if (MafxChecksum.crc32(data) != checksum) {
        throw const FormatException('Chunk checksum mismatch.');
      }

      final directory = await _getTempDirectory();
      final safeName = _sanitizeName(fileName);

      if (safeName.isEmpty) {
        throw const FormatException('Invalid file name.');
      }

      final incoming = _incoming.putIfAbsent(
        fileId,
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

      // If this was the final chunk, wait until merging succeeds
      // before acknowledging the chunk to the sender.
      final result = await incoming.mergeIfComplete();

      if (result != null) {
        _incoming.remove(fileId);
        onFileReceived?.call(result);
      }

      final ack = jsonEncode({
        'success': true,
        'fileId': fileId,
        'chunkIndex': chunkIndex,
      });

      socket.write('$ack\n');
      await socket.flush();
    } catch (error) {
      final response = jsonEncode({
        'success': false,
        'error': error.toString(),
      });

      try {
        socket.write('$response\n');
        await socket.flush();
      } catch (_) {
        // Socket may already be closed.
      }
    } finally {
      await reader.close();
      socket.destroy();
    }
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

  Future<File>? _mergeFuture;

  bool get isComplete => _received.length == totalChunks;

  Future<void> writeChunk({
    required int index,
    required int offset,
    required List<int> bytes,
  }) async {
    final operation = _writeQueue.then((_) async {
      if (_received.contains(index)) {
        throw const FormatException('Duplicate chunk received.');
      }

      if (index < 0 || index >= totalChunks) {
        throw const FormatException('Chunk index is out of range.');
      }

      if (offset < 0 || offset + bytes.length > fileSize) {
        throw const FormatException('Chunk range is invalid.');
      }

      final path =
          '${directory.path}${Platform.pathSeparator}'
          'mafx_${fileId}_$index.part';

      final chunkFile = File(path);

      await chunkFile.writeAsBytes(bytes, flush: true);

      _chunkPaths[index] = path;
      _received.add(index);
    });

    // Recover the queue if this operation fails, while preserving
    // the original error for the caller awaiting "operation".
    _writeQueue = operation.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    );

    await operation;
  }

  /// Merges once all chunks have arrived.
  ///
  /// Only the first caller receives the completed file.
  /// Other concurrent callers wait for merging and receive null.
  Future<File?> mergeIfComplete() async {
    await _writeQueue;

    if (!isComplete) {
      return null;
    }

    final existing = _mergeFuture;

    if (existing != null) {
      await existing;
      return null;
    }

    final future = merge();
    _mergeFuture = future;

    return await future;
  }

  Future<File> merge() async {
    await _writeQueue;

    if (!isComplete) {
      throw StateError('Cannot merge an incomplete file.');
    }

    final outputPath =
        '${directory.path}${Platform.pathSeparator}'
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
    } catch (_) {
      await sink.close();

      if (await output.exists()) {
        await output.delete();
      }

      rethrow;
    } finally {
      // The sink is closed in the catch block on failure.
      // On success, close it here.
      // File length is checked after closing.
    }

    await sink.close();

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
    for (final path in _chunkPaths.values) {
      try {
        final file = File(path);

        if (await file.exists()) {
          await file.delete();
        }
      } catch (_) {
        // Best-effort cleanup.
      }
    }

    _chunkPaths.clear();
    _received.clear();
  }
}

/// Maintains a single subscription to the TCP stream while reading
/// exact byte counts or newline-delimited responses.
class _SocketReader {
  _SocketReader(Socket socket)
      : _iterator = StreamIterator<List<int>>(socket);

  final StreamIterator<List<int>> _iterator;

  List<int> _buffer = <int>[];
  int _offset = 0;
  bool _closed = false;

  Future<int> _nextByte() async {
    while (_offset >= _buffer.length) {
      if (!await _iterator.moveNext()) {
        throw const SocketException('Unexpected end of socket stream.');
      }

      _buffer = _iterator.current;
      _offset = 0;
    }

    return _buffer[_offset++];
  }

  Future<List<int>> readExact(int count) async {
    if (count < 0) {
      throw ArgumentError.value(count, 'count');
    }

    if (count == 0) return <int>[];

    final result = Uint8List(count);

    for (var index = 0; index < count; index++) {
      result[index] = await _nextByte();
    }

    return result;
  }

  Future<String> readLine({int maxLength = 64 * 1024}) async {
    final builder = BytesBuilder(copy: false);

    while (true) {
      final byte = await _nextByte();

      if (byte == 10) {
        return utf8.decode(builder.takeBytes());
      }

      if (byte != 13) {
        if (builder.length >= maxLength) {
          throw const FormatException('Socket line is too long.');
        }

        builder.addByte(byte);
      }
    }
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;

    await _iterator.cancel();
  }
}

String _sanitizeName(String input) {
  final name = input.replaceAll('\\', '/').split('/').last.trim();

  return name.replaceAll(
    RegExp(r'[\x00-\x1F<>:"|?*]'),
    '',
  );
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
