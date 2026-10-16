import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TransferService {
  TransferService._();

  static const String _historyKey = 'mafx_transfer_history';

  HttpServer? _server;
  bool _disposed = false;

  bool get isServerRunning => _server != null;

  /// Starts a local HTTP server for receiving files.
  /// Both devices must be able to reach each other over the local network.
  Future<int> startReceiver({
    InternetAddress? address,
    int port = 0,
  }) async {
    if (_disposed) {
      throw StateError('TransferService has been disposed.');
    }

    if (_server != null) {
      return _server!.port;
    }

    final bindAddress = address ?? InternetAddress.anyIPv4;

    final server = await HttpServer.bind(
      bindAddress,
      port,
      shared: false,
    );

    if (_disposed) {
      await server.close(force: true);
      throw StateError('TransferService has been disposed.');
    }

    _server = server;
    unawaited(_handleRequests(server));

    return server.port;
  }

  Future<void> _handleRequests(HttpServer server) async {
    try {
      await for (final request in server) {
        if (_disposed) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          await request.response.close();
          continue;
        }

        if (request.method == 'GET' &&
            request.uri.path == '/health') {
          request.response.headers.contentType =
              ContentType.json;

          request.response.write(
            jsonEncode({
              'app': 'MAFX_SHARE',
              'status': 'ready',
              'version': 1,
            }),
          );

          await request.response.close();
          continue;
        }

        request.response.statusCode = HttpStatus.notFound;
        request.response.headers.contentType =
            ContentType.json;

        request.response.write(
          jsonEncode({
            'error': 'Endpoint not found',
          }),
        );

        await request.response.close();
      }
    } on SocketException catch (error) {
      debugPrint('MAFX SHARE server socket error: $error');
    } catch (error, stackTrace) {
      debugPrint('MAFX SHARE server error: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  /// Checks whether a remote MAFX SHARE receiver is reachable.
  Future<bool> checkReceiver(String baseUrl) async {
    HttpClient? client;

    try {
      final uri = Uri.parse(baseUrl);
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return false;
      }

      client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 5);

      final request = await client.getUrl(
        uri.resolve('/health'),
      );

      final response = await request.close().timeout(
        const Duration(seconds: 5),
      );

      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 5));

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

  /// Records a completed transfer in local app history.
  Future<void> recordTransfer({
    required String fileName,
    required String direction,
    required int bytes,
  }) async {
    if (fileName.trim().isEmpty) {
      throw ArgumentError.value(fileName, 'fileName');
    }

    if (direction != 'sent' && direction != 'received') {
      throw ArgumentError.value(direction, 'direction');
    }

    if (bytes < 0) {
      throw ArgumentError.value(bytes, 'bytes');
    }

    final prefs = await SharedPreferences.getInstance();
    final entries = prefs.getStringList(_historyKey) ?? [];

    final record = jsonEncode({
      'fileName': fileName,
      'direction': direction,
      'bytes': bytes,
      'completedAt': DateTime.now().toUtc().toIso8601String(),
    });

    entries.insert(0, record);

    // Keep the history bounded.
    if (entries.length > 100) {
      entries.removeRange(100, entries.length);
    }

    await prefs.setStringList(_historyKey, entries);
  }

  /// Returns the locally selected file paths.
  /// Files must be picked using FilePicker withData: false.
  List<String> getFilePaths(List<PlatformFile> files) {
    final paths = <String>[];

    for (final file in files) {
      final path = file.path;

      if (path == null || path.isEmpty) {
        throw StateError(
          'Cannot access the local path for "${file.name}".',
        );
      }

      paths.add(path);
    }

    return paths;
  }

  Future<void> stopReceiver() async {
    final server = _server;
    _server = null;

    if (server != null) {
      await server.close(force: true);
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;

    _disposed = true;
    await stopReceiver();
  }
}
