"""
Extract text from an in-memory file (PDF / Word / Excel / CSV / scanned image).

Everything runs in worker memory. The caller writes the source bytes to a RAM
disk (/dev/shm) so plaintext never touches the worker's persistent disk; this
module only ever sees bytes / a tmpfs path.

Strategy by type:
  - PDF:   PyMuPDF text layer; if a page has no text (scanned), rasterize it
           and OCR with Tesseract.
  - image: Tesseract OCR.
  - docx:  python-docx.
  - xlsx:  openpyxl.
  - csv/txt: decode directly.
"""

from __future__ import annotations

import csv
import io
import os

import fitz  # PyMuPDF
import pytesseract
from PIL import Image


def _ocr_image(img: "Image.Image") -> str:
    return pytesseract.image_to_string(img)


def _extract_pdf(data: bytes) -> str:
    parts: list[str] = []
    with fitz.open(stream=data, filetype="pdf") as doc:
        for page in doc:
            text = page.get_text().strip()
            if text:
                parts.append(text)
            else:
                # No text layer -> scanned page. Rasterize @300dpi and OCR.
                pix = page.get_pixmap(dpi=300)
                img = Image.open(io.BytesIO(pix.tobytes("png")))
                parts.append(_ocr_image(img))
    return "\n".join(parts)


def _extract_docx(data: bytes) -> str:
    import docx  # python-docx

    document = docx.Document(io.BytesIO(data))
    return "\n".join(p.text for p in document.paragraphs)


def _extract_xlsx(data: bytes) -> str:
    import openpyxl

    wb = openpyxl.load_workbook(io.BytesIO(data), read_only=True, data_only=True)
    lines: list[str] = []
    for ws in wb.worksheets:
        for row in ws.iter_rows(values_only=True):
            lines.append(",".join("" if c is None else str(c) for c in row))
    return "\n".join(lines)


def _extract_csv(data: bytes) -> str:
    text = data.decode("utf-8", errors="replace")
    reader = csv.reader(io.StringIO(text))
    return "\n".join(",".join(row) for row in reader)


def extract_text(data: bytes, filename: str, content_type: str = "") -> str:
    """Dispatch on extension/content-type and return extracted text."""
    ext = os.path.splitext(filename)[1].lower()

    if ext == ".pdf" or content_type == "application/pdf":
        return _extract_pdf(data)
    if ext in (".png", ".jpg", ".jpeg", ".tif", ".tiff", ".bmp") or content_type.startswith("image/"):
        return _ocr_image(Image.open(io.BytesIO(data)))
    if ext == ".docx":
        return _extract_docx(data)
    if ext in (".xlsx", ".xlsm"):
        return _extract_xlsx(data)
    if ext in (".csv", ".tsv"):
        return _extract_csv(data)
    if ext in (".txt", ".md", ".json", ".log"):
        return data.decode("utf-8", errors="replace")

    # Last resort: try OCR as an image, else decode as text.
    try:
        return _ocr_image(Image.open(io.BytesIO(data)))
    except Exception:
        return data.decode("utf-8", errors="replace")
