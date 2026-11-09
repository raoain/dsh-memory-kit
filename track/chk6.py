from pypdf import PdfReader
base = "F:/Tools/coo-day1/track/"
for f in ["guarded-chain-v3.pdf","structure-and-gears-v3.pdf","digital-core-and-biology-v3.pdf","silicon-advantages-and-outlook-v2.pdf"]:
    r = PdfReader(base + f)
    t = r.pages[1].extract_text() or ""
    print(f, "pages", len(r.pages), "| first:", t[:50].replace("\n", " / "))