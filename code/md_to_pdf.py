#!/usr/bin/env python3
"""Convert a Markdown file to PDF using markdown + weasyprint."""

import sys
import markdown
from weasyprint import HTML

CSS = """
@import url('https://fonts.googleapis.com/css2?family=Noto+Sans+KR:wght@400;700&family=Source+Code+Pro&display=swap');

body {
    font-family: 'Noto Sans KR', 'DejaVu Sans', Arial, sans-serif;
    font-size: 11pt;
    line-height: 1.7;
    color: #1a1a1a;
    margin: 0;
    padding: 0;
}
@page {
    size: A4;
    margin: 20mm 18mm 20mm 18mm;
    @bottom-right {
        content: counter(page) " / " counter(pages);
        font-size: 9pt;
        color: #888;
    }
}
h1 {
    font-size: 22pt;
    color: #1a1a2e;
    border-bottom: 3px solid #1a1a2e;
    padding-bottom: 6px;
    margin-top: 0;
    page-break-after: avoid;
}
h2 {
    font-size: 15pt;
    color: #16213e;
    border-bottom: 1.5px solid #ccc;
    padding-bottom: 4px;
    margin-top: 28px;
    page-break-after: avoid;
}
h3 {
    font-size: 12pt;
    color: #0f3460;
    margin-top: 18px;
    page-break-after: avoid;
}
h4 {
    font-size: 11pt;
    color: #333;
    page-break-after: avoid;
}
pre {
    background: #f4f4f4;
    border: 1px solid #ddd;
    border-left: 4px solid #1a1a2e;
    border-radius: 4px;
    padding: 10px 14px;
    font-family: 'Source Code Pro', 'DejaVu Sans Mono', 'Courier New', monospace;
    font-size: 8.5pt;
    line-height: 1.45;
    overflow-x: auto;
    white-space: pre-wrap;
    word-wrap: break-word;
    page-break-inside: avoid;
}
code {
    font-family: 'Source Code Pro', 'DejaVu Sans Mono', 'Courier New', monospace;
    font-size: 8.5pt;
    background: #f0f0f0;
    border: 1px solid #ddd;
    border-radius: 3px;
    padding: 1px 4px;
}
pre code {
    background: none;
    border: none;
    padding: 0;
    font-size: inherit;
}
table {
    border-collapse: collapse;
    width: 100%;
    margin: 12px 0;
    font-size: 9.5pt;
    page-break-inside: avoid;
}
th {
    background: #1a1a2e;
    color: white;
    padding: 7px 10px;
    text-align: left;
    font-weight: bold;
}
td {
    border: 1px solid #ddd;
    padding: 6px 10px;
    vertical-align: top;
}
tr:nth-child(even) td {
    background: #f9f9f9;
}
blockquote {
    border-left: 4px solid #1a1a2e;
    margin: 12px 0;
    padding: 6px 14px;
    background: #f0f4ff;
    color: #333;
    font-style: italic;
}
hr {
    border: none;
    border-top: 1.5px solid #ccc;
    margin: 20px 0;
}
a {
    color: #0f3460;
}
ul, ol {
    padding-left: 22px;
    margin: 6px 0;
}
li {
    margin: 3px 0;
}
p {
    margin: 8px 0;
}
"""

def convert(md_path, pdf_path):
    with open(md_path, encoding="utf-8") as f:
        md_text = f.read()

    # Remove mermaid blocks (not renderable in weasyprint)
    import re
    md_text = re.sub(r"```mermaid.*?```", "[Diagram — see Markdown source]", md_text, flags=re.DOTALL)

    html_body = markdown.markdown(
        md_text,
        extensions=["tables", "fenced_code", "codehilite", "toc"]
    )
    html = f"""<!DOCTYPE html>
<html>
<head>
<meta charset="utf-8">
<style>{CSS}</style>
</head>
<body>
{html_body}
</body>
</html>"""

    HTML(string=html).write_pdf(pdf_path)
    print(f"  ✓  {pdf_path}")

if __name__ == "__main__":
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <input.md> <output.pdf>")
        sys.exit(1)
    convert(sys.argv[1], sys.argv[2])
