import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const Duration _standardTransferTimeout =
      Duration(minutes: 10);
  static const Duration _highSpeedTransferTimeout =
      Duration(minutes: 30);

  static const int _standardChunkSize = 64 * 1024;
  static const int _highSpeedChunkSize = 1024 * 1024;

  HttpServer? _server;
  String? _sessionToken;
  String? _activeMode;
  Future<int>? _startingReceiver;

  HttpClient? _sendClient;

  bool get isServerRunning => _server != null;

  String? get sessionToken => _sessionToken;

  String? get activeMode => _activeMode;

  int? get port => _server?.port;

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

    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      0,
      shared: false,
    );

    _sessionToken = token;
    _activeMode = null;
    _server = server;

    unawaited(_handleRequests(server));

    debugPrint(
      'MAFX SHARE receiver started on port ${server.port}',
    );

    return server.port;
  }

  Future<void> _handleRequests(HttpServer server) async {
    try {
      await for (final request in server) {
        unawaited(_handleRequestSafely(request));
      }
    } catch (error, stackTrace) {
      debugPrint('MAFX SHARE server error: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (identical(_server, server)) {
        _server = null;
        _sessionToken = null;
        _activeMode = null;
      }

      debugPrint('MAFX SHARE receiver stopped.');
    }
  }

  Future<void> _handleRequestSafely(HttpRequest request) async {
    try {
      if (request.method == 'GET' &&
          request.uri.path == '/health') {
        await _handleHealthCheck(request);
        return;
      }

      if (request.method == 'POST' &&
          request.uri.path == '/connect') {
        await _handleConnectionRequest(request);
        return;
      }

      if (request.method == 'POST' &&
          request.uri.path == '/upload') {
        await _receiveFile(request);
        return;
      }

      await _sendJson(
        request.response,
        HttpStatus.notFound,
        {
          'success': false,
          'error': 'Endpoint not found',
        },
      );
    } catch (error, stackTrace) {
      debugPrint('MAFX SHARE request error: $error');
      debugPrintStack(stackTrace: stackTrace);

      try {
        if (!request.response.headersSent) {
          await _sendJson(
            request.response,
            HttpStatus.internalServerError,
            {
              'success': false,
              'error': 'Request failed',
            },
          );
        } else {
          await request.response.close();
        }
      } catch (responseError) {
        debugPrint(
          'Unable to close failed response: $responseError',
        );
      }
    }
  }

  Future<void> _sendJson(
    HttpResponse response,
    int statusCode,
    Map<String, dynamic> body,
  ) async {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.headers.set('Cache-Control', 'no-store');
    response.write(jsonEncode(body));
    await response.close();
  }

  Future<void> _handleHealthCheck(HttpRequest request) async {
    await _sendJson(
      request.response,
      HttpStatus.ok,
      {
        'app': 'MAFX_SHARE',
        'status': 'ready',
        'version': 1,
      },
    );
  }

  Future<void> _handleConnectionRequest(
    HttpRequest request,
  ) async {
    final activeToken = _sessionToken;

    if (activeToken == null) {
      await _sendJson(
        request.response,
        HttpStatus.serviceUnavailable,
        {
          'success': false,
          'error': 'Receiver is not running',
        },
      );
      return;
    }

    try {
      final body = await utf8.decoder
          .bind(request)
          .join()
          .timeout(_connectionTimeout);

      final decoded = jsonDecode(body);

      if (decoded is! Map<String, dynamic>) {
        await _sendJson(
          request.response,
          HttpStatus.badRequest,
          {
            'success': false,
            'error': 'Invalid connection request',
          },
        );
        return;
      }

      final suppliedToken = decoded['token'];
      final requestedMode = decoded['mode'];

      if (suppliedToken is! String ||
          suppliedToken.isEmpty ||
          suppliedToken != activeToken) {
        await _sendJson(
          request.response,
          HttpStatus.unauthorized,
          {
            'success': false,
            'error': 'Invalid session token',
          },
        );
        return;
      }

      if (requestedMode is! String ||
          !_isValidMode(requestedMode)) {
        await _sendJson(
          request.response,
          HttpStatus.badRequest,
          {
            'success': false,
            'error': 'Unsupported transfer mode',
          },
        );
        return;
      }

      _activeMode = requestedMode;

      await _sendJson(
        request.response,
        HttpStatus.ok,
        {
          'success': true,
          'connected': true,
          'app': 'MAFX_SHARE',
          'version': 1,
          'mode': requestedMode,
        },
      );

      debugPrint(
        'MAFX SHARE sender authenticated using $requestedMode.',
      );
    } on FormatException {
      await _sendJson(
        request.response,
        HttpStatus.badRequest,
        {
          'success': false,
          'error': 'Invalid connection data',
        },
      );
    } on TimeoutException {
      await _sendJson(
        request.response,
        HttpStatus.requestTimeout,
        {
          'success': false,
          'error': 'Connection request timed out',
        },
      );
    }
  }

  Future<void> _receiveFile(HttpRequest request) async {
    final activeToken = _sessionToken;
    final suppliedToken = request.headers.value('x-mafx-token');
    final suppliedMode = request.headers.value('x-mafx-mode');
    final negotiatedMode = _activeMode;

    if (activeToken == null ||
        suppliedToken == null ||
        suppliedToken != activeToken) {
      await _sendJson(
        request.response,
        HttpStatus.unauthorized,
        {
          'success': false,
          'error': 'Invalid session token',
        },
      );
      return;
    }

    if (negotiatedMode == null) {
      await _sendJson(
        request.response,
        HttpStatus.forbidden,
        {
          'success': false,
          'error': 'Connect to the receiver before sending files',
        },
      );
      return;
    }

    if (suppliedMode != negotiatedMode) {
      await _sendJson(
        request.response,
        HttpStatus.conflict,
        {
          'success': false,
          'error': 'Transfer mode does not match the connection',
        },
      );
      return;
    }

    final rawName = request.headers.value('x-file-name');

    if (rawName == null || rawName.trim().isEmpty) {
      await _sendJson(
        request.response,
        HttpStatus.badRequest,
        {
          'success': false,
          'error': 'Missing file name',
        },
      );
      return;
    }

    final fileName = _sanitizeFileName(rawName);

    if (fileName.isEmpty ||
        fileName == '.' ||
        fileName == '..') {
      await _sendJson(
        request.response,
        HttpStatus.badRequest,
        {
          'success': false,
          'error': 'Invalid file name',
        },
      );
      return;
    }

    final expectedLength = request.contentLength;
    final directory = await getApplicationDocumentsDirectory();

    await directory.create(recursive: true);

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final storedName = '$_receivedPrefix${timestamp}_$fileName';

    final file = File(
      '${directory.path}${Platform.pathSeparator}$storedName',
    );

    IOSink? sink;
    var completed = false;

    try {
      await file.create(exclusive: true);
      sink = file.openWrite();

      await sink
          .addStream(request)
          .timeout(_timeoutForMode(negotiatedMode));

      await sink.flush();
      await sink.close();
      sink = null;

      final receivedBytes = await file.length();

      if (expectedLength >= 0 &&
          receivedBytes != expectedLength) {
        throw const FormatException(
          'Received file size does not match the expected size.',
        );
      }

      await recordTransfer(
        fileName: fileName,
        direction: 'received',
        bytes: receivedBytes,
      );

      completed = true;

      await _sendJson(
        request.response,
        HttpStatus.created,
        {
          'success': true,
          'fileName': fileName,
          'bytes': receivedBytes,
          'mode': negotiatedMode,
        },
      );

      debugPrint(
        'MAFX SHARE received $fileName '
        '($receivedBytes bytes, $negotiatedMode)',
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to receive $fileName: $error');
      debugPrintStack(stackTrace: stackTrace);

      try {
        await sink?.close();
      } catch (closeError) {
        debugPrint('Unable to close file sink: $closeError');
      }

      rethrow;
    } finally {
      if (!completed) {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (error) {
          debugPrint('Unable to remove incomplete file: $error');
        }
      }
    }
  }

  String _sanitizeFileName(String rawName) {
    final normalized = rawName.replaceAll('\\', '/');
    final name = normalized.split('/').last.trim();

    return name.replaceAll(
      RegExp(r'[\x00-\x1F<>:"|?*]'),
      '_',
    );
  }

  Future<bool> checkReceiver(String baseUrl) async {
    HttpClient? client;

    try {
      final uri = Uri.parse(baseUrl);

      if ((uri.scheme != 'http' && uri.scheme != 'https') ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty) {
        return false;
      }

      client = HttpClient()
        ..connectionTimeout = _connectionTimeout;

      final request = await client
          .getUrl(uri.resolve('/health'))
          .timeout(_connectionTimeout);

      final response = await request
          .close()
          .timeout(_connectionTimeout);

      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(_connectionTimeout);

      if (response.statusCode != HttpStatus.ok) {
        return false;
      }

      final decoded = jsonDecode(body);

      return decoded is Map &&
          decoded['app'] == 'MAFX_SHARE' &&
          decoded['status'] == 'ready' &&
          decoded['version'] == 1;
    } catch (error) {
      debugPrint('Receiver check failed: $error');
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  Future<bool> connectToReceiver({
    required String receiverUrl,
    required String token,
    required String mode,
  }) async {
    if (token.isEmpty || !_isValidMode(mode)) {
      return false;
    }

    HttpClient? client;

    try {
      final baseUri = Uri.parse(receiverUrl);

      if ((baseUri.scheme != 'http' &&
              baseUri.scheme != 'https') ||
          baseUri.host.isEmpty ||
          baseUri.userInfo.isNotEmpty) {
        return false;
      }

      client = HttpClient()
        ..connectionTimeout = _sendConnectionTimeout;

      final request = await client
          .postUrl(baseUri.resolve('/connect'))
          .timeout(_sendConnectionTimeout);

      request.headers.contentType = ContentType.json;
      request.headers.set(
        HttpHeaders.cacheControlHeader,
        'no-store',
      );

      request.write(jsonEncode({
        'token': token,
        'mode': mode,
      }));

      final response = await request
          .close()
          .timeout(_sendConnectionTimeout);

      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(_connectionTimeout);

      if (response.statusCode != HttpStatus.ok) {
        debugPrint(
          'Receiver authentication failed: '
          '${response.statusCode}',
        );
        return false;
      }

      final decoded = jsonDecode(body);

      if (decoded is! Map<String, dynamic>) {
        return false;
      }

      return decoded['success'] == true &&
          decoded['connected'] == true &&
          decoded['app'] == 'MAFX_SHARE' &&
          decoded['version'] == 1 &&
          decoded['mode'] == mode;
    } catch (error, stackTrace) {
      debugPrint('Connection handshake failed: $error');
      debugPrintStack(stackTrace: stackTrace);
      return false;
    } finally {
      client?.close(force: true);
    }
  }

  Future<void> recordTransfer({
    required String fileName,
    required String direction,
    required int bytes,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList(_historyKey) ?? [];

    entries.insert(
      0,
      jsonEncode({
        'fileName': fileName,
        'direction': direction,
        'bytes': bytes,
        'completedAt': DateTime.now().toUtc().toIso8601String(),
      }),
    );

    if (entries.length > _maxHistoryEntries) {
      entries.removeRange(_maxHistoryEntries, entries.length);
    }

    await prefs.setStringList(_historyKey, entries);
  }

  Future<List<File>> getReceivedFiles() async {
    final directory = await getApplicationDocumentsDirectory();

    if (!await directory.exists()) {
      return [];
    }

    final files = <File>[];

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File && _isManagedReceivedFile(entity.path)) {
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

  bool _isManagedReceivedFile(String path) {
    final name = path.split(Platform.pathSeparator).last;
    return name.startsWith(_receivedPrefix);
  }

  String getReceivedFileName(File file) {
    final storedName = file.uri.pathSegments.isEmpty
        ? file.path.split(Platform.pathSeparator).last
        : Uri.decodeComponent(file.uri.pathSegments.last);

    if (!storedName.startsWith(_receivedPrefix)) {
      return storedName;
    }

    final remainder = storedName.substring(_receivedPrefix.length);
    final separator = remainder.indexOf('_');

    if (separator < 0 || separator == remainder.length - 1) {
      return remainder;
    }

    return remainder.substring(separator + 1);
  }

  Future<void> stopReceiver() async {
    final server = _server;

    _server = null;
    _sessionToken = null;
    _activeMode = null;

    if (server != null) {
      await server.close(force: true);
      debugPrint('MAFX SHARE receiver closed.');
    }
  }

  Future<void> dispose() async {
    await stopReceiver();

    _sendClient?.close(force: true);
    _sendClient = null;
  }

  Stream<List<int>> _readFileChunks(
    File file,
    int chunkSize,
  ) async* {
    RandomAccessFile? handle;

    try {
      handle = await file.open(mode: FileMode.read);

      while (true) {
        final chunk = await handle.read(chunkSize);

        if (chunk.isEmpty) {
          break;
        }

        yield chunk;
      }
    } finally {
      await handle?.close();
    }
  }

  Future<bool> sendFile({
    required String receiverUrl,
    required String token,
    required String filePath,
    required String fileName,
    String mode = standardMode,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    if (token.isEmpty) {
      throw Exception('Connection token is missing.');
    }

    if (!_isValidMode(mode)) {
      throw Exception('Unsupported transfer mode.');
    }

    final file = File(filePath);

    if (!await file.exists()) {
      throw Exception('File not found: $fileName');
    }

    final safeName = _sanitizeFileName(fileName);

    if (safeName.isEmpty ||
        safeName == '.' ||
        safeName == '..') {
      throw Exception('Invalid file name: $fileName');
    }

    final baseUri = Uri.parse(receiverUrl);

    if ((baseUri.scheme != 'http' &&
            baseUri.scheme != 'https') ||
        baseUri.host.isEmpty ||
        baseUri.userInfo.isNotEmpty) {
      throw Exception('Invalid receiver address.');
    }

    final uri = baseUri.resolve('/upload');
    final fileSize = await file.length();
    final transferTimeout = _timeoutForMode(mode);
    final client = _getSendClient();

    try {
      final request = await client
          .postUrl(uri)
          .timeout(_sendConnectionTimeout);

      request.headers.set('x-mafx-token', token);
      request.headers.set('x-mafx-mode', mode);
      request.headers.set('x-file-name', safeName);
      request.headers.set(
        HttpHeaders.cacheControlHeader,
        'no-store',
      );
      request.headers.contentType = ContentType.binary;
      request.contentLength = fileSize;

      var sentBytes = 0;

      onProgress?.call(0, fileSize);

      final stream = _readFileChunks(
        file,
        _chunkSizeForMode(mode),
      ).map((chunk) {
        sentBytes += chunk.length;

        onProgress?.call(
          sentBytes > fileSize ? fileSize : sentBytes,
          fileSize,
        );

        return chunk;
      });

      await request
          .addStream(stream)
          .timeout(transferTimeout);

      final response = await request
          .close()
          .timeout(transferTimeout);

      final body = await response
          .transform(utf8.decoder)
          .join()
          .timeout(_connectionTimeout);

      if (response.statusCode != HttpStatus.created) {
        throw Exception(
          'Transfer failed with status '
          '${response.statusCode}: $body',
        );
      }

      final decoded = jsonDecode(body);

      if (decoded is! Map<String, dynamic>) {
        throw Exception('Receiver returned an invalid response.');
      }

      if (decoded['success'] != true ||
          decoded['bytes'] != fileSize ||
          decoded['mode'] != mode) {
        throw Exception(
          'Receiver did not confirm the complete file '
          'or the selected transfer mode.',
        );
      }

      await recordTransfer(
        fileName: safeName,
        direction: 'sent',
        bytes: fileSize,
      );

      onProgress?.call(fileSize, fileSize);

      debugPrint(
        'MAFX SHARE sent $safeName '
        '($fileSize bytes, $mode)',
      );

      return true;
    } catch (_) {
      // Discard a potentially unhealthy pooled connection after a failure.
      _sendClient?.close(force: true);
      _sendClient = null;
      rethrow;
    }
  }
}
