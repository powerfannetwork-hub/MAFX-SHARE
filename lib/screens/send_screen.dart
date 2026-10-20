import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:photo_manager/photo_manager.dart';

import '../services/transfer_service.dart';
import 'media_browser_screen.dart';

class SendScreen extends StatefulWidget {
final String receiverUrl;
final String receiverToken;
final String? category;
final String transferMode;
final int? receiverTcpPort;

const SendScreen({
super.key,
required this.receiverUrl,
required this.receiverToken,
this.category,
this.transferMode = TransferService.standardMode,
this.receiverTcpPort,
});

@override
State<SendScreen> createState() => _SendScreenState();
}

class _SendScreenState extends State<SendScreen> {
final TransferService _service = TransferService.instance;

final List<_SelectedFile> _selectedFiles = [];
final List<_SelectedFile> _failedFiles = [];

bool _sending = false;
double _progress = 0;
double _fileProgress = 0;

String _status = '';
String _currentFileName = '';

int _currentFileSent = 0;
int _currentFileSize = 0;
int _sentCount = 0;
int _totalBytesSent = 0;
DateTime? _speedSampleTime;
int _speedSampleBytes = 0;
double _speedBytesPerSecond = 0;

bool get _isHighSpeed =>
widget.transferMode == TransferService.highSpeedMode;

String get _category => (widget.category ?? 'files').toLowerCase();

static const Color _green = Color(0xFF00D084);
static const Color _background = Color(0xFF101820);
static const Color _panel = Color(0xFF192832);

Future<void> _pickFiles() async {
if (_sending) return;

if (!_service.isPaired) {
  _showMessage('Connect to a device before selecting files.');
  return;
}

if (_category == 'photos' ||
    _category == 'videos' ||
    _category == 'music') {
  await _pickMedia();
} else {
  await _pickDocuments();
}

}

Future<void> _pickMedia() async {
final String category;

switch (_category) {
  case 'photos':
    category = 'Photos';
    break;
  case 'videos':
    category = 'Videos';
    break;
  default:
    category = 'Music';
}

try {
  final assets = await Navigator.of(context).push<List<AssetEntity>>(
    MaterialPageRoute<List<AssetEntity>>(
      builder: (_) => MediaBrowserScreen(
        category: category,
        allowMultiple: true,
      ),
    ),
  );

  if (!mounted || assets == null || assets.isEmpty) return;

  final files = <_SelectedFile>[];

  for (final asset in assets) {
    final file = await asset.file;

    if (file == null || !await file.exists()) continue;

    final title = asset.title?.trim();
    final name = title != null && title.isNotEmpty
        ? title
        : 'media_${asset.id}';

    files.add(
      _SelectedFile(
        name: name,
        path: file.path,
        size: await file.length(),
      ),
    );
  }

  if (mounted) _addFiles(files);
} catch (error, stackTrace) {
  debugPrint('Media selection error: $error');
  debugPrintStack(stackTrace: stackTrace);
  _showMessage('Unable to open media browser: $error');
}

}

Future<void> _pickDocuments() async {
try {
final isApkCategory = _category == 'apps';
final result = await FilePicker.platform.pickFiles(
allowMultiple: true,
type: isApkCategory ? FileType.custom : FileType.any,
allowedExtensions: isApkCategory ? const <String>['apk'] : null,
withData: false,
);

  if (!mounted || result == null) return;

  final files = <_SelectedFile>[];

  for (final item in result.files) {
    final path = item.path;

    if (path == null || path.isEmpty) continue;

    files.add(
      _SelectedFile(
        name: item.name,
        path: path,
        size: item.size,
      ),
    );
  }

  if (mounted) _addFiles(files);
} catch (error, stackTrace) {
  debugPrint('File selection error: $error');
  debugPrintStack(stackTrace: stackTrace);
  _showMessage('Unable to select files: $error');
}

}

void _addFiles(List<_SelectedFile> files) {
if (files.isEmpty) {
_showMessage('No accessible files were found.');
return;
}

var added = 0;

setState(() {
  for (final file in files) {
    if (!_selectedFiles.any((item) => item.path == file.path)) {
      _selectedFiles.add(file);
      added++;
    }
  }

  _status = added > 0
      ? 'Added $added file(s).'
      : 'These files are already selected.';
});

}

void _removeFile(_SelectedFile file) {
if (_sending) return;

setState(() {
  _selectedFiles.remove(file);
  _status = 'Removed ${file.name}.';
});

}

void _clearFiles() {
if (_sending) return;

setState(() {
  _selectedFiles.clear();
  _failedFiles.clear();
  _progress = 0;
  _fileProgress = 0;
  _currentFileName = '';
  _currentFileSent = 0;
  _currentFileSize = 0;
  _sentCount = 0;
  _totalBytesSent = 0;
  _status = 'Selected files cleared.';
});

}

Future<void> _sendFiles() async {
if (_sending || _selectedFiles.isEmpty) return;

if (!_service.isPaired) {
  _showMessage('Connection lost. Reconnect before sending files.');
  return;
}

if (_isHighSpeed &&
    (widget.receiverTcpPort == null ||
        widget.receiverTcpPort! < 1 ||
        widget.receiverTcpPort! > 65535)) {
  _showMessage(
    'The high-speed TCP port is missing. Reconnect using a new QR code.',
  );
  return;
}

final uri = Uri.tryParse(widget.receiverUrl);

if (uri == null ||
    uri.host.isEmpty ||
    uri.port < 1 ||
    uri.port > 65535) {
  _showMessage('Invalid receiver address. Please reconnect.');
  return;
}

final files = List<_SelectedFile>.from(_selectedFiles);
final total = files.length;

setState(() {
  _sending = true;
  _progress = 0;
  _fileProgress = 0;
  _currentFileName = '';
  _currentFileSent = 0;
  _currentFileSize = 0;
  _sentCount = 0;
  _totalBytesSent = 0;
  _speedSampleTime = DateTime.now();
  _speedSampleBytes = 0;
  _speedBytesPerSecond = 0;
  _failedFiles.clear();
  _status = 'Preparing files...';
});

var sent = 0;

for (var index = 0; index < total; index++) {
  if (!mounted) return;

  final selected = files[index];

  setState(() {
    _currentFileName = selected.name;
    _currentFileSize = selected.size;
    _currentFileSent = 0;
    _speedSampleTime = DateTime.now();
    _speedSampleBytes = 0;
    _speedBytesPerSecond = 0;
    _fileProgress = 0;
    _progress = index / total;
    _status = 'Sending ${selected.name}...';
  });

  try {
    final file = File(selected.path);

    if (!await file.exists()) {
      throw Exception('The selected file no longer exists.');
    }

    final size = await file.length();

    await _service.sendFile(
      file: file,
      receiverIp: uri.host,
      receiverPort: uri.port,
      token: widget.receiverToken,
      fileName: selected.name,
      mode: widget.transferMode,
      tcpPort: _isHighSpeed ? widget.receiverTcpPort : null,
      onProgress: (sentBytes, totalBytes) {
        if (!mounted) return;

        setState(() {
          _currentFileSent = sentBytes;
          _currentFileSize = totalBytes;
          final now = DateTime.now();
          final sampleTime = _speedSampleTime;
          if (sampleTime == null) {
            _speedSampleTime = now;
            _speedSampleBytes = sentBytes;
          } else {
            final elapsedMs = now.difference(sampleTime).inMilliseconds;
            if (elapsedMs >= 500) {
              final delta = sentBytes - _speedSampleBytes;
              if (delta >= 0) {
                _speedBytesPerSecond = delta * 1000 / elapsedMs;
              }
              _speedSampleTime = now;
              _speedSampleBytes = sentBytes;
            }
          }

          _fileProgress = totalBytes > 0
              ? (sentBytes / totalBytes)
                  .clamp(0.0, 1.0)
                  .toDouble()
              : 0.0;
        });
      },
    );

    sent++;
    _totalBytesSent += size;
  } catch (error, stackTrace) {
    _failedFiles.add(selected);
    debugPrint('Failed to send ${selected.name}: $error');
    debugPrintStack(stackTrace: stackTrace);
  }

  if (!mounted) return;

  setState(() {
    _sentCount = sent;
    _progress = (index + 1) / total;
    _status = _failedFiles.isEmpty
        ? 'Sent $sent of $total file(s)...'
        : 'Sent $sent; failed ${_failedFiles.length}.';
  });
}

if (!mounted) return;

setState(() {
  _sending = false;
  _progress = 1;
  _fileProgress = 0;
  _currentFileSent = 0;
  _currentFileSize = 0;
  _speedBytesPerSecond = 0;

  if (_failedFiles.isEmpty) {
    _status = 'All files sent successfully!';
    _selectedFiles.clear();
  } else {
    _status = 'Sent $sent of $total file(s). '
        '${_failedFiles.length} file(s) failed.';
  }
});

if (_failedFiles.isEmpty) {
  _showMessage('All files sent successfully!');
} else {
  _showMessage('Some files failed. You can retry them.');
}

}

Future<void> _retryFailedFiles() async {
if (_sending || _failedFiles.isEmpty) return;

final failed = List<_SelectedFile>.from(_failedFiles);

setState(() {
  _selectedFiles
    ..clear()
    ..addAll(failed);

  _failedFiles.clear();
  _progress = 0;
  _fileProgress = 0;
  _currentFileName = '';
  _currentFileSent = 0;
  _currentFileSize = 0;
  _sentCount = 0;
  _totalBytesSent = 0;
  _speedSampleTime = DateTime.now();
  _speedSampleBytes = 0;
  _speedBytesPerSecond = 0;
  _status = 'Retrying failed files...';
});

await _sendFiles();

}

void _showMessage(String message) {
if (!mounted) return;

ScaffoldMessenger.of(context).showSnackBar(
  SnackBar(
    content: Text(message),
    behavior: SnackBarBehavior.floating,
  ),
);

}

String _formatSize(int bytes) {
if (bytes < 1024) return '$bytes B';

if (bytes < 1024 * 1024) {
  return '${(bytes / 1024).toStringAsFixed(1)} KB';
}

if (bytes < 1024 * 1024 * 1024) {
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';

}

String _formatSpeed(double bytesPerSecond) {
  if (bytesPerSecond <= 0 || !bytesPerSecond.isFinite) return 'Calculating…';
  return '${_formatSize(bytesPerSecond.round())}/s';
}

String _formatRemaining() {
  if (_speedBytesPerSecond <= 0 || _currentFileSize <= 0) return 'Calculating…';
  final remainingBytes = (_currentFileSize - _currentFileSent).clamp(0, _currentFileSize);
  final seconds = (remainingBytes / _speedBytesPerSecond).ceil();
  if (seconds < 60) return '${seconds}s left';
  final minutes = seconds ~/ 60;
  final remainder = seconds % 60;
  if (minutes < 60) return '${minutes}m ${remainder}s left';
  return '${minutes ~/ 60}h ${minutes % 60}m left';
}

IconData _fileIcon(String name) {
final extension =
name.contains('.') ? name.split('.').last.toLowerCase() : '';

switch (extension) {
  case 'jpg':
  case 'jpeg':
  case 'png':
  case 'webp':
  case 'gif':
  case 'heic':
    return Icons.image_rounded;
  case 'mp4':
  case 'mkv':
  case 'mov':
  case 'avi':
  case 'webm':
  case '3gp':
    return Icons.video_file_rounded;
  case 'mp3':
  case 'm4a':
  case 'wav':
  case 'aac':
  case 'flac':
  case 'ogg':
    return Icons.audio_file_rounded;
  case 'apk':
    return Icons.android_rounded;
  case 'pdf':
    return Icons.picture_as_pdf_rounded;
  case 'zip':
  case 'rar':
  case '7z':
    return Icons.folder_zip_rounded;
  case 'doc':
  case 'docx':
    return Icons.description_rounded;
  case 'xls':
  case 'xlsx':
    return Icons.table_chart_rounded;
  case 'ppt':
  case 'pptx':
    return Icons.slideshow_rounded;
  case 'txt':
    return Icons.text_snippet_rounded;
  default:
    return Icons.insert_drive_file_rounded;
}

}

Widget _buildFileCard(_SelectedFile file) {
return Container(
margin: const EdgeInsets.only(bottom: 10),
padding: const EdgeInsets.all(12),
decoration: BoxDecoration(
color: _panel,
borderRadius: BorderRadius.circular(14),
border: Border.all(color: Colors.white10),
),
child: Row(
children: [
Container(
width: 48,
height: 48,
decoration: BoxDecoration(
color: _green.withValues(alpha: 0.12),
borderRadius: BorderRadius.circular(12),
),
child: Icon(_fileIcon(file.name), color: _green, size: 27),
),
const SizedBox(width: 12),
Expanded(
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Text(
file.name,
maxLines: 2,
overflow: TextOverflow.ellipsis,
style: const TextStyle(
color: Colors.white,
fontWeight: FontWeight.w600,
),
),
const SizedBox(height: 5),
Text(
_formatSize(file.size),
style: const TextStyle(
color: Colors.white60,
fontSize: 12,
),
),
],
),
),
if (!_sending)
IconButton(
tooltip: 'Remove file',
onPressed: () => _removeFile(file),
icon: const Icon(Icons.close_rounded, color: Colors.white70),
),
],
),
);
}

