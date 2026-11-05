# %% [markdown]
# # Cleanify — thực nghiệm 2 mô hình
#
# | | Mô hình A (hiện tại) | Mô hình B (đề xuất) |
# |---|---|---|
# | Tìm ứng viên | PDQ → Hamming; MobileNet top-3 mutual (chỉ cho ảnh chưa vào nhóm trùng) | Hợp nhất 2 kênh: PDQ ≤ 70 và MobileNet top-K (K lớn hơn), không loại cặp chỉ vì 1 kênh |
# | Xác minh | Ngưỡng cố định: Hamming ≤ 32, cosine ≥ 0,55 | Nhiều tầng: SHA → (Hamming, cosine) **đã calibrate** → ORB+RANSAC khi cần |
# | Gom nhóm | Union-Find + chỉ giữ ảnh nối trực tiếp với ảnh đại diện | Gom ràng buộc: ảnh vào nhóm phải tương thích với đại diện và các thành viên, không thì thành "Uncertain" |
#
# **Cách đo:** từ N ảnh gốc, tự sinh biến thể (nén lại, đổi sáng, crop, xoay, nhiễu...) nên biết chắc ảnh nào cùng nguồn.
# Hai mô hình chạy trên cùng tập **test** (B calibrate trên tập **train**, tách theo nguồn ảnh).
#
# **Chạy:** Runtime → Run all. Muốn dùng ảnh của bạn, đổi `SOURCE = "upload"` ở ô cấu hình.
# Kết quả chỉ để so sánh A và B, **không** dùng để chốt ngưỡng sản xuất (cần ảnh thật có gán nhãn).

# %%
import os, io, sys, math, time, random, json, hashlib, zipfile, itertools
from pathlib import Path
import numpy as np
import pandas as pd
import matplotlib.pyplot as plt
from PIL import Image, ImageOps, ImageEnhance, ImageFilter

STUB = os.environ.get("CLEANIFY_STUB") == "1"   # chỉ dùng khi kiểm thử ngoài Colab (không có torch)

# %% [markdown]
# ## 1. Cấu hình

# %%
CFG = dict(
    SOURCE="flowers",          # "flowers" (ảnh mẫu, tự tải) | "upload" (zip ảnh của bạn) | "drive" | "synthetic"
    DRIVE_DIR="/content/drive/MyDrive/photos",
    N_SOURCES=250,             # số ảnh gốc; tổng ảnh ≈ N_SOURCES x (1 + VARIANTS_PER_SOURCE)
    VARIANTS_PER_SOURCE=3,
    SEED=1,
    # --- Mô hình A: đúng ScanConfig hiện tại ---
    A_MAX_HAMMING=32, A_SIMILAR_MAX=70, A_K=3, A_FLOOR=0.55,
    # --- Mô hình B ---
    B_K=10,                    # top-K của kênh embedding
    B_CAND_FLOOR=0.30,         # cosine tối thiểu để vào danh sách ứng viên
    B_SIM_COS=0.55,            # cosine để xếp vào "Similar"
    TARGET_PRECISION=0.96,     # mục tiêu sai <= 4% (cận dưới Wilson)
    B_MIN_FRAC=0.5,            # tỉ lệ thành viên mẫu phải tương thích khi ảnh mới vào nhóm
    B_USE_ORB=True, ORB_MIN_COS=0.30, ORB_BUDGET=3000,
)
CFG.update(json.loads(os.environ.get("CLEANIFY_CFG", "{}")))
rnd = random.Random(CFG["SEED"]); np.random.seed(CFG["SEED"])

# %% [markdown]
# ## 2. Dữ liệu: ảnh gốc + biến thể có nhãn "cùng nguồn"

# %%
def _shrink(im, side=800):
    im = ImageOps.exif_transpose(im).convert("RGB")
    s = side / max(im.size)
    return im.resize((int(im.width * s), int(im.height * s)), Image.LANCZOS) if s < 1 else im

def synthetic_scene(r, size=(640, 480)):
    from PIL import ImageDraw
    base = np.array([r.randint(30, 220) for _ in range(3)], dtype=np.float32)
    arr = np.tile(base, (size[1], size[0], 1))
    arr = np.clip(arr + np.linspace(-40, 40, size[1])[:, None, None] * r.choice([-1, 1]), 0, 255).astype(np.uint8)
    im = Image.fromarray(arr); d = ImageDraw.Draw(im)
    for _ in range(r.randint(6, 12)):
        x, y, w, h = r.randint(0, size[0] - 80), r.randint(0, size[1] - 80), r.randint(40, 200), r.randint(40, 200)
        (d.ellipse if r.random() < .5 else d.rectangle)([x, y, x + w, y + h], fill=tuple(r.randint(0, 255) for _ in range(3)))
    return im.filter(ImageFilter.GaussianBlur(1.2))

