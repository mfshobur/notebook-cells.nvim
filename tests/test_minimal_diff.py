"""Run: python3 tests/test_minimal_diff.py"""
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parent.parent / "scripts" / "nb_minimal_diff.py"


def cell(src, outputs=None, **meta):
    return {
        "cell_type": "code",
        "execution_count": 1,
        "id": "c" + str(abs(hash("".join(src))) % 1000),
        "metadata": meta,
        "outputs": outputs or [],
        "source": src,
    }


def run(original, written):
    with tempfile.TemporaryDirectory() as d:
        o, w = Path(d, "o.ipynb"), Path(d, "w.ipynb")
        o.write_text(json.dumps(original, indent=1) + "\n")
        w.write_text(json.dumps(written, indent=2))
        subprocess.run([sys.executable, str(SCRIPT), str(o), str(w)], check=True)
        return w.read_text()


def nb(cells):
    return {"cells": cells, "metadata": {"kernelspec": {"name": "python3"}}, "nbformat": 4, "nbformat_minor": 5}


class MinimalDiff(unittest.TestCase):
    def test_unchanged_cells_are_restored_byte_for_byte(self):
        original = nb([cell(["a = 1\n"], [{"output_type": "stream", "name": "stdout", "text": ["1\n"]}]), cell(["b = 2\n"])])
        # jupytext strips trailing newlines, drops outputs and adds noise metadata
        written = nb([cell(["a = 1"], lines_to_next_cell=2), cell(["b = 2"])])
        out = run(original, written)
        self.assertEqual(out, json.dumps(original, indent=1) + "\n")

    def test_changed_cell_keeps_other_cells_and_trailing_newline_style(self):
        original = nb([cell(["a = 1\n"]), cell(["b = 2\n"])])
        written = nb([cell(["a = 1"]), cell(["b = 3"], lines_to_next_cell=1)])
        out = json.loads(run(original, written))
        self.assertEqual(out["cells"][0], original["cells"][0])
        self.assertEqual(out["cells"][1]["source"], ["b = 3\n"])
        self.assertNotIn("lines_to_next_cell", out["cells"][1]["metadata"])

    def test_notebook_metadata_comes_from_original(self):
        original = nb([cell(["a\n"])])
        written = nb([cell(["a"])])
        written["metadata"] = {"jupytext": {"formats": "ipynb,py"}}
        out = json.loads(run(original, written))
        self.assertEqual(out["metadata"], original["metadata"])


class ClearOutputs(unittest.TestCase):
    def test_outputs_and_counts_removed_but_style_kept(self):
        notebook = nb([cell(["a = 1\n"], [{"output_type": "stream", "name": "stdout", "text": ["1\n"]}]), cell(["b = 2\n"])])
        with tempfile.TemporaryDirectory() as d:
            path = Path(d, "n.ipynb")
            path.write_text(json.dumps(notebook, indent=1) + "\n")
            subprocess.run([sys.executable, str(SCRIPT), "--clear-outputs", str(path)], check=True)
            text = path.read_text()
        out = json.loads(text)
        self.assertTrue(all(c["outputs"] == [] and c["execution_count"] is None for c in out["cells"]))
        self.assertTrue(text.endswith("\n"))
        self.assertEqual([c["source"] for c in out["cells"]], [c["source"] for c in notebook["cells"]])


class LineEndings(unittest.TestCase):
    def test_crlf_files_keep_crlf(self):
        notebook = nb([cell(["a = 1\n"], [{"output_type": "stream", "name": "stdout", "text": ["1\n"]}])])
        with tempfile.TemporaryDirectory() as d:
            path = Path(d, "n.ipynb")
            path.write_bytes((json.dumps(notebook, indent=1) + "\n").replace("\n", "\r\n").encode())
            subprocess.run([sys.executable, str(SCRIPT), "--clear-outputs", str(path)], check=True)
            data = path.read_bytes()
        self.assertIn(b"\r\n", data)
        self.assertNotIn(b"\n", data.replace(b"\r\n", b""))


class NormalizeOutputs(unittest.TestCase):
    def run_normalize(self, outputs, count=3):
        c = cell(["x\n"], outputs)
        c["execution_count"] = count
        with tempfile.TemporaryDirectory() as d:
            path = Path(d, "n.ipynb")
            path.write_text(json.dumps(nb([c]), indent=1) + "\n")
            subprocess.run([sys.executable, str(SCRIPT), "--normalize-outputs", str(path)], check=True)
            return json.loads(path.read_text())["cells"][0]["outputs"]

    def test_text_with_newline_becomes_stream(self):
        out = self.run_normalize([{"output_type": "display_data", "data": {"text/plain": ["hi\n"]}, "metadata": {}}])
        self.assertEqual(out, [{"name": "stdout", "output_type": "stream", "text": ["hi\n"]}])

    def test_text_without_newline_becomes_execute_result(self):
        out = self.run_normalize([{"output_type": "display_data", "data": {"text/plain": ["42"]}, "metadata": {}}])
        self.assertEqual(out[0]["output_type"], "execute_result")
        self.assertEqual(out[0]["execution_count"], 3)

    def test_images_and_errors_are_kept(self):
        image = {"output_type": "display_data", "data": {"text/plain": ["<Figure>"], "image/png": "AAAA"}, "metadata": {}}
        error = {"output_type": "error", "ename": "E", "evalue": "v", "traceback": []}
        self.assertEqual(self.run_normalize([image, error]), [image, error])


if __name__ == "__main__":
    unittest.main()
