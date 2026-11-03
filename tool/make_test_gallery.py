#!/usr/bin/env python3
"""Tạo bộ ảnh thử cho Cleanify từ CIFAR-10 đã giải nén.

CIFAR-10 gần như không có ảnh trùng, nên script chọn ngẫu nhiên N ảnh rồi
CHỦ ĐỘNG tạo thêm bản trùng để biết trước đáp án:

  exact        sao chép y hệt từng byte        -> app phải báo "trùng SHA-256"
  near_jpeg    nén lại JPEG chất lượng thấp    -> PDQ phải gom cùng nhóm
  near_resize  thu nhỏ rồi nén lại             -> PDQ phải gom cùng nhóm
  near_bright  tăng sáng nhẹ                   -> PDQ phải gom cùng nhóm

Ảnh gốc CIFAR chỉ 32x32 nên được phóng lên --size (mặc định 256) trước khi lưu.
Kết quả: <out>/IMG_xxxx.jpg + <out>/manifest.csv (đáp án để đối chiếu với app).

Yêu cầu: python3 + Pillow (pip3 install pillow).
Ví dụ:   7z x train.7z -otrain
         python3 tool/make_test_gallery.py train gallery --count 300
"""
import argparse
import csv
import io
import random
import shutil
import sys
from pathlib import Path

from PIL import Image, ImageEnhance


def jpeg_bytes(im: Image.Image, quality: int) -> bytes:
    buf = io.BytesIO()
    im.save(buf, format="JPEG", quality=quality)
    return buf.getvalue()


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", type=Path, help="thư mục chứa ảnh CIFAR đã giải nén (*.png)")
    ap.add_argument("out", type=Path, help="thư mục đầu ra (sẽ được tạo mới)")
    ap.add_argument("--count", type=int, default=300, help="số ảnh gốc khác nhau (mặc định 300)")
    ap.add_argument("--exact", type=int, default=30, help="số ảnh có bản sao y hệt")
    ap.add_argument("--near", type=int, default=45, help="số ảnh có bản gần giống (chia đều 3 kiểu)")
    ap.add_argument("--size", type=int, default=256, help="cạnh ảnh sau khi phóng (mặc định 256)")
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()

    files = sorted(a.src.rglob("*.png"))
    if len(files) < a.count:
        print(f"Chỉ thấy {len(files)} ảnh .png trong {a.src}, cần ít nhất {a.count}.", file=sys.stderr)
        return 1
    if a.exact + a.near > a.count:
        print("--exact + --near không được vượt quá --count.", file=sys.stderr)
        return 1
    if a.out.exists() and any(a.out.iterdir()):
        print(f"{a.out} đã tồn tại và không rỗng, hãy chọn thư mục khác.", file=sys.stderr)
        return 1
    a.out.mkdir(parents=True, exist_ok=True)

    rnd = random.Random(a.seed)
    picked = rnd.sample(files, a.count)
    exact_idx = set(rnd.sample(range(a.count), a.exact))
    rest = [i for i in range(a.count) if i not in exact_idx]
    near_idx = rnd.sample(rest, a.near)
    kinds = ["near_jpeg", "near_resize", "near_bright"]
    near_kind = {i: kinds[n % 3] for n, i in enumerate(near_idx)}

    rows = []  # (group, file, kind, source)
    serial = 0
    pending = []  # (group, kind, source, data)

    for gid, src in enumerate(picked, start=1):
        im = Image.open(src).convert("RGB").resize((a.size, a.size), Image.BICUBIC)
        orig = jpeg_bytes(im, 92)
        pending.append((gid, "original", src.name, orig))
        i = gid - 1
        if i in exact_idx:
            pending.append((gid, "exact", src.name, orig))
        elif i in near_kind:
            k = near_kind[i]
            if k == "near_jpeg":
                data = jpeg_bytes(Image.open(io.BytesIO(orig)), 40)
            elif k == "near_resize":
                small = Image.open(io.BytesIO(orig)).resize((a.size * 3 // 4,) * 2, Image.BICUBIC)
                data = jpeg_bytes(small, 80)
            else:
                data = jpeg_bytes(ImageEnhance.Brightness(Image.open(io.BytesIO(orig))).enhance(1.12), 92)
            pending.append((gid, k, src.name, data))

    # Xáo thứ tự để bản trùng không nằm cạnh bản gốc.
    rnd.shuffle(pending)
    for gid, kind, srcname, data in pending:
        serial += 1
        name = f"IMG_{serial:04d}.jpg"
        (a.out / name).write_bytes(data)
        rows.append((gid, name, kind, srcname))

    with open(a.out / "manifest.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["group", "file", "kind", "cifar_source"])
        w.writerows(sorted(rows))

    n_groups = a.exact + a.near
    print(f"Đã tạo {len(rows)} ảnh trong {a.out}")
    print(f"  {a.count} ảnh gốc, {a.exact} bản sao y hệt, {a.near} bản gần giống")
    print(f"  Đáp án mong đợi: {n_groups} nhóm trùng "
          f"({a.exact} nhóm exact + {a.near} nhóm near), "
          f"{a.exact + a.near} ảnh có thể dọn.")
    print("  Đối chiếu từng nhóm với manifest.csv. manifest.csv không phải ảnh, đừng copy vào máy.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
