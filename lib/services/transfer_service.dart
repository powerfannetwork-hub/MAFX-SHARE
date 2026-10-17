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

  static const Duration _connectionTimeout = Duration(seconds: 5);
  static const Duration _sendConnectionTimeout = Duration(seconds: 15);
  static const Duration _transferTimeout = Duration(minutes: 10);

  HttpServer? _server;
  String? _sessionToken;

  Future<int>? _startingReceiver;

  bool get isServerRunning => _server != null;

  String? get sessionToken => _sessionToken;

  int? get port => _server?.port;

  /// Starts the receiver server.
  ///
  /// If startup is already in progress, wait for that same operation.
  /// If the server is already running, reuse its port.
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
    _server = server;

    // Handle requests independently so a health check can respond
    // while another request is transferring a file.
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
        debugPrint('Unable to close failed response: $responseError');
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

  Future<void> _receiveFile(HttpRequest request) async {
    final activeToken = _sessionToken;
    final suppliedToken = request.headers.value('x-mafx-token');

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

    if (fileName.isEmpty || fileName == '.' || fileName == '..') {
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
    final timestamp = DateTime.now().microsecondsSinceEpoch;

    // Use exclusive creation to avoid overwriting an existing file.
    final file = File(
      '${directory.path}${Platform.pathSeparator}'
      '${timestamp}_$fileName',
    );

    IOSink? sink;
    var completed = false;

    try {
      sink = file.openWrite();

      await sink.addStream(request).timeout(_transferTimeout);

      await sink.flush();
      await sink.close();
      sink = null;

      final bytes = await file.length();

      if (expectedLength >= 0 && bytes != expectedLength) {
        throw const FormatException(
          'Received file size does not match the expected size.',
        );
      }

      await recordTransfer(
        fileName: fileName,
        direction: 'received',
        bytes: bytes,
      );

      completed = true;

      await _sendJson(
        request.response,
        HttpStatus.created,
        {
          'success': true,
          'fileName': fileName,
          'bytes': bytes,
        },
      );

      debugPrint(
        'MAFX SHARE received $fileName ($bytes bytes)',
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

  /// Returns files saved by MAFX SHARE in its documents directory.
  Future<List<File>> getReceivedFiles() async {
    final directory = await getApplicationDocumentsDirectory();

    if (!await directory.exists()) {
      return [];
    }

    final files = <File>[];

    await for (final entity in directory.list(followLinks: false)) {
      if (entity is File) {
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

  Future<void> stopReceiver() async {
    final server = _server;

    _server = null;
    _sessionToken = null;

    if (server != null) {
      await server.close(force: true);
      debugPrint('MAFX SHARE receiver closed.');
    }
  }

  Future<void> dispose() async {
    await stopReceiver();
  }

  Future<bool> sendFile({
    required String receiverUrl,
    required String token,
    required String filePath,
    required String fileName,
    void Function(int sentBytes, int totalBytes)? onProgress,
  }) async {
    final file = File(filePath);

    if (!await file.exists()) {
      throw Exception('File not found: $fileName');
    }

    final safeName = _sanitizeFileName(fileName);

    if (safeName.isEmpty || safeName == '.' || safeName == '..') {
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

    final client = HttpClient()
      ..connectionTimeout = _sendConnectionTimeout;

    try {
      final request = await client
          .postUrl(uri)
          .timeout(_sendConnectionTimeout);

      request.headers.set('x-mafx-token', token);
      request.headers.set('x-file-name', safeName);
      request.headers.set(
        HttpHeaders.cacheControlHeader,
        'no-store',
      );
      request.headers.contentType = ContentType.binary;
      request.contentLength = fileSize;

      var sentBytes = 0;

      final stream = file.openRead().map((chunk) {
        sentBytes += chunk.length;

        onProgress?.call(
          sentBytes,
          fileSize,
        );

        return chunk;
      });

      await request.addStream(stream).timeout(_transferTimeout);

      final response = await request
          .close()
          .timeout(_transferTimeout);

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

      Map<String, dynamic> result;

      try {
        final decoded = jsonDecode(body);

        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('Invalid response.');
        }

        result = decoded;
      } catch (_) {
        throw Exception('Receiver returned an invalid response.');
      }

      if (result['success'] != true ||
          result['bytes'] != fileSize) {
        throw Exception(
          'Receiver did not confirm the complete file.',
        );
      }

      await recordTransfer(
        fileName: safeName,
        direction: 'sent',
        bytes: fileSize,
      );

      debugPrint(
        'MAFX SHARE sent $safeName ($fileSize bytes)',
      );

      return true;
    } finally {
      client.close(force: true);
    }
  }
}
