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

  bool get isServerRunning => _server != null;

  String? get sessionToken => _sessionToken;

  int? get port => _server?.port;

  Future<int> startReceiver() async {
    final existingServer = _server;

    if (existingServer != null) {
      return existingServer.port;
    }

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

    unawaited(_handleRequests(server));

    debugPrint(
      'MAFX SHARE receiver started on port ${server.port}',
    );

    return server.port;
  }

  Future<void> _handleRequests(HttpServer server) async {
    try {
      await for (final request in server) {
        try {
          if (request.method == 'GET' &&
              request.uri.path == '/health') {
            await _handleHealthCheck(request);
            continue;
          }

          if (request.method == 'POST' &&
              request.uri.path == '/upload') {
            await _receiveFile(request);
            continue;
          }

          request.response.statusCode = HttpStatus.notFound;
          request.response.headers.contentType = ContentType.json;

          request.response.write(
            jsonEncode({
              'success': false,
              'error': 'Endpoint not found',
            }),
          );

          await request.response.close();
        } catch (error, stackTrace) {
          debugPrint('MAFX SHARE request error: $error');
          debugPrintStack(stackTrace: stackTrace);

          try {
            request.response.statusCode =
                HttpStatus.internalServerError;

            request.response.headers.contentType = ContentType.json;

            request.response.write(
              jsonEncode({
                'success': false,
                'error': 'Transfer failed',
              }),
            );

            await request.response.close();
          } catch (closeError) {
            debugPrint(
              'Unable to close failed response: $closeError',
            );
          }
        }
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

  Future<void> _handleHealthCheck(HttpRequest request) async {
    request.response.statusCode = HttpStatus.ok;
    request.response.headers.contentType = ContentType.json;

    request.response.write(
      jsonEncode({
        'app': 'MAFX_SHARE',
        'status': 'ready',
        'version': 1,
      }),
    );

    await request.response.close();
  }

  Future<void> _receiveFile(HttpRequest request) async {
    final activeToken = _sessionToken;

    if (activeToken == null ||
        request.headers.value('x-mafx-token') != activeToken) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.headers.contentType = ContentType.json;

      request.response.write(
        jsonEncode({
          'success': false,
          'error': 'Invalid session token',
        }),
      );

      await request.response.close();
      return;
    }

    final rawName = request.headers.value('x-file-name');

    if (rawName == null || rawName.trim().isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;

      request.response.write(
        jsonEncode({
          'success': false,
          'error': 'Missing file name',
        }),
      );

      await request.response.close();
      return;
    }

    final fileName = _sanitizeFileName(rawName);

    if (fileName.isEmpty || fileName == '.' || fileName == '..') {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.headers.contentType = ContentType.json;

      request.response.write(
        jsonEncode({
          'success': false,
          'error': 'Invalid file name',
        }),
      );

      await request.response.close();
      return;
    }

    final directory = await getApplicationDocumentsDirectory();

    final timestamp = DateTime.now().microsecondsSinceEpoch;
    final safeName = '${timestamp}_$fileName';

    final file = File(
      '${directory.path}${Platform.pathSeparator}$safeName',
    );

    var completed = false;
    IOSink? sink;

    try {
      sink = file.openWrite();

      // Rubuta bayanan da ake karɓa zuwa fayil ɗin.
      // addStream yana jiran rubutun ya kammala.
      await sink.addStream(request).timeout(_transferTimeout);

      await sink.flush();
      await sink.close();
      sink = null;

      final bytes = await file.length();

      await recordTransfer(
        fileName: fileName,
        direction: 'received',
        bytes: bytes,
      );

      request.response.statusCode = HttpStatus.created;
      request.response.headers.contentType = ContentType.json;

      request.response.write(
        jsonEncode({
          'success': true,
          'fileName': fileName,
          'bytes': bytes,
        }),
      );

      await request.response.close();

      completed = true;

      debugPrint(
        'MAFX SHARE received $fileName ($bytes bytes)',
      );
    } catch (error) {
      debugPrint('Failed to receive $fileName: $error');

      try {
        await sink?.close();
      } catch (closeError) {
        debugPrint('Unable to close file sink: $closeError');
      }

      try {
        request.response.statusCode =
            HttpStatus.internalServerError;

        request.response.headers.contentType = ContentType.json;

        request.response.write(
          jsonEncode({
            'success': false,
            'error': 'Unable to receive file',
          }),
        );

        await request.response.close();
      } catch (responseError) {
        debugPrint(
          'Unable to send transfer error response: $responseError',
        );
      }

      rethrow;
    } finally {
      if (!completed) {
        try {
          if (await file.exists()) {
            await file.delete();
          }
        } catch (error) {
          debugPrint(
            'Unable to remove incomplete file: $error',
          );
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
          uri.host.isEmpty) {
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
      entries.removeRange(
        _maxHistoryEntries,
        entries.length,
      );
    }

    await prefs.setStringList(_historyKey, entries);
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
        baseUri.host.isEmpty) {
      throw Exception('Invalid receiver address.');
    }

    final uri = baseUri.resolve('/upload');

    final client = HttpClient()
      ..connectionTimeout = _sendConnectionTimeout;

    try {
      final request = await client
          .postUrl(uri)
          .timeout(_sendConnectionTimeout);

      request.headers.set('x-mafx-token', token);
      request.headers.set('x-file-name', safeName);
      request.headers.contentType = ContentType.binary;
      request.contentLength = await file.length();

      await request.addStream(file.openRead());

      final response = await request
          .close()
          .timeout(_transferTimeout);

      final body = await response.transform(utf8.decoder).join();

      if (response.statusCode != HttpStatus.created) {
        throw Exception(
          'Transfer failed with status '
          '${response.statusCode}: $body',
        );
      }

      final bytes = await file.length();

      await recordTransfer(
        fileName: safeName,
        direction: 'sent',
        bytes: bytes,
      );

      debugPrint(
        'MAFX SHARE sent $safeName ($bytes bytes)',
      );

      return true;
    } finally {
      client.close(force: true);
    }
  }
}
