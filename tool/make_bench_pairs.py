#!/usr/bin/env python3
"""Dựng bộ cặp ảnh CÓ NHÃN TỰ ĐỘNG từ COIL-100 (obj<ID>__<GÓC>.png) để thử pipeline calibrate.

Không cần gán nhãn tay. Nhãn suy ra từ tên file:
  similar    cùng vật thể, góc lệch <= --max-angle độ (xoay vòng)
  different  hai vật thể khác nhau
  dup        ảnh gốc + biến thể tự sinh (JPEG thấp, thu nhỏ, chỉnh sáng, bản sao y hệt)

Chia train/test THEO VẬT THỂ. Ghi <out>/manifest.csv và <out>/variants/.
Sau đó: score_pairs.py --src <src> --out <out>  rồi  calibrate.py --out <out>

LƯU Ý: COIL là vật thể trên nền đơn giản, KHÔNG phải ảnh điện thoại, và không có
người. Dùng để kiểm tra đường ống và xem hình dạng phân phối điểm; KHÔNG dùng để
chốt ngưỡng cuối. Tab Người không có dữ liệu. COIL-100 chỉ dùng cho nghiên cứu,
không đưa vào app.

Ví dụ: python tool/make_bench_pairs.py ~/Desktop/data/data_1 eval_bench_coil
"""
import argparse
import csv
import random
import re
import shutil
import sys
from collections import defaultdict
from pathlib import Path

from PIL import Image, ImageEnhance


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", type=Path)
    ap.add_argument("out", type=Path)
    ap.add_argument("--max-angle", type=int, default=45)
    ap.add_argument("--pos-per-obj", type=int, default=60)
    ap.add_argument("--neg-per-obj", type=int, default=60)
    ap.add_argument("--variants", type=int, default=120)
    ap.add_argument("--min-views", type=int, default=8, help="bỏ vật thể có ít góc hơn mức này")
    ap.add_argument("--train-ratio", type=float, default=0.7)
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()
    if a.out.exists() and any(a.out.iterdir()):
        print(f"{a.out} đã tồn tại và không rỗng.", file=sys.stderr)
        return 1
    rnd = random.Random(a.seed)

    by = defaultdict(dict)  # obj -> {angle: filename}
    for f in a.src.iterdir():
        m = re.match(r"obj(\d+)__(\d+)\.png$", f.name)
        if m:
            by[int(m.group(1))][int(m.group(2))] = f.name
    by = {o: v for o, v in by.items() if len(v) >= a.min_views}
    if len(by) < 3:
        print("Cần ít nhất 3 vật thể đủ góc.", file=sys.stderr)
        return 1
    objs = sorted(by)
    rnd.shuffle(objs)
    n_train = min(max(1, round(len(objs) * a.train_ratio)), len(objs) - 1)
    split = {o: ("train" if i < n_train else "test") for i, o in enumerate(objs)}

    rows, seen = [], set()

    def add(a_, b_, label, kind, o1, o2):
        key = frozenset((a_, b_))
        if a_ == b_ or key in seen:
            return
        seen.add(key)
        rows.append({"asset_a": a_, "asset_b": b_, "kind": kind, "split": split[o1],
                     "scene_a": o1, "scene_b": o2, "label": label, "label_source": "bench"})

    def circ(x, y):
        d = abs(x - y) % 360
        return min(d, 360 - d)

    for o in objs:
        angs = sorted(by[o])
        cand = [(x, y) for i, x in enumerate(angs) for y in angs[i + 1:] if 0 < circ(x, y) <= a.max_angle]
        rnd.shuffle(cand)
        for x, y in cand[: a.pos_per_obj]:
            add("src:" + by[o][x], "src:" + by[o][y], "similar", "same_object", o, o)
    for sp in ("train", "test"):
        pool = [o for o in objs if split[o] == sp]
        if len(pool) < 2:
            continue
        for o in pool:
            made = 0
            for _ in range(a.neg_per_obj * 20):
                if made >= a.neg_per_obj:
                    break
                o2 = rnd.choice([p for p in pool if p != o])
                n0 = len(rows)
                add("src:" + by[o][rnd.choice(sorted(by[o]))], "src:" + by[o2][rnd.choice(sorted(by[o2]))],
                    "different", "cross_object", o, o2)
                made += len(rows) - n0

    vdir = a.out / "variants"
    vdir.mkdir(parents=True, exist_ok=True)
    allimgs = [(o, ang, fn) for o in objs for ang, fn in by[o].items()]
    kinds = ["jpeg", "resize", "bright", "exact"]
    for n, (o, ang, fn) in enumerate(rnd.sample(allimgs, min(a.variants, len(allimgs)))):
        kind = kinds[n % 4]
        stem = f"{n:03d}_{Path(fn).stem}_{kind}"
        im = Image.open(a.src / fn).convert("RGB")
        if kind == "exact":
            dst = vdir / (stem + ".png")
            shutil.copy2(a.src / fn, dst)
        else:
            dst = vdir / (stem + ".jpg")
            if kind == "jpeg":
                im.save(dst, "JPEG", quality=40)
            elif kind == "resize":
                w, h = im.size
                im.resize((max(1, w // 2), max(1, h // 2)), Image.LANCZOS).save(dst, "JPEG", quality=80)
            else:
                ImageEnhance.Brightness(im).enhance(1.15).save(dst, "JPEG", quality=85)
        add("src:" + fn, "out:variants/" + dst.name, "dup", "variant", o, o)

    rnd.shuffle(rows)
    for i, r in enumerate(rows, 1):
        r["pair_id"] = f"p{i:05d}"
    fields = ["pair_id", "asset_a", "asset_b", "kind", "split", "scene_a", "scene_b", "label", "label_source"]
    with open(a.out / "manifest.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    from collections import Counter
    c = Counter((r["label"], r["split"]) for r in rows)
    print(f"{len(objs)} vật thể (train {n_train}), {len(rows)} cặp.")
    for k, v in sorted(c.items()):
        print(f"  {k[0]:10s} {k[1]:5s} {v}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
