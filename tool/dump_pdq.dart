// Băm PDQ bằng ĐÚNG code của app để đối chiếu với bản port Python.
//
// Chạy từ thư mục gốc dự án (đã `flutter pub get`):
//   dart run tool/dump_pdq.dart eval_out/thumbs128 eval_out/pdq_dart.csv
//
// Đầu vào : thư mục chứa thumbnail JPEG 128px (score_pairs.py tạo ra).
// Đầu ra  : CSV `file,pdq_hex` (4 word 64-bit, mỗi word 16 ký tự hex).
import 'dart:io';

import 'package:cleanify/engines/pdq/pdq_engine.dart';

void main(List<String> args) {
  if (args.length != 2) {
    stderr.writeln('Dùng: dart run tool/dump_pdq.dart <thư_mục_thumbs> <file_csv_ra>');
    exit(64);
  }
  final files = Directory(args[0])
      .listSync()
      .whereType<File>()
      .where((f) => f.path.toLowerCase().endsWith('.jpg'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));
  final sink = StringBuffer('file,pdq_hex\n');
  var ok = 0;
  for (final f in files) {
    final words = pdqHash(f.readAsBytesSync());
    if (words == null) continue;
    final hex = [
      for (final w in words)
        BigInt.from(w).toUnsigned(64).toRadixString(16).padLeft(16, '0')
    ].join();
    sink.writeln('${f.uri.pathSegments.last},$hex');
    ok++;
  }
  File(args[1]).writeAsStringSync(sink.toString());
  stdout.writeln('Đã băm $ok/${files.length} ảnh -> ${args[1]}');
}
