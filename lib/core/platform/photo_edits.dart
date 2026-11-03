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
