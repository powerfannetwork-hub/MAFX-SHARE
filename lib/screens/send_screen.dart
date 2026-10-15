import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'connect_screen.dart';

class SendScreen extends StatelessWidget {
  final String? category;

  const SendScreen({
    super.key,
    this.category,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Photos', Icons.photo_library_rounded, Colors.green),
      ('Videos', Icons.video_library_rounded, Colors.blue),
      ('Music', Icons.music_note_rounded, Colors.purple),
      ('Apps', Icons.apps_rounded, Colors.orange),
      ('Files', Icons.folder_rounded, Colors.teal),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Send Files'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Choose what to send',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: AppTheme.navy,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Select a category to browse your files.',
              style: TextStyle(color: Colors.blueGrey),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) =>
                    const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final item = items[index];

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
                      contentPadding: const EdgeInsets.all(12),
                      leading: CircleAvatar(
                        radius: 25,
                        backgroundColor:
                            item.$3.withValues(alpha: 0.12),
                        child: Icon(
                          item.$2,
                          color: item.$3,
                        ),
                      ),
                      title: Text(
                        item.$1,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      subtitle: Text(
                        'Browse ${item.$1.toLowerCase()}',
                      ),
                      trailing: const Icon(
                        Icons.chevron_right_rounded,
                      ),
                      onTap: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              '${item.$1} file selection will be added next.',
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => const ConnectScreen(),
                    ),
                  );
                },
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text('CONNECT DEVICE'),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.green,
                  foregroundColor: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
