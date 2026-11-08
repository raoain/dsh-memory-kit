from pypdf import PdfReader
r = PdfReader(r"F:\Tools\coo-day1\track\guarded-chain-v2.pdf")
print("pages", len(r.pages))
print((r.pages[0].extract_text() or "")[:100].replace("\n"," / "))
print((r.pages[1].extract_text() or "")[:100].replace("\n"," / "))
