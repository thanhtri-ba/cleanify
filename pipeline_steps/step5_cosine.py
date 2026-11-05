#!/usr/bin/env python3
"""BƯỚC 5 — So cosine giữa các vector (không chạy lại CNN).

1) Trừ vector trung bình của thư viện rồi L2-normalize lại (đặc trưng MobileNet đều dương
   nên cosine thô giữa ảnh bất kỳ đã cao).
2) Mỗi ảnh lấy --k hàng xóm có cosine cao nhất và >= --floor.
3) Giữ cạnh "mutual": cả hai ảnh đều có nhau trong top-k (tránh gom cả cụm cùng loại cảnh).
--exclude-dups: bỏ ảnh đã thuộc nhóm trùng (cần chạy bước 1 và/hoặc 3 trước), giống thác nước của app.
Vào : out/4_embeddings.npz
Ra  : out/5_similar_pairs.csv (a, b, cosine)
"""
from pathlib import Path

import numpy as np

from common import (MAX_HAMMING, MIN_MEAN_COUNT, SIM_FLOOR, SIM_K, base_parser, dup_members,
                    ensure_index, need, write_csv)


def main():
    ap = base_parser(__doc__)
    ap.add_argument("--k", type=int, default=SIM_K)
    ap.add_argument("--floor", type=float, default=SIM_FLOOR)
    ap.add_argument("--not-mutual", action="store_true", help="chỉ cần một đầu có trong top-k")
    ap.add_argument("--exclude-dups", action="store_true")
    a = ap.parse_args()
    src, out = Path(a.src), Path(a.out)
    ensure_index(src, out)
    z = np.load(need(out / "4_embeddings.npz", "step4_embed.py"))
    emb, valid = z["emb"], z["valid"].copy()
    if a.exclude_dups:
        for i in dup_members(out, MAX_HAMMING):
            valid[i] = False
    ids = np.nonzero(valid)[0]
    if len(ids) < MIN_MEAN_COUNT:
        raise SystemExit(f"Chỉ có {len(ids)} vector (< {MIN_MEAN_COUNT}); trung bình không có nghĩa, bỏ qua như app.")
    E = emb[ids].astype(np.float32)
    E -= E.mean(axis=0, keepdims=True)
    E /= np.maximum(np.linalg.norm(E, axis=1, keepdims=True), 1e-12)
    m, k = len(ids), min(a.k, len(ids) - 1)
    nb = np.full((m, k), -1, dtype=np.int64)
    nc = np.full((m, k), -2.0, dtype=np.float32)
    for s in range(0, m, 512):
        S = E[s:s + 512] @ E.T
        S[np.arange(S.shape[0]), np.arange(s, s + S.shape[0])] = -2
        top = np.argpartition(-S, k - 1, axis=1)[:, :k]
        tc = np.take_along_axis(S, top, axis=1)
        o = np.argsort(-tc, axis=1)
        nb[s:s + 512] = np.take_along_axis(top, o, axis=1)
        nc[s:s + 512] = np.take_along_axis(tc, o, axis=1)
    votes, cos = {}, {}
    for r in range(m):
        for p in range(k):
            c = float(nc[r, p])
            if c < a.floor:
                continue
            i, j = int(ids[r]), int(ids[nb[r, p]])
            key = (min(i, j), max(i, j))
            votes[key] = votes.get(key, 0) + 1
            cos[key] = c
    need_v = 1 if a.not_mutual else 2
    pairs = sorted((i, j, cos[(i, j)]) for (i, j), v in votes.items() if v >= need_v)
    write_csv(out / "5_similar_pairs.csv", ["a", "b", "cosine"], [[i, j, f"{c:.4f}"] for i, j, c in pairs])
    print(f"{len(pairs)} cặp (k={k}, cosine >= {a.floor}, {'một đầu' if a.not_mutual else 'mutual'}) "
          f"trên {m} ảnh -> {out / '5_similar_pairs.csv'}")


if __name__ == "__main__":
    main()
