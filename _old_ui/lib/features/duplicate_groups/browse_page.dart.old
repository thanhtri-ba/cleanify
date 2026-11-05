import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:photo_manager_image_provider/photo_manager_image_provider.dart';

import '../../core/scanner/scan_session.dart' show cosineBand;
import '../scan/scan_controller.dart';

/// Lưới tất cả ảnh đã quét. Chạm vào một ảnh để xem các ảnh giống nó nhất theo AI.
/// Chỉ xem, không có thao tác xóa.
class BrowsePage extends StatelessWidget {
  const BrowsePage({super.key, required this.controller});
  final ScanController controller;

  @override
  Widget build(BuildContext context) {
    final s = controller.session;
    final assets = s?.assets ?? const <AssetEntity>[];
    final hasEmb = s?.embeddings.isNotEmpty ?? false;
    return Scaffold(
      appBar: AppBar(title: Text('Tất cả ảnh (${assets.length})')),
      body: Column(children: [
        if (!hasEmb)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('Chưa có dữ liệu AI cho lần quét này (bước AI bị bỏ qua '
                'hoặc lỗi), nên chưa xem được ảnh giống nhau.'),
          ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(4),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4, mainAxisSpacing: 2, crossAxisSpacing: 2),
            itemCount: assets.length,
            itemBuilder: (_, i) => GestureDetector(
              onTap: hasEmb
                  ? () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => NeighborsPage(
                          controller: controller, asset: assets[i])))
                  : null,
              child: AssetEntityImage(assets[i],
                  isOriginal: false,
                  thumbnailSize: const ThumbnailSize.square(200),
                  fit: BoxFit.cover),
            ),
          ),
        ),
      ]),
    );
  }
}

/// Ảnh được chọn ở trên cùng, bên dưới là các ảnh giống nó nhất (cosine giảm dần).
/// Dùng để tự quan sát mô hình thấy gì giống nhau, từ đó chọn mức "Độ nhạy" hợp lý.
class NeighborsPage extends StatelessWidget {
  const NeighborsPage(
      {super.key, required this.controller, required this.asset});
  final ScanController controller;
  final AssetEntity asset;

  @override
  Widget build(BuildContext context) {
    final nb = controller.session?.neighborsOf(asset.id, k: 40) ?? const [];
    return Scaffold(
      appBar: AppBar(title: const Text('Ảnh giống nhất')),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
          child: AspectRatio(
            aspectRatio: 1.3,
            child: AssetEntityImage(asset,
                isOriginal: false,
                thumbnailSize: const ThumbnailSize.square(800),
                fit: BoxFit.contain),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.all(4),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3, mainAxisSpacing: 4, crossAxisSpacing: 4),
            delegate: SliverChildBuilderDelegate(
              childCount: nb.length,
              (_, i) => Stack(fit: StackFit.expand, children: [
                AssetEntityImage(nb[i].asset,
                    isOriginal: false,
                    thumbnailSize: const ThumbnailSize.square(400),
                    fit: BoxFit.cover),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: Colors.black54,
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(
                        '#${i + 1} · ${cosineBand(nb[i].cosine)} · ${nb[i].cosine.toStringAsFixed(2)}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white, fontSize: 11)),
                  ),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }
}
