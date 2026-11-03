#!/usr/bin/env python3
"""Sinh danh sách CẶP ỨNG VIÊN để gán nhãn và calibrate ngưỡng cho Cleanify.

Đầu vào : thư mục ảnh thật (vd. eval_real/) đã xuất từ iPhone. Nên xuất ảnh gốc
          dạng JPEG (Ảnh > Xuất > "Tương thích nhất") hoặc cài `pip install pillow-heif`
          để đọc HEIC. EXIF DateTimeOriginal được dùng để chia "cảnh".
Đầu ra  : <out>/candidates.csv  các cặp ứng viên (chưa có nhãn, trừ cặp tự sinh)
          <out>/scenes.csv      ảnh nào thuộc cảnh nào, split nào
          <out>/variants/       bản sao/biến thể tự sinh (nén lại, thu nhỏ, chỉnh sáng)

Loại cặp (cột kind):
  within_scene  hai ảnh cùng một cảnh (cách nhau <= --window-min phút)
  hard_neg      khác cảnh nhưng trông giống nhau (dHash gần) -> âm tính khó
  rand_neg      khác cảnh, ngẫu nhiên
  variant       ảnh gốc + biến thể do script tạo -> tự gán nhãn `dup`

Chia train/test THEO CẢNH, không theo cặp, để không rò rỉ: mọi cặp có cả hai ảnh
trong cùng một split.

Hạn chế: cặp "cùng một người, khác cảnh" khó tìm khi chưa có model; hiện chỉ có
trong rand_neg/hard_neg nếu tình cờ gặp. Có thể bổ sung bằng cách khai thác theo
embedding OSNet ở bước calibrate.

Ví dụ: python3 tool/build_eval_pairs.py eval_real eval_out
"""
import argparse
import csv
import datetime as dt
import random
import shutil
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageEnhance, ImageOps

try:  # tùy chọn: đọc HEIC
    from pillow_heif import register_heif_opener

    register_heif_opener()
except Exception:
    pass

EXTS = {".jpg", ".jpeg", ".png", ".heic", ".heif", ".webp"}


def exif_time(path: Path, im: Image.Image) -> float:
    try:
        ex = im.getexif()
        s = ex.get_ifd(0x8769).get(36867) or ex.get(306)
        if s:
            return dt.datetime.strptime(str(s).strip()[:19], "%Y:%m:%d %H:%M:%S").timestamp()
    except Exception:
        pass
    return path.stat().st_mtime


def dhash(im: Image.Image) -> np.ndarray:
    g = ImageOps.exif_transpose(im).convert("L").resize((9, 8), Image.BILINEAR)
    a = np.asarray(g, dtype=np.int16)
    return (a[:, 1:] > a[:, :-1]).flatten()