Widget _buildProgressPanel() {
return Container(
margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
padding: const EdgeInsets.all(16),
decoration: BoxDecoration(
color: _panel,
borderRadius: BorderRadius.circular(16),
),
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
Row(
children: [
Icon(
_sending
? Icons.sync_rounded
: _failedFiles.isEmpty
? Icons.check_circle_outline_rounded
: Icons.warning_amber_rounded,
color: _green,
),
const SizedBox(width: 8),
Expanded(
child: Text(
_status,
style: const TextStyle(
color: Colors.white,
fontWeight: FontWeight.w600,
),
),
),
],
),
if (_sending || _progress > 0) ...[
const SizedBox(height: 14),
LinearProgressIndicator(
value: _progress.clamp(0.0, 1.0).toDouble(),
color: _green,
backgroundColor: Colors.white12,
minHeight: 6,
borderRadius: BorderRadius.circular(10),
),
const SizedBox(height: 8),
Text(
'${(_progress * 100).round()}% complete',
style: const TextStyle(color: Colors.white60, fontSize: 12),
),
],
if (_sending) ...[
const SizedBox(height: 14),
Text(
'Current file: $_currentFileName',
maxLines: 2,
overflow: TextOverflow.ellipsis,
style: const TextStyle(
color: Colors.white,
fontWeight: FontWeight.w600,
),
),
const SizedBox(height: 8),
LinearProgressIndicator(
value: _fileProgress,
color: _green,
backgroundColor: Colors.white12,
minHeight: 5,
borderRadius: BorderRadius.circular(10),
),
const SizedBox(height: 6),
Text(
'${(_fileProgress * 100).round()}% — '
'${_formatSize(_currentFileSent)} / '
'${_formatSize(_currentFileSize)}',
style: const TextStyle(color: Colors.white60, fontSize: 12),
),
const SizedBox(height: 6),
Row(
  children: [
    Expanded(
      child: Text(
        'Speed: ${_formatSpeed(_speedBytesPerSecond)}',
        style: const TextStyle(color: Colors.white70, fontSize: 12),
      ),
    ),
    Text(
      _formatRemaining(),
      style: const TextStyle(color: Colors.white70, fontSize: 12),
    ),
  ],
),
],
if (_sentCount > 0) ...[
const SizedBox(height: 8),
Text(
'Successful files: $_sentCount',
style: const TextStyle(color: _green),
),
Text(
'Transferred: ${_formatSize(_totalBytesSent)}',
style: const TextStyle(color: Colors.white70),
),
],
if (_failedFiles.isNotEmpty) ...[
const SizedBox(height: 12),
const Text(
'Failed files:',
style: TextStyle(
color: Colors.redAccent,
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 5),
..._failedFiles.map(
(file) => Padding(
padding: const EdgeInsets.only(bottom: 4),
child: Text(
'• ${file.name}',
style: const TextStyle(
color: Colors.redAccent,
fontSize: 12,
),
),
),
),
const SizedBox(height: 8),
OutlinedButton.icon(
onPressed: _sending ? null : _retryFailedFiles,
icon: const Icon(Icons.refresh_rounded),
label: const Text('Retry Failed Files'),
style: OutlinedButton.styleFrom(
foregroundColor: _green,
side: const BorderSide(color: _green),
),
),
],
],
),
);
}

