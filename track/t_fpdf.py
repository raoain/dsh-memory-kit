from fpdf import FPDF
pdf = FPDF()
pdf.add_page()
pdf.add_font("msyh", "", "C:/Windows/Fonts/msyh.ttc")
pdf.set_font("msyh", size=14)
pdf.multi_cell(0, 8, "测试：中文 hello world")
pdf.output(r"F:\Tools\coo-day1\track\t_fpdf.pdf")
print("ok")
