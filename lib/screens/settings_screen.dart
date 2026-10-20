import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: const [
          Text(
            'Device',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppTheme.navy,
            ),
          ),
          SizedBox(height: 12),
          _SettingCard(
            icon: Icons.phone_android_rounded,
            title: 'Device Name',
            subtitle: 'MAFX-ANDROID',
          ),
          SizedBox(height: 24),
          Text(
            'Connection',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppTheme.navy,
            ),
          ),
          SizedBox(height: 12),
          _SettingCard(
            icon: Icons.wifi_rounded,
            title: 'Wi-Fi Direct',
            subtitle: 'Direct wireless connection',
          ),
          SizedBox(height: 12),
          _SettingCard(
            icon: Icons.wifi_tethering_rounded,
            title: 'Hotspot',
            subtitle: 'Connect using a local hotspot',
          ),
          SizedBox(height: 24),
          Text(
            'Transfer',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppTheme.navy,
            ),
          ),
          SizedBox(height: 12),
          _SettingCard(
            icon: Icons.speed_rounded,
            title: 'Transfer Speed',
            subtitle: 'Optimized transfer settings',
          ),
          SizedBox(height: 12),
          _SettingCard(
            icon: Icons.restart_alt_rounded,
            title: 'Automatic Resume',
            subtitle: 'Resume interrupted transfers',
          ),
          SizedBox(height: 24),
          Text(
            'About',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: AppTheme.navy,
            ),
          ),
          SizedBox(height: 12),
          _SettingCard(
            icon: Icons.info_outline_rounded,
            title: 'MAFX SHARE',
            subtitle: 'Version 1.0.0 • Flutter',
          ),
        ],
      ),
    );
  }
}

class _SettingCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SettingCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(17),
        border: Border.all(
          color: const Color(0xFFE5EDF4),
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 45,
          height: 45,
          decoration: BoxDecoration(
            color: const Color(0xFFE2F8EC),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(
            icon,
            color: AppTheme.green,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Text(subtitle),
      ),
    );
  }
}
