#!/usr/bin/env python3
"""So sánh tốc độ embed của các model ONNX trong assets/models (trên máy này).

Chạy (trong .venv của project, đã có onnxruntime):
    python3 tool/bench_models.py
    python3 tool/bench_models.py --batch 16 --runs 15 --threads 4

Đo CPU của MÁY TÍNH, không phải điện thoại: chỉ dùng để so TỈ LỆ giữa các model.
Tốc độ thật trên iOS/Android phải đo bằng app (dòng timings 'AI: ...' ở màn hình
kết quả, build --release). In thêm số lượng từng loại toán tử nếu có gói `onnx`.
"""
import argparse
import collections
import statistics
import sys
import time
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--models", type=Path, default=Path("assets/models"))
    ap.add_argument("--batch", type=int, default=16, help="khớp ScanConfig.modelBatch")
    ap.add_argument("--runs", type=int, default=10)
    ap.add_argument("--warmup", type=int, default=2)
    ap.add_argument("--threads", type=int, default=0, help="0 = mặc định của onnxruntime")
    a = ap.parse_args()
    try:
        import numpy as np
        import onnxruntime as ort
    except ImportError as e:
        print(f"Thiếu thư viện: {e}\n  pip install onnxruntime numpy", file=sys.stderr)
        return 1
    try:
        import onnx
    except ImportError:
        onnx = None

    files = sorted(a.models.glob("*.onnx"))
    if not files:
        print(f"Không thấy *.onnx trong {a.models}", file=sys.stderr)
        return 1

    x = np.random.rand(a.batch, 3, 224, 224).astype(np.float32)
    print(f"batch={a.batch} runs={a.runs} threads={a.threads or 'mặc định'}  (CPU máy tính, chỉ so tỉ lệ)\n")
    rows = []
    for f in files:
        so = ort.SessionOptions()
        if a.threads:
            so.intra_op_num_threads = a.threads
        s = ort.InferenceSession(str(f), so, providers=["CPUExecutionProvider"])
        name = s.get_inputs()[0].name
        for _ in range(a.warmup):
            s.run(None, {name: x})
        ts = []
        for _ in range(a.runs):
            t = time.perf_counter()
            out = s.run(None, {name: x})[0]
            ts.append(time.perf_counter() - t)
        med = statistics.median(ts)
        rows.append((f.name, f.stat().st_size / 1e6, out.shape[1], med / a.batch * 1000, a.batch / med))
        if onnx is not None:
            ops = collections.Counter(n.op_type for n in onnx.load(str(f)).graph.node)
            print(f"{f.name}: {sum(ops.values())} node; top: " +
                  ", ".join(f"{k}x{v}" for k, v in ops.most_common(6)))
    print()
    print(f"{'model':<18}{'MB':>8}{'dim':>7}{'ms/ảnh':>10}{'ảnh/s':>9}")
    for n, mb, d, ms, ips in rows:
        print(f"{n:<18}{mb:>8.1f}{d:>7}{ms:>10.1f}{ips:>9.1f}")
    if len(rows) > 1:
        base = min(rows, key=lambda r: r[3])
        print()
        for r in rows:
            print(f"{r[0]}: chậm hơn {r[3] / base[3]:.1f}x so với {base[0]}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
