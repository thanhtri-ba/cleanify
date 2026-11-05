import 'package:flutter/material.dart';

import '../../theme/widgets.dart';
import '../home/home_kit.dart';
import 'scan_controller.dart';
import 'smart_scan_page.dart';
import '../../theme/app_icons.dart';

/// Màn "Quét thất bại" (Figma 1:702).
class ScanErrorPage extends StatelessWidget {
  const ScanErrorPage({super.key, required this.controller});
  final ScanController controller;

  void _home(BuildContext context) =>
      Navigator.of(context).popUntil((r) => r.isFirst);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Stack(children: [
        const Positioned(top: 0, left: 0, right: 0, child: Aura()),
        SafeArea(
        child: Column(children: [
          HTopBar(title: 'Quét dung lượng', onBack: () => _home(context)),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(children: [
              HCard(
                padding: 20,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Row(children: [
                    HDisc(AppIcons.autoAwesomeOutlined, size: 40),
                    SizedBox(width: 12),
                    Expanded(
                      child: Text('Chưa quét xong.',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: kInk)),
                    ),
                  ]),
                  const SizedBox(height: 12),
                  Text(controller.error ?? 'Thư viện ảnh tạm thời không khả dụng. Hãy thử lại sau giây lát.',
                      style: const TextStyle(fontSize: 14, height: 1.5, color: kInk3)),
                ]),
              ),
              const SizedBox(height: 14),
              SlateButton(
                label: 'Thử lại',
                onPressed: () {
                  controller.start();
                  Navigator.of(context).pushReplacement(MaterialPageRoute(
                      builder: (_) => SmartScanPage(controller: controller)));
                },
              ),
              const SizedBox(height: 12),
              const Text('Không có ảnh hay video nào bị xóa. Bạn có thể thử lại an toàn.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: kInk3)),
            ]),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: OutlineBtn(label: '‹ Về màn quét', onPressed: () => _home(context)),
          ),
        ]),
      ),
      ]),
    );
  }
}
