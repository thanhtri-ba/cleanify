import 'dart:async';
import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';

import '../../core/scanner/scan_progress.dart';
import '../duplicate_groups/results_page.dart';
import 'scan_controller.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller});
  final ScanController controller;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Cleanify')),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: controller,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 8),
                Icon(Icons.photo_library_outlined,
                    size: 72, color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text('Dọn ảnh trùng',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text(
                  'Quét hoàn toàn trên thiết bị. Không lưu lịch sử, '
                  'kết quả chỉ nằm trong bộ nhớ và mất khi đóng app.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 24),
                const SizedBox(height: 16),
                _StatusArea(controller: controller),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Bảng thời gian từng giai đoạn của lần quét (hiện cả khi đang quét).
class TimingsCard extends StatelessWidget {
  const TimingsCard({super.key, required this.timings});
  final List<String> timings;

  @override
  Widget build(BuildContext context) {
    if (timings.isEmpty) return const SizedBox.shrink();
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Thời gian xử lý',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            SelectableText(
              timings.join('\n'),
              style: const TextStyle(
                  fontFamily: 'Menlo', fontSize: 12, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusArea extends StatelessWidget {
  const _StatusArea({required this.controller});
  final ScanController controller;

  @override
  Widget build(BuildContext context) {
    switch (controller.status) {
      case ScanStatus.idle:
        return Align(
          alignment: Alignment.topCenter,
          child: FilledButton.icon(
            onPressed: controller.start,
            icon: const Icon(Icons.search),
            label: const Text('Bắt đầu quét'),
          ),
        );
      case ScanStatus.scanning:
        final p = controller.progress;
        return Column(
          children: [
            LinearProgressIndicator(value: p?.fraction),
            const SizedBox(height: 12),
            Text(controller.paused ? 'Đã tạm dừng' : (p?.label ?? 'Đang chuẩn bị…')),
            const SizedBox(height: 8),
            _ElapsedTimer(controller: controller),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: controller.paused ? controller.resume : controller.pause,
                  icon: Icon(controller.paused ? Icons.play_arrow : Icons.pause),
                  label: Text(controller.paused ? 'Tiếp tục' : 'Tạm dừng'),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: controller.cancel,
                  child: const Text('Hủy'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Tạm dừng có hiệu lực ở ranh giới batch.',
              style: TextStyle(fontSize: 12),
            ),
            TimingsCard(timings: controller.session?.timings ?? const []),
          ],
        );
      case ScanStatus.error:
        return Column(
          children: [
            Text(controller.error ?? 'Lỗi không xác định',
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
            const SizedBox(height: 12),
            FilledButton(onPressed: controller.start, child: const Text('Thử lại')),
          ],
        );
      case ScanStatus.done:
        final s = controller.session!;
        return Column(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.check_circle_outline),
                title: Text('${s.groups.length} nhóm ảnh trùng'),
                subtitle: Text(
                  'Quét ${s.scanned} ảnh · '
                  '${s.reclaimable} ảnh có thể dọn'
                  '${s.hashFailures > 0 ? ' · ${s.hashFailures} ảnh không đọc được' : ''}',
                ),
              ),
            ),
            TimingsCard(timings: s.timings),
            const SizedBox(height: 8),
            _ElapsedRow(label: 'Thời gian quét', text: formatElapsed(s.elapsed)),
            const SizedBox(height: 12),
            if (s.groups.isNotEmpty)
              FilledButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => ResultsPage(controller: controller),
                )),
                child: const Text('Xem kết quả'),
              ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: controller.start,
              child: const Text('Quét lại'),
            ),
            TextButton(
              onPressed: controller.clearResults,
              child: const Text('Xóa kết quả khỏi bộ nhớ'),
            ),
          ],
        );
    }
  }
}

/// Đồng hồ chạy khi đang quét. Chỉ rebuild đoạn text, không rebuild cả trang.
/// Stopwatch nằm ở [ScanController] nên tạm dừng thì giá trị đứng yên.
class _ElapsedTimer extends StatefulWidget {
  const _ElapsedTimer({required this.controller});
  final ScanController controller;

  @override
  State<_ElapsedTimer> createState() => _ElapsedTimerState();
}

class _ElapsedTimerState extends State<_ElapsedTimer> {
  late final Timer _ticker;
  late String _text = formatElapsed(widget.controller.elapsed);

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final next = formatElapsed(widget.controller.elapsed);
      if (next != _text) setState(() => _text = next);
    });
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _ElapsedRow(label: 'Đã chạy', text: _text);
}

class _ElapsedRow extends StatelessWidget {
  const _ElapsedRow({required this.label, required this.text});
  final String label;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.timer_outlined, size: 18),
        const SizedBox(width: 6),
        Text(
          '$label: $text',
          style: const TextStyle(
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