IMG_EXT = {".jpg", ".jpeg", ".png", ".webp", ".bmp"}

def load_originals():
    src, n = CFG["SOURCE"], CFG["N_SOURCES"]
    imgs = []
    if src == "upload":
        from google.colab import files
        print("Chọn 1 file .zip chứa ảnh của bạn (hoặc nhiều ảnh):")
        for name, data in files.upload().items():
            if name.lower().endswith(".zip"):
                with zipfile.ZipFile(io.BytesIO(data)) as z:
                    for nm in z.namelist():
                        if Path(nm).suffix.lower() in IMG_EXT and "__MACOSX" not in nm:
                            imgs.append(Image.open(io.BytesIO(z.read(nm))))
            elif Path(name).suffix.lower() in IMG_EXT:
                imgs.append(Image.open(io.BytesIO(data)))
    elif src == "drive":
        from google.colab import drive
        drive.mount("/content/drive")
        imgs = [Image.open(p) for p in sorted(Path(CFG["DRIVE_DIR"]).rglob("*")) if p.suffix.lower() in IMG_EXT]
    elif src == "flowers":
        import torchvision
        ds = torchvision.datasets.Flowers102(root="/content/data", split="train", download=True)
        imgs = [ds[i][0] for i in rnd.sample(range(len(ds)), min(n, len(ds)))]
    else:
        imgs = [synthetic_scene(rnd) for _ in range(n)]
    rnd.shuffle(imgs)
    imgs = imgs[:n]
    if len(imgs) < 40:
        print("CẢNH BÁO: dưới 40 ảnh gốc, kết quả không đáng tin.")
    return [_shrink(im) for im in imgs]

KINDS = ["exact", "recompress", "resize", "bright", "dark", "color",
         "crop_light", "crop_heavy", "rotate", "blur", "noise"]

def _center_crop(im, f, r):
    w, h = im.size
    cw, ch = int(w * f), int(h * f)
    x, y = r.randint(0, w - cw), r.randint(0, h - ch)
    return im.crop((x, y, x + cw, y + ch))

def make_variant(im, kind, r):
    """Trả (ảnh, chất lượng JPEG). Chất lượng None = dùng đúng byte của ảnh gốc."""
    w, h = im.size
    if kind == "exact":      return im, None
    if kind == "recompress": return im, r.choice([30, 40, 50])
    if kind == "resize":
        s = r.uniform(0.3, 0.6); return im.resize((max(48, int(w * s)), max(48, int(h * s))), Image.LANCZOS), 80
    if kind == "bright":     return ImageEnhance.Brightness(im).enhance(r.uniform(1.35, 1.8)), 90
    if kind == "dark":       return ImageEnhance.Brightness(im).enhance(r.uniform(0.4, 0.65)), 90
    if kind == "color":
        return ImageEnhance.Contrast(ImageEnhance.Color(im).enhance(r.choice([0.0, 0.3, 1.9]))).enhance(r.uniform(0.8, 1.3)), 90
    if kind == "crop_light": return _center_crop(im, 0.9, r), 90
    if kind == "crop_heavy": return _center_crop(im, 0.65, r), 90
    if kind == "rotate":
        return _center_crop(im.rotate(r.uniform(-8, 8), resample=Image.BICUBIC), 0.88, r), 90
    if kind == "blur":       return im.filter(ImageFilter.GaussianBlur(r.uniform(2, 3.5))), 85
    if kind == "noise":
        a = np.asarray(im, dtype=np.float32) + np.random.normal(0, 14, (h, w, 3))
        return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)), 85
    raise ValueError(kind)

def _jpeg(im, q):
    b = io.BytesIO(); im.save(b, "JPEG", quality=q); return b.getvalue()

def build_benchmark(originals, r):
    P, ptr = [], 0
    for s, im in enumerate(originals):
        ob = _jpeg(im, 92)
        P.append(dict(src=s, kind="original", bytes=ob))
        ks = []
        while len(ks) < CFG["VARIANTS_PER_SOURCE"]:        # xoay vòng để mọi loại biến thể có mặt đều nhau
            k = KINDS[ptr % len(KINDS)]; ptr += 1
            if k not in ks: ks.append(k)
        for k in ks:
            v, q = make_variant(im, k, r)
            P.append(dict(src=s, kind=k, bytes=ob if q is None else _jpeg(v, q)))
    return P

