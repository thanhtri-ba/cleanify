#!/usr/bin/env python3
"""Ghép experiment_src.py (các ô đánh dấu '# %%') thành cleanify_experiment.ipynb."""
import json
from pathlib import Path

here = Path(__file__).resolve().parent
lines = (here / "experiment_src.py").read_text(encoding="utf-8").splitlines()
cells, cur, kind = [], [], None

def flush():
    global cur
    while cur and not cur[-1].strip():
        cur.pop()
    if kind and cur:
        if kind == "markdown":
            src = [l[2:] if l.startswith("# ") else l.lstrip("#") for l in cur]
            cells.append({"cell_type": "markdown", "metadata": {}, "source": "\n".join(src)})
        else:
            cells.append({"cell_type": "code", "metadata": {}, "execution_count": None, "outputs": [], "source": "\n".join(cur)})
    cur = []

for l in lines:
    if l.startswith("# %%"):
        flush()
        kind = "markdown" if "[markdown]" in l else "code"
    else:
        cur.append(l)
flush()
for c in cells:
    c["source"] = c["source"].splitlines(keepends=True)
nb = {"cells": cells, "metadata": {"colab": {"provenance": []}, "kernelspec": {"display_name": "Python 3", "name": "python3"},
      "language_info": {"name": "python"}}, "nbformat": 4, "nbformat_minor": 5}
(here / "cleanify_experiment.ipynb").write_text(json.dumps(nb, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"{len(cells)} ô -> cleanify_experiment.ipynb")