@override
Widget build(BuildContext context) {
return Scaffold(
backgroundColor: _background,
appBar: AppBar(
title: const Text('Transfer Files'),
backgroundColor: _background,
foregroundColor: Colors.white,
elevation: 0,
actions: [
if (_selectedFiles.isNotEmpty && !_sending)
IconButton(
tooltip: 'Clear selected files',
onPressed: _clearFiles,
icon: const Icon(Icons.delete_sweep_rounded),
),
],
),
body: SafeArea(
child: Column(
children: [
Container(
width: double.infinity,
padding: const EdgeInsets.all(16),
color: _panel,
child: Column(
crossAxisAlignment: CrossAxisAlignment.start,
children: [
const Row(
children: [
Icon(Icons.devices_rounded, color: _green),
SizedBox(width: 8),
Text(
'MAFX SHARE',
style: TextStyle(
color: Colors.white,
fontWeight: FontWeight.bold,
fontSize: 18,
),
),
],
),
const SizedBox(height: 12),
const Text(
'Receiver address',
style: TextStyle(color: Colors.white60, fontSize: 12),
),
const SizedBox(height: 4),
SelectableText(
widget.receiverUrl,
style: const TextStyle(
color: _green,
fontWeight: FontWeight.w600,
),
),
const SizedBox(height: 8),
Text(
'Category: ${widget.category ?? 'Files'}',
style: const TextStyle(color: Colors.white70),
),
const SizedBox(height: 8),
Container(
padding: const EdgeInsets.symmetric(
horizontal: 10,
vertical: 7,
),
decoration: BoxDecoration(
color: _isHighSpeed
? _green.withValues(alpha: 0.12)
: Colors.white.withValues(alpha: 0.06),
borderRadius: BorderRadius.circular(10),
border: Border.all(
color: _isHighSpeed ? _green : Colors.white24,
),
),
child: Row(
mainAxisSize: MainAxisSize.min,
children: [
Icon(
_isHighSpeed
? Icons.bolt_rounded
: Icons.speed_rounded,
size: 18,
color: _isHighSpeed ? _green : Colors.white70,
),
const SizedBox(width: 6),
Text(
_isHighSpeed
? '5G+ High-Speed Mode'
: 'Standard Transfer Mode',
style: TextStyle(
color: _isHighSpeed ? _green : Colors.white70,
fontWeight: FontWeight.w600,
fontSize: 12,
),
),
],
),
),
if (_isHighSpeed && widget.receiverTcpPort != null) ...[
const SizedBox(height: 8),
Text(
'High-Speed TCP port: ${widget.receiverTcpPort}',
style: const TextStyle(
color: Colors.white60,
fontSize: 12,
),
),
],
const SizedBox(height: 8),
Text(
'${_selectedFiles.length} file(s) selected',
style: const TextStyle(color: _green),
),
],
),
),
Padding(
padding: const EdgeInsets.all(16),
child: Row(
children: [
Expanded(
child: OutlinedButton.icon(
onPressed: _sending ? null : _pickFiles,
icon: const Icon(Icons.add_rounded),
label: const Text('Add Files'),
style: OutlinedButton.styleFrom(
foregroundColor: _green,
side: const BorderSide(color: _green),
padding: const EdgeInsets.symmetric(vertical: 14),
),
),
),
const SizedBox(width: 12),
Expanded(
child: ElevatedButton.icon(
onPressed: _sending || _selectedFiles.isEmpty
? null
: _sendFiles,
icon: Icon(
_sending
? Icons.sync_rounded
: Icons.send_rounded,
),
label: Text(_sending ? 'Sending...' : 'Send Now'),
style: ElevatedButton.styleFrom(
backgroundColor: _green,
foregroundColor: Colors.black,
padding: const EdgeInsets.symmetric(vertical: 14),
),
),
),
],
),
),
if (_selectedFiles.isNotEmpty)
Padding(
padding: const EdgeInsets.symmetric(horizontal: 16),
child: Row(
children: [
const Expanded(
child: Text(
'Selected files',
style: TextStyle(
color: Colors.white,
fontSize: 16,
fontWeight: FontWeight.bold,
),
),
),
Text(
'${_selectedFiles.length} item(s)',
style: const TextStyle(
color: Colors.white60,
fontSize: 12,
),
),
],
),
),
const SizedBox(height: 8),
Expanded(
child: _selectedFiles.isEmpty
? Center(
child: Padding(
padding: const EdgeInsets.all(28),
child: Column(
mainAxisAlignment: MainAxisAlignment.center,
children: [
Icon(
Icons.folder_open_rounded,
size: 76,
color: Colors.white.withValues(alpha: 0.25),
),
const SizedBox(height: 16),
const Text(
'No files selected',
style: TextStyle(
color: Colors.white,
fontSize: 19,
fontWeight: FontWeight.bold,
),
),
const SizedBox(height: 8),
const Text(
'Tap Add Files to choose photos, videos, music, '
'documents, or other files.',
textAlign: TextAlign.center,
style: TextStyle(
color: Colors.white60,
height: 1.5,
),
),
],
),
),
)
: ListView.builder(
padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
itemCount: _selectedFiles.length,
itemBuilder: (context, index) =>
_buildFileCard(_selectedFiles[index]),
),
),
if (_status.isNotEmpty) _buildProgressPanel(),
],
),
),
);
}
}

class _SelectedFile {
final String name;
final String path;
final int size;

const _SelectedFile({
required this.name,
required this.path,
required this.size,
});
}
