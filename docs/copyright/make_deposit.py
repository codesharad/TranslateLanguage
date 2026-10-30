"""Rebuilds the copyright source-code deposit. Run from the repository root: python docs/copyright/make_deposit.py
Needs pymupdf (pip install pymupdf) and the Consolas font."""
import hashlib
import re
import subprocess
import textwrap

import pymupdf

SKIP = re.compile(r"node_modules|/build/|\.dart_tool|generated|^mobile/(windows|linux|macos|web)/")
EXT = re.compile(r"\.(ts|sql|py|dart|kt|swift)$")
out = subprocess.run(["git", "ls-files"], capture_output=True, text=True).stdout.split("\n")
files = sorted(f for f in out if f and EXT.search(f) and not SKIP.search(f))
WIDTH, PER_PAGE = 100, 55
BS = chr(92)
lines, manifest = [], []
for f in files:
    raw = open(f, "rb").read()
    text = raw.decode("utf-8", errors="replace").replace("\ufeff", "")
    manifest.append((f, len(text.splitlines()), hashlib.sha256(raw).hexdigest()))
    lines.append(f"===== {f} =====")
    for ln in text.splitlines():
        ln = ln.expandtabs(4).rstrip()
        ln = "".join(c if ord(c) < 128 else BS + "u%04x" % ord(c) for c in ln)
        lines.extend(textwrap.wrap(ln, WIDTH, replace_whitespace=False, drop_whitespace=False,
                                   subsequent_indent="    ") or [""])
    lines.append("")
pages = [lines[i:i + PER_PAGE] for i in range(0, len(lines), PER_PAGE)]
total = len(pages)
print("files", len(files), "lines", len(lines), "pages", total)
font = r"C:\Windows\Fonts\consola.ttf"


def write(path, idxs):
    doc = pymupdf.open()
    for i in idxs:
        p = doc.new_page(width=595, height=842)
        p.insert_text((40, 40), f"TranslateLanguage - source code - page {i + 1} of {total}", fontsize=8,
                      fontname="cons", fontfile=font)
        y = 62
        for ln in pages[i]:
            p.insert_text((40, y), ln, fontsize=7.2, fontname="cons", fontfile=font)
            y += 13.4
    doc.save(path)


write("docs/copyright/source_code_first_10_pages.pdf", range(0, min(10, total)))
write("docs/copyright/source_code_last_10_pages.pdf", range(max(total - 10, 0), total))
with open("docs/copyright/source_manifest.txt", "w", encoding="utf-8") as fh:
    fh.write("File, lines, SHA-256 (taken from the git working tree)\n\n")
    for f, n, h in manifest:
        fh.write(f"{f}  {n}  {h}\n")
    fh.write(f"\nTotal files: {len(files)}; listing lines: {len(lines)}; pages at {PER_PAGE} lines: {total}\n")
    fh.write("Non-ASCII characters in the PDFs are shown as backslash-u escapes.\n")
