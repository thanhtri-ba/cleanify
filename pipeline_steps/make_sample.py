#!/usr/bin/env python3
"""Sinh bộ ảnh THỬ TỔNG HỢP để chạy thử các bước (không thay thế ảnh thật khi calibrate).

python3 make_sample.py --dst sample_photos
Gồm: ảnh độc lập, bản sao y hệt, bản nén lại/thu nhỏ, bản đổi sáng, bản crop.
"""
import argparse
import random
import shutil
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter


def scene(rnd, size=(640, 480)):
    base = np.array([rnd.randint(30, 220) for _ in range(3)], dtype=np.uint8)
    arr = np.tile(base, (size[1], size[0], 1)).astype(np.float32)
    gy = np.linspace(-40, 40, size[1])[:, None, None] * rnd.choice([-1, 1])
    arr = np.clip(arr + gy, 0, 255).astype(np.uint8)
    im = Image.fromarray(arr)
    d = ImageDraw.Draw(im)
    for _ in range(rnd.randint(6, 12)):
        x, y = rnd.randint(0, size[0] - 80), rnd.randint(0, size[1] - 80)
        w, h = rnd.randint(40, 200), rnd.randint(40, 200)
        col = tuple(rnd.randint(0, 255) for _ in range(3))
        (d.ellipse if rnd.random() < .5 else d.rectangle)([x, y, x + w, y + h], fill=col)
    return im.filter(ImageFilter.GaussianBlur(1.2))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dst", default="sample_photos")
    ap.add_argument("--scenes", type=int, default=40)
    a = ap.parse_args()
    dst = Path(a.dst)
    dst.mkdir(parents=True, exist_ok=True)
    rnd = random.Random(7)
    for s in range(a.scenes):
        im = scene(rnd)
        p = dst / f"s{s:03d}.jpg"
        im.save(p, quality=92)
        if s % 4 == 0:
            shutil.copy(p, dst / f"s{s:03d}_copy.jpg")
        if s % 4 == 1:
            im.resize((320, 240)).save(dst / f"s{s:03d}_small.jpg", quality=60)
        if s % 4 == 2:
            ImageEnhance.Brightness(im).enhance(1.35).save(dst / f"s{s:03d}_bright.jpg", quality=90)
        if s % 8 == 3:
            im.crop((40, 30, 600, 450)).save(dst / f"s{s:03d}_crop.jpg", quality=90)
    print(f"{len(list(dst.glob('*.jpg')))} ảnh -> {dst}")


if __name__ == "__main__":
    main()
