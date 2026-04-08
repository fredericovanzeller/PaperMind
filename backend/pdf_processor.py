"""PaperMind — PDF & image text processor with 3-layer OCR."""

import logging
import fitz  # PyMuPDF
import subprocess
from pathlib import Path
from typing import List
from .models import DocumentChunk

logger = logging.getLogger("papermind.pdf_processor")

# Caminho do ocr_tool (Apple Vision CLI)
OCR_TOOL_PATH = Path(__file__).parent.parent / "ocr_tool"


def text_quality_score(text: str) -> float:
    """Avalia a qualidade do texto extraído (0.0 a 1.0)."""
    if not text.strip():
        return 0.0

    words = text.split()
    if not words:
        return 0.0

    good_words = 0
    for w in words:
        clean = w.strip(".,;:!?()[]{}\"'")
        if len(clean) >= 2 and sum(c.isalpha() for c in clean) > len(clean) * 0.5:
            good_words += 1

    return good_words / len(words)


def ocr_apple_vision(image_path: str) -> str:
    """OCR via Apple Vision CLI — melhor para manuscritos e formulários."""
    try:
        if not OCR_TOOL_PATH.exists():
            return ""

        result = subprocess.run(
            [str(OCR_TOOL_PATH), image_path],
            capture_output=True, text=True, timeout=60
        )
        if result.returncode == 0:
            return result.stdout.strip()
        else:
            logger.warning("Apple Vision OCR erro: %s", result.stderr)
            return ""
    except Exception as e:
        logger.warning("Apple Vision OCR falhou: %s", e)
        return ""


def ocr_tesseract(image_path: str) -> str:
    """OCR via Tesseract — fallback para texto impresso."""
    try:
        import pytesseract
        from PIL import Image

        image = Image.open(image_path)
        text = pytesseract.image_to_string(image, lang="por+eng")
        return text.strip()
    except Exception as e:
        logger.warning("Tesseract OCR falhou: %s", e)
        return ""


def ocr_page(page) -> str:
    """OCR de uma página PDF com 3 camadas: Apple Vision → Tesseract."""
    import tempfile
    import os

    # Renderizar página como imagem
    pix = page.get_pixmap(dpi=300)
    tmp_path = tempfile.mktemp(suffix=".png")
    pix.save(tmp_path)

    try:
        # Camada 1: Apple Vision (melhor qualidade)
        text = ocr_apple_vision(tmp_path)
        if text and text_quality_score(text) > 0.3:
            return text

        # Camada 2: Tesseract (fallback)
        text = ocr_tesseract(tmp_path)
        if text and text_quality_score(text) > 0.3:
            return text

        return text or ""
    finally:
        # Limpar ficheiro temporário
        try:
            os.unlink(tmp_path)
        except OSError:
            pass


def process_pdf(filepath: str) -> List[DocumentChunk]:
    """
    Extrai texto de um PDF com 3 camadas de OCR.
    1. Texto digital (get_text)
    2. Apple Vision OCR (manuscritos, formulários)
    3. Tesseract OCR (fallback)
    """
    doc = fitz.open(filepath)
    filename = Path(filepath).name
    chunks = []
    chunk_index = 0

    for page_num, page in enumerate(doc, start=1):
        # Camada 1: Extrair texto digital
        digital_text = page.get_text().strip()
        digital_quality = text_quality_score(digital_text)

        # Se texto digital é bom (>0.6), usar directamente
        if digital_quality > 0.6 and len(digital_text) > 50:
            text = digital_text
        else:
            # Texto digital fraco — fazer OCR
            ocr_text = ocr_page(page)
            ocr_quality = text_quality_score(ocr_text)

            # Usar o melhor resultado
            if ocr_quality > digital_quality and len(ocr_text) > len(digital_text):
                text = ocr_text
            elif digital_text:
                text = digital_text
            else:
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


def process_image_text(text: str, filename: str) -> List[DocumentChunk]:
    """Para imagens já com OCR feito pelo iPhone."""
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
