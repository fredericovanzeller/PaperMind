"""PaperMind — PDF & image text processor with page-aware chunking + OCR."""

import fitz  # PyMuPDF
from pathlib import Path
from typing import List
from .models import DocumentChunk


def text_quality_score(text: str) -> float:
    """Avalia a qualidade do texto extraído (0.0 a 1.0)."""
    if not text.strip():
        return 0.0

    words = text.split()
    if not words:
        return 0.0

    # Contar palavras "reais" (mais de 2 caracteres, maioria letras)
    good_words = 0
    for w in words:
        clean = w.strip(".,;:!?()[]{}\"'")
        if len(clean) >= 2 and sum(c.isalpha() for c in clean) > len(clean) * 0.5:
            good_words += 1

    return good_words / len(words)


def process_pdf(filepath: str) -> List[DocumentChunk]:
    """
    Extrai texto de um PDF e divide em chunks com referência à página.
    Se o texto extraído for de má qualidade ou inexistente, faz OCR.
    """
    doc = fitz.open(filepath)
    filename = Path(filepath).name
    chunks = []
    chunk_index = 0

    for page_num, page in enumerate(doc, start=1):
        text = page.get_text().strip()

        # Avaliar qualidade do texto extraído
        quality = text_quality_score(text)

        # Se qualidade baixa (< 0.4) ou sem texto, tentar OCR
        if quality < 0.4 or not text:
            ocr_text = ocr_page(page)
            # Usar OCR se for melhor que o texto original
            if text_quality_score(ocr_text) > quality:
                text = ocr_text

        if not text or len(text.strip()) < 20:
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

        pix = page.get_pixmap(dpi=300)
        img_data = pix.tobytes("png")
        image = Image.open(io.BytesIO(img_data))

        text = pytesseract.image_to_string(image, lang="por+eng")
        return text.strip()
    except Exception as e:
        print(f"OCR falhou: {e}")
        return ""


def process_image_text(text: str, filename: str) -> List[DocumentChunk]:
    """
    Para imagens já com OCR feito pelo iPhone.
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