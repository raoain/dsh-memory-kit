from pypdf import PdfReader
r = PdfReader(r"F:\Tools\coo-day1\track\shoulian-mother-v1.pdf")
print("pages", len(r.pages))
for i in (0, 1, 2):
    t = (r.pages[i].extract_text() or "")[:120].replace("\n", " / ")
    print(i+1, t)