ORIGINALS = load_originals()
P = build_benchmark(ORIGINALS, rnd)
N = len(P)
SRC = np.array([p["src"] for p in P]); KIND = np.array([p["kind"] for p in P])
SHA = np.array([hashlib.sha256(p["bytes"]).hexdigest() for p in P])
SIZE = np.array([len(p["bytes"]) for p in P])
SAME = SRC[:, None] == SRC[None, :]
print(f"{len(ORIGINALS)} ảnh gốc -> {N} ảnh; {int(np.triu(SAME, 1).sum())} cặp cùng nguồn")
print(pd.Series(KIND).value_counts().to_string())

# %% [markdown]
# ## 3. Đặc trưng: PDQ-style 256 bit, MobileNetV3-Large 960D, ảnh xám cho ORB

# %%
_COS = np.array([[math.cos(math.pi * (2 * x + 1) * u / 128) for x in range(64)] for u in range(16)])

def pdq_bits(jpeg_bytes):
    """Bản port của lib/engines/pdq/pdq_engine.dart."""
    a = np.asarray(Image.open(io.BytesIO(jpeg_bytes)).convert("RGB").resize((64, 64), Image.BOX), dtype=np.float64)
    lum = 0.299 * a[..., 0] + 0.587 * a[..., 1] + 0.114 * a[..., 2]
    flat = (_COS @ (lum @ _COS.T)).reshape(256)
    s = np.sort(flat)
    return flat > (s[127] + s[128]) / 2

def fit(im, w, h, q=None):
    t = ImageOps.fit(im, (w, h), Image.BICUBIC)
    if q is None: return t
    b = io.BytesIO(); t.save(b, "JPEG", quality=q); return b.getvalue()

BITS = np.zeros((N, 256), dtype=bool)
T224, GRAY = [], []
for i, p in enumerate(P):
    im = Image.open(io.BytesIO(p["bytes"])).convert("RGB")
    BITS[i] = pdq_bits(fit(im, 128, 128, 70))                       # giống thumbnail app xin cho PDQ
    T224.append(Image.open(io.BytesIO(fit(im, 224, 224, 85))).convert("RGB"))
    GRAY.append(np.asarray(fit(im, 384, 384).convert("L")))
Bf = BITS.astype(np.float32)
HM = (256 - (Bf @ Bf.T + (1 - Bf) @ (1 - Bf).T)).round().astype(np.int16)   # ma trận Hamming N x N

def embed_all(imgs):
    if STUB:   # chỉ để kiểm thử đường ống ngoài Colab
        x = np.stack([np.asarray(im.resize((8, 8)), dtype=np.float32).reshape(-1) / 255 for im in imgs])
        return x / np.linalg.norm(x, axis=1, keepdims=True)
    import torch, torchvision
    w = torchvision.models.MobileNet_V3_Large_Weights.IMAGENET1K_V1
    m = torchvision.models.mobilenet_v3_large(weights=w).eval()
    net = torch.nn.Sequential(m.features, m.avgpool, torch.nn.Flatten())      # vector 960 chiều, bỏ classifier
    mean = torch.tensor([0.485, 0.456, 0.406]).view(1, 3, 1, 1); std = torch.tensor([0.229, 0.224, 0.225]).view(1, 3, 1, 1)
    out = []
    with torch.no_grad():
        for s in range(0, len(imgs), 32):
            x = torch.from_numpy(np.stack([np.asarray(im, dtype=np.float32) / 255 for im in imgs[s:s + 32]])).permute(0, 3, 1, 2)
            out.append(net((x - mean) / std).numpy())
    e = np.concatenate(out)
    return e / np.linalg.norm(e, axis=1, keepdims=True)

t0 = time.time(); E = embed_all(T224).astype(np.float32)
print(f"Embedding {E.shape} trong {time.time() - t0:.1f}s")

def center_cos(Es):
    """Trừ vector trung bình rồi L2-normalize (giống centerEmbeddings của app), trả ma trận cosine."""
    X = Es - Es.mean(0, keepdims=True)
    X = X / np.maximum(np.linalg.norm(X, axis=1, keepdims=True), 1e-12)
    return X @ X.T

# %% [markdown]
# ## 4. Thí nghiệm 1 — thất thoát ở khâu tìm ứng viên
# Đo: trong mọi cặp **thật sự cùng nguồn**, mỗi kênh tìm được bao nhiêu? (Recall ứng viên là trần của cả hệ thống.)

# %%
iu = np.triu_indices(N, 1)
TRUE = SAME[iu]; N_TRUE = int(TRUE.sum())
S_ALL = center_cos(E)

def lsh_matrix(bands, rbits, max_bucket=48):
    C = np.zeros((N, N), bool); w = (1 << np.arange(rbits)).astype(np.int64)
    for b in range(bands):
        keys = BITS[:, b * rbits:(b + 1) * rbits].astype(np.int64) @ w
        d = {}
        for i, k in enumerate(keys): d.setdefault(int(k), []).append(i)
        for bk in d.values():
            if 2 <= len(bk) <= max_bucket:
                for x in range(len(bk)):
                    for y in range(x + 1, len(bk)): C[bk[x], bk[y]] = True
    return C

