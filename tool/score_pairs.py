#!/usr/bin/env python3
"""Tính điểm từng cặp ảnh: Hamming PDQ, cosine embedding (cột cos_dino; mặc định MobileNet,
đã trừ vector trung bình giống app), cosine ReID (OSNet).

Đọc <out>/manifest.csv (nếu có) hoặc candidates.csv, ghi <out>/scores.csv và
<out>/thumbs128/ + <out>/pdq_map.csv (thumbnail 128px để tool/dump_pdq.dart băm
bằng đúng code Dart của app).

Ví dụ:
  python tool/score_pairs.py --src eval_real --out eval_out
  # (tùy chọn) PDQ khớp tuyệt đối với app:
  dart run tool/dump_pdq.dart eval_out/thumbs128 eval_out/pdq_dart.csv
  python tool/score_pairs.py --src eval_real --out eval_out --pdq-dart eval_out/pdq_dart.csv

Yêu cầu: numpy, pillow, onnxruntime (xem requirements-eval.txt).
"""
import argparse
import csv
import hashlib
import pickle
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import eval_common as ec  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--models", type=Path, default=Path("assets/models"))
    ap.add_argument("--pdq-dart", type=Path, help="CSV do tool/dump_pdq.dart tạo ra")
    ap.add_argument("--no-cache", action="store_true")
    ap.add_argument("--embed", default="mobilenet",
                    help="tên model embedding trong --models (mobilenet hoặc dino); cột kết quả vẫn là cos_dino")
    ap.add_argument("--no-center", action="store_true",
                    help="KHÔNG trừ vector trung bình (cosine thô). Mặc định trừ trung bình giống app.")
    a = ap.parse_args()

    pairs_file = a.out / ("manifest.csv" if (a.out / "manifest.csv").exists() else "candidates.csv")
    if not pairs_file.exists():
        print(f"Không thấy {pairs_file}. Chạy build_eval_pairs.py trước.", file=sys.stderr)
        return 1
    with open(pairs_file, newline="", encoding="utf-8") as fh:
        pairs = list(csv.DictReader(fh))
    assets = sorted({r[k] for r in pairs for k in ("asset_a", "asset_b")})
    print(f"{len(pairs)} cặp, {len(assets)} ảnh duy nhất (đọc từ {pairs_file.name}).")

    dino = reid = None
    for name in (a.embed, "osnet"):
        mp = a.models / f"{name}.onnx"
        if not mp.exists():
            print(f"CẢNH BÁO: không thấy {mp}, bỏ qua {name}.", file=sys.stderr)
            continue
        emb = ec.Embedder(mp)
        if name == a.embed:
            dino = emb
        else:
            reid = emb

    thumbs_dir = a.out / "thumbs128"
    thumbs_dir.mkdir(parents=True, exist_ok=True)
    cache_path = a.out / "scores_cache.pkl"
    cache = {}
    if cache_path.exists() and not a.no_cache:
        try:
            cache = pickle.loads(cache_path.read_bytes())
        except Exception:
            cache = {}

    feats, pdq_files = {}, {}
    for n, asset in enumerate(assets, 1):
        path = ec.resolve_asset(asset, a.src, a.out)
        st = path.stat()
        key = (asset, st.st_size, int(st.st_mtime), a.embed if dino is not None else None, reid is not None)
        fname = hashlib.sha1(asset.encode()).hexdigest()[:12] + ".jpg"
        pdq_files[asset] = fname
        if key in cache and (thumbs_dir / fname).exists():
            feats[asset] = cache[key]
            continue
        try:
            im = ec.load_rgb(path)
        except Exception as e:
            print(f"  bỏ qua {asset}: {e}", file=sys.stderr)
            continue
        t128 = ec.thumb_bytes(im, ec.PDQ_THUMB)
        (thumbs_dir / fname).write_bytes(t128)
        bits = ec.pdq_bits(t128)
        d = r = None
        if dino is not None:
            d = dino(ec.preprocess_dino(ec.thumb_bytes(im, ec.DINO_THUMB)))
        if reid is not None:
            r = reid(ec.preprocess_reid(ec.thumb_bytes(im, ec.REID_THUMB)))
        feats[asset] = (bits, d, r)
        cache[key] = feats[asset]
        if n % 25 == 0 or n == len(assets):
            print(f"  {n}/{len(assets)} ảnh", flush=True)
        if n % 100 == 0:  # lưu định kỳ để chạy lại được nếu bị ngắt
            cache_path.write_bytes(pickle.dumps(cache))
    cache_path.write_bytes(pickle.dumps(cache))

    with open(a.out / "pdq_map.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["asset", "file"])
        for asset, f in pdq_files.items():
            w.writerow([asset, f])

    if a.pdq_dart:
        by_file = {}
        with open(a.pdq_dart, newline="", encoding="utf-8") as fh:
            for row in csv.DictReader(fh):
                by_file[row["file"]] = row["pdq_hex"]
        diffs = []
        for asset, (bits, d, r) in list(feats.items()):
            hx = by_file.get(pdq_files[asset])
            if hx and len(hx) == 64:
                dart_bits = ec.hex_to_bits(hx)
                if bits is not None:
                    diffs.append(ec.hamming(bits, dart_bits))
                feats[asset] = (dart_bits, d, r)
        if diffs:
            print(f"PDQ Dart vs bản port Python (cùng thumbnail): trung bình {np.mean(diffs):.2f} bit lệch, "
                  f"tối đa {max(diffs)} / 256, trên {len(diffs)} ảnh.")
        else:
            print("CẢNH BÁO: --pdq-dart không khớp ảnh nào, vẫn dùng bản port Python.", file=sys.stderr)

    # Giống app (centerEmbeddings): trừ vector trung bình rồi L2-normalize lại.
    # Trung bình lấy trên toàn bộ ảnh của tập đánh giá; app lấy trên ~256 ảnh rải đều
    # thư viện, nên tập đánh giá cần đa dạng (không chỉ ảnh trong các cặp ứng viên).
    vecs = [f[1] for f in feats.values() if f[1] is not None]
    if dino is not None and not a.no_center:
        if len(vecs) >= 32:
            mean = np.mean(vecs, axis=0)

            def center(v):
                if v is None:
                    return None
                c = v - mean
                n = float(np.linalg.norm(c))
                return c / n if n > 0 else c

            feats = {k: (f[0], center(f[1]), f[2]) for k, f in feats.items()}
            print(f"Đã trừ vector trung bình ({len(vecs)} ảnh) trước khi tính cosine.")
        else:
            print(f"CẢNH BÁO: chỉ {len(vecs)} embedding (< 32), không trừ trung bình; "
                  "cosine là cosine thô, KHÔNG khớp với app.", file=sys.stderr)

    def cos(x, y):
        return float(np.dot(x, y)) if x is not None and y is not None else None

    rows = []
    for p in pairs:
        fa, fb = feats.get(p["asset_a"]), feats.get(p["asset_b"])
        if not fa or not fb:
            continue
        ham = ec.hamming(fa[0], fb[0]) if fa[0] is not None and fb[0] is not None else None
        rows.append({"pair_id": p["pair_id"], "hamming": ham,
                     "cos_dino": cos(fa[1], fb[1]), "cos_reid": cos(fa[2], fb[2])})
    with open(a.out / "scores.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=["pair_id", "hamming", "cos_dino", "cos_reid"])
        w.writeheader()
        for r in rows:
            w.writerow({k: ("" if v is None else v) for k, v in r.items()})
    print(f"Đã ghi {len(rows)} dòng vào {a.out / 'scores.csv'}.")
    print("Tiếp theo: python tool/calibrate.py --out", a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
