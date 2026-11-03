#!/usr/bin/env python3
"""Công cụ gán nhãn cặp ảnh, chạy cục bộ (chỉ 127.0.0.1, không gửi ảnh ra ngoài).

Đọc <out>/candidates.csv (từ build_eval_pairs.py), ghi tiến độ vào <out>/manifest.csv
sau MỖI lần gán nhãn nên thoát giữa chừng vẫn tiếp tục được.

5 nhãn (phím tắt):
  1 dup             cùng MỘT ảnh (bản sao, nén lại, đổi kích thước, chỉnh sáng nhẹ)
  2 similar         cùng cảnh/vật thể nhưng khác khoảnh khắc hoặc góc, KHÔNG phải cùng người
  3 similar_person  cùng cảnh VÀ có cùng một người
  4 person_only     có cùng một người nhưng khác cảnh
  5 different       không liên quan
  0 bỏ qua (skip)   không chắc; sẽ không dùng khi calibrate
  z hoàn tác lần gán gần nhất

Cặp tự sinh (label_source=auto) không hiện ra. Loại cặp (kind) và cảnh được ẩn
có chủ đích để không ảnh hưởng đến cách bạn gán nhãn.

Ví dụ: python3 tool/label_pairs.py --src eval_real --out eval_out
"""
import argparse
import csv
import io
import json
import os
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

from PIL import Image, ImageOps

try:
    from pillow_heif import register_heif_opener

    register_heif_opener()
except Exception:
    pass

LABELS = ["dup", "similar", "similar_person", "person_only", "different"]
ALLOWED = set(LABELS) | {"skip"}

PAGE = """<!doctype html><html lang="vi"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Gán nhãn cặp ảnh</title>
<style>
:root{--bg:#fff;--fg:#1c1c1e;--mut:#6b6b70;--bd:#d9d9de;--ac:#0f766e}
@media (prefers-color-scheme:dark){:root{--bg:#161618;--fg:#f2f2f4;--mut:#9a9aa2;--bd:#34343a;--ac:#2dd4bf}}
body{margin:0;background:var(--bg);color:var(--fg);font:15px/1.45 system-ui,sans-serif}
main{max-width:1200px;margin:0 auto;padding:16px}
.top{display:flex;justify-content:space-between;gap:12px;color:var(--mut);font-size:13px}
.pair{display:grid;grid-template-columns:1fr 1fr;gap:12px;margin:12px 0}
@media (max-width:700px){.pair{grid-template-columns:1fr}}
figure{margin:0;border:1px solid var(--bd);border-radius:8px;padding:8px;text-align:center}
img{max-width:100%;max-height:62vh;object-fit:contain}
figcaption{color:var(--mut);font-size:12px;word-break:break-all}
.btns{display:flex;flex-wrap:wrap;gap:8px}
button{flex:1 1 150px;padding:10px;border:1px solid var(--bd);background:transparent;color:var(--fg);
border-radius:8px;font:inherit;cursor:pointer}
button:hover{border-color:var(--ac)}
kbd{font:12px ui-monospace,monospace;border:1px solid var(--bd);border-radius:4px;padding:0 5px;margin-right:4px}
small{display:block;color:var(--mut);font-size:12px}
#msg{margin:24px 0;font-size:18px}
</style></head><body><main>
<div class="top"><span id="prog">Đang tải…</span><span>Phím: 1–5 gán nhãn · 0 bỏ qua · z hoàn tác</span></div>
<div id="msg" hidden></div>
<div class="pair" id="pair"><figure><img id="ia" alt="Ảnh A"><figcaption id="na"></figcaption></figure>
<figure><img id="ib" alt="Ảnh B"><figcaption id="nb"></figcaption></figure></div>
<div class="btns" id="btns">
<button data-k="dup"><kbd>1</kbd>dup<small>cùng một ảnh</small></button>
<button data-k="similar"><kbd>2</kbd>similar<small>cùng cảnh/vật, không cùng người</small></button>
<button data-k="similar_person"><kbd>3</kbd>similar + người<small>cùng cảnh, cùng một người</small></button>
<button data-k="person_only"><kbd>4</kbd>cùng người<small>khác cảnh</small></button>
<button data-k="different"><kbd>5</kbd>khác<small>không liên quan</small></button>
<button data-k="skip"><kbd>0</kbd>bỏ qua<small>không chắc</small></button>
<button id="undo"><kbd>z</kbd>hoàn tác</button></div>
<script>
const KEYS={'1':'dup','2':'similar','3':'similar_person','4':'person_only','5':'different','0':'skip'};
let cur=null,busy=false;
const $=id=>document.getElementById(id);
function show(d){
  cur=d.finished?null:d;
  $('pair').hidden=$('btns').hidden=!!d.finished;
  $('msg').hidden=!d.finished;
  if(d.finished){$('msg').textContent='Đã gán nhãn hết các cặp. Có thể đóng trang này.';}
  else{
    const t=Date.now();
    $('ia').src='/img/'+d.pair_id+'/a?t='+t;$('ib').src='/img/'+d.pair_id+'/b?t='+t;
    $('na').textContent=d.name_a;$('nb').textContent=d.name_b;
  }
  $('prog').textContent='Đã gán '+d.done+'/'+d.total+' · còn '+d.remaining;
}
async function post(path,body){
  const r=await fetch(path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body||{})});
  return r.json();
}
async function next(){show(await (await fetch('/api/next')).json());}
async function send(label){
  if(!cur||busy)return;busy=true;
  try{await post('/api/label',{pair_id:cur.pair_id,label});await next();}finally{busy=false;}
}
async function undo(){if(busy)return;busy=true;try{show(await post('/api/undo'));}finally{busy=false;}}
document.querySelectorAll('button[data-k]').forEach(b=>b.onclick=()=>send(b.dataset.k));
$('undo').onclick=undo;
addEventListener('keydown',e=>{if(e.ctrlKey||e.metaKey||e.altKey)return;
  if(KEYS[e.key])send(KEYS[e.key]);else if(e.key==='z')undo();});
next();
</script></main></body></html>"""


