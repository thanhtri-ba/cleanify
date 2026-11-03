import 'dart:io';

import 'package:crypto/crypto.dart';

/// SHA-256 của file, đọc theo stream từng khối — không nạp cả file vào RAM.
Future<String> sha256OfFile(String path) async {
  final digest = await sha256.bind(File(path).openRead()).first;
  return digest.toString();
}