def topk_edges(S, k, floor, mutual=True):
    S = S.copy(); np.fill_diagonal(S, -2); k = min(k, S.shape[0] - 1)
    nb = np.argpartition(-S, k - 1, axis=1)[:, :k]
    votes, cs = {}, {}
    for i in range(S.shape[0]):
        for j in nb[i]:
            c = S[i, j]
            if c < floor: continue
            key = (min(i, int(j)), max(i, int(j))); votes[key] = votes.get(key, 0) + 1; cs[key] = c
    return {key: cs[key] for key, v in votes.items() if v >= (2 if mutual else 1)}

def edges_to_mask(edges):
    M = np.zeros((N, N), bool)
    for (a, b) in edges: M[a, b] = True
    return M[iu]

rows = []
def add_row(name, mask):
    rows.append(dict(kênh=name, cặp_ứng_viên=int(mask.sum()), recall_cặp_cùng_nguồn=round(float((mask & TRUE).sum()) / N_TRUE, 3)))

H_iu = HM[iu]
add_row("PDQ, so mọi cặp, Hamming ≤ 32 (app khi thư viện nhỏ)", H_iu <= 32)
add_row("PDQ, so mọi cặp, Hamming ≤ 70", H_iu <= 70)
add_row("PDQ LSH 16x16 (app khi thư viện lớn) rồi lọc ≤ 32", lsh_matrix(16, 16)[iu] & (H_iu <= 32))
add_row("PDQ LSH 32x8 rồi lọc ≤ 32", lsh_matrix(32, 8)[iu] & (H_iu <= 32))
for k, mu in ((3, True), (10, False), (20, False)):
    add_row(f"MobileNet top-{k} ({'mutual' if mu else 'một đầu'}, cosine ≥ 0,30)", edges_to_mask(topk_edges(S_ALL, k, 0.30, mu)))
add_row("HỢP NHẤT: PDQ ≤ 70 + MobileNet top-10", (H_iu <= 70) | edges_to_mask(topk_edges(S_ALL, 10, 0.30, False)))
df1 = pd.DataFrame(rows); display(df1) if "display" in globals() else print(df1.to_string())

# %% [markdown]
# **Lý thuyết cho LSH:** xác suất một cặp có Hamming h trở thành ứng viên với `bands` băng, mỗi băng `r` bit là `1 - (1 - (1 - h/256)^r)^bands`.
# Cấu hình 16x16 (app) bỏ sót đáng kể ở Hamming ~32 dù thư viện lớn hay nhỏ, vì đây là tính chất của cách chia băng, không phải do số ảnh.

# %%
def p_cand(h, bands, r): return 1 - (1 - (1 - h / 256) ** r) ** bands
hs = [8, 16, 24, 32, 40, 48, 56, 70]
th = pd.DataFrame({f"{b}x{r}": [round(p_cand(h, b, r), 3) for h in hs] for b, r in ((16, 16), (21, 12), (32, 8))}, index=[f"h={h}" for h in hs])
print("Xác suất thành ứng viên theo Hamming:"); print(th.to_string())
print("Băng ngắn hơn (r nhỏ) bắt được nhiều hơn nhưng bucket đông hơn => tốn nhiều phép so hơn. Cần đo trên thư viện thật.")

# %% [markdown]
# ## 5. Hai mô hình
# Cả hai chạy trên **tập test** (chỉ số cục bộ 0..m-1). Mỗi mô hình trả về:
# `auto` = nhóm được phép tự chọn xóa (Trùng / Exact+Near), `review` = nhóm chỉ để xem (Tương tự), `uncertain` = cặp chưa chắc.

# %%
def show(df):
    try: display(df)
    except NameError: print(df.to_string())

def sim_pct(h): return 100.0 * (1 - h / 256)

def build_groups(edges, sizes):
    """Union-Find, rồi chỉ giữ ảnh có cạnh TRỰC TIẾP với ảnh đại diện (lớn nhất). Trả list [rep, ...]."""
    parent = {}
    def find(x):
        while parent.setdefault(x, x) != x:
            parent[x] = parent[parent[x]]; x = parent[x]
        return x
    for (i, j) in edges:
        ri, rj = find(i), find(j)
        if ri != rj: parent[rj] = ri
    comps = {}
    for x in list(parent): comps.setdefault(find(x), []).append(x)
    out = []
    for mem in comps.values():
        if len(mem) < 2: continue
        rep = max(mem, key=lambda q: (sizes[q], -q))
        kept = [q for q in mem if q != rep and (min(q, rep), max(q, rep)) in edges]
        if kept: out.append([rep] + kept)
    return out

