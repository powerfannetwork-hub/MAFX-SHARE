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

  HttpServer? _server;
  String? _sessionToken;

  bool get isServerRunning => _server != null;
  String? get sessionToken => _sessionToken;
  int? get port => _server?.port;

  Future<int> startReceiver() async {
    if (_server != null) return _server!.port;

    final random = Random.secure();
    final token = List<int>.generate(
      32,
      (_) => random.nextInt(256),
    );

    _sessionToken = base64UrlEncode(token).replaceAll('=', '');

    final server = await HttpServer.bind(
      InternetAddress.anyIPv4,
      0,
      shared: false,
    );

    _server = server;
    unawaited(_handleRequests(server));

    return server.port;
  }

  Future<void> _handleRequests(HttpServer server) async {
    try {
      await for (final request in server) {
        try {
          if (request.method == 'GET' &&
              request.uri.path == '/health') {
            request.response.headers.contentType = ContentType.json;
            request.response.write(jsonEncode({
              'app': 'MAFX_SHARE',
              'status': 'ready',
              'version': 1,
            }));
            await request.response.close();
            continue;
          }

          if (request.method == 'POST' &&
              request.uri.path == '/upload') {
            await _receiveFile(request);
            continue;
          }

          request.response.statusCode = HttpStatus.notFound;
          request.response.headers.contentType = ContentType.json;
          request.response.write(jsonEncode({
            'error': 'Endpoint not found',
          }));
          await request.response.close();
        } catch (error) {
          debugPrint('MAFX SHARE request error: $error');
          if (!request.response.headersSent) {
            request.response.statusCode = HttpStatus.internalServerError;
            request.response.write('Transfer failed');
          }
          try {
            await request.response.close();
          } catch (_) {}
        }
      }
    } catch (error, stackTrace) {
      debugPrint('MAFX SHARE server error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<void> _receiveFile(HttpRequest request) async {
    if (_sessionToken == null ||
        request.headers.value('x-mafx-token') != _sessionToken) {
      request.response.statusCode = HttpStatus.unauthorized;
      request.response.write('Invalid session token');
      await request.response.close();
      return;
    }

    final rawName = request.headers.value('x-file-name');
    if (rawName == null || rawName.trim().isEmpty) {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('Missing file name');
      await request.response.close();
      return;
    }

    final fileName = rawName
        .replaceAll('\\', '/')
        .split('/')
        .last
        .replaceAll(RegExp(r'[\x00-\x1F]'), '_')
        .trim();

    if (fileName.isEmpty || fileName == '.' || fileName == '..') {
      request.response.statusCode = HttpStatus.badRequest;
      request.response.write('Invalid file name');
      await request.response.close();
      return;
    }

    final directory = await getApplicationDocumentsDirectory();
    final safeName = '${DateTime.now().millisecondsSinceEpoch}_$fileName';
    final file = File('${directory.path}/$safeName');

    try {
      final sink = file.openWrite();
      await request.pipe(sink);

      final bytes = await file.length();

      await recordTransfer(
        fileName: fileName,
        direction: 'received',
        bytes: bytes,
      );

      request.response.statusCode = HttpStatus.created;
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'success': true,
        'fileName': fileName,
        'bytes': bytes,
      }));
      await request.response.close();
    } catch (_) {
      if (await file.exists()) {
        await file.delete();
      }
      rethrow;
    }
  }

  Future<bool> checkReceiver(String baseUrl) async {
    HttpClient? client;

    try {
      final uri = Uri.parse(baseUrl);
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return false;
      }

      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);

      final request = await client.getUrl(uri.resolve('/health'));
      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );

      final body = await utf8.decoder.bind(response).join();

      if (response.statusCode != HttpStatus.ok) return false;

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

    if (entries.length > 100) {
      entries.removeRange(100, entries.length);
    }

    await prefs.setStringList(_historyKey, entries);
  }

  Future<void> stopReceiver() async {
    final server = _server;
    _server = null;
    _sessionToken = null;

    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> dispose() => stopReceiver();
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

  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 15);

  try {
    final uri = Uri.parse(receiverUrl).resolve('/upload');
    final request = await client.postUrl(uri);

    request.headers.set('x-mafx-token', token);
    request.headers.set('x-file-name', fileName);
    request.headers.contentType = ContentType.binary;
    request.contentLength = await file.length();

    await request.addStream(file.openRead());

    final response = await request.close().timeout(
      const Duration(minutes: 10),
    );

    final body = await response.transform(utf8.decoder).join();

    if (response.statusCode != HttpStatus.created) {
      throw Exception('Transfer failed: $body');
    }

    await recordTransfer(
      fileName: fileName,
      direction: 'sent',
      bytes: await file.length(),
    );

    return true;
  } finally {
    client.close(force: true);
  }
}
