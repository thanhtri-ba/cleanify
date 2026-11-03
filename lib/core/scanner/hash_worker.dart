import 'dart:isolate';
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

/// Băm một batch trong isolate riêng để không chặn UI.
Future<List<HashOutput>> hashBatch(List<HashInput> inputs) =>
    Isolate.run(() => _hashBatch(inputs));

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
