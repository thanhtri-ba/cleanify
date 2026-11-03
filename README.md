# Cleanify — Stateless Offline Image Scanner

Quét ảnh trùng hoàn toàn trên thiết bị. **Không SQLite, không database, không lưu lịch sử quét.**
Kết quả nằm trong `ScanSession` (RAM), mất khi đóng app hoặc khi bấm "Xóa kết quả khỏi bộ nhớ".

## Pipeline

SHA-256 (stream, exact) → PDQ-style 256-bit hash (thumbnail 128px → 64×64 → DCT 16×16) →
Hamming (≤ 40 trên 256 bit, tức độ giống PDQ ≥ 84%) → nhóm bằng Union-Find.

Thư viện tới 6000 ảnh so mọi cặp (không sót); lớn hơn dùng LSH (16 band × 16 bit), recall của cặp Hamming cao là xác suất.
SHA-256 chỉ tính cho ảnh nghi trùng (PDQ trùng khít hoặc nằm trong cặp ứng viên). Batch 128 ảnh, thumbnail song song 8.

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
