#!/usr/bin/env python3
"""Export OSNet (person Re-ID) sang ONNX cho Cleanify. Chạy trên máy của bạn.

Cần TRỌNG SỐ ĐÃ HUẤN LUYỆN RE-ID (file .pth). Trọng số ImageNet thì KHÔNG dùng
được: nó không biết "cùng một người". Bạn tự tải một file .pth (ví dụ
osnet_x0_25 hoặc osnet_x1_0 huấn luyện trên Market-1501/MSMT17) từ model zoo của
torchreid hoặc từ một trang như https://huggingface.co/LibreYOLO/LibreReID-osnet
(xem danh sách file trên trang), rồi đọc giấy phép của đúng file đó trước khi dùng.

Cài đặt (một lần):
    python3 -m venv .venv && source .venv/bin/activate
    pip install torch torchvision onnx onnxruntime numpy torchreid

Chạy:
    python3 tool/export_osnet_onnx.py --weights osnet_x0_25_market.pth \\
        --arch osnet_x0_25 --out assets/models/osnet.onnx

Script xuất ONNX (batch động, đầu vào 1x3x256x128), rồi tự kiểm tra: so kết quả
PyTorch với ONNX Runtime và in số chiều embedding. HÃY GỬI LẠI các dòng in ra.

Tiền xử lý trong app phải khớp: resize 128 (rộng) x 256 (cao), RGB, chia 255,
trừ mean [0.485, 0.456, 0.406], chia std [0.229, 0.224, 0.225], rồi L2-normalize
đầu ra.
"""
import argparse
import sys
from pathlib import Path


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--weights", required=True, type=Path, help="file .pth đã huấn luyện Re-ID")
    ap.add_argument("--arch", default="osnet_x0_25",
                    help="osnet_x1_0, osnet_ain_x1_0, osnet_ain_x0_5... (phải khớp tên file trọng số)")
    ap.add_argument("--out", type=Path, default=Path("assets/models/osnet.onnx"))
    ap.add_argument("--opset", type=int, default=17)
    a = ap.parse_args()

    if not a.weights.is_file():
        print(f"Không thấy file trọng số: {a.weights}", file=sys.stderr)
        return 1
    try:
        import numpy as np
        import onnx
        import onnxruntime as ort
        import torch
        try:
            from torchreid.models import build_model
            from torchreid.utils import load_pretrained_weights
        except ImportError:  # bản PyPI 0.2.5 đặt mã trong torchreid.reid.*
            from torchreid.reid.models import build_model
            from torchreid.reid.utils import load_pretrained_weights
    except ImportError as e:
        print(f"Thiếu thư viện: {e}\nXem phần 'Cài đặt' ở đầu file.", file=sys.stderr)
        return 1

    # num_classes chỉ ảnh hưởng lớp phân loại; load_pretrained_weights bỏ qua
    # các khóa không khớp kích thước, và ta chỉ lấy đặc trưng trước lớp đó.
    model = build_model(a.arch, num_classes=1, pretrained=False)
    load_pretrained_weights(model, str(a.weights))
    model.eval()

    dummy = torch.randn(1, 3, 256, 128)
    with torch.no_grad():
        ref = model(dummy)  # ở chế độ eval, torchreid trả về vector đặc trưng
    if isinstance(ref, (tuple, list)):
        ref = ref[0]
    print(f"PyTorch: đầu ra shape {tuple(ref.shape)}")

    a.out.parent.mkdir(parents=True, exist_ok=True)
    torch.onnx.export(
        model, dummy, str(a.out),
        input_names=["input"], output_names=["embedding"],
        dynamic_axes={"input": {0: "batch"}, "embedding": {0: "batch"}},
        opset_version=a.opset, do_constant_folding=True,
    )
    onnx.checker.check_model(onnx.load(str(a.out)))

    sess = ort.InferenceSession(str(a.out), providers=["CPUExecutionProvider"])
    got = sess.run(None, {"input": dummy.numpy()})[0]
    diff = float(np.abs(got - ref.numpy()).max())
    batch = sess.run(None, {"input": np.concatenate([dummy.numpy()] * 3)})[0]
    print(f"ONNX   : đầu ra shape {got.shape}, batch=3 -> {batch.shape}")
    print(f"Sai lệch tối đa so với PyTorch: {diff:.2e}  (kỳ vọng < 1e-3)")
    print(f"Số chiều embedding: {got.shape[1]}")
    print(f"Kích thước file: {a.out.stat().st_size / 1e6:.1f} MB -> {a.out}")
    if diff > 1e-3:
        print("CẢNH BÁO: sai lệch lớn, đừng dùng file này.", file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
