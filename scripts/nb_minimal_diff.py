#!/usr/bin/env python3
"""Minimise .ipynb diffs after a jupytext round trip.

usage: nb_minimal_diff.py ORIGINAL.ipynb WRITTEN.ipynb

Cells in WRITTEN whose type and source match a cell in ORIGINAL are replaced by
the original cell object (keeps formatting, ids, outputs, metadata). Changed or
new cells are kept as jupytext wrote them, minus noisy jupytext-only metadata.
Notebook-level metadata is taken from ORIGINAL. The file is written back in
ORIGINAL's JSON style (indent, trailing newline).
"""
import json
import sys

NOISE = ("lines_to_next_cell", "lines_to_end_of_cell_marker")


def norm(cell):
    src = cell.get("source", "")
    if isinstance(src, list):
        src = "".join(src)
    return cell.get("cell_type"), src.rstrip("\n")


def detect_indent(text):
    for line in text.splitlines()[1:3]:
        n = len(line) - len(line.lstrip(" "))
        if n:
            return n
    return 1


def main(orig_path, new_path):
    orig_text = open(orig_path, encoding="utf-8").read()
    orig = json.loads(orig_text)
    new = json.load(open(new_path, encoding="utf-8"))

    pool = {}
    for c in orig.get("cells", []):
        pool.setdefault(norm(c), []).append(c)

    # Some tools end every cell source with "\n"; copy that convention.
    def ends_nl(c):
        src = c.get("source")
        return isinstance(src, list) and bool(src) and src[-1].endswith("\n")

    code = [c for c in orig.get("cells", []) if c.get("source")]
    trailing_nl = bool(code) and sum(map(ends_nl, code)) * 2 > len(code)

    merged = []
    for c in new.get("cells", []):
        key = norm(c)
        if pool.get(key):
            merged.append(pool[key].pop(0))
        else:
            for n in NOISE:
                c.get("metadata", {}).pop(n, None)
            src = c.get("source")
            if trailing_nl and isinstance(src, list) and src and not src[-1].endswith("\n"):
                src[-1] += "\n"
            merged.append(c)

    out = dict(new)
    out["cells"] = merged
    for k in ("metadata", "nbformat", "nbformat_minor"):
        if k in orig:
            out[k] = orig[k]

    text = json.dumps(out, indent=detect_indent(orig_text), ensure_ascii=False)
    if orig_text.endswith("\n"):
        text += "\n"
    with open(new_path, "w", encoding="utf-8") as f:
        f.write(text)


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
