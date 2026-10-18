import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/mafx_transfer_engine.dart';

class TransferService {
  TransferService._();

  static final TransferService instance = TransferService._();

  static const String _historyKey = 'mafx_transfer_history';
  static const int _maxHistoryEntries = 100;
  static const String _receivedPrefix = 'mafx_received_';

  static const String standardMode = 'STANDARD';
  static const String highSpeedMode = '5G_PLUS';

  static const Duration _connectionTimeout = Duration(seconds: 5);
  static const Duration _sendConnectionTimeout = Duration(seconds: 15);
  static const Duration _standardTransferTimeout = Duration(minutes: 10);
  static const Duration _highSpeedTransferTimeout = Duration(minutes: 30);

  static const int _standardChunkSize = 64 * 1024;
  static const int _highSpeedChunkSize = 1024 * 1024;

  final MafxTransferEngine _engine = MafxTransferEngine(
    parallelCount: 6,
  );

  HttpServer? _server;
  MafxReceiver? _tcpReceiver;

  String? _sessionToken;
  String? _activeMode;

  Future<int>? _startingReceiver;
  HttpClient? _sendClient;

  bool get isServerRunning => _server != null;

  String? get sessionToken => _sessionToken;

  String? get activeMode => _activeMode;

  int? get port => _server?.port;

  int? get tcpPort => _tcpReceiver?.port;

  bool get isTcpReceiverRunning => _tcpReceiver != null;

  bool _isValidMode(String mode) {
    return mode == standardMode || mode == highSpeedMode;
  }

  Duration _timeoutForMode(String mode) {
    return mode == highSpeedMode
        ? _highSpeedTransferTimeout
        : _standardTransferTimeout;
  }

  int _chunkSizeForMode(String mode) {
    return mode == highSpeedMode
        ? _highSpeedChunkSize
        : _standardChunkSize;
  }

  HttpClient _getSendClient() {
    final existing = _sendClient;

    if (existing != null) {
      return existing;
    }

    final client = HttpClient()
      ..connectionTimeout = _sendConnectionTimeout
      ..maxConnectionsPerHost = 4
      ..idleTimeout = const Duration(seconds: 30);

    _sendClient = client;
    return client;
  }

