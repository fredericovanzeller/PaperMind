"""PaperMind — PDF & image text processor with page-aware chunking + OCR."""

import fitz  # PyMuPDF
from pathlib import Path
from typing import List
from .models import DocumentChunk


def process_pdf(filepath: str) -> List[DocumentChunk]:
    """
    Extrai texto de um PDF e divide em chunks com referência à página.
    Se uma página não tiver texto (scan), faz OCR.
    """
    doc = fitz.open(filepath)
    filename = Path(filepath).name
    chunks = []
    chunk_index = 0

    for page_num, page in enumerate(doc, start=1):
        text = page.get_text().strip()

        # Se não há texto, tentar OCR (página é provavelmente um scan)
        if not text:
            text = ocr_page(page)

        if not text:
            continue

        words = text.split()
        chunk_size = 400
        overlap = 50

        for i in range(0, len(words), chunk_size - overlap):
            chunk_text = " ".join(words[i:i + chunk_size])
            if len(chunk_text) > 50:
                chunks.append(DocumentChunk(
                    text=chunk_text,
                    source=filename,
                    page_number=page_num,
                    chunk_index=chunk_index,
                ))
                chunk_index += 1

    return chunks


def ocr_page(page) -> str:
    """Faz OCR de uma página PDF usando pytesseract."""
    try:
        import pytesseract
        from PIL import Image
        import io

        # Renderizar página como imagem (300 DPI para boa qualidade OCR)
        pix = page.get_pixmap(dpi=300)
        img_data = pix.tobytes("png")
        image = Image.open(io.BytesIO(img_data))

        # OCR com suporte a português e inglês
        text = pytesseract.image_to_string(image, lang="por+eng")
        return text.strip()
    except Exception as e:
        print(f"OCR falhou: {e}")
        return ""


def process_image_text(text: str, filename: str) -> List[DocumentChunk]:
    """
    Para imagens já com OCR feito pelo iPhone.
    Recebe texto extraído e divide em chunks.
    """
    words = text.split()
    chunks = []
    chunk_size = 400
    overlap = 50

    for i, idx in enumerate(range(0, len(words), chunk_size - overlap)):
        chunk_text = " ".join(words[idx:idx + chunk_size])
        if len(chunk_text) > 50:
            chunks.append(DocumentChunk(
                text=chunk_text,
                source=filename,
                page_number=1,
                chunk_index=i,
            ))

    return chunks