import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'connect_screen.dart';

/// Helps users prepare Wi-Fi/hotspot before opening the existing QR flow.
class ConnectionPrepScreen extends StatefulWidget {
  final TransferRole role;
  final String? category;

  const ConnectionPrepScreen({
    super.key,
    required this.role,
    this.category,
  });

  @override
  State<ConnectionPrepScreen> createState() => _ConnectionPrepScreenState();
}

class _ConnectionPrepScreenState extends State<ConnectionPrepScreen> {
  static const Color _green = Color(0xFF008D5A);
  static const Color _background = Color(0xFF19191D);
  static const MethodChannel _settings = MethodChannel('com.mafx.share/settings');

  bool _ready = false;
  bool _openingSettings = false;

  Future<void> _openSettings(String destination) async {
    setState(() => _openingSettings = true);
    try {
      await _settings.invokeMethod<void>('openNetworkSettings', {
        'destination': destination,
      });
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open settings: ${error.message ?? error.code}')),
        );
      }
    } finally {
      if (mounted) setState(() => _openingSettings = false);
    }
  }

  void _continue() {
    if (!_ready) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ConnectScreen(
          role: widget.role,
          category: widget.category,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isSender = widget.role == TransferRole.send;
    return Scaffold(
      backgroundColor: _background,
      appBar: AppBar(
        title: const Text('Prepare connection'),
        backgroundColor: _green,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const SizedBox(height: 8),
            Icon(isSender ? Icons.send_rounded : Icons.download_rounded,
                size: 64, color: const Color(0xFF00D18B)),
            const SizedBox(height: 18),
            Text(
              isSender ? 'Ready to send?' : 'Ready to receive?',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            const Text(
              'Connect both phones to the same Wi-Fi network, or turn on a hotspot on one phone and connect the other phone to it.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, height: 1.5),
            ),
            const SizedBox(height: 28),
            _SettingsButton(
              icon: Icons.wifi_rounded,
              title: 'Open Wi-Fi settings',
              subtitle: 'Connect to the same Wi-Fi network',
              onPressed: _openingSettings ? null : () => _openSettings('wifi'),
            ),
            const SizedBox(height: 12),
            _SettingsButton(
              icon: Icons.wifi_tethering_rounded,
              title: 'Open hotspot settings',
              subtitle: 'Turn on hotspot if you are sharing without a router',
              onPressed: _openingSettings ? null : () => _openSettings('hotspot'),
            ),
            const SizedBox(height: 22),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF29292F),
                borderRadius: BorderRadius.circular(14),
              ),
              child: CheckboxListTile(
                value: _ready,
                onChanged: (value) => setState(() => _ready = value ?? false),
                activeColor: _green,
                checkColor: Colors.white,
                title: const Text('I have prepared the Wi-Fi or hotspot connection',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
                subtitle: const Text('Next will open the QR code or scanner.',
                    style: TextStyle(color: Colors.white70)),
                controlAffinity: ListTileControlAffinity.leading,
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              height: 52,
              child: FilledButton.icon(
                onPressed: _ready ? _continue : null,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('NEXT'),
                style: FilledButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: Colors.white12,
                  disabledForegroundColor: Colors.white38,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onPressed;

  const _SettingsButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: const Color(0xFF29292F),
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(icon, color: const Color(0xFF00D18B), size: 30),
        title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle, style: const TextStyle(color: Colors.white70)),
        trailing: const Icon(Icons.open_in_new_rounded, color: Colors.white70),
        onTap: onPressed,
      ),
    );
  }
}
