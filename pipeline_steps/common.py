"""Hàm dùng chung cho các bước. Cần: numpy, pillow. Bước 4 cần onnxruntime, bước 6 cần opencv-python.

Các hằng bên dưới lấy từ ScanConfig của app (lib/core/scanner/scan_orchestrator.dart).
Đổi ở đây (hoặc bằng tham số dòng lệnh của từng bước) để thử ngưỡng khác.
"""
import argparse
import csv
import io
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps

try:  # tùy chọn: đọc HEIC
    from pillow_heif import register_heif_opener

    register_heif_opener()
except Exception:
    pass

IMG_EXT = {".jpg", ".jpeg", ".png", ".webp", ".bmp", ".heic", ".heif"}

# ---- ngưỡng giống app ----
MAX_HAMMING = 32            # ScanConfig.maxHamming: Hamming <= 32 => "Trùng"
SIMILAR_MAX_HAMMING = 70    # ScanConfig.similarMaxHamming: 33..70 => "Tương tự" (chỉ xem)
SIM_K = 3                   # ScanConfig.similarModelK
SIM_FLOOR = 0.55            # ScanConfig.similarModelFloor (cosine sau khi trừ trung bình)
MIN_MEAN_COUNT = 32         # ScanConfig.modelMinMeanCount
LOCAL_MIN_INLIERS = 45
LOCAL_NEIGHBORS = 6
LOCAL_WINDOW_MIN = 5
LOCAL_MAX_PAIRS = 3000
LOCAL_SIDE = 640

# thumbnail app xin từ photo_manager: (rộng, cao, chất lượng JPEG)
PDQ_THUMB = (128, 128, 70)
EMB_THUMB = (224, 224, 85)


# ------------------------------------------------------------------ CLI / file
def base_parser(desc: str) -> argparse.ArgumentParser:
    ap = argparse.ArgumentParser(description=desc)
    ap.add_argument("--src", required=True, help="thư mục ảnh đầu vào")
    ap.add_argument("--out", default="out", help="thư mục kết quả (mặc định: out)")
    return ap


def write_csv(path: Path, header, rows):
    path.parent.mkdir(parents=True, exist_ok=True)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)


def read_csv(path: Path):
    with open(path, newline="", encoding="utf-8") as f:
        return list(csv.DictReader(f))


def need(path: Path, step: str):
    if not path.exists():
        raise SystemExit(f"Thiếu {path}. Hãy chạy {step} trước.")
    return path


def ensure_index(src: Path, out: Path):
    """out/photos.csv: danh sách ảnh có thứ tự cố định, mọi bước dùng chung chỉ số này.
    Đổi bộ ảnh thì xóa thư mục out/ rồi chạy lại từ bước 1."""
    out.mkdir(parents=True, exist_ok=True)
    f = out / "photos.csv"
    if not f.exists():
        out_r = out.resolve()
        files = sorted(
            p for p in src.rglob("*")
            if p.is_file() and p.suffix.lower() in IMG_EXT and not p.name.startswith(".")
            and out_r not in p.resolve().parents
        )
        rows = []
        for i, p in enumerate(files):
            st = p.stat()
            rows.append([i, str(p.relative_to(src)), st.st_size, int(st.st_mtime)])
        write_csv(f, ["idx", "path", "size", "mtime"], rows)
    return [
        dict(idx=int(r["idx"]), path=r["path"], size=int(r["size"]), mtime=int(r["mtime"]))
        for r in read_csv(f)
    ]


# ---------------------------------------------------------------------- ảnh
def load_rgb(path: Path) -> Image.Image:
    with Image.open(path) as im:
        if im.format == "JPEG":
            im.draft("RGB", (1024, 1024))
        return ImageOps.exif_transpose(im).convert("RGB")


def fit_jpeg(im: Image.Image, spec) -> bytes:
    w, h, q = spec
    t = ImageOps.fit(im, (w, h), Image.BICUBIC)
    buf = io.BytesIO()
    t.save(buf, "JPEG", quality=q)
    return buf.getvalue()


# ------------------------------------------------------------- PDQ (bản port)
_COS = np.array(
    [[math.cos(math.pi * (2 * x + 1) * u / 128) for x in range(64)] for u in range(16)],
    dtype=np.float64,
)


def pdq_bits(img_bytes: bytes):
    """256 bit kiểu PDQ (giống lib/engines/pdq/pdq_engine.dart). None nếu lỗi giải mã."""
    try:
        im = Image.open(io.BytesIO(img_bytes)).convert("RGB")
    except Exception:
        return None
    a = np.asarray(im.resize((64, 64), Image.BOX), dtype=np.float64)
    lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
    coeff = _COS @ (lum @ _COS.T)
    flat = coeff.reshape(256)
    s = np.sort(flat)
    return flat > (s[127] + s[128]) / 2


