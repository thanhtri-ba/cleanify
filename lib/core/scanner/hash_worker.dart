import 'dart:io' show Platform;
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../../engines/pdq/pdq_engine.dart';
import '../../engines/sha256/sha_engine.dart';

class HashInput {
  const HashInput({required this.index, this.thumb, this.filePath});
  final int index;
  final Uint8List? thumb;
  final String? filePath;
}

class HashOutput {
  const HashOutput({required this.index, this.sha256Hex, this.pdq});
  final int index;
  final String? sha256Hex;
  final Uint64List? pdq;
}

/// Số isolate băm song song: chừa 1 lõi cho UI, tối đa 4 (băm PDQ chạy bằng Dart
/// nên nhiều lõi giúp được, nhưng quá nhiều chỉ tốn RAM sao chép dữ liệu).
final int _workers = math.max(1, math.min(4, Platform.numberOfProcessors - 1));

/// Băm một batch ngoài isolate chính để không chặn UI. Batch được chia đều cho
/// [_workers] isolate chạy song song; mỗi kết quả giữ nguyên [HashOutput.index]
/// nên gộp lại không đổi nghĩa. Thứ tự đầu ra theo chỉ số đầu vào.
Future<List<HashOutput>> hashBatch(List<HashInput> inputs) async {
  if (inputs.length < 2 || _workers == 1) {
    return Isolate.run(() => _hashBatch(inputs));
  }
  final k = math.min(_workers, inputs.length);
  final size = (inputs.length + k - 1) ~/ k;
  final parts = <List<HashInput>>[
    for (var i = 0; i < inputs.length; i += size)
      inputs.sublist(i, math.min(i + size, inputs.length)),
  ];
  final results = await Future.wait([
    for (final part in parts) Isolate.run(() => _hashBatch(part)),
  ]);
  return [for (final r in results) ...r];
}

Future<List<HashOutput>> _hashBatch(List<HashInput> inputs) async {
  final out = <HashOutput>[];
  for (final input in inputs) {
    String? sha;
    Uint64List? pdq;
    try {
      if (input.filePath != null) sha = await sha256OfFile(input.filePath!);
    } catch (_) {}
    try {
      if (input.thumb != null) pdq = pdqHash(input.thumb!);
    } catch (_) {}
    out.add(HashOutput(index: input.index, sha256Hex: sha, pdq: pdq));
  }
  return out;
}
