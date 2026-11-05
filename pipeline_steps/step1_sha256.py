#!/usr/bin/env python3
"""BƯỚC 1 — SHA-256: tìm ảnh trùng TUYỆT ĐỐI từng byte (không dùng model).

Vào : thư mục ảnh (--src)
Ra  : out/photos.csv, out/1_sha256.csv (idx, sha256), in số nhóm trùng khít
"""
import hashlib
from pathlib import Path

from common import base_parser, ensure_index, write_csv


def sha256_file(p: Path) -> str:
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    a = base_parser(__doc__).parse_args()
    src, out = Path(a.src), Path(a.out)
    photos = ensure_index(src, out)
    rows, by = [], {}
    for p in photos:
        try:
            s = sha256_file(src / p["path"])
        except Exception:
            s = ""
        rows.append([p["idx"], s])
        if s:
            by.setdefault(s, []).append(p["idx"])
    write_csv(out / "1_sha256.csv", ["idx", "sha256"], rows)
    groups = [v for v in by.values() if len(v) > 1]
    print(f"{len(photos)} ảnh; {len(groups)} nhóm trùng khít, "
          f"{sum(len(g) - 1 for g in groups)} ảnh thừa")
    for g in groups[:10]:
        print("  ", [photos[i]["path"] for i in g])


if __name__ == "__main__":
    main()
