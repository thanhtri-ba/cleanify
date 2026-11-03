import 'package:flutter/material.dart';

import 'core/scanner/scan_orchestrator.dart';
import 'features/scan/home_page.dart';
import 'features/scan/scan_controller.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const CleanifyApp());
}

class CleanifyApp extends StatefulWidget {
  const CleanifyApp({super.key});

  @override
  State<CleanifyApp> createState() => _CleanifyAppState();
}

class _CleanifyAppState extends State<CleanifyApp> {
  final _controller = ScanController(orchestrator: ScanOrchestrator());

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cleanify',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
      ),
      home: HomePage(controller: _controller),
    );
  }
}