def bits_to_hex(bits) -> str:
    words = [0, 0, 0, 0]
    for i in np.nonzero(bits)[0]:
        words[int(i) >> 6] |= 1 << (int(i) & 63)
    return "".join(f"{w:016x}" for w in words)


POP = np.array([bin(i).count("1") for i in range(256)], dtype=np.uint8)


def hex_to_packed(h: str):
    return np.frombuffer(bytes.fromhex(h), dtype=np.uint8)


def sim_pct(hamming: int) -> float:
    return 100.0 * (1 - hamming / 256)


def load_pdq(out: Path, n: int):
    """Trả (packed n x 32 byte, valid n bool)."""
    packed = np.zeros((n, 32), dtype=np.uint8)
    valid = np.zeros(n, dtype=bool)
    for r in read_csv(need(out / "2_pdq.csv", "step2_pdq.py")):
        if r["pdq"]:
            i = int(r["idx"])
            packed[i] = hex_to_packed(r["pdq"])
            valid[i] = True
    return packed, valid


def exact_pairs(packed, valid, max_h):
    """So mọi cặp: không bỏ sót cặp nào. Trả list (i, j, hamming)."""
    out = []
    n = len(packed)
    for i in range(n):
        if not valid[i]:
            continue
        d = POP[packed[i + 1:] ^ packed[i]].sum(axis=1, dtype=np.int32)
        for k in np.nonzero((d <= max_h) & valid[i + 1:])[0]:
            out.append((i, i + 1 + int(k), int(d[k])))
    return out


def lsh_pairs(packed, valid, max_h, max_bucket=48):
    """LSH 16 band x 16 bit như app khi thư viện lớn. Chỉ là ứng viên, có thể sót."""
    n = len(packed)
    seen, out = set(), []
    for b in range(16):
        keys = (packed[:, 2 * b].astype(np.uint32) << 8) | packed[:, 2 * b + 1]
        buckets = {}
        for i in range(n):
            if valid[i]:
                buckets.setdefault(int(keys[i]), []).append(i)
        for bk in buckets.values():
            if len(bk) < 2 or len(bk) > max_bucket:
                continue
            for x in range(len(bk)):
                for y in range(x + 1, len(bk)):
                    i, j = bk[x], bk[y]
                    if (i, j) in seen:
                        continue
                    seen.add((i, j))
                    d = int(POP[packed[i] ^ packed[j]].sum())
                    if d <= max_h:
                        out.append((i, j, d))
    return out


# ------------------------------------------------------------------- nhóm
def dup_members(out: Path, max_h: int):
    """Chỉ số ảnh đã thuộc nhóm trùng (SHA trùng hoặc Hamming <= max_h) nếu đã có file."""
    s = set()
    f = out / "3_pairs_exact.csv"
    if f.exists():
        for r in read_csv(f):
            if int(r["hamming"]) <= max_h:
                s.update([int(r["a"]), int(r["b"])])
    f = out / "1_sha256.csv"
    if f.exists():
        by = {}
        for r in read_csv(f):
            if r["sha256"]:
                by.setdefault(r["sha256"], []).append(int(r["idx"]))
        for v in by.values():
            if len(v) > 1:
                s.update(v)
    return s


def build_groups(edges, sizes):
    """edges: {(i,j): (score, nguồn)}, i<j. Gộp bằng Union-Find, rồi chỉ giữ ảnh có cạnh
    TRỰC TIẾP với ảnh đại diện (lớn nhất) để không bị bắc cầu A~B~C. Trả list (rep, [(idx, score, nguồn)])."""
    parent = {}

    def find(x):
        while parent.setdefault(x, x) != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x

    for (i, j) in edges:
        ri, rj = find(i), find(j)
        if ri != rj:
            parent[rj] = ri
    comps = {}
    for x in list(parent):
        comps.setdefault(find(x), []).append(x)
    groups = []
    for members in comps.values():
        if len(members) < 2:
            continue
        rep = max(members, key=lambda m: (sizes[m], -m))
        kept = []
        for m in members:
            if m == rep:
                continue
            e = edges.get((min(m, rep), max(m, rep)))
            if e:
                kept.append((m, e[0], e[1]))
        if kept:
            groups.append((rep, sorted(kept, key=lambda t: -t[1])))
    groups.sort(key=lambda g: -len(g[1]))
    return groups
