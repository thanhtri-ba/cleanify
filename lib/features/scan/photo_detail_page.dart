import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/scanner/scan_session.dart';
import '../../theme/motion.dart';
import '../home/home_kit.dart';
import '../../theme/app_icons.dart';
import '../../theme/app_icon.dart';

/// Kết quả so sánh pixel hai ảnh (thu nhỏ). [differentPercent] là tỉ lệ điểm ảnh
/// khác nhau rõ rệt, KHÔNG phải độ giống PDQ; heatmap là PNG RGBA trong suốt, chỗ
/// đỏ là chỗ khác.
class PixelDiff {
  const PixelDiff(this.differentPercent, this.heatmapPng);
  final double differentPercent;
  final Uint8List heatmapPng;
  double get samePercent => 100 - differentPercent;
}

const int _diffSide = 96;
const int _diffThreshold = 32; // chênh luminance (0-255) coi là "khác"

/// Chạy trong isolate qua [compute]: nhận bytes ảnh đã thu nhỏ của hai ảnh.
PixelDiff computePixelDiff(List<Uint8List> pair) {
  Uint8List lum(Uint8List bytes) {
    final d = img.decodeImage(bytes);
    if (d == null) return Uint8List(_diffSide * _diffSide);
    final s = img.copyResize(d,
        width: _diffSide,
        height: _diffSide,
        interpolation: img.Interpolation.average);
    final out = Uint8List(_diffSide * _diffSide);
    for (var y = 0; y < _diffSide; y++) {
      for (var x = 0; x < _diffSide; x++) {
        final p = s.getPixel(x, y);
        out[y * _diffSide + x] =
            (0.299 * p.r + 0.587 * p.g + 0.114 * p.b).round().clamp(0, 255);
      }
    }
    return out;
  }

  final a = lum(pair[0]);
  final b = lum(pair[1]);
  final heat = img.Image(width: _diffSide, height: _diffSide, numChannels: 4);
  var diff = 0;
  for (var y = 0; y < _diffSide; y++) {
    for (var x = 0; x < _diffSide; x++) {
      final i = y * _diffSide + x;
      final d = (a[i] - b[i]).abs();
      if (d > _diffThreshold) {
        diff++;
        heat.setPixelRgba(x, y, 230, 60, 60, math.min(220, 90 + d));
      } else {
        heat.setPixelRgba(x, y, 0, 0, 0, 0);
      }
    }
  }
  return PixelDiff(100 * diff / (_diffSide * _diffSide),
      Uint8List.fromList(img.encodePng(heat)));
}

/// Xem chi tiết một nhóm: vuốt qua từng ảnh, xem thông tin, độ giống với ảnh giữ
/// (đại diện) và, nếu người dùng muốn, so sánh điểm giống/khác. Chỉ xem, không xóa.
class PhotoDetailPage extends StatefulWidget {
  const PhotoDetailPage({super.key, required this.group, this.initialIndex = 0});
  final DuplicateGroup group;
  final int initialIndex;
  @override
  State<PhotoDetailPage> createState() => _PhotoDetailPageState();
}

class _PhotoDetailPageState extends State<PhotoDetailPage> {
  late final PageController _pc = PageController(initialPage: widget.initialIndex);
  late int _i = widget.initialIndex;
  final Map<int, Future<PixelDiff>> _diffs = {};
  bool _showDiff = false;
  bool _diffRequested = false; // đã từng bật: chỉ tính heatmap khi khách yêu cầu

  List<DuplicateItem> get _items => widget.group.items;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  Future<PixelDiff> _diffOf(int index) => _diffs.putIfAbsent(index, () async {
        final a = await _items.first.asset
            .thumbnailDataWithSize(const ThumbnailSize.square(192));
        final b = await _items[index]
            .asset
            .thumbnailDataWithSize(const ThumbnailSize.square(192));
        if (a == null || b == null) {
          throw StateError('Không đọc được ảnh để so sánh');
        }
        return compute(computePixelDiff, [a, b]);
      });

