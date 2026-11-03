#!/usr/bin/env python3
"""Sinh bộ ảnh thử TỔNG HỢP (không cần dataset ngoài) cho Cleanify.

Mỗi cảnh là ảnh vẽ bằng thuật toán (nền gradient + hình khối + nhiễu), nên
KHÔNG thay thế ảnh thật khi calibrate ngưỡng DINO. Dùng để kiểm tra pipeline.

Loại ảnh và kết quả mong đợi:
  original     ảnh gốc, đứng một mình hoặc là đại diện nhóm
  exact        sao chép y hệt từng byte        -> Fast Scan: nhóm exact
  near_jpeg    nén lại JPEG chất lượng thấp    -> Fast Scan: nhóm near
  near_resize  thu nhỏ rồi nén lại             -> Fast Scan: nhóm near
  near_bright  tăng sáng nhẹ                   -> Fast Scan: nhóm near
  angle        cùng cảnh nhưng xoay/phối cảnh/zoom -> Fast Scan: KHÔNG gom (kỳ vọng);
               Deep Scan (embedding) sau này mới phải gom vào "Ảnh tương tự"

EXIF DateTimeOriginal và mtime được đặt: ảnh cùng nhóm cách nhau vài chục giây,
các nhóm khác nhau cách nhau vài phút, để thử cửa sổ thời gian.

Ví dụ: python3 tool/make_synthetic_gallery.py test_gallery
"""
import argparse
import csv
import datetime as dt
import io
import os
import random
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

W, H = 640, 480


