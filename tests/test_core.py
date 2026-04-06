"""
PaperMind — Testes básicos dos componentes.

Executar: python -m pytest tests/ -v
"""

import pytest
from pathlib import Path

# ── Testes dos Models ────────────────────────────────────────

def test_document_chunk_creation():
    from backend.models import DocumentChunk
    chunk = DocumentChunk(
        text="Este é um texto de teste",
        source="teste.pdf",
        page_number=1,
        chunk_index=0,
    )
    assert chunk.text == "Este é um texto de teste"
    assert chunk.source == "teste.pdf"
    assert chunk.page_number == 1


def test_upload_response():
    from backend.models import UploadResponse
    resp = UploadResponse(
        status="success",
        filename="Fatura_EDP_Marco2026",
        total_chunks=5,
        document_type="fatura",
    )
    assert resp.status == "success"
    assert resp.total_chunks == 5


def test_sync_status():
    from backend.models import SyncStatus
    status = SyncStatus(inbox_count=3, processed_count=47)
    assert status.inbox_count == 3
    assert status.last_sync is None


# ── Testes do PDF Processor ──────────────────────────────────

def test_process_image_text():
    from backend.pdf_processor import process_image_text
    text = " ".join(["palavra"] * 500)  # 500 palavras
    chunks = process_image_text(text, "scan.jpg")
    assert len(chunks) > 0
    assert chunks[0].source == "scan.jpg"
    assert chunks[0].page_number == 1


def test_process_image_text_empty():
    from backend.pdf_processor import process_image_text
    chunks = process_image_text("", "empty.jpg")
    assert len(chunks) == 0


def test_process_image_text_short():
    from backend.pdf_processor import process_image_text
    chunks = process_image_text("curto", "short.jpg")
    assert len(chunks) == 0  # < 50 chars


# ── Testes do Hybrid Search ──────────────────────────────────

def test_hybrid_search_empty():
    from backend.hybrid_search import HybridSearch
    hs = HybridSearch()
    results = hs.search("teste")
    assert results == []


def test_hybrid_search_with_chunks():
    from backend.hybrid_search import HybridSearch
    from backend.models import DocumentChunk

    hs = HybridSearch()
    chunks = [
        DocumentChunk(text="fatura electricidade EDP março 2026", source="fatura.pdf", page_number=1, chunk_index=0),
        DocumentChunk(text="contrato arrendamento apartamento Lisboa", source="contrato.pdf", page_number=1, chunk_index=0),
        DocumentChunk(text="recibo pagamento renda mensal", source="recibo.pdf", page_number=1, chunk_index=0),
    ]
    hs.build_index(chunks)

    results = hs.search("fatura EDP", n_results=2)
    assert len(results) <= 2
    assert results[0].source == "fatura.pdf"  # deve ser o mais relevante


# ── Testes do Vector Store ───────────────────────────────────

def test_vector_store_init(tmp_path):
    from backend.embeddings import VectorStore
    vs = VectorStore(persist_dir=str(tmp_path / "test_chroma"))
    assert vs.count == 0


def test_vector_store_add_and_count(tmp_path):
    from backend.embeddings import VectorStore
    from backend.models import DocumentChunk

    vs = VectorStore(persist_dir=str(tmp_path / "test_chroma"))
    chunks = [
        DocumentChunk(text="texto de teste para embeddings", source="teste.pdf", page_number=1, chunk_index=0),
    ]
    vs.add_chunks(chunks)
    assert vs.count == 1


# ── Teste de integração da Inbox ─────────────────────────────

def test_inbox_watcher_init(tmp_path):
    from backend.inbox_watcher import InboxWatcher
    inbox = tmp_path / "Inbox"
    inbox.mkdir()

    processed = []
    watcher = InboxWatcher(str(inbox), on_new_file=lambda f: processed.append(f))
    assert watcher.inbox_path == inbox