# ---------- Mô hình A: như app hiện tại ----------
def run_A(ids):
    t0 = time.time(); m = len(ids); H = HM[np.ix_(ids, ids)]; sha = SHA[ids]; sizes = SIZE[ids]
    a_, b_ = np.triu_indices(m, 1); h = H[a_, b_]; sh = sha[a_] == sha[b_]
    sel = (h <= CFG["A_MAX_HAMMING"]) | sh
    dup_edges = {(int(a), int(b)): (100.0 if s else sim_pct(hh)) for a, b, hh, s in zip(a_[sel], b_[sel], h[sel], sh[sel])}
    auto = build_groups(dup_edges, sizes)
    in_dup = {x for g in auto for x in g}
    sim_edges = {}
    sel2 = (h > CFG["A_MAX_HAMMING"]) & (h <= CFG["A_SIMILAR_MAX"]) & ~sh
    for a, b, hh in zip(a_[sel2], b_[sel2], h[sel2]):
        if int(a) not in in_dup and int(b) not in in_dup: sim_edges[(int(a), int(b))] = sim_pct(hh)
    rest = np.array([i for i in range(m) if i not in in_dup])
    if len(rest) >= 32:                                   # app bỏ bước AI nếu dưới 32 vector
        Sr = center_cos(E[ids][rest])
        for (a, b), c in topk_edges(Sr, CFG["A_K"], CFG["A_FLOOR"], True).items():
            ga, gb = int(rest[a]), int(rest[b]); key = (min(ga, gb), max(ga, gb))
            sim_edges[key] = max(sim_edges.get(key, 0), 100 * float(c))
    return dict(auto=auto, review=build_groups(sim_edges, sizes), uncertain=set(), seconds=time.time() - t0, stats={})

# ---------- Mô hình B: ORB ----------
import cv2
ORB = cv2.ORB_create(nfeatures=800); BFM = cv2.BFMatcher(cv2.NORM_HAMMING)
_KP, _ORB = {}, {}
def _feat(g):
    if g not in _KP:
        kps, des = ORB.detectAndCompute(GRAY[g], None)
        _KP[g] = (np.float32([k.pt for k in kps]) if kps else np.zeros((0, 2), np.float32), des)
    return _KP[g]

def orb_inliers(g1, g2):
    key = (min(g1, g2), max(g1, g2))
    if key in _ORB: return _ORB[key]
    p1, d1 = _feat(key[0]); p2, d2 = _feat(key[1]); inl = 0
    if d1 is not None and d2 is not None and len(d1) >= 8 and len(d2) >= 8:
        good = [m[0] for m in BFM.knnMatch(d1, d2, k=2) if len(m) == 2 and m[0].distance < 0.75 * m[1].distance]
        if len(good) >= 8:
            a = np.float32([p1[m.queryIdx] for m in good]).reshape(-1, 1, 2)
            b = np.float32([p2[m.trainIdx] for m in good]).reshape(-1, 1, 2)
            _, mask = cv2.findHomography(a, b, cv2.RANSAC, 5.0)
            inl = int(mask.sum()) if mask is not None else 0
    _ORB[key] = inl
    return inl

# ---------- Mô hình B: calibrate ngưỡng trên tập TRAIN ----------
def wilson_lb(tp, n, z=1.645):
    if n <= 0: return 0.0
    p = tp / n; den = 1 + z * z / n; c = p + z * z / (2 * n)
    s = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n))
    return max(0.0, (c - s) / den)