  /// Authenticates with a receiver before allowing file transfers.
  ///
  /// The receiver must provide its HTTP URL and current session token.
  /// The selected mode is validated by the receiver before the connection
  /// is considered successful.
  Future<bool> connectToReceiver({
    required String receiverUrl,
    required String token,
    required String mode,
  }) async {
    if (token.trim().isEmpty || !_isValidMode(mode)) {
      return false;
    }

    final Uri uri;

    try {
      uri = Uri.parse(receiverUrl);
    } catch (_) {
      return false;
    }

    if (uri.scheme != 'http' ||
        uri.host.isEmpty ||
        uri.port < 1 ||
        uri.port > 65535) {
      return false;
    }

    final client = _getSendClient();

    try {
      final verifyRequest = await client
          .post(
            uri.replace(path: '/verify', query: null, fragment: null),
          )
          .timeout(_connectionTimeout);

      verifyRequest.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set(HttpHeaders.acceptHeader, 'application/json');

      verifyRequest.write(jsonEncode({'token': token}));

      final verifyResponse = await verifyRequest
          .close()
          .timeout(_connectionTimeout);

      final verifyText = await utf8.decoder
          .bind(verifyResponse)
          .join()
          .timeout(_connectionTimeout);

      if (verifyResponse.statusCode < 200 ||
          verifyResponse.statusCode >= 300) {
        return false;
      }

      final verifyData = jsonDecode(verifyText);

      if (verifyData is! Map<String, dynamic> ||
          verifyData['success'] != true ||
          verifyData['verified'] != true) {
        return false;
      }

      final modeRequest = await client
          .post(
            uri.replace(path: '/mode', query: null, fragment: null),
          )
          .timeout(_connectionTimeout);

      modeRequest.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set(HttpHeaders.acceptHeader, 'application/json');

      modeRequest.write(
        jsonEncode({
          'token': token,
          'mode': mode,
        }),
      );

      final modeResponse = await modeRequest
          .close()
          .timeout(_connectionTimeout);

      final modeText = await utf8.decoder
          .bind(modeResponse)
          .join()
          .timeout(_connectionTimeout);

      if (modeResponse.statusCode < 200 ||
          modeResponse.statusCode >= 300) {
        return false;
      }

      final modeData = jsonDecode(modeText);

      if (modeData is! Map<String, dynamic> ||
          modeData['success'] != true ||
          modeData['mode'] != mode) {
        return false;
      }

      _activeMode = mode;
      return true;
    } on TimeoutException catch (error) {
      debugPrint('Receiver authentication timed out: $error');
      return false;
    } on SocketException catch (error) {
      debugPrint('Unable to reach receiver: $error');
      return false;
    } on HttpException catch (error) {
      debugPrint('Receiver HTTP error: $error');
      return false;
    } on FormatException catch (error) {
      debugPrint('Invalid receiver response: $error');
      return false;
    } catch (error, stackTrace) {
      debugPrint('Receiver authentication failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    }
  }

  Future<int> startReceiver() {
    final existingServer = _server;

    if (existingServer != null) {
      return Future<int>.value(existingServer.port);
    }

    final existingStart = _startingReceiver;

    if (existingStart != null) {
      return existingStart;
    }

    final future = _startReceiverInternal();
    _startingReceiver = future;

    return future.whenComplete(() {
      if (identical(_startingReceiver, future)) {
        _startingReceiver = null;
      }
    });
  }

  Future<int> _startReceiverInternal() async {
    final random = Random.secure();

    final tokenBytes = List<int>.generate(
      32,
      (_) => random.nextInt(256),
    );

    final token = base64UrlEncode(tokenBytes).replaceAll('=', '');

    HttpServer? server;
    MafxReceiver? tcpReceiver;

    try {
      server = await HttpServer.bind(
        InternetAddress.anyIPv4,
        0,
        shared: false,
      );

      final directory = await getApplicationDocumentsDirectory();
      await directory.create(recursive: true);

      tcpReceiver = await _engine.startReceiver(
        port: 0,
        bindAddress: '0.0.0.0',
        expectedToken: token,
        outputDirectory: directory.path,
        onFileReceived: (file) {
          unawaited(_recordTcpReceivedFile(file));
        },
      );

      _sessionToken = token;
      _activeMode = null;
      _server = server;
      _tcpReceiver = tcpReceiver;

      unawaited(_handleRequests(server));

      debugPrint(
        'MAFX SHARE HTTP receiver started on port ${server.port}',
      );
      debugPrint(
        'MAFX SHARE TCP receiver started on port ${tcpReceiver.port}',
      );

      return server.port;
    } catch (error, stackTrace) {
      debugPrint('Unable to start receiver: $error');
      debugPrintStack(stackTrace: stackTrace);

      try {
        await server?.close(force: true);
      } catch (_) {}

      try {
        await tcpReceiver?.close();
      } catch (_) {}

      _sessionToken = null;
      _activeMode = null;
      _server = null;
      _tcpReceiver = null;

      rethrow;
    }
  }

  Future<void> _recordTcpReceivedFile(File file) async {
    try {
      if (!await file.exists()) return;

      final bytes = await file.length();
      final fileName = getReceivedFileName(file);

      await recordTransfer(
        fileName: fileName,
        direction: 'received',
        bytes: bytes,
      );

      debugPrint(
        'MAFX SHARE received $fileName ($bytes bytes, TCP)',
      );
    } catch (error, stackTrace) {
      debugPrint('Unable to record received TCP file: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _handleRequests(HttpServer server) async {
    try {
      await for (final request in server) {
        unawaited(_handleRequest(request));
      }
    } catch (error, stackTrace) {
      debugPrint('MAFX HTTP server error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _handleRequest(HttpRequest request) async {
    try {
      request.response.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set(HttpHeaders.cacheControlHeader, 'no-store')
        ..set('Access-Control-Allow-Origin', '*')
        ..set(
          'Access-Control-Allow-Methods',
          'GET, POST, OPTIONS',
        )
        ..set(
          'Access-Control-Allow-Headers',
          'Content-Type, Authorization',
        );

      if (request.method == 'OPTIONS') {
        request.response.statusCode = HttpStatus.noContent;
        await request.response.close();
        return;
      }

      final path = request.uri.path;

      if (request.method == 'GET' &&
          (path == '/health' || path == '/')) {
        await _writeJson(request.response, {
          'success': true,
          'app': 'MAFX SHARE',
          'status': 'ready',
          'httpPort': port,
          'tcpPort': tcpPort,
        });
        return;
      }

      if (request.method == 'GET' && path == '/info') {
        await _writeJson(request.response, {
          'success': true,
          'app': 'MAFX SHARE',
          'httpPort': port,
          'tcpPort': tcpPort,
          'modes': [standardMode, highSpeedMode],
        });
        return;
      }

      if (request.method == 'POST' && path == '/mode') {
        final body = await _readJsonBody(request);

        final mode = body['mode'];
        final token = body['token'];

        if (mode is! String || !_isValidMode(mode)) {
          await _writeError(
            request.response,
            HttpStatus.badRequest,
            'Invalid transfer mode.',
          );
          return;
        }

        if (!_isValidToken(token)) {
          await _writeError(
            request.response,
            HttpStatus.unauthorized,
            'Invalid session token.',
          );
          return;
        }

        _activeMode = mode;

        await _writeJson(request.response, {
          'success': true,
          'mode': mode,
          'chunkSize': _chunkSizeForMode(mode),
          'tcpPort': tcpPort,
        });
        return;
      }

      if (request.method == 'POST' && path == '/verify') {
        final body = await _readJsonBody(request);

        if (!_isValidToken(body['token'])) {
          await _writeError(
            request.response,
            HttpStatus.unauthorized,
            'Invalid session token.',
          );
          return;
        }

        await _writeJson(request.response, {
          'success': true,
          'verified': true,
          'tcpPort': tcpPort,
          'mode': _activeMode,
        });
        return;
      }

      if (request.method == 'POST' && path == '/stop') {
        final body = await _readJsonBody(request);

        if (!_isValidToken(body['token'])) {
          await _writeError(
            request.response,
            HttpStatus.unauthorized,
            'Invalid session token.',
          );
          return;
        }

        await _writeJson(request.response, {
          'success': true,
          'message': 'Receiver will stop.',
        });

        unawaited(
          Future<void>.delayed(
            const Duration(milliseconds: 150),
            stopReceiver,
          ),
        );
        return;
      }

      if (request.method == 'POST' && path == '/upload') {
        await _handleUpload(request);
        return;
      }

      await _writeError(
        request.response,
        HttpStatus.notFound,
        'Endpoint not found.',
      );
    } catch (error, stackTrace) {
      debugPrint('Request handling failed: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!request.response.headersSent) {
        await _writeError(
          request.response,
          HttpStatus.internalServerError,
          'Request could not be completed.',
        );
      } else {
        try {
          await request.response.close();
        } catch (_) {}
      }
    }
  }

  Future<void> _handleUpload(HttpRequest request) async {
    final authorization = request.headers.value('authorization');

    final suppliedToken = authorization?.startsWith('Bearer ') == true
        ? authorization!.substring(7)
        : request.uri.queryParameters['token'];

    if (!_isValidToken(suppliedToken)) {
      await _writeError(
        request.response,
        HttpStatus.unauthorized,
        'Invalid session token.',
      );
      return;
    }

    final rawFileName =
        request.headers.value('x-file-name') ??
        request.uri.queryParameters['name'] ??
        'received_file';

    final fileName = _sanitizeFileName(rawFileName);

    if (fileName.isEmpty) {
      await _writeError(
        request.response,
        HttpStatus.badRequest,
        'Invalid file name.',
      );
      return;
    }

    final directory = await getApplicationDocumentsDirectory();
    await directory.create(recursive: true);

    final output = File(
      '${directory.path}${Platform.pathSeparator}'
      '$_receivedPrefix'
      '${DateTime.now().microsecondsSinceEpoch}_$fileName',
    );

    final sink = output.openWrite();
    var totalBytes = 0;

    try {
      await for (final data in request) {
        totalBytes += data.length;
        sink.add(data);
      }

      await sink.flush();
      await sink.close();

      await recordTransfer(
        fileName: fileName,
        direction: 'received',
        bytes: totalBytes,
      );

      await _writeJson(request.response, {
        'success': true,
        'fileName': fileName,
        'bytes': totalBytes,
      });
    } catch (_) {
      try {
        await sink.close();
      } catch (_) {}

      try {
        if (await output.exists()) {
          await output.delete();
        }
      } catch (_) {}

      rethrow;
    }
  }

  Future<Map<String, dynamic>> _readJsonBody(
    HttpRequest request,
  ) async {
    final text = await utf8.decoder.bind(request).join();

    if (text.isEmpty) {
      return <String, dynamic>{};
    }

    final decoded = jsonDecode(text);

    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Expected a JSON object.');
    }

    return decoded;
  }

  bool _isValidToken(Object? token) {
    final expected = _sessionToken;

    return expected != null &&
        token is String &&
        token.isNotEmpty &&
        token == expected;
  }

  Future<void> _writeJson(
    HttpResponse response,
    Map<String, dynamic> body,
  ) async {
    response.statusCode = HttpStatus.ok;
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _writeError(
    HttpResponse response,
    int statusCode,
    String message,
  ) async {
    response.statusCode = statusCode;
    response.write(
      jsonEncode({
        'success': false,
        'error': message,
      }),
    );
    await response.close();
  }

  Future<void> stopReceiver() async {
    final server = _server;
    final tcpReceiver = _tcpReceiver;

    _server = null;
    _tcpReceiver = null;
    _sessionToken = null;
    _activeMode = null;

    try {
      await server?.close(force: true);
    } catch (error) {
      debugPrint('HTTP receiver close error: $error');
    }

    try {
      await tcpReceiver?.close();
    } catch (error) {
      debugPrint('TCP receiver close error: $error');
    }
  }

  /// Sends a file using the TCP engine in high-speed mode.
  Future<void> sendFileHighSpeed({
    required File file,
    required String receiverIp,
    required int receiverPort,
    required String token,
    String? fileName,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', file.path);
    }

    if (receiverPort < 1 || receiverPort > 65535) {
      throw ArgumentError.value(
        receiverPort,
        'receiverPort',
        'Invalid TCP port',
      );
    }

    if (token.isEmpty) {
      throw const FormatException('Session token is required.');
    }

    await _engine.sendFileParallel(
      file,
      receiverIp,
      port: receiverPort,
      fileName: fileName,
      token: token,
      onProgress: onProgress,
      connectTimeout: _sendConnectionTimeout,
      transferTimeout: _highSpeedTransferTimeout,
    );

    await recordTransfer(
      fileName: fileName ?? getReceivedFileName(file),
      direction: 'sent',
      bytes: await file.length(),
    );
  }

  /// Sends a file using HTTP upload.
  Future<void> sendFileStandard({
    required File file,
    required String receiverIp,
    required int receiverPort,
    required String token,
    String? fileName,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    if (!await file.exists()) {
      throw FileSystemException('File does not exist', file.path);
    }

    if (receiverPort < 1 || receiverPort > 65535) {
      throw ArgumentError.value(
        receiverPort,
        'receiverPort',
        'Invalid HTTP port',
      );
    }

    if (token.isEmpty) {
      throw const FormatException('Session token is required.');
    }

    final client = _getSendClient();
    final size = await file.length();

    final name = _sanitizeFileName(
      fileName ?? getReceivedFileName(file),
    );

    if (name.isEmpty) {
      throw const FormatException(
        'Invalid file name. Please select the file again.',
      );
    }

    final request = await client
        .post(
          Uri(
            scheme: 'http',
            host: receiverIp,
            port: receiverPort,
            path: '/upload',
          ),
        )
        .timeout(_connectionTimeout);

    request.headers
      ..set(
        HttpHeaders.contentTypeHeader,
        'application/octet-stream',
      )
      ..set(HttpHeaders.contentLengthHeader, size)
      ..set(
        HttpHeaders.authorizationHeader,
        'Bearer $token',
      )
      ..set('x-file-name', name);

    var sentBytes = 0;

    final stream = file.openRead().transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (data, sink) {
          sentBytes += data.length;
          onProgress?.call(sentBytes, size);
          sink.add(data);
        },
      ),
    );

    await request.addStream(stream);

    final response = await request.close().timeout(
      _standardTransferTimeout,
    );

    final responseText = await utf8.decoder
        .bind(response)
        .join()
        .timeout(_standardTransferTimeout);

    if (response.statusCode < 200 ||
        response.statusCode >= 300) {
      throw HttpException(
        'Upload failed (${response.statusCode}): $responseText',
      );
    }

    final decoded = jsonDecode(responseText);

    if (decoded is! Map<String, dynamic> ||
        decoded['success'] != true) {
      throw const FormatException(
        'Receiver rejected the file.',
      );
    }

    await recordTransfer(
      fileName: name,
      direction: 'sent',
      bytes: size,
    );
  }

  Future<void> sendFile({
    required File file,
    required String receiverIp,
    required int receiverPort,
    required String token,
    String? mode,
    String? fileName,
    int? tcpPort,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final selectedMode = mode ?? _activeMode ?? standardMode;

    if (!_isValidMode(selectedMode)) {
      throw ArgumentError.value(
        selectedMode,
        'mode',
        'Invalid transfer mode.',
      );
    }

    if (receiverIp.trim().isEmpty) {
      throw ArgumentError.value(
        receiverIp,
        'receiverIp',
        'Receiver IP address is required.',
      );
    }

    if (token.trim().isEmpty) {
      throw const FormatException(
        'Session token is required.',
      );
    }

    if (selectedMode == highSpeedMode) {
      if (tcpPort == null || tcpPort < 1 || tcpPort > 65535) {
        throw ArgumentError.value(
          tcpPort,
          'tcpPort',
          'A valid TCP port is required for 5G+ mode. '
              'Reconnect using a new QR code.',
        );
      }

      await sendFileHighSpeed(
        file: file,
        receiverIp: receiverIp,
        receiverPort: tcpPort,
        token: token,
        fileName: fileName,
        onProgress: onProgress,
      );

      return;
    }

    if (receiverPort < 1 || receiverPort > 65535) {
      throw ArgumentError.value(
        receiverPort,
        'receiverPort',
        'A valid HTTP port is required for STANDARD mode.',
      );
    }

    await sendFileStandard(
      file: file,
      receiverIp: receiverIp,
      receiverPort: receiverPort,
      token: token,
      fileName: fileName,
      onProgress: onProgress,
    );
  }

  Future<void> recordTransfer({
    required String fileName,
    required String direction,
    required int bytes,
  }) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final existing =
          preferences.getStringList(_historyKey) ?? [];

      final entry = <String, dynamic>{
        'fileName': fileName,
        'direction': direction,
        'bytes': bytes,
        'timestamp': DateTime.now().toIso8601String(),
      };

      existing.insert(0, jsonEncode(entry));

      if (existing.length > _maxHistoryEntries) {
        existing.removeRange(
          _maxHistoryEntries,
          existing.length,
        );
      }

      await preferences.setStringList(_historyKey, existing);
    } catch (error) {
      debugPrint('Unable to save transfer history: $error');
    }
  }

  Future<List<Map<String, dynamic>>> getTransferHistory() async {
    final preferences = await SharedPreferences.getInstance();
    final values = preferences.getStringList(_historyKey) ?? [];

    final result = <Map<String, dynamic>>[];

    for (final value in values) {
      try {
        final decoded = jsonDecode(value);

        if (decoded is Map<String, dynamic>) {
          result.add(decoded);
        }
      } catch (_) {
        // Skip malformed history entries.
      }
    }

    return result;
  }

  Future<List<File>> getReceivedFiles() async {
    final directory = await getApplicationDocumentsDirectory();

    if (!await directory.exists()) {
      return <File>[];
    }

    final files = <File>[];

    await for (final entity in directory.list(
      recursive: false,
      followLinks: false,
    )) {
      if (entity is! File) continue;

      final name = entity.uri.pathSegments.isEmpty
          ? ''
          : entity.uri.pathSegments.last;

      if (name.startsWith(_receivedPrefix)) {
        files.add(entity);
      }
    }

    files.sort((a, b) {
      return b.lastModifiedSync().compareTo(
            a.lastModifiedSync(),
          );
    });

    return files;
  }

  String getReceivedFileName(File file) {
    final name = file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;

    if (name.startsWith(_receivedPrefix)) {
      final withoutPrefix = name.substring(_receivedPrefix.length);
      final separator = withoutPrefix.indexOf('_');

      if (separator >= 0 && separator + 1 < withoutPrefix.length) {
        return withoutPrefix.substring(separator + 1);
      }

      return withoutPrefix;
    }

    return name;
  }

  String _sanitizeFileName(String input) {
    final normalized = input.replaceAll('\\', '/');
    final name = normalized.split('/').last.trim();

    return name.replaceAll(
      RegExp(r'[\x00-\x1F<>:"|?*]'),
      '',
    );
  }

  void dispose() {
    unawaited(stopReceiver());

    _sendClient?.close(force: true);
    _sendClient = null;
  }
}
