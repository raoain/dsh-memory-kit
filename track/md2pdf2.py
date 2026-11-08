import re, os
from fpdf import FPDF

ROOT = r"F:\Tools\dsh-memory-kit\docs\theory"
FILES = ["theory-original-2026-11-01.md","theory-conclusions-2026-11-01.md","causal-chain-2026-11-02.md","minimum-beat.md","vision.md"]
OUT = r"F:\Tools\coo-day1\track\shoulian-mother-v1.pdf"

pdf = FPDF()
pdf.set_auto_page_break(True, margin=18)
pdf.add_font("cn", "", r"C:/Windows/Fonts/msyh.ttc")
pdf.add_font("cnb", "", r"C:/Windows/Fonts/msyhbd.ttc")

def put(text, style="", size=10, h=5.8):
    pdf.set_font("cnb" if style == "b" else "cn", size=size)
    if not text:
        pdf.ln(2)
        return
    # 长无空格串按字符切，避免 "Not enough horizontal space"
    while len(text) > 0:
        chunk = text[:120]
        text = text[120:]
        pdf.multi_cell(0, h, chunk, new_x="LMARGIN", new_y="NEXT")

def clean(s):
    s = re.sub(r"\*\*(.+?)\*\*", r"\1", s)
    s = re.sub(r"`([^`]+)`", r"\1", s)
    s = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", s)
    return s

pdf.add_page()
pdf.set_y(70)
put("守链 / The Guarded Chain", "b", 24, 13)
put("")
put("把「连续」当作问题与答案的合成主体理论", "", 13, 9)
put("A Continuity-First Theory of Synthetic Agents", "", 12, 8)
put("")
put("作者：守链 (Raoain)  ·  版本 1.0  ·  CC BY 4.0", "", 10, 7)
put("2026-11-05  ·  github.com/raoain/dsh-memory-kit", "", 9, 6)

for fi in FILES:
    pdf.add_page()
    text = open(os.path.join(ROOT, fi), encoding="utf-8").read()
    for line in text.split("\n"):
        r = line.rstrip()
        if not r.strip():
            put("")
        elif r.startswith("# "):
            put(clean(r[2:]), "b", 18, 9)
        elif r.startswith("## "):
            put("")
            put(clean(r[3:]), "b", 14, 8)
        elif r.startswith("### "):
            put(clean(r[4:]), "b", 11.5, 7)
        elif r.startswith("> "):
            put("  " + clean(r[2:]), "", 9.5, 5.4)
        elif r.startswith("```"):
            continue
        elif r.strip().startswith("|"):
            cells = [c.strip() for c in r.strip().strip("|").split("|")]
            if all(re.fullmatch(r":?-{2,}:?", c or "-") for c in cells):
                continue
            put("  " + " · ".join(clean(c) for c in cells), "", 8.5, 5.0)
        elif re.match(r"^\s*[-*] ", r):
            put("  · " + clean(r.strip()[2:]), "", 10, 5.8)
        else:
            put(clean(r), "", 10, 5.8)

pdf.output(OUT)
print("wrote", OUT, os.path.getsize(OUT))