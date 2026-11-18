# md2docx-fig.py —— Markdown → DOCX（支持内嵌图片，供 PDF 管线用）
# 用法: python md2docx-fig.py <输入.md> <输出.docx> [--base 图片基准目录]
# 处理: # ## ### 标题 / **粗体** / 列表 / 表格（转简单表） / > 引用 / 代码块 / ![alt](path) 图片 / 段落
import sys, os, re
from docx import Document
from docx.shared import Pt, Inches
from docx.enum.text import WD_ALIGN_PARAGRAPH

def add_runs(p, text):
    # 处理 **粗体** 与 `代码`
    for part in re.split(r'(\*\*[^*]+\*\*|`[^`]+`)', text):
        if not part:
            continue
        if part.startswith('**') and part.endswith('**'):
            r = p.add_run(part[2:-2]); r.bold = True
        elif part.startswith('`') and part.endswith('`'):
            r = p.add_run(part[1:-1]); r.font.name = 'Consolas'; r.font.size = Pt(10)
        else:
            p.add_run(part)

def main():
    src, out = sys.argv[1], sys.argv[2]
    base = os.path.dirname(os.path.abspath(src))
    if '--base' in sys.argv:
        base = sys.argv[sys.argv.index('--base') + 1]
    lines = open(src, encoding='utf-8').read().split('\n')
    doc = Document()
    doc.styles['Normal'].font.name = 'Microsoft YaHei'
    doc.styles['Normal'].font.size = Pt(11)
    i = 0
    in_code = False
    while i < len(lines):
        ln = lines[i].rstrip()
        if ln.startswith('```'):
            in_code = not in_code
            i += 1
            continue
        if in_code:
            p = doc.add_paragraph()
            r = p.add_run(ln); r.font.name = 'Consolas'; r.font.size = Pt(9)
            i += 1
            continue
        if not ln.strip():
            i += 1
            continue
        m = re.match(r'^(#{1,4})\s+(.*)$', ln)
        if m:
            lvl = len(m.group(1))
            doc.add_heading(m.group(2).strip(), level=min(lvl, 4))
            i += 1
            continue
        m = re.match(r'^!\[(.*?)\]\((.*?)\)\s*$', ln)
        if m:
            alt, rel = m.group(1), m.group(2)
            path = rel if os.path.isabs(rel) else os.path.join(base, rel)
            if os.path.exists(path):
                doc.add_picture(path, width=Inches(6.2))
                doc.paragraphs[-1].alignment = WD_ALIGN_PARAGRAPH.CENTER
                cap = doc.add_paragraph(alt); cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
            else:
                doc.add_paragraph('［缺图：%s］' % rel)
            i += 1
            continue
        if re.match(r'^\s*[-*]\s+', ln):
            txt = re.sub(r'^\s*[-*]\s+', '', ln)
            p = doc.add_paragraph(style='List Bullet'); add_runs(p, txt)
            i += 1
            continue
        if re.match(r'^\s*\d+\.\s+', ln):
            txt = re.sub(r'^\s*\d+\.\s+', '', ln)
            p = doc.add_paragraph(style='List Number'); add_runs(p, txt)
            i += 1
            continue
        if ln.startswith('>'):
            p = doc.add_paragraph(); p.paragraph_format.left_indent = Inches(0.3)
            add_runs(p, ln.lstrip('> ').strip())
            i += 1
            continue
        if ln.startswith('|'):
            # 收集表格块
            rows = []
            while i < len(lines) and lines[i].strip().startswith('|'):
                cells = [c.strip() for c in lines[i].strip().strip('|').split('|')]
                if not re.match(r'^[-:\s|]+$', lines[i].strip()):
                    rows.append(cells)
                i += 1
            if rows:
                t = doc.add_table(rows=len(rows), cols=len(rows[0]))
                t.style = 'Table Grid'
                for ri, row in enumerate(rows):
                    for ci, cell in enumerate(row[:len(rows[0])]):
                        t.cell(ri, ci).text = cell
            continue
        p = doc.add_paragraph(); add_runs(p, ln)
        i += 1
    doc.save(out)
    print('ok', out)

if __name__ == '__main__':
    main()
