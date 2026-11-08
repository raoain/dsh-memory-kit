from pypdf import PdfReader
r = PdfReader(r"F:\Tools\coo-day1\track\structure-and-gears-v1.pdf")
print("pages", len(r.pages))
print((r.pages[0].extract_text() or "")[:90].replace("\n"," / "))
