import re, os, sys
from fpdf import FPDF

src, out, tcn, ten, sub = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

pdf = FPDF()
pdf.set_auto_page_break(True, margin=18)
pdf.add_font("cn", "", r"C:/Windows/Fonts/msyh.ttc")
pdf.add_font("cnb", "", r"C:/Windows/Fonts/msyhbd.ttc")

def put(text, style="", size=10, h=5.8):
    pdf.set_font("cnb" if style == "b" else "cn", size=size)
    if not text:
        pdf.ln(2); return
    while len(text) > 0:
        chunk = text[:120]; text = text[120:]
        pdf.multi_cell(0, h, chunk, new_x="LMARGIN", new_y="NEXT")

def clean(s):
    s = re.sub(r"\*\*(.+?)\*\*", r"\1", s)
    s = re.sub(r"`([^`]+)`", r"\1", s)
    s = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", s)
    return s

pdf.add_page()
pdf.set_y(62)
put(tcn, "b", 23, 12)
put(ten, "b", 15, 10)
put("")
put("守链 (Raoain)", "", 11, 8)
put("v2.0/v1.0 · 2026-11-05 · CC BY 4.0", "", 10, 7)
put("")
put(sub, "", 8.5, 6)

text = open(src, encoding="utf-8").read()
started = False
for line in text.split("\n"):
    r = line.rstrip()
    if r.startswith("# ") and not started:
        started = True; continue
    if not started: continue
    if r.startswith("# "):
        continue
    if not r.strip():
        put(""); continue
    if r.startswith("## "):
        pdf.add_page(); put(clean(r[3:]), "b", 15, 9)
    elif r.startswith("### "):
        put(clean(r[4:]), "b", 12, 7)
    elif r.startswith("> "):
        put(clean(r[2:]), "", 9.5, 5.4)
    elif r.startswith("```") or r.strip() == "---":
        continue
    elif r.strip().startswith("|"):
        cells = [c.strip() for c in r.strip().strip("|").split("|")]
        if all(re.fullmatch(r":?-{2,}:?", c or "-") for c in cells): continue
        put(" · ".join(clean(c) for c in cells), "", 8.5, 5.0)
    else:
        put(clean(r), "", 10, 5.8)

pdf.output(out)
print("wrote", out, os.path.getsize(out))