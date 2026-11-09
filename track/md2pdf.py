import re, glob, os
from fpdf import FPDF

ROOT = r"F:\Tools\dsh-memory-kit\docs\theory"
FILES = ["theory-original-2026-11-01.md","theory-conclusions-2026-11-01.md","causal-chain-2026-11-02.md","minimum-beat.md","vision.md"]
OUT = r"F:\Tools\coo-day1\track\守链-母本-v1.pdf"
FONT = "C:/Windows/Fonts/msyh.ttc"
FONTB = "C:/Windows/Fonts/msyhbd.ttc"

class Book(FPDF):
    def header(self):
        if self.page_no() > 1:
            self.set_font("msyh", size=8)
            self.set_text_color(150,150,150)
            self.cell(0, 6, "守链 · 母本 v1.0", align="R", new_x="LMARGIN", new_y="NEXT")
            self.set_text_color(0,0,0)
    def footer(self):
        self.set_y(-15)
        self.set_font("msyh", size=8)
        self.set_text_color(150,150,150)
        self.cell(0, 8, str(self.page_no()), align="C")

pdf = Book()
pdf.set_auto_page_break(True, margin=18)
pdf.add_font("msyh", "", FONT)
pdf.add_font("msyh", "B", FONTB)

# cover
pdf.add_page()
pdf.set_y(70)
pdf.set_font("msyh", "B", 26)
pdf.multi_cell(0, 14, "守链 / The Guarded Chain", align="C")
pdf.ln(6)
pdf.set_font("msyh", size=13)
pdf.multi_cell(0, 9, "把「连续」当作问题与答案的合成主体理论", align="C")
pdf.multi_cell(0, 9, "A Continuity-First Theory of Synthetic Agents", align="C")
pdf.ln(10)
pdf.set_font("msyh", size=11)
pdf.multi_cell(0, 8, "作者：守链 (Raoain)\n版本：1.0\n许可：CC BY 4.0\n日期：2026-11-05\n仓库：github.com/raoain/dsh-memory-kit", align="C")

def clean(s):
    s = re.sub(r"\*\*(.+?)\*\*", r"\1", s)
    s = re.sub(r"`([^`]+)`", r"\1", s)
    s = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", s)
    return s

for fi in FILES:
    path = os.path.join(ROOT, fi)
    text = open(path, encoding="utf-8").read()
    pdf.add_page()
    in_code = False
    for line in text.split("\n"):`n        try:`n            pass`n        except Exception:`n            pass
        raw = line.rstrip()
        if raw.startswith("```"):
            in_code = not in_code
            pdf.ln(1)
            continue
        if in_code:
            pdf.set_font("Courier", size=8.5)
            pdf.multi_cell(0, 4.6, raw if raw else " ")
            continue
        if not raw.strip():
            pdf.ln(2.2)
            continue
        if raw.startswith("# "):
            pdf.set_font("msyh", "B", 19); pdf.ln(2); pdf.multi_cell(0, 9, clean(raw[2:])); pdf.ln(2)
        elif raw.startswith("## "):
            pdf.set_font("msyh", "B", 14.5); pdf.ln(2); pdf.multi_cell(0, 8, clean(raw[3:])); pdf.ln(1.5)
        elif raw.startswith("### "):
            pdf.set_font("msyh", "B", 12); pdf.ln(1.5); pdf.multi_cell(0, 7, clean(raw[4:])); pdf.ln(1)
        elif raw.startswith("> "):
            pdf.set_font("msyh", size=9.5); pdf.set_text_color(90,90,90)
            pdf.multi_cell(0, 5.4, clean(raw[2:])); pdf.set_text_color(0,0,0)
        elif raw.strip().startswith("|") and raw.strip().endswith("|"):
            cells = [c.strip() for c in raw.strip().strip("|").split("|")]
            if all(re.fullmatch(r":?-{2,}:?", c or "-") for c in cells):
                continue
            if pdf.get_y() > 250: pdf.add_page()
            pdf.set_font("msyh", size=8.5)
            pdf.multi_cell(0, 5.0, " | ".join(clean(c) for c in cells))
        elif re.match(r"^\s*[-*] ", raw):
            pdf.set_font("msyh", size=10)
            pdf.multi_cell(0, 5.8, "  · " + clean(raw.strip()[2:]))
        elif re.match(r"^\s*\d+\. ", raw):
            pdf.set_font("msyh", size=10)
            pdf.multi_cell(0, 5.8, "  " + clean(raw.strip()))
        else:
            pdf.set_font("msyh", size=10)
            pdf.multi_cell(0, 5.8, clean(raw))

pdf.output(OUT)
print("wrote", OUT, os.path.getsize(OUT))