import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class ConnectScreen extends StatelessWidget {
  const ConnectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Connect Device'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [
                  Color(0xFF06253E),
                  Color(0xFF075C64),
                ],
              ),
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.wifi_tethering_rounded,
                  color: Color(0xFF43E8A0),
                  size: 78,
                ),
                SizedBox(height: 18),
                Text(
                  'Connect nearby devices',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Choose a connection method to begin.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white70,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          _ConnectOption(
            icon: Icons.qr_code_scanner_rounded,
            title: 'Scan QR Code',
            subtitle: 'Connect by scanning another phone',
            onTap: () => _showComingSoon(context),
          ),
          const SizedBox(height: 12),
          _ConnectOption(
            icon: Icons.devices_rounded,
            title: 'Nearby Devices',
            subtitle: 'Discover devices on your network',
            onTap: () => _showComingSoon(context),
          ),
          const SizedBox(height: 12),
          _ConnectOption(
            icon: Icons.wifi_tethering_rounded,
            title: 'Wi-Fi Direct / Hotspot',
            subtitle: 'Connect without mobile internet',
            onTap: () => _showComingSoon(context),
          ),
        ],
      ),
    );
  }

  void _showComingSoon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Connection functionality will be implemented next.',
        ),
      ),
    );
  }
}

class _ConnectOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ConnectOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(
          color: Color(0xFFE5EDF4),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(15),
        leading: Icon(
          icon,
          color: AppTheme.green,
          size: 30,
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right_rounded),
        onTap: onTap,
      ),
    );
  }
}
