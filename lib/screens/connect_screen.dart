import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'qr_screen.dart';
import 'scan_qr_screen.dart';

class ConnectScreen extends StatelessWidget {
  const ConnectScreen({super.key});

  Future<void> _scanQr(BuildContext context) async {
    final result = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => const ScanQrScreen(),
      ),
    );

    if (!context.mounted || result == null) return;

    final mode = result['mode'] == '5G_PLUS' ? '5G+' : 'Standard';
    final session = result['session']?.toString() ?? '';

    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('QR Code Recognized'),
        content: Text(
          'Mode: $mode\n\n'
          'Session: $session\n\n'
          'An gano QR code ɗin MAFX SHARE. '
          'Haɗin na’urori da tura fayiloli ba su kammala ba tukuna.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showMyQr(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const QrScreen(),
      ),
    );
  }

  void _showInfo(BuildContext context, String title, String message) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Device'),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const SizedBox(height: 12),
          const Icon(
            Icons.devices_rounded,
            size: 76,
            color: Color(0xFF00AEEF),
          ),
          const SizedBox(height: 16),
          Text(
            'Connect Your Devices',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Choose how you want to connect your devices.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 28),

          _ConnectOption(
            icon: Icons.qr_code_2_rounded,
            title: 'Show My QR Code',
            subtitle: 'Display a QR code for another device to scan',
            color: const Color(0xFF00AEEF),
            onTap: () => _showMyQr(context),
          ),

          const SizedBox(height: 14),

          _ConnectOption(
            icon: Icons.qr_code_scanner_rounded,
            title: 'Scan QR Code',
            subtitle: 'Scan a MAFX SHARE QR code with your camera',
            color: Colors.green,
            onTap: () => _scanQr(context),
          ),

          const SizedBox(height: 14),

          _ConnectOption(
            icon: Icons.wifi_rounded,
            title: 'Wi-Fi / Hotspot',
            subtitle: 'Connection support is still being developed',
            color: Colors.orange,
            onTap: () => _showInfo(
              context,
              'Wi-Fi / Hotspot',
              'The actual device connection and file-transfer service '
                  'has not been implemented yet.',
            ),
          ),

          const SizedBox(height: 24),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF00AEEF).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFF00AEEF).withValues(alpha: 0.25),
              ),
            ),
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF00AEEF),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'QR generation and scanning are being connected '
                    'to the transfer system. Reading a QR code alone '
                    'does not establish a device connection.',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ConnectOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _ConnectOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 12,
        ),
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: color, size: 28),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 5),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        onTap: onTap,
      ),
    );
  }
}
