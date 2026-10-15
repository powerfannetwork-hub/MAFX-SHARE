import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

class TransfersScreen extends StatelessWidget {
  const TransfersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Transfers'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: const Color(0xFFE5EDF4),
              ),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.swap_vert_circle_rounded,
                  color: AppTheme.green,
                  size: 48,
                ),
                SizedBox(height: 16),
                Text(
                  'No active transfers',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Your transfer progress, speed and remaining '
                  'time will appear here when a transfer starts.',
                  style: TextStyle(
                    color: Colors.blueGrey,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          const _TransferInfoCard(
            icon: Icons.speed_rounded,
            title: 'Transfer Speed',
            subtitle: 'Waiting for a transfer',
          ),
          const SizedBox(height: 12),
          const _TransferInfoCard(
            icon: Icons.restart_alt_rounded,
            title: 'Resume Transfer',
            subtitle: 'Continue interrupted transfers',
          ),
        ],
      ),
    );
  }
}

class _TransferInfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _TransferInfoCard({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      child: ListTile(
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
      ),
    );
  }
}
