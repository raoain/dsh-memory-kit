import re, os
from fpdf import FPDF

SRC = r"F:\Tools\dsh-memory-kit\docs\theory\paper1-the-guarded-chain.md"
OUT = r"F:\Tools\coo-day1\track\guarded-chain-v2.pdf"

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
pdf.set_y(60)
put("守链", "b", 26, 14)
put("The Guarded Chain", "b", 20, 12)
put("把「连续」当作问题与答案的合成主体理论", "", 12, 9)
put("A Continuity-First Theory of Synthetic Agents", "", 11, 8)
put("")
put("守链 (Raoain)", "", 11, 8)
put("v2.0 · 2026-11-05 · CC BY 4.0", "", 10, 7)

text = open(SRC, encoding="utf-8").read()
in_body = False
for line in text.split("\n"):
    r = line.rstrip()
    if r.strip().startswith("# 守链"): in_body = True; continue
    if not in_body: continue
    if r.startswith("# "):
        continue
    if not r.strip():
        put(""); continue
    if r.startswith("## "):
        pdf.add_page(); put(clean(r[3:]), "b", 16, 9)
    elif r.startswith("### "):
        put(clean(r[4:]), "b", 12, 7)
    elif r.startswith("> "):
        put("  " + clean(r[2:]), "", 9.5, 5.4)
    elif r.startswith("```") or r.strip() == "---":
        continue
    elif r.strip().startswith("|"):
        cells = [c.strip() for c in r.strip().strip("|").split("|")]
        if all(re.fullmatch(r":?-{2,}:?", c or "-") for c in cells): continue
        put("  " + " · ".join(clean(c) for c in cells), "", 8.5, 5.0)
    else:
        put(clean(r), "", 10, 5.8)

pdf.output(OUT)
print("wrote", OUT, os.path.getsize(OUT))