class Store:
    def __init__(self, src: Path, out: Path):
        self.src, self.out = src.resolve(), out.resolve()
        self.lock = threading.Lock()
        self.history = []
        self.manifest = self.out / "manifest.csv"
        path = self.manifest if self.manifest.exists() else self.out / "candidates.csv"
        with open(path, newline="", encoding="utf-8") as fh:
            self.rows = list(csv.DictReader(fh))
        if not self.rows:
            raise SystemExit("Không có cặp nào để gán nhãn.")
        self.fields = list(self.rows[0].keys())
        self.by_id = {r["pair_id"]: r for r in self.rows}

    def manual(self):
        return [r for r in self.rows if r["label_source"] != "auto"]

    def resolve(self, asset: str) -> Path:
        root, rel = (self.src, asset[4:]) if asset.startswith("src:") else (self.out, asset[4:])
        p = (root / rel).resolve()
        p.relative_to(root)  # ném lỗi nếu thoát khỏi thư mục gốc
        return p

    def save(self):
        tmp = self.manifest.with_suffix(".csv.tmp")
        with open(tmp, "w", newline="", encoding="utf-8") as fh:
            w = csv.DictWriter(fh, fieldnames=self.fields)
            w.writeheader()
            w.writerows(self.rows)
        os.replace(tmp, self.manifest)

    def view(self, row=None):
        man = self.manual()
        done = sum(1 for r in man if r["label"] != "")
        base = {"done": done, "total": len(man), "remaining": len(man) - done}
        if row is None:
            row = next((r for r in man if r["label"] == ""), None)
        if row is None:
            return {**base, "finished": True}
        return {**base, "pair_id": row["pair_id"],
                "name_a": row["asset_a"].split(":", 1)[1], "name_b": row["asset_b"].split(":", 1)[1]}

    def set_label(self, pair_id, label):
        with self.lock:
            row = self.by_id.get(pair_id)
            if row is None or row["label_source"] == "auto" or label not in ALLOWED:
                return False
            row["label"], row["label_source"] = label, "manual"
            self.history.append(pair_id)
            self.save()
            return True

    def undo(self):
        with self.lock:
            if not self.history:
                return self.view()
            row = self.by_id[self.history.pop()]
            row["label"], row["label_source"] = "", ""
            self.save()
            return self.view(row)


def jpeg_bytes(path: Path) -> bytes:
    with Image.open(path) as im:
        im = ImageOps.exif_transpose(im).convert("RGB")
        im.thumbnail((1100, 1100))
        buf = io.BytesIO()
        im.save(buf, "JPEG", quality=85)
        return buf.getvalue()


def make_handler(store: Store, port: int):
    class H(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def _host_ok(self):
            return self.headers.get("Host", "").split(":")[0] in ("127.0.0.1", "localhost")

        def _send(self, code, body, ctype):
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _json(self, obj, code=200):
            self._send(code, json.dumps(obj).encode(), "application/json")

        def do_GET(self):
            if not self._host_ok():
                return self._send(403, b"forbidden", "text/plain")
            path = self.path.split("?")[0]
            if path == "/":
                return self._send(200, PAGE.encode("utf-8"), "text/html; charset=utf-8")
            if path == "/api/next":
                return self._json(store.view())
            parts = path.strip("/").split("/")
            if len(parts) == 3 and parts[0] == "img" and parts[2] in ("a", "b"):
                row = store.by_id.get(parts[1])
                if row is None:
                    return self._send(404, b"not found", "text/plain")
                try:
                    data = jpeg_bytes(store.resolve(row["asset_" + parts[2]]))
                except Exception:
                    return self._send(404, b"not found", "text/plain")
                return self._send(200, data, "image/jpeg")
            self._send(404, b"not found", "text/plain")

        def do_POST(self):
            if not self._host_ok() or "application/json" not in self.headers.get("Content-Type", ""):
                return self._send(403, b"forbidden", "text/plain")
            n = int(self.headers.get("Content-Length") or 0)
            try:
                body = json.loads(self.rfile.read(n) or b"{}")
            except ValueError:
                return self._json({"error": "bad json"}, 400)
            if self.path == "/api/label":
                ok = store.set_label(str(body.get("pair_id")), str(body.get("label")))
                return self._json({"ok": ok}, 200 if ok else 400)
            if self.path == "/api/undo":
                return self._json(store.undo())
            self._send(404, b"not found", "text/plain")

    return H


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--src", type=Path, required=True, help="thư mục ảnh thật (eval_real)")
    ap.add_argument("--out", type=Path, required=True, help="thư mục có candidates.csv (eval_out)")
    ap.add_argument("--port", type=int, default=8765)
    a = ap.parse_args()
    if not (a.out / "candidates.csv").exists():
        print(f"Không thấy {a.out}/candidates.csv. Chạy build_eval_pairs.py trước.", file=sys.stderr)
        return 1
    store = Store(a.src, a.out)
    man = store.manual()
    print(f"{len(man)} cặp cần gán nhãn, đã xong {sum(1 for r in man if r['label'])}.")
    srv = ThreadingHTTPServer(("127.0.0.1", a.port), make_handler(store, a.port))
    print(f"Mở trình duyệt: http://127.0.0.1:{a.port}   (Ctrl+C để dừng)")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
