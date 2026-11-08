from pypdf import PdfReader
r = PdfReader(r"F:\Tools\coo-day1\track\zen-p2.pdf")
t = "".join((p.extract_text() or "") for p in r.pages)
print("pages", len(r.pages), "chars", len(t))
for k in ["为什么闭环不能省","统一的是机制","记忆是副产物","两套语域","传动轴","判断"]:
    print(k, "->", ("有" if k in t else "没有"))
