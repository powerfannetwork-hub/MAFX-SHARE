import 'package:flutter/material.dart';

class AppTheme {
  static const Color green = Color(0xFF08A85A);
  static const Color blue = Color(0xFF1478F8);
  static const Color navy = Color(0xFF062B45);
  static const Color background = Color(0xFFF4F8FC);

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: green,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: navy,
        centerTitle: false,
      ),
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: Color(0xFFDDF8E9),
      ),
    );
  }
}