  String _date(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final it = _items[_i];
    final isRep = _i == 0;
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(children: [
          HTopBar(
              title: 'Ảnh ${_i + 1}/${_items.length}',
              onBack: () => Navigator.of(context).pop()),
          Expanded(
            flex: 5,
            child: PageView.builder(
              controller: _pc,
              itemCount: _items.length,
              onPageChanged: (v) => setState(() => _i = v),
              itemBuilder: (_, k) => InteractiveViewer(
                child: Stack(fit: StackFit.expand, children: [
                  Hero(
                    tag: 'photo_${_items[k].asset.id}',
                    child: AssetEntityImage(_items[k].asset,
                        isOriginal: false,
                        fit: BoxFit.contain,
                        thumbnailSize: const ThumbnailSize.square(1400)),
                  ),
                  if (_diffRequested && k != 0)
                    AnimatedOpacity(
                      opacity: _showDiff ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: _heatmap(k),
                    ),
                ]),
              ),
            ),
          ),
          Expanded(
            flex: 4,
            child: ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 16), children: [
              HCard(
                padding: 14,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _row('Vai trò', isRep ? 'Ảnh đề xuất giữ (độ phân giải cao nhất)' : 'Ảnh so với ảnh giữ'),
                  _row('Độ phân giải', '${it.asset.width} × ${it.asset.height}'),
                  _row('Ngày tạo', _date(it.asset.createDateTime)),
                  if (!isRep) ..._similarityRows(it),
                ]),
              ),
              if (!isRep) ...[
                const SizedBox(height: 12),
                if (!_showDiff)
                  OutlinedButton.icon(
                    onPressed: () => setState(() {
                      _diffRequested = true;
                      _showDiff = true;
                    }),
                    icon: const AppIcon(AppIcons.compareOutlined, size: 18),
                    label: const Text('Xem điểm giống / khác'),
                  )
                else
                  _diffCard(_i),
              ],
            ]),
          ),
        ]),
      ),
    );
  }

  List<Widget> _similarityRows(DuplicateItem it) {
    if (it.exact) {
      return [_row('Độ giống', 'Giống hệt (cùng SHA-256)')];
    }
    final s = it.similarity;
    if (s == null) return [_row('Độ giống', 'Không có điểm số (nhóm theo cách khác)')];
    final h = (256 * (1 - s / 100)).round();
    return [
      _row('Độ giống (PDQ)', '${s.toStringAsFixed(1)}%'),
      _row('Hamming', '$h / 256 bit khác'),
    ];
  }

  Widget _heatmap(int k) => FutureBuilder<PixelDiff>(
        future: _diffOf(k),
        builder: (_, snap) => snap.hasData
            ? IgnorePointer(
                child: Image.memory(snap.data!.heatmapPng,
                    fit: BoxFit.fill, filterQuality: FilterQuality.low))
            : const SizedBox.shrink(),
      );

  Widget _diffCard(int k) => FutureBuilder<PixelDiff>(
        future: _diffOf(k),
        builder: (_, snap) {
          if (snap.hasError) {
            return const Text('Không so sánh được hai ảnh này.',
                style: TextStyle(fontSize: 13, color: kInk3));
          }
          if (!snap.hasData) {
            return const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
            );
          }
          final d = snap.data!;
          return HCard(
            padding: 14,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              CountUp(
                  value: d.samePercent,
                  decimals: 1,
                  builder: (t) => _row('Điểm giống', '$t%')),
              CountUp(
                  value: d.differentPercent,
                  decimals: 1,
                  builder: (t) => _row('Điểm khác', '$t%')),
              const SizedBox(height: 4),
              const Text(
                  'Vùng đỏ trên ảnh là chỗ khác so với ảnh giữ. Đây là so sánh điểm ảnh '
                  'trên bản thu nhỏ, chỉ mang tính tham khảo (ảnh lệch khung sẽ báo khác nhiều).',
                  style: TextStyle(fontSize: 12, height: 1.4, color: kInk3)),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                    onPressed: () => setState(() => _showDiff = false),
                    child: const Text('Ẩn', style: TextStyle(color: kInk))),
              ),
            ]),
          );
        },
      );

  Widget _row(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 120,
              child: Text(k, style: const TextStyle(fontSize: 13, color: kInk3))),
          Expanded(
              child: Text(v,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600, color: kInk))),
        ]),
      );
}
