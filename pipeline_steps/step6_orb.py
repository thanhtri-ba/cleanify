#!/usr/bin/env python3
"""BƯỚC 6 (TÙY CHỌN) — ORB + RANSAC: bắt ảnh bị crop, zoom, vẽ lên, chụp lệch khung.

Chỉ so các cặp chụp gần nhau về thời gian (EXIF DateTimeOriginal, thiếu thì mtime):
mỗi ảnh với tối đa --neighbors ảnh kế tiếp trong --window phút, tối đa --max-pairs cặp.
Bỏ cặp đã là "Trùng"/"Tương tự theo PDQ" (cần out/3_pairs_exact.csv nếu muốn bỏ).
Cần: pip install opencv-python
Ra  : out/6_orb_pairs.csv (a, b, inliers) cho mọi cặp đã so; bước 7 lọc theo --min-inliers.
"""
from pathlib import Path

import numpy as np

from common import (LOCAL_MAX_PAIRS, LOCAL_NEIGHBORS, LOCAL_SIDE, LOCAL_WINDOW_MIN,
                    SIMILAR_MAX_HAMMING, base_parser, dup_members, ensure_index, load_rgb,
                    read_csv, write_csv)


def photo_time(path: Path, fallback: int) -> float:
    try:
        from PIL import Image
        with Image.open(path) as im:
            ex = im.getexif()
            s = ex.get_ifd(0x8769).get(36867) or ex.get(306)
        if s:
            import datetime as dt
            return dt.datetime.strptime(str(s)[:19], "%Y:%m:%d %H:%M:%S").timestamp()
    except Exception:
        pass
    return float(fallback)


def main():
    ap = base_parser(__doc__)
    ap.add_argument("--neighbors", type=int, default=LOCAL_NEIGHBORS)
    ap.add_argument("--window", type=float, default=LOCAL_WINDOW_MIN, help="phút")
    ap.add_argument("--max-pairs", type=int, default=LOCAL_MAX_PAIRS)
    ap.add_argument("--side", type=int, default=LOCAL_SIDE)
    a = ap.parse_args()
    import cv2

    src, out = Path(a.src), Path(a.out)
    photos = ensure_index(src, out)
    near = set()
    f = out / "3_pairs_exact.csv"
    if f.exists():
        near = {(int(r["a"]), int(r["b"])) for r in read_csv(f) if int(r["hamming"]) <= SIMILAR_MAX_HAMMING}
    dups = dup_members(out, 0)  # chỉ SHA trùng khít nếu có
    times = [photo_time(src / p["path"], p["mtime"]) for p in photos]
    order = sorted(range(len(photos)), key=lambda i: (times[i], i))
    pairs = []
    for p in range(len(order)):
        for q in range(p + 1, min(p + 1 + a.neighbors, len(order))):
            i, j = order[p], order[q]
            if times[j] - times[i] > a.window * 60:
                break
            key = (min(i, j), max(i, j))
            if key in near or (i in dups and j in dups):
                continue
            pairs.append(key)
    pairs = pairs[:a.max_pairs]
    orb = cv2.ORB_create(nfeatures=1000)
    cache = {}

    def feats(i):
        if i not in cache:
            im = load_rgb(src / photos[i]["path"])
            s = a.side / max(im.size)
            if s < 1:
                im = im.resize((int(im.width * s), int(im.height * s)))
            g = cv2.cvtColor(np.asarray(im), cv2.COLOR_RGB2GRAY)
            cache[i] = orb.detectAndCompute(g, None)
        return cache[i]

    bf = cv2.BFMatcher(cv2.NORM_HAMMING)
    rows = []
    for n, (i, j) in enumerate(pairs):
        try:
            k1, d1 = feats(i)
            k2, d2 = feats(j)
            inl = 0
            if d1 is not None and d2 is not None and len(k1) >= 8 and len(k2) >= 8:
                good = [m[0] for m in bf.knnMatch(d1, d2, k=2) if len(m) == 2 and m[0].distance < 0.75 * m[1].distance]
                if len(good) >= 8:
                    s1 = np.float32([k1[m.queryIdx].pt for m in good]).reshape(-1, 1, 2)
                    s2 = np.float32([k2[m.trainIdx].pt for m in good]).reshape(-1, 1, 2)
                    _, mask = cv2.findHomography(s1, s2, cv2.RANSAC, 5.0)
                    inl = int(mask.sum()) if mask is not None else 0
        except Exception:
            inl = 0
        rows.append([i, j, inl])
        if len(cache) > 64:
            cache.clear()
        if (n + 1) % 50 == 0 or n + 1 == len(pairs):
            print(f"  đã so {n + 1}/{len(pairs)} cặp", flush=True)
    write_csv(out / "6_orb_pairs.csv", ["a", "b", "inliers"], rows)
    print(f"{len(rows)} cặp đã so -> {out / '6_orb_pairs.csv'}")


if __name__ == "__main__":
    main()