def load_meta(path: Path):
    with Image.open(path) as im:
        t = exif_time(path, im)
        if im.format == "JPEG":
            im.draft("RGB", (320, 320))
        im.load()
        return t, dhash(im)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", type=Path, help="thư mục ảnh thật")
    ap.add_argument("out", type=Path, help="thư mục đầu ra (phải rỗng hoặc chưa có)")
    ap.add_argument("--window-min", type=float, default=30, help="khoảng cách tối đa trong một cảnh (phút)")
    ap.add_argument("--max-within", type=int, default=12, help="số cặp tối đa mỗi cảnh")
    ap.add_argument("--hard-neg", type=int, default=60, help="số âm tính khó mỗi split")
    ap.add_argument("--rand-neg", type=int, default=40, help="số âm tính ngẫu nhiên mỗi split")
    ap.add_argument("--variants", type=int, default=30, help="số ảnh gốc được tạo biến thể")
    ap.add_argument("--train-ratio", type=float, default=0.7)
    ap.add_argument("--seed", type=int, default=42)
    a = ap.parse_args()

    if not a.src.is_dir():
        print(f"Không thấy thư mục {a.src}", file=sys.stderr)
        return 1
    if a.out.exists() and any(a.out.iterdir()):
        print(f"{a.out} đã tồn tại và không rỗng.", file=sys.stderr)
        return 1
    rnd = random.Random(a.seed)

    # 1. Đọc ảnh
    photos, skipped = [], 0
    for f in sorted(a.src.rglob("*")):
        if not f.is_file() or f.name.startswith(".") or f.suffix.lower() not in EXTS:
            continue
        try:
            t, h = load_meta(f)
        except Exception as e:
            skipped += 1
            print(f"  bỏ qua {f.name}: {e}", file=sys.stderr)
            continue
        photos.append({"rel": f.relative_to(a.src).as_posix(), "path": f, "t": t, "h": h})
    if len(photos) < 10:
        print(f"Chỉ đọc được {len(photos)} ảnh (bỏ qua {skipped}). Cần ít nhất 10.", file=sys.stderr)
        return 1

    # 2. Chia cảnh theo khoảng cách thời gian
    photos.sort(key=lambda p: p["t"])
    scene = 0
    for i, p in enumerate(photos):
        if i > 0 and p["t"] - photos[i - 1]["t"] > a.window_min * 60:
            scene += 1
        p["scene"] = scene
    n_scenes = scene + 1
    ids = list(range(n_scenes))
    rnd.shuffle(ids)
    n_train = min(max(1, round(n_scenes * a.train_ratio)), max(1, n_scenes - 1))
    split_of = {sid: ("train" if k < n_train else "test") for k, sid in enumerate(ids)}
    if n_scenes < 4:
        print(f"CẢNH BÁO: chỉ có {n_scenes} cảnh, tập test sẽ rất nhỏ.", file=sys.stderr)
    for p in photos:
        p["split"] = split_of[p["scene"]]

    rows, seen = [], set()

    def add(pa, pb, kind, label="", source=""):
        key = frozenset((pa, pb))
        if pa == pb or key in seen:
            return False
        seen.add(key)
        rows.append({"a": pa, "b": pb, "kind": kind, "label": label, "label_source": source})
        return True

    # 3. Cặp trong cảnh
    by_scene = {}
    for idx, p in enumerate(photos):
        by_scene.setdefault(p["scene"], []).append(idx)
    for members in by_scene.values():
        k = len(members)
        if k < 2:
            continue
        allp = [(members[i], members[j]) for i in range(k) for j in range(i + 1, k)]
        if len(allp) <= a.max_within:
            chosen = allp
        else:
            adj = [(members[i], members[i + 1]) for i in range(k - 1)]
            rest = [x for x in allp if x not in set(adj)]
            rnd.shuffle(rest)
            chosen = adj + rest[: max(0, a.max_within - len(adj))]
        for i, j in chosen:
            add("src:" + photos[i]["rel"], "src:" + photos[j]["rel"], "within_scene")

    # 4. Âm tính khó và ngẫu nhiên, mỗi split riêng
    for split in ("train", "test"):
        pool = [i for i, p in enumerate(photos) if p["split"] == split]
        if len(pool) < 2:
            continue
        H = np.stack([photos[i]["h"] for i in pool])
        sc = np.array([photos[i]["scene"] for i in pool])
        cand = []
        for x in range(len(pool)):
            d = (H[x + 1:] != H[x]).sum(1)
            diff = sc[x + 1:] != sc[x]
            for off in np.nonzero(diff & (d <= 20))[0]:
                cand.append((int(d[off]), x, x + 1 + int(off)))
        cand.sort()
        use, cnt, made = {}, 0, 0
        for _, x, y in cand:
            if made >= a.hard_neg:
                break
            if use.get(x, 0) >= 3 or use.get(y, 0) >= 3:
                continue
            if add("src:" + photos[pool[x]]["rel"], "src:" + photos[pool[y]]["rel"], "hard_neg"):
                use[x] = use.get(x, 0) + 1
                use[y] = use.get(y, 0) + 1
                made += 1
        made, tries = 0, 0
        while made < a.rand_neg and tries < a.rand_neg * 30:
            tries += 1
            x, y = rnd.sample(range(len(pool)), 2)
            if sc[x] == sc[y]:
                continue
            if add("src:" + photos[pool[x]]["rel"], "src:" + photos[pool[y]]["rel"], "rand_neg"):
                made += 1

    # 5. Biến thể tự sinh (nhãn dup biết trước)
    vdir = a.out / "variants"
    vdir.mkdir(parents=True, exist_ok=True)
    kinds = ["jpeg", "resize", "bright", "exact"]
    for n, idx in enumerate(rnd.sample(range(len(photos)), min(a.variants, len(photos)))):
        p = photos[idx]
        kind = kinds[n % len(kinds)]
        stem = f"{n:03d}_{Path(p['rel']).stem}_{kind}"
        try:
            if kind == "exact":
                dst = vdir / (stem + p["path"].suffix.lower())
                shutil.copy2(p["path"], dst)
            else:
                with Image.open(p["path"]) as im0:
                    im = ImageOps.exif_transpose(im0).convert("RGB")
                dst = vdir / (stem + ".jpg")
                if kind == "jpeg":
                    im.save(dst, "JPEG", quality=40)
                elif kind == "resize":
                    w, h = im.size
                    im.resize((max(1, w // 2), max(1, h // 2)), Image.LANCZOS).save(dst, "JPEG", quality=80)
                else:
                    ImageEnhance.Brightness(im).enhance(1.15).save(dst, "JPEG", quality=85)
        except Exception as e:
            print(f"  không tạo được biến thể {stem}: {e}", file=sys.stderr)
            continue
        add("src:" + p["rel"], "out:variants/" + dst.name, "variant", "dup", "auto")

    # 6. Ghi kết quả
    split_by_rel = {p["rel"]: p for p in photos}

    def info(asset):
        if asset.startswith("src:"):
            p = split_by_rel[asset[4:]]
            return p["scene"], p["split"]
        return None, None  # chỉ gọi cho ảnh gốc; biến thể dùng split của ảnh gốc

    rnd.shuffle(rows)
    out_rows = []
    for k, r in enumerate(rows, 1):
        sa, spa = info(r["a"])
        if r["kind"] == "variant":
            sb, spb = sa, spa
        else:
            sb, spb = info(r["b"])
        out_rows.append({
            "pair_id": f"p{k:05d}", "asset_a": r["a"], "asset_b": r["b"], "kind": r["kind"],
            "split": spa, "scene_a": sa, "scene_b": sb, "label": r["label"],
            "label_source": r["label_source"],
        })
    with open(a.out / "candidates.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(out_rows[0].keys()))
        w.writeheader()
        w.writerows(out_rows)
    with open(a.out / "scenes.csv", "w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh)
        w.writerow(["asset", "taken_at", "scene_id", "split"])
        for p in photos:
            w.writerow(["src:" + p["rel"], dt.datetime.fromtimestamp(p["t"]).isoformat(timespec="seconds"),
                        p["scene"], p["split"]])

    from collections import Counter
    c = Counter((r["kind"], r["split"]) for r in out_rows)
    print(f"{len(photos)} ảnh, {n_scenes} cảnh (train {n_train}), bỏ qua {skipped} file.")
    for (kind, split), n in sorted(c.items()):
        print(f"  {kind:13s} {split:5s} {n}")
    manual = sum(1 for r in out_rows if r["label_source"] != "auto")
    print(f"Tổng {len(out_rows)} cặp, cần gán nhãn tay: {manual}.")
    print(f"Tiếp theo: python3 tool/label_pairs.py --src {a.src} --out {a.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
