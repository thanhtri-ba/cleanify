"""Hàm dùng chung cho score_pairs.py và calibrate.py (Python 3.9+).

Mô phỏng pipeline của app Cleanify để tính điểm cặp ảnh ngoài app:
  * PDQ  : bản port Python của lib/engines/pdq/pdq_engine.dart
  * DINO : tiền xử lý khớp lib/engines/dino/onnx_dino_engine.dart
  * ReID : tiền xử lý khớp lib/engines/person/onnx_reid_engine.dart

LƯU Ý ĐỘ TƯƠNG ĐƯƠNG: thumbnail trong app do photo_manager/hệ điều hành tạo, ở đây
mô phỏng bằng cắt giữa + resize bicubic + JPEG; copyResize(average) của gói `image`
(Dart) xấp xỉ bằng BOX của Pillow. Vì vậy điểm KHÔNG khớp từng bit với app. Để PDQ
khớp tuyệt đối, dùng tool/dump_pdq.dart rồi truyền --pdq-dart cho score_pairs.py.
"""
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

MEAN = np.array([0.485, 0.456, 0.406], dtype=np.float32)
STD = np.array([0.229, 0.224, 0.225], dtype=np.float32)

# Kích thước thumbnail mà app yêu cầu từ photo_manager (xem các engine Dart).
PDQ_THUMB = (128, 128, 70)      # scan_orchestrator._prepare
DINO_THUMB = (224, 224, 85)     # onnx_dino_engine.embed
REID_THUMB = (256, 512, 85)     # onnx_reid_engine.analyze (kReidWidth*2, kReidHeight*2)
DINO_SIZE = 224
REID_W, REID_H = 128, 256


def resolve_asset(asset: str, src: Path, out: Path) -> Path:
    root, rel = (src, asset[4:]) if asset.startswith("src:") else (out, asset[4:])
    p = (root / rel).resolve()
    p.relative_to(root.resolve())  # chặn thoát khỏi thư mục gốc
    return p


def load_rgb(path: Path) -> Image.Image:
    with Image.open(path) as im:
        if im.format == "JPEG":
            im.draft("RGB", (1024, 1024))
        return ImageOps.exif_transpose(im).convert("RGB")


def thumb_bytes(im: Image.Image, spec) -> bytes:
    w, h, q = spec
    t = ImageOps.fit(im, (w, h), Image.BICUBIC)
    buf = io.BytesIO()
    t.save(buf, "JPEG", quality=q)
    return buf.getvalue()


# ---------------------------------------------------------------- PDQ (port)
_COS = np.array(
    [[math.cos(math.pi * (2 * x + 1) * u / 128) for x in range(64)] for u in range(16)],
    dtype=np.float64,
)


def pdq_bits(img_bytes: bytes):
    """256 bit (mảng bool, chỉ số i = v*16+u như bản Dart). None nếu không giải mã được."""
    try:
        im = Image.open(io.BytesIO(img_bytes)).convert("RGB")
    except Exception:
        return None
    a = np.asarray(im.resize((64, 64), Image.BOX), dtype=np.float64)
    lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]  # [y][x]
    tmp = lum @ _COS.T          # [y][u]
    coeff = _COS @ tmp          # [v][u]
    flat = coeff.reshape(256)
    s = np.sort(flat)
    median = (s[127] + s[128]) / 2
    return flat > median


def bits_to_hex(bits) -> str:
    """4 word 64-bit, bit i nằm ở word i>>6, vị trí i&63 (giống bản Dart)."""
    words = [0, 0, 0, 0]
    for i in np.nonzero(bits)[0]:
        words[int(i) >> 6] |= 1 << (int(i) & 63)
    return "".join(f"{w:016x}" for w in words)


def hex_to_bits(h: str):
    bits = np.zeros(256, dtype=bool)
    for k in range(4):
        w = int(h[k * 16:(k + 1) * 16], 16)
        for b in range(64):
            if (w >> b) & 1:
                bits[k * 64 + b] = True
    return bits


def hamming(a, b) -> int:
    return int(np.count_nonzero(a != b))


# ------------------------------------------------------ tiền xử lý + ONNX
def _norm_chw(im: Image.Image) -> np.ndarray:
    x = np.asarray(im, dtype=np.float32) / 255.0
    x = (x - MEAN) / STD
    return np.ascontiguousarray(x.transpose(2, 0, 1))[None]


def preprocess_dino(thumb: bytes) -> np.ndarray:
    im = Image.open(io.BytesIO(thumb)).convert("RGB").resize((DINO_SIZE, DINO_SIZE), Image.BOX)
    return _norm_chw(im)


def preprocess_reid(thumb: bytes) -> np.ndarray:
    im = Image.open(io.BytesIO(thumb)).convert("RGB").resize((REID_W, REID_H), Image.BOX)
    return _norm_chw(im)


class Embedder:
    """ONNX Runtime, chuẩn hóa L2 giống l2NormalizeAt của app."""

    def __init__(self, model_path: Path):
        import onnxruntime as ort

        self.s = ort.InferenceSession(str(model_path), providers=["CPUExecutionProvider"])
        self.inp = self.s.get_inputs()[0].name

    def __call__(self, x: np.ndarray):
        out = self.s.run(None, {self.inp: x})[0]
        v = np.asarray(out, dtype=np.float32).reshape(-1)
        n = float(np.linalg.norm(v))
        return v / n if n * n >= 1e-12 else None


# ------------------------------------------------- chọn ngưỡng có cận tin cậy
def precision_lower_bound(tp: int, n: int, alpha: float = 0.05) -> float:
    """Cận dưới một phía của precision. Clopper-Pearson nếu có scipy, không thì Wilson."""
    if n <= 0 or tp <= 0:
        return 0.0
    try:
        from scipy.stats import beta

        return float(beta.ppf(alpha, tp, n - tp + 1))
    except Exception:
        from statistics import NormalDist

        z = NormalDist().inv_cdf(1 - alpha)
        p = tp / n
        den = 1 + z * z / n
        centre = p + z * z / (2 * n)
        spread = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
        return max(0.0, (centre - spread) / den)


def select_threshold(scores, y, target, match_if_ge=True, alpha=0.05):
    """Ngưỡng DỄ DÃI nhất mà cận dưới precision >= target. None nếu không có.

    match_if_ge=True : cosine (điểm càng cao càng giống)
    match_if_ge=False: Hamming (điểm càng thấp càng giống)
    """
    scores = np.asarray(scores, dtype=np.float64)
    y = np.asarray(y).astype(int)
    s = scores if match_if_ge else -scores
    best = None
    for t in np.unique(s)[::-1]:  # từ nghiêm ngặt đến dễ dãi
        pred = s >= t
        n = int(pred.sum())
        tp = int(y[pred].sum())
        if precision_lower_bound(tp, n, alpha) >= target:
            best = t
    if best is None:
        return None
    return float(best if match_if_ge else -best)


def evaluate(pred, y):
    pred = np.asarray(pred, dtype=bool)
    y = np.asarray(y).astype(int)
    n = int(pred.sum())
    tp = int(y[pred].sum())
    pos = int(y.sum())
    return {
        "n_pred": n, "tp": tp, "positives": pos,
        "precision": (tp / n) if n else None,
        "recall": (tp / pos) if pos else None,
    }
