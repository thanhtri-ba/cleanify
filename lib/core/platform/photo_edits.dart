import 'dart:io' show Platform;

import 'package:flutter/services.dart';

/// Cầu nối tới PhotoKit (iOS): ảnh nào đã chỉnh sửa trong ứng dụng Ảnh, và
/// thumbnail của BẢN GỐC (chưa chỉnh). Xem AppDelegate.swift (PhotoEditsChannel).
/// Android không có cơ chế tương đương: mọi hàm trả về rỗng.
class PhotoEdits {
  static const _ch = MethodChannel('cleanify/photo_edits');

  bool get supported => Platform.isIOS;

  /// Trong [ids] (AssetEntity.id = localIdentifier), những ảnh có dữ liệu chỉnh sửa.
  Future<Set<String>> editedIds(List<String> ids) async {
    if (!supported || ids.isEmpty) return {};
    final r = await _ch.invokeListMethod<String>('editedIds', {'ids': ids});
    return {...?r};
  }

  /// Tổng và còn trống của bộ nhớ máy (byte); null nếu không đọc được.
  Future<({int total, int free})?> storage() async {
    if (!supported) return null;
    final r = await _ch.invokeMapMethod<String, int>('storage', {'ids': <String>[]});
    final t = r?['total'];
    final f = r?['free'];
    if (t == null || f == null) return null;
    return (total: t, free: f);
  }

  /// Id của mọi ảnh chụp màn hình, mới nhất trước.
  Future<List<String>> screenshotIds() async {
    if (!supported) return [];
    final r = await _ch
        .invokeListMethod<String>('screenshotIds', {'ids': <String>[]});
    return r ?? [];
  }

  /// Dung lượng file (byte) theo id, đọc từ metadata (không tải iCloud). Id không
  /// lấy được thì không có trong kết quả hoặc bằng 0.
  Future<Map<String, int>> fileSizes(List<String> ids) async {
    if (!supported || ids.isEmpty) return {};
    final r = await _ch.invokeMapMethod<String, int>('fileSizes', {'ids': ids});
    return r ?? {};
  }

  /// JPEG thumbnail bản gốc theo id. Ảnh không lấy được (vd. còn trên iCloud)
  /// không có trong kết quả.
  Future<Map<String, Uint8List>> originalThumbs(List<String> ids,
      {int size = 128}) async {
    if (!supported || ids.isEmpty) return {};
    final r = await _ch.invokeMapMethod<String, Uint8List>(
        'originalThumbs', {'ids': ids, 'size': size});
    return r ?? {};
  }
}
