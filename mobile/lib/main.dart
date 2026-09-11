import 'package:flutter/material.dart';
import 'config.dart';
import 'screens/home_screen.dart';
import 'services/receipt_upload_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Registered before runApp so no status/progress update from
  // background_downloader is missed — including one delivered because the
  // OS just relaunched the app to report an upload that finished while it
  // was terminated.
  await ReceiptUploadManager.instance.init(AppConfig.baseUrl);
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
