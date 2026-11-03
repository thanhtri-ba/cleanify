#!/usr/bin/env python3
"""Tạo tập con nhỏ từ PersonX (chỉ dùng nghiên cứu, KHÔNG phân phối, KHÔNG thương mại).

Đọc bộ PersonX_v1 sẵn có trên máy, lấy N ID × 36 ảnh từ một thư mục nền, đặt
tên PX_xxxx.jpg (xáo trộn), gắn EXIF DateTimeOriginal + mtime: ảnh của cùng một
ID cách nhau vài giây, các ID cách nhau 20 phút. Đáp án ở manifest.csv.

Ảnh là crop người nhỏ, không phải ảnh điện thoại toàn khung. Chỉ dùng để thử
bước gom "cùng một người" khi đã có model Re-ID. Fast Scan có thể gom các khung
liên tiếp gần giống nhau; đó là hành vi bình thường.

Thư mục đầu ra phải nằm trong .gitignore.

Ví dụ: python3 tool/prepare_personx_subset.py ~/Downloads/PersonX_v1 test_gallery_personx
"""
import argparse, csv, datetime as dt, io, os, random, sys
from collections import defaultdict
from pathlib import Path
from PIL import Image


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", type=Path, help="thư mục PersonX_v1")
    ap.add_argument("out", type=Path, help="thư mục đầu ra (phải rỗng hoặc chưa có)")
    ap.add_argument("--bg", default="5", help="thư mục nền 1-6 (4-6 là nền cảnh); mặc định 5")
    ap.add_argument("--split", default="bounding_box_test")
    ap.add_argument("--ids", type=int, default=50)
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()

    d = a.src / a.bg / a.split
    if not d.is_dir():
        print(f"Không thấy {d}", file=sys.stderr); return 1
    if a.out.exists() and any(a.out.iterdir()):
        print(f"{a.out} đã tồn tại và không rỗng.", file=sys.stderr); return 1
    a.out.mkdir(parents=True, exist_ok=True)

    by_id = defaultdict(list)
    for f in sorted(d.glob("*.jpg")):
        by_id[f.name.split("_")[0]].append(f)
    rnd = random.Random(a.seed)
    chosen = sorted(rnd.sample(sorted(by_id), min(a.ids, len(by_id))))

    t0 = dt.datetime(2026, 10, 15, 9, 0, 0)
    items = []
    for gi, pid in enumerate(chosen):
        base = t0 + dt.timedelta(minutes=20 * gi)
        for k, f in enumerate(by_id[pid]):
            items.append((pid, f, base + dt.timedelta(seconds=5 * k)))
    rnd.shuffle(items)

    rows = []
    for n, (pid, f, when) in enumerate(items, 1):
        im = Image.open(f).convert("RGB")
        ex = im.getexif(); s = when.strftime("%Y:%m:%d %H:%M:%S")
        ex[0x0132] = s; ex.get_ifd(0x8769)[0x9003] = s
        name = f"PX_{n:04d}.jpg"
        buf = io.BytesIO(); im.save(buf, "JPEG", quality=95, exif=ex)
        (a.out / name).write_bytes(buf.getvalue())
        ts = when.timestamp(); os.utime(a.out / name, (ts, ts))
        rows.append((pid, name, f.name, when.isoformat()))
    with open(a.out / "manifest.csv", "w", newline="") as fh:
        w = csv.writer(fh); w.writerow(["person", "file", "source", "taken_at"]); w.writerows(sorted(rows))
    print(f"Đã tạo {len(rows)} ảnh, {len(chosen)} người, trong {a.out}")
    print("Dữ liệu chỉ dùng nghiên cứu. manifest.csv không phải ảnh, đừng copy vào máy.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