def calibrate(train_ids):
    """Chọn (H1, C1) LỎNG nhất sao cho cận dưới precision >= mục tiêu; rồi ngưỡng ORB cho cặp Hamming > H1."""
    m = len(train_ids); H = HM[np.ix_(train_ids, train_ids)]; S = center_cos(E[train_ids]); Y = SAME[np.ix_(train_ids, train_ids)]
    a_, b_ = np.triu_indices(m, 1); h = H[a_, b_]; c = S[a_, b_]; y = Y[a_, b_]
    ex = SHA[train_ids][a_] == SHA[train_ids][b_]
    tgt = CFG["TARGET_PRECISION"]; best = None
    for H1 in range(8, 65, 4):
        for C1 in np.round(np.linspace(-0.3, 0.9, 25), 3):
            pred = (h <= H1) & (c >= C1) & ~ex; n = int(pred.sum())
            if n < 20: continue
            tp = int((pred & y).sum()); lb = wilson_lb(tp, n)
            if lb >= tgt and (best is None or tp > best["tp"]): best = dict(H1=H1, C1=float(C1), tp=tp, n=n, lb=lb)
    if best is None:
        print("CẢNH BÁO: không có quy tắc đạt mục tiêu precision trên tập train; dùng quy tắc chặt mặc định.")
        best = dict(H1=16, C1=0.5, tp=0, n=0, lb=0.0)
    rule = dict(H1=best["H1"], C1=best["C1"], T_orb=None)
    if CFG["B_USE_ORB"]:
        cand = np.nonzero((h > rule["H1"]) & (c >= CFG["ORB_MIN_COS"]) & ~ex)[0]
        cand = cand[np.argsort(-c[cand])][:min(CFG["ORB_BUDGET"], 2000)]
        inl = np.array([orb_inliers(int(train_ids[a_[q]]), int(train_ids[b_[q]])) for q in cand]); yy = y[cand]
        for T in range(10, 121, 5):
            pred = inl >= T; n = int(pred.sum())
            if n >= 10 and wilson_lb(int((pred & yy).sum()), n) >= tgt: rule["T_orb"] = T; break
    print("Quy tắc đã calibrate:", rule, "| precision cận dưới (train):", round(best["lb"], 3), "| số cặp:", best["n"])
    return rule

# ---------- Mô hình B: hợp nhất ứng viên + xác minh nhiều tầng + gom ràng buộc ----------
def run_B(ids, rule, constrained=True):
    t0 = time.time(); m = len(ids); H = HM[np.ix_(ids, ids)]; S = center_cos(E[ids]); sha = SHA[ids]; sizes = SIZE[ids]
    budget = [CFG["ORB_BUDGET"]]; stats = dict(orb_calls=0)
    def orb(i, j):
        if not (CFG["B_USE_ORB"] and rule["T_orb"] is not None): return -1
        key = (min(int(ids[i]), int(ids[j])), max(int(ids[i]), int(ids[j])))
        if key not in _ORB:
            if budget[0] <= 0: return -1
            budget[0] -= 1; stats["orb_calls"] += 1
        return orb_inliers(*key)
    def tier(i, j):
        if sha[i] == sha[j]: return "exact"
        h, c = H[i, j], S[i, j]
        if h <= rule["H1"]: return "near" if c >= rule["C1"] else "uncertain"      # PDQ gần nhưng embedding không phù hợp
        if c >= CFG["ORB_MIN_COS"] and rule["T_orb"] is not None and orb(i, j) >= rule["T_orb"]: return "near"
        if h <= CFG["A_SIMILAR_MAX"] or c >= CFG["B_SIM_COS"]: return "similar"
        return "reject"
    # 1) hợp nhất ứng viên từ hai kênh
    a_, b_ = np.triu_indices(m, 1); h = H[a_, b_]; sh = sha[a_] == sha[b_]
    k1 = (h <= CFG["A_SIMILAR_MAX"]) | sh
    cand = {(int(a), int(b)) for a, b in zip(a_[k1], b_[k1])} | set(topk_edges(S, CFG["B_K"], CFG["B_CAND_FLOOR"], False))
    # 2) xác minh nhiều tầng (cặp cosine cao được ưu tiên ngân sách ORB)
    tiers = {}
    for p in sorted(cand, key=lambda p: -S[p]): tiers[p] = tier(*p)
    def t(i, j):
        key = (min(i, j), max(i, j))
        if key not in tiers: tiers[key] = tier(*key)
        return tiers[key]
    NEAR = ("exact", "near")
    def conf(p): return (3 if tiers[p] == "exact" else 0) + (1 - H[p] / 256) + S[p]
    uncertain = {p for p, tt in tiers.items() if tt == "uncertain"}
    near_pairs = sorted((p for p, tt in tiers.items() if tt in NEAR), key=conf, reverse=True)
    # 3) gom nhóm
    if not constrained:
        auto = build_groups({p: 1.0 for p in near_pairs}, sizes)
    else:
        gid, groups, nxt = {}, {}, [0]
        def rep_of(mem): return max(mem, key=lambda q: (sizes[q], -q))
        def pick(x, mem, k=8):
            if len(mem) <= k: return list(mem)
            r = rep_of(mem)
            return [r] + sorted((q for q in mem if q != r), key=lambda q: S[x, q])[:k - 1]
        def ok(res): return not any(z == "reject" for z in res) and np.mean([z in NEAR for z in res]) >= CFG["B_MIN_FRAC"]
        def can_join(x, g):
            mem = groups[g]
            if t(x, rep_of(mem)) not in NEAR: return False
            return ok([t(x, q) for q in pick(x, mem)])
        def can_merge(g1, g2):
            r1, r2 = rep_of(groups[g1]), rep_of(groups[g2])
            if t(r1, r2) not in NEAR: return False
            return ok([t(x, y) for x in pick(r2, groups[g1], 4) for y in pick(r1, groups[g2], 4)])
        for (i, j) in near_pairs:
            gi, gj = gid.get(i), gid.get(j)
            if gi is None and gj is None:
                groups[nxt[0]] = [i, j]; gid[i] = gid[j] = nxt[0]; nxt[0] += 1
            elif gi is None or gj is None:
                x, g = (i, gj) if gi is None else (j, gi)
                if can_join(x, g): groups[g].append(x); gid[x] = g
                else: uncertain.add((i, j))
            elif gi != gj:
                if can_merge(gi, gj):
                    for q in groups[gj]: gid[q] = gi
                    groups[gi] += groups.pop(gj)
                else: uncertain.add((i, j))
        auto = [[rep_of(mem)] + [q for q in mem if q != rep_of(mem)] for mem in groups.values()]
    in_auto = {q for g in auto for q in g}
    sim_edges = {p: 100 * float(S[p]) for p, tt in tiers.items() if tt == "similar" and p[0] not in in_auto and p[1] not in in_auto}
    stats["tiers"] = pd.Series(list(tiers.values())).value_counts().to_dict()
    return dict(auto=auto, review=build_groups(sim_edges, sizes), uncertain=uncertain, seconds=time.time() - t0, stats=stats)

