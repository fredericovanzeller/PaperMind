"""PaperMind — PDF & image text processor with page-aware chunking + OCR."""

import fitz  # PyMuPDF
from pathlib import Path
from typing import List
from .models import DocumentChunk


def process_pdf(filepath: str) -> List[DocumentChunk]:
    """
    Extrai texto de um PDF e divide em chunks com referência à página.
    Combina texto extraído com OCR para capturar campos preenchidos.
    """
    doc = fitz.open(filepath)
    filename = Path(filepath).name
    chunks = []
    chunk_index = 0

    for page_num, page in enumerate(doc, start=1):
        # Extrair texto da camada digital
        digital_text = page.get_text().strip()

        # Sempre fazer OCR para capturar campos preenchidos
        ocr_text = ocr_page(page)

        # Usar o texto mais completo
        if not digital_text:
            text = ocr_text
        elif not ocr_text:
            text = digital_text
        else:
            # Combinar: se OCR tem conteúdo que o digital não tem, usar OCR
            # OCR captura campos preenchidos que get_text() não vê
            digital_words = set(digital_text.lower().split())
            ocr_words = set(ocr_text.lower().split())
            new_words = ocr_words - digital_words

            # Se OCR encontrou >20% de palavras novas, usar OCR
            if len(new_words) > len(ocr_words) * 0.2:
                text = ocr_text
            else:
                text = digital_text

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