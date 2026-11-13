#!/usr/bin/env python3
"""Minimise .ipynb diffs after a jupytext round trip.

usage: nb_minimal_diff.py ORIGINAL.ipynb WRITTEN.ipynb
       nb_minimal_diff.py --clear-outputs NOTEBOOK.ipynb
       nb_minimal_diff.py --normalize-outputs NOTEBOOK.ipynb

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


def keep_eol(out, orig_text):
    """Write with the line endings of the original file (no platform translation)."""
    return out.replace("\n", "\r\n") if "\r\n" in orig_text else out


def detect_indent(text):
    for line in text.splitlines()[1:3]:
        n = len(line) - len(line.lstrip(" "))
        if n:
            return n
    return 1


def main(orig_path, new_path):
    orig_text = open(orig_path, encoding="utf-8", newline="").read()
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
    with open(new_path, "w", encoding="utf-8", newline="") as f:
        f.write(keep_eol(text, orig_text))


def clear_outputs(path):
    """Remove every output and execution count, keeping the file's JSON style."""
    text = open(path, encoding="utf-8", newline="").read()
    nb = json.loads(text)
    for c in nb.get("cells", []):
        if c.get("cell_type") == "code":
            c["outputs"] = []
            c["execution_count"] = None
    out = json.dumps(nb, indent=detect_indent(text), ensure_ascii=False)
    if text.endswith("\n"):
        out += "\n"
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(keep_eol(out, text))


def normalize_outputs(path):
    """Give molten's exported outputs the types Jupyter would have written.

    Molten stores every plain-text output as display_data. Text that ends with a
    newline is what print() produces, so it becomes a stdout stream; other plain
    text is the repr of the cell's last expression, so it becomes execute_result.
    Anything with other mime types (images, html) and errors is left alone.
    Stderr output cannot be told apart and is written as stdout.
    """
    text = open(path, encoding="utf-8", newline="").read()
    nb = json.loads(text)
    for c in nb.get("cells", []):
        if c.get("cell_type") != "code":
            continue
        outs = []
        for o in c.get("outputs", []):
            data = o.get("data") or {}
            if o.get("output_type") == "display_data" and list(data) == ["text/plain"]:
                body = data["text/plain"]
                joined = "".join(body) if isinstance(body, list) else body
                if joined.endswith("\n"):
                    o = {"name": "stdout", "output_type": "stream", "text": body}
                else:
                    o = {
                        "data": data,
                        "execution_count": c.get("execution_count"),
                        "metadata": o.get("metadata", {}),
                        "output_type": "execute_result",
                    }
            outs.append(o)
        c["outputs"] = outs
    out = json.dumps(nb, indent=detect_indent(text), ensure_ascii=False)
    if text.endswith("\n"):
        out += "\n"
    with open(path, "w", encoding="utf-8", newline="") as f:
        f.write(keep_eol(out, text))


if __name__ == "__main__":
    if sys.argv[1] == "--clear-outputs":
        clear_outputs(sys.argv[2])
    elif sys.argv[1] == "--normalize-outputs":
        normalize_outputs(sys.argv[2])
    else:
        main(sys.argv[1], sys.argv[2])