# %% [markdown]
# ## 6. Chạy: calibrate B trên train, đo A và B trên test

# %%
srcs = np.unique(SRC); np.random.RandomState(CFG["SEED"]).shuffle(srcs)
TRAIN_S = set(srcs[:len(srcs) // 2].tolist())
TRAIN_IDS = np.array([i for i in range(N) if int(SRC[i]) in TRAIN_S]); TEST_IDS = np.array([i for i in range(N) if int(SRC[i]) not in TRAIN_S])
print(f"train {len(TRAIN_IDS)} ảnh | test {len(TEST_IDS)} ảnh")
RULE = calibrate(TRAIN_IDS)
RES = {
    "A (hiện tại)": run_A(TEST_IDS),
    "B0 (B, gom như A)": run_B(TEST_IDS, RULE, constrained=False),
    "B (đầy đủ)": run_B(TEST_IDS, RULE, constrained=True),
}
for k, v in RES.items(): print(k, "-", round(v["seconds"], 2), "s", v["stats"])

# %% [markdown]
# ## 7. Kết quả
# - **Pair precision / recall (auto):** chỉ tính nhóm được phép tự chọn xóa. Precision phải ≥ 96% theo mục tiêu sai ≤ 4%.
# - **B³ P/R/F1:** chất lượng phân nhóm tổng thể, nhạy với nhóm bị gom nhầm hoặc tách vụn.
# - **Review recall:** cặp cùng nguồn được tìm thấy ở bất kỳ tầng nào (auto + Tương tự + Uncertain) — đo mức thất thoát.
# - **Nhóm đường kính > 32:** nhóm có 2 thành viên cách nhau xa hơn ngưỡng trùng — dấu hiệu nối chuỗi.

# %%
def pairs_of(groups):
    s = set()
    for g in groups:
        for a, b in itertools.combinations(sorted(g), 2): s.add((a, b))
    return s

def evaluate(name, res, ids):
    m = len(ids); lab = SRC[ids]; Hs = HM[np.ix_(ids, ids)]
    truth = {(int(a), int(b)) for a, b in np.argwhere(np.triu(SAME[np.ix_(ids, ids)], 1))}
    pred = pairs_of(res["auto"]); tp = len(pred & truth)
    rev = pred | pairs_of(res["review"]) | {(min(p), max(p)) for p in res["uncertain"]}
    cl = -np.ones(m, int)
    for gi, g in enumerate(res["auto"]): cl[list(g)] = gi
    nxt = len(res["auto"])
    for i in range(m):
        if cl[i] < 0: cl[i] = nxt; nxt += 1
    bp, br = [], []
    for i in range(m):
        mem = np.nonzero(cl == cl[i])[0]; same = int((lab[mem] == lab[i]).sum())
        bp.append(same / len(mem)); br.append(same / int((lab == lab[i]).sum()))
    P_, R_ = float(np.mean(bp)), float(np.mean(br))
    diam = [max(Hs[a, b] for a, b in itertools.combinations(g, 2)) for g in res["auto"]]
    m_ = dict(mô_hình=name,
              pair_precision=round(tp / len(pred), 3) if pred else float("nan"),
              pair_recall=round(tp / len(truth), 3),
              B3_P=round(P_, 3), B3_R=round(R_, 3), B3_F1=round(2 * P_ * R_ / (P_ + R_), 3),
              review_recall=round(len(rev & truth) / len(truth), 3),
              nhóm_auto=len(res["auto"]),
              nhóm_lẫn_nguồn=sum(len(set(lab[g].tolist())) > 1 for g in res["auto"]),
              nhóm_đường_kính_gt32=sum(d > 32 for d in diam),
              cặp_gom_sai=len(pred - truth), giây=round(res["seconds"], 2))
    orig = {int(lab[i]): i for i in range(m) if KIND[ids[i]] == "original"}
    kd = {}
    for i in range(m):
        k = KIND[ids[i]]
        if k == "original": continue
        o = orig[int(lab[i])]; key = (min(i, o), max(i, o))
        kd.setdefault(k, []).append((key in pred, key in rev))
    kind = pd.DataFrame({f"{name} | auto": {k: np.mean([a for a, _ in v]) for k, v in kd.items()},
                         f"{name} | thấy được": {k: np.mean([b for _, b in v]) for k, v in kd.items()}}).round(2)
    return m_, kind, sorted(pred - truth)

EV = {n: evaluate(n, r, TEST_IDS) for n, r in RES.items()}
summary = pd.DataFrame([v[0] for v in EV.values()]).set_index("mô_hình")
show(summary)

# %% [markdown]
# ### Recall theo loại biến thể (tỉ lệ ảnh biến thể được ghép đúng với ảnh gốc)
# `auto` = nằm cùng nhóm tự xóa với ảnh gốc; `thấy được` = có xuất hiện ở bất kỳ tầng nào (kể cả để xem).

# %%
kind_df = pd.concat([v[1] for v in EV.values()], axis=1)
show(kind_df)
auto_cols = [c for c in kind_df.columns if c.endswith("| auto")]
ax = kind_df[auto_cols].plot.bar(figsize=(11, 4), ylim=(0, 1.05), title="Recall tự động theo loại biến thể")
ax.set_ylabel("tỉ lệ ghép đúng"); plt.xticks(rotation=30, ha="right"); plt.tight_layout(); plt.show()

# %% [markdown]
# ### Xem các cặp gom sai (kiểm tra bằng mắt)
# Nếu bạn dùng ảnh thật mà thư mục gốc đã có sẵn ảnh gần giống nhau, chúng sẽ bị tính là "gom sai" ở đây — hãy nhìn trước khi kết luận.

# %%
def show_wrong(name, k=6):
    wrong = EV[name][2][:k]
    if not wrong: print(name, ": không có cặp gom sai."); return
    fig, axs = plt.subplots(len(wrong), 2, figsize=(5, 2.2 * len(wrong)))
    axs = np.atleast_2d(axs)
    for r, (a, b) in enumerate(wrong):
        for c, q in enumerate((a, b)):
            axs[r, c].imshow(T224[int(TEST_IDS[q])]); axs[r, c].axis("off")
            axs[r, c].set_title(f"nguồn {SRC[TEST_IDS[q]]} | {KIND[TEST_IDS[q]]}", fontsize=8)
    fig.suptitle(f"{name}: cặp gom sai"); plt.tight_layout(); plt.show()
for n in ("A (hiện tại)", "B (đầy đủ)"): show_wrong(n)

# %% [markdown]
# ## 8. Cách đọc kết quả
# 1. So **pair_precision** trước. Mục tiêu của bạn là sai ≤ 4%, tức precision ≥ 0,96. Mô hình nào không đạt thì recall của nó không có ý nghĩa.
# 2. Nếu B **review_recall** cao hơn A nhưng **pair_recall (auto)** thấp hơn: B đang đẩy ca khó sang "Uncertain/Tương tự" — đúng chủ ý, nhưng cần quyết định giao diện cho tầng đó.
# 3. So **B0** với **B**: chênh lệch giữa hai dòng này là tác dụng riêng của "gom ràng buộc". So **A** với **B0**: là tác dụng của hợp nhất ứng viên + calibrate ngưỡng.
# 4. Cột `nhóm_đường_kính_gt32` và `nhóm_lẫn_nguồn` đo lỗi nối chuỗi. Giá trị càng gần 0 càng tốt.
# 5. Ảnh biến thể ở đây do máy sinh, dễ hơn ảnh thật (chụp liên tiếp, gửi qua ứng dụng nhắn tin, chỉnh sửa tay). Hãy chạy lại với `SOURCE = "upload"` bằng ảnh của bạn, và đừng chốt ngưỡng sản xuất khi chưa có nhãn thật (`tool/label_pairs.py`).
# 6. Mô hình đang dùng MobileNetV3 ImageNet chưa fine-tune. Nếu embedding là mắt xích yếu (cột `thấy được` thấp ở crop/rotate), đó là lúc cân nhắc fine-tune hoặc thử model khác.
