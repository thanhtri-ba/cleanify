# Cleanify — Stateless Offline Image Scanner

Quét ảnh trùng hoàn toàn trên thiết bị. **Không SQLite, không database, không lưu lịch sử quét.**
Kết quả nằm trong `ScanSession` (RAM), mất khi đóng app hoặc khi bấm "Xóa kết quả khỏi bộ nhớ".

## Pipeline

SHA-256 (stream, exact) → PDQ-style 256-bit hash (thumbnail 128px → 64×64 → DCT 16×16) →
LSH (16 band × 16 bit) + Hamming → (tùy chọn) DINO xác minh vùng mơ hồ → nhóm bằng Union-Find.

Batch mặc định 256 ảnh, I/O song song 16, Hamming ≤ 24 (chắc chắn ≤ 12). Đây là điểm khởi đầu, cần benchmark.

## Dùng vào project Cleanify có sẵn

1. Sao chép `lib/` và `test/` vào project (thay `main.dart` nếu chưa có gì quan trọng).
2. Gộp `dependencies` trong `pubspec.yaml`: `photo_manager`, `photo_manager_image_provider`, `crypto`, `image`.
3. `flutter pub get`
4. Quyền truy cập:
   - **Android** (`android/app/src/main/AndroidManifest.xml`):
     ```xml
     <uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>
     <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE" android:maxSdkVersion="32"/>
     ```
     `minSdkVersion` ≥ 21 (theo yêu cầu của photo_manager).
   - **iOS** (`ios/Runner/Info.plist`):
     ```xml
     <key>NSPhotoLibraryUsageDescription</key>
     <string>Cleanify cần đọc thư viện ảnh để tìm ảnh trùng.</string>
     ```
5. `flutter test` rồi `flutter run` trên thiết bị thật (cần ảnh trong thư viện).

## Deep Scan (chưa bật)

`lib/engines/dino/dino_engine.dart` là interface. Cần: file `dino.onnx`, input size, số chiều embedding.
Khi có, viết implementation ONNX Runtime Mobile và truyền vào `ScanOrchestrator(dino: ...)`.
Hiện Deep Scan chỉ xác minh cặp mơ hồ do PDQ tìm ra; tìm "cùng vật thể khác góc chụp" cần tầng
tìm ứng viên riêng (xem mục DINO trong tài liệu kiến trúc).
# cleanify
