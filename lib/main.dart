import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import 'features/home/home_page.dart';
import 'features/onboarding/onboarding_flow.dart';
import 'core/platform/scan_notifier.dart';
import 'features/scan/scan_controller.dart';
import 'theme/app_theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  ScanNotifier.instance.init();
  runApp(const CleanifyApp());
}

class CleanifyApp extends StatefulWidget {
  const CleanifyApp({super.key});

  @override
  State<CleanifyApp> createState() => _CleanifyAppState();
}

class _CleanifyAppState extends State<CleanifyApp> {
  /// null = đang kiểm tra quyền; true = chưa từng được hỏi quyền Ảnh.
  /// Không lưu cờ xuống đĩa: onboarding chỉ hiện khi quyền còn notDetermined.
  bool? _showOnboarding;
  final ScanController _scan = ScanController();

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    var show = false;
    try {
      final s = await PhotoManager.getPermissionState(
          requestOption: const PermissionRequestOption());
      show = s == PermissionState.notDetermined;
    } catch (_) {}
    if (mounted) setState(() => _showOnboarding = show);
  }

  @override
  void dispose() {
    _scan.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cleanify',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.light,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      home: switch (_showOnboarding) {
        null => const Scaffold(),
        true => OnboardingFlow(
            onFinished: () => setState(() => _showOnboarding = false)),
        false => HomePage(controller: _scan),
      },
    );
  }
}
