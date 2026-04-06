"""PaperMind — PDF & image text processor with page-aware chunking."""

import fitz  # PyMuPDF
from pathlib import Path
from typing import List
from .models import DocumentChunk


def process_pdf(filepath: str) -> List[DocumentChunk]:
    """
    Extrai texto de um PDF e divide em chunks com referência à página.
    Chunk size: 400 palavras com overlap de 50 para manter contexto.
    """
    doc = fitz.open(filepath)
    filename = Path(filepath).name
    chunks = []
    chunk_index = 0

    for page_num, page in enumerate(doc, start=1):
        text = page.get_text().strip()
        if not text:
            continue

        words = text.split()
        chunk_size = 400
        overlap = 50

        for i in range(0, len(words), chunk_size - overlap):
            chunk_text = " ".join(words[i:i + chunk_size])
            if len(chunk_text) > 50:  # ignorar chunks demasiado curtos
                chunks.append(DocumentChunk(
                    text=chunk_text,
                    source=filename,
                    page_number=page_num,
                    chunk_index=chunk_index,
                ))
                chunk_index += 1

    return chunks


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
                page_number=1,  # imagem = página 1
                chunk_index=i,
            ))

    return chunks