def make_scene(rnd: random.Random) -> Image.Image:
    c1 = tuple(rnd.randint(20, 235) for _ in range(3))
    c2 = tuple(rnd.randint(20, 235) for _ in range(3))
    t = np.linspace(0, 1, H)[:, None, None]
    ang = rnd.choice([0, 1])
    grad = np.linspace(0, 1, W)[None, :, None] if ang else t
    base = (np.array(c1) * (1 - grad) + np.array(c2) * grad)
    base = np.broadcast_to(base, (H, W, 3)).copy()
    im = Image.fromarray(base.astype("uint8"))
    d = ImageDraw.Draw(im)
    for _ in range(rnd.randint(6, 11)):
        col = tuple(rnd.randint(0, 255) for _ in range(3))
        x0, y0 = rnd.randint(0, W - 80), rnd.randint(0, H - 80)
        x1, y1 = x0 + rnd.randint(50, 260), y0 + rnd.randint(50, 220)
        shape = rnd.choice(["e", "r", "p"])
        if shape == "e":
            d.ellipse([x0, y0, x1, y1], fill=col)
        elif shape == "r":
            d.rectangle([x0, y0, x1, y1], fill=col)
        else:
            d.polygon([(x0, y1), ((x0 + x1) // 2, y0), (x1, y1)], fill=col)
    im = im.filter(ImageFilter.GaussianBlur(1.2))
    noise = np.random.default_rng(rnd.randint(0, 2**31)).normal(0, 6, (H, W, 3))
    arr = np.clip(np.asarray(im).astype("float32") + noise, 0, 255).astype("uint8")
    return Image.fromarray(arr)


def jpeg(im: Image.Image, q: int, when: dt.datetime) -> bytes:
    exif = im.getexif()
    s = when.strftime("%Y:%m:%d %H:%M:%S")
    exif[0x0132] = s
    exif.get_ifd(0x8769)[0x9003] = s
    buf = io.BytesIO()
    im.save(buf, format="JPEG", quality=q, exif=exif)
    return buf.getvalue()


def angle_variant(im: Image.Image, rnd: random.Random, k: int) -> Image.Image:
    if k == 0:  # xoay + giữ khung
        out = im.rotate(rnd.choice([-1, 1]) * rnd.uniform(8, 18), resample=Image.BICUBIC, expand=False, fillcolor=(0, 0, 0))
        return out
    if k == 1:  # phối cảnh
        m = rnd.uniform(0.06, 0.14)
        dx, dy = int(W * m), int(H * m)
        quad = (dx, dy, 0, H - dy, W, H, W - dx, 0)
        return im.transform((W, H), Image.QUAD, quad, Image.BICUBIC)
    z = rnd.uniform(0.62, 0.78)  # zoom/cắt lệch tâm
    cw, ch = int(W * z), int(H * z)
    x0, y0 = rnd.randint(0, W - cw), rnd.randint(0, H - ch)
    return im.crop((x0, y0, x0 + cw, y0 + ch)).resize((W, H), Image.BICUBIC)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", type=Path)
    ap.add_argument("--count", type=int, default=150, help="số cảnh gốc khác nhau")
    ap.add_argument("--exact", type=int, default=15)
    ap.add_argument("--near", type=int, default=30, help="chia đều 3 kiểu")
    ap.add_argument("--angle", type=int, default=20, help="số cảnh có biến thể đổi góc (mỗi cảnh 2 biến thể)")
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()
    if a.exact + a.near + a.angle > a.count:
        print("exact + near + angle không được vượt quá count", file=sys.stderr)
        return 1
    if a.out.exists() and any(a.out.iterdir()):
        print(f"{a.out} đã tồn tại và không rỗng, hãy chọn thư mục khác.", file=sys.stderr)
        return 1
    a.out.mkdir(parents=True, exist_ok=True)

    rnd = random.Random(a.seed)
    ids = list(range(a.count))
    rnd.shuffle(ids)
    exact_ids = set(ids[: a.exact])
    near_ids = ids[a.exact : a.exact + a.near]
    angle_ids = set(ids[a.exact + a.near : a.exact + a.near + a.angle])
    near_kind = {g: ["near_jpeg", "near_resize", "near_bright"][n % 3] for n, g in enumerate(near_ids)}

    t0 = dt.datetime(2026, 10, 1, 9, 0, 0)
    pending = []  # (group, kind, data, when)
    for g in range(a.count):
        when = t0 + dt.timedelta(minutes=7 * g)
        im = make_scene(rnd)
        orig = jpeg(im, 92, when)
        pending.append((g + 1, "original", orig, when))
        if g in exact_ids:
            pending.append((g + 1, "exact", orig, when))
        elif g in near_kind:
            base = Image.open(io.BytesIO(orig))
            k = near_kind[g]
            w2 = when + dt.timedelta(seconds=20)
            if k == "near_jpeg":
                data = jpeg(base, 40, w2)
            elif k == "near_resize":
                data = jpeg(base.resize((W * 3 // 4, H * 3 // 4), Image.BICUBIC), 80, w2)
            else:
                data = jpeg(ImageEnhance.Brightness(base).enhance(1.12), 92, w2)
            pending.append((g + 1, k, data, w2))
        elif g in angle_ids:
            for k in range(2):
                w2 = when + dt.timedelta(seconds=25 * (k + 1))
                pending.append((g + 1, "angle", jpeg(angle_variant(im, rnd, k + rnd.choice([0, 1])), 90, w2), w2))

    rnd.shuffle(pending)
    rows = []
    for i, (g, kind, data, when) in enumerate(pending, start=1):
        name = f"IMG_{i:04d}.jpg"
        p = a.out / name
        p.write_bytes(data)
        ts = when.timestamp()
        os.utime(p, (ts, ts))
        rows.append((g, name, kind, when.isoformat()))
    with open(a.out / "manifest.csv", "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["group", "file", "kind", "taken_at"])
        w.writerows(sorted(rows))

    n_angle = sum(1 for r in rows if r[2] == "angle")
    print(f"Đã tạo {len(rows)} ảnh trong {a.out}")
    print(f"  {a.count} cảnh gốc | {a.exact} bản exact | {a.near} bản near | {n_angle} ảnh đổi góc ({a.angle} nhóm)")
    print(f"  Fast Scan kỳ vọng: {a.exact} nhóm exact + {a.near} nhóm near = {a.exact + a.near} nhóm, "
          f"{a.exact + a.near} ảnh dọn được. Ảnh 'angle' KHÔNG được gom.")
    print("  manifest.csv không phải ảnh, đừng copy vào máy.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
