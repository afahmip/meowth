import 'package:flutter/material.dart';
import 'config.dart';

void main() {
  runApp(const MeowtApp());
}

class MeowtApp extends StatelessWidget {
  const MeowtApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Meowth',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Meowth'),
      ),
      body: Center(
        child: Text(
          'API: ${AppConfig.baseUrl}',
          style: Theme.of(context).textTheme.bodyLarge,
        ),
      ),
    );
  }
}
