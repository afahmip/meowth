import 'package:flutter/material.dart';
import 'screens/home_screen.dart';

void main() {
  runApp(const MeowtApp());
}

class MeowtApp extends StatelessWidget {
  const MeowtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meowth',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF111827)),
        fontFamily: 'SF Pro Display',
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
