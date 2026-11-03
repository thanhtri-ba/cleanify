#!/usr/bin/env python3
"""Tạo tập con từ COIL-100 (100 vật thể x 72 góc quay) để thử gom "cùng vật thể, khác góc".

COIL-100 dành cho nghiên cứu; không phân phối, không đưa vào app. Thư mục đầu ra
phải nằm trong .gitignore.

Đọc ảnh obj<ID>__<GÓC>.png (có thể nằm trong nhiều thư mục con), lấy N vật thể,
đổi sang JPEG chất lượng 95 kèm EXIF DateTimeOriginal + mtime: mọi góc của một
vật thể cách nhau 3 giây, các vật thể cách nhau 15 phút. Tên PX-kiểu: CL_xxxx.jpg
(xáo trộn). Đáp án ở manifest.csv (object, angle).

Ví dụ: python3 tool/prepare_coil_subset.py ~/Downloads/coil-100/data test_gallery_coil
"""
import argparse, csv, datetime as dt, io, os, random, re, sys
from collections import defaultdict
from pathlib import Path
from PIL import Image


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--objects", type=int, default=20)
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()
    if a.out.exists() and any(a.out.iterdir()):
        print(f"{a.out} đã tồn tại và không rỗng.", file=sys.stderr); return 1
    pat = re.compile(r"obj(\d+)__(\d+)\.png$")
    by = defaultdict(list)
    for f in a.src.rglob("*.png"):
        m = pat.match(f.name)
        if m: by[int(m.group(1))].append((int(m.group(2)), f))
    if not by:
        print("Không thấy file obj*__*.png", file=sys.stderr); return 1
    rnd = random.Random(a.seed)
    chosen = sorted(rnd.sample(sorted(by), min(a.objects, len(by))))
    a.out.mkdir(parents=True, exist_ok=True)
    t0 = dt.datetime(2026, 10, 20, 9, 0, 0)
    items = []
    for gi, oid in enumerate(chosen):
        base = t0 + dt.timedelta(minutes=15 * gi)
        for k, (ang, f) in enumerate(sorted(by[oid])):
            items.append((oid, ang, f, base + dt.timedelta(seconds=3 * k)))
    rnd.shuffle(items)
    rows = []
    for n, (oid, ang, f, when) in enumerate(items, 1):
        im = Image.open(f).convert("RGB")
        ex = im.getexif(); s = when.strftime("%Y:%m:%d %H:%M:%S")
        ex[0x0132] = s; ex.get_ifd(0x8769)[0x9003] = s
        name = f"CL_{n:04d}.jpg"
        buf = io.BytesIO(); im.save(buf, "JPEG", quality=95, exif=ex)
        (a.out / name).write_bytes(buf.getvalue())
        ts = when.timestamp(); os.utime(a.out / name, (ts, ts))
        rows.append((f"obj{oid}", ang, name, when.isoformat()))
    with open(a.out / "manifest.csv", "w", newline="") as fh:
        w = csv.writer(fh); w.writerow(["object", "angle", "file", "taken_at"]); w.writerows(sorted(rows))
    print(f"Đã tạo {len(rows)} ảnh, {len(chosen)} vật thể, trong {a.out}")
    print("manifest.csv không phải ảnh, đừng copy vào máy.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
