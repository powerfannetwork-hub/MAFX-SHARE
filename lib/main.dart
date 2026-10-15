import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'send_screen.dart';
import 'receive_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF12121A),
      body: SafeArea(
        child: Column(
          children: [
            const SizedBox(height: 80),
            Text(
              "Transfer Files Instantly",
              style: GoogleFonts.poppins(
                fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white),
            ),
            const SizedBox(height: 8),
            Text(
              "Share photos, videos, documents without internet",
              style: GoogleFonts.poppins(fontSize: 13, color: Colors.white54),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
            // SEND BUTTON
            _MainButton(
              text: "SEND",
              color: const Color(0xFF3A7BFF),
              icon: Icons.send_rounded,
              onTap: () => Navigator.push(context, 
                MaterialPageRoute(builder: (_) => const SendScreen())),
            ),
            const SizedBox(height: 20),
            // RECEIVED BUTTON
            _MainButton(
              text: "RECEIVED",
              color: const Color(0xFF00C876),
              icon: Icons.download_rounded,
              onTap: () => Navigator.push(context, 
                MaterialPageRoute(builder: (_) => const ReceiveScreen())),
            ),
            const Spacer(),
            const Text("✓ Fast Transfer • No Internet", 
              style: TextStyle(color: Colors.greenAccent, fontSize: 12)),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class _MainButton extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _MainButton({required this.text, required this.color, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: MediaQuery.of(context).size.width * 0.85,
        height: 90,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 36, color: Colors.white),
            const SizedBox(width: 12),
            Text(text, style: GoogleFonts.poppins(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }
}
