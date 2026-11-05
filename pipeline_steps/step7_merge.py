#!/usr/bin/env python3
"""BƯỚC 7 — Gộp kết quả theo "thác nước" như app: ảnh đã vào một nhóm thì không vào nhóm sau.

  Tab Trùng    : SHA-256 trùng khít + PDQ Hamming <= --max-hamming
  Tab Tương tự : (chỉ ảnh chưa vào nhóm Trùng) PDQ Hamming trong (max-hamming, similar-max]
                 + cosine MobileNet (bước 5, nếu có) + ORB inliers >= --min-inliers (bước 6, nếu có)
Mỗi nhóm giữ ảnh đại diện (dung lượng lớn nhất) và chỉ ảnh có cạnh TRỰC TIẾP với nó.
Vào : các file out/ của bước 1, 3 (bắt buộc: 2 và 3), 5, 6 nếu có
Ra  : out/7_groups.csv, out/7_report.html
"""
import html
from pathlib import Path

from common import (LOCAL_MIN_INLIERS, MAX_HAMMING, SIMILAR_MAX_HAMMING, base_parser, build_groups,
                    ensure_index, need, read_csv, sim_pct, write_csv)


def main():
    ap = base_parser(__doc__)
    ap.add_argument("--max-hamming", type=int, default=MAX_HAMMING)
    ap.add_argument("--similar-max", type=int, default=SIMILAR_MAX_HAMMING)
    ap.add_argument("--min-inliers", type=int, default=LOCAL_MIN_INLIERS)
    a = ap.parse_args()
    src, out = Path(a.src), Path(a.out)
    photos = ensure_index(src, out)
    sizes = [p["size"] for p in photos]

    dup_edges, pdq = {}, {}
    for r in read_csv(need(out / "3_pairs_exact.csv", "step3_hamming.py")):
        i, j, h = int(r["a"]), int(r["b"]), int(r["hamming"])
        pdq[(i, j)] = h
        if h <= a.max_hamming:
            dup_edges[(i, j)] = (sim_pct(h), "pdq")
    f = out / "1_sha256.csv"
    if f.exists():
        by = {}
        for r in read_csv(f):
            if r["sha256"]:
                by.setdefault(r["sha256"], []).append(int(r["idx"]))
        for v in by.values():
            for x in v[1:]:
                dup_edges[(v[0], x)] = (100.0, "sha256")
    dup_groups = build_groups(dup_edges, sizes)
    in_dup = {rep for rep, _ in dup_groups} | {m for _, ms in dup_groups for m, _, _ in ms}

    sim_edges = {}

    def add(i, j, score, src_name):
        if i in in_dup or j in in_dup:
            return
        k = (min(i, j), max(i, j))
        if k not in sim_edges or score > sim_edges[k][0]:
            sim_edges[k] = (score, src_name)

    for (i, j), h in pdq.items():
        if a.max_hamming < h <= a.similar_max:
            add(i, j, sim_pct(h), "pdq")
    f = out / "5_similar_pairs.csv"
    if f.exists():
        for r in read_csv(f):
            add(int(r["a"]), int(r["b"]), 100 * float(r["cosine"]), "mobilenet")
    else:
        print("(chưa có bước 5: bỏ qua MobileNet)")
    f = out / "6_orb_pairs.csv"
    if f.exists():
        for r in read_csv(f):
            if int(r["inliers"]) >= a.min_inliers:
                add(int(r["a"]), int(r["b"]), min(100.0, float(r["inliers"])), "orb")
    sim_groups = build_groups(sim_edges, sizes)

    rows, blocks = [], []
    for tab, groups in (("trung", dup_groups), ("tuong_tu", sim_groups)):
        for gi, (rep, members) in enumerate(groups, 1):
            gid = f"{tab}-{gi}"
            rows.append([gid, tab, rep, photos[rep]["path"], "rep", "", ""])
            cells = [(rep, "đại diện", "")]
            for m, sc, s in members:
                rows.append([gid, tab, m, photos[m]["path"], "member", f"{sc:.1f}", s])
                cells.append((m, f"{sc:.1f} ({s})", ""))
            blocks.append((gid, cells))
    write_csv(out / "7_groups.csv", ["group", "tab", "idx", "path", "role", "score", "source"], rows)

    parts = ["<meta charset=utf-8><title>Cleanify steps</title>"
             "<style>body{font:14px sans-serif;margin:16px}.g{margin:12px 0;padding:8px;border:1px solid #ccc}"
             ".c{display:inline-block;margin:4px;text-align:center;width:150px}img{width:150px;height:110px;object-fit:cover}</style>"]
    parts.append(f"<h2>Trùng: {len(dup_groups)} nhóm &nbsp; Tương tự: {len(sim_groups)} nhóm</h2>")
    for gid, cells in blocks:
        parts.append(f"<div class=g><b>{gid}</b><br>")
        for idx, label, _ in cells:
            uri = (src / photos[idx]["path"]).resolve().as_uri()
            parts.append(f"<div class=c><img src='{uri}' loading=lazy><br>{html.escape(label)}</div>")
        parts.append("</div>")
    (out / "7_report.html").write_text("".join(parts), encoding="utf-8")
    print(f"Trùng: {len(dup_groups)} nhóm ({sum(len(m) for _, m in dup_groups)} ảnh thừa); "
          f"Tương tự: {len(sim_groups)} nhóm -> {out / '7_groups.csv'}, {out / '7_report.html'}")


if __name__ == "__main__":
    main()
