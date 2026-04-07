"""
PaperMind — RAG Engine (orquestrador).

Liga todos os componentes: PDF processor, vector store, hybrid search, LLM.
"""

import re
import time
from pathlib import Path
from datetime import datetime
from typing import List, Optional

from .models import (
    AskResponse,
    DocumentChunk,
    DocumentInfo,
    Source,
    SyncStatus,
    UploadResponse,
)
from .pdf_processor import process_pdf, process_image_text
from .embeddings import VectorStore
from .hybrid_search import HybridSearch
from .llm import LocalLLM


# Caminhos locais (configuráveis)
ICLOUD_BASE = Path.home() / "Developer" / "PaperMind" / "data"
ICLOUD_INBOX = ICLOUD_BASE / "Inbox"
ICLOUD_PROCESSED = ICLOUD_BASE / "Processed"
CHROMA_DIR = str(ICLOUD_BASE / "Database")


def clean_query(query: str) -> str:
    """Remove pontuação da query para busca limpa."""
    return re.sub(r'[^\w\s]', '', query)


class RAGEngine:
    def __init__(self, chroma_dir: Optional[str] = None):
        self.vector_store = VectorStore(persist_dir=chroma_dir or CHROMA_DIR)
        self.hybrid_search = HybridSearch(semantic_weight=0.6)
        self.llm = LocalLLM()
        self.documents: List[DocumentInfo] = []
        self._last_sync: Optional[datetime] = None
        self._all_chunks: List[DocumentChunk] = []

        existing_chunks = self.vector_store.get_all_chunks()
        if existing_chunks:
            self._all_chunks = existing_chunks
            self.hybrid_search.build_index(existing_chunks)
            self._rebuild_document_list(existing_chunks)
            print(f"Índice reconstruído: {len(existing_chunks)} chunks, {len(self.documents)} documentos")

    def _rebuild_document_list(self, chunks: List[DocumentChunk]):
        """Reconstrói a lista de documentos a partir dos chunks no ChromaDB."""
        doc_map: dict = {}
        for chunk in chunks:
            if chunk.source not in doc_map:
                doc_map[chunk.source] = {
                    "filename": chunk.source,
                    "total_chunks": 0,
                }
            doc_map[chunk.source]["total_chunks"] += 1

        self.documents = []
        for name, info in doc_map.items():
            self.documents.append(
                DocumentInfo(
                    filename=info["filename"],
                    total_chunks=info["total_chunks"],
                    document_type="documento",
                    date_added=datetime.now(),
                    file_path="",
                )
            )

    def _text_search(self, query: str, n_results: int = 5) -> List[DocumentChunk]:
        """Busca directa por texto — prioriza chunks com a palavra mais rara."""
        cleaned = clean_query(query)
        query_words = [w.lower() for w in cleaned.split() if len(w) > 2]
        if not query_words or not self._all_chunks:
            return []

        # Encontrar frequência de cada palavra da query nos chunks
        total = len(self._all_chunks)
        word_freq = {}
        for w in query_words:
            word_freq[w] = sum(1 for c in self._all_chunks if w in c.text.lower())

        # Ordenar palavras por raridade (menos frequente primeiro)
        rare_words = sorted(query_words, key=lambda w: word_freq.get(w, total))

        # Primeiro: chunks que contêm a palavra mais rara
        rarest = rare_words[0]
        priority_chunks = [c for c in self._all_chunks if rarest in c.text.lower()]

        # Se encontrou chunks com a palavra rara, usar esses
        if priority_chunks:
            scored = []
            for chunk in priority_chunks:
                chunk_lower = chunk.text.lower()
                matches = sum(1 for w in query_words if w in chunk_lower)
                scored.append((matches, chunk))
            scored.sort(key=lambda x: x[0], reverse=True)
            return [chunk for _, chunk in scored[:n_results]]

        # Fallback: busca normal por contagem de matches
        scored = []
        for chunk in self._all_chunks:
            chunk_lower = chunk.text.lower()
            matches = sum(1 for w in query_words if w in chunk_lower)
            if matches > 0:
                scored.append((matches, chunk))

        scored.sort(key=lambda x: x[0], reverse=True)
        return [chunk for _, chunk in scored[:n_results]]

    def ingest_file(
        self, filepath: str, original_name: Optional[str] = None
    ) -> UploadResponse:
        """Processa um ficheiro e indexa-o."""
        path = Path(filepath)
        name = original_name or path.name

        try:
            if path.suffix.lower() == ".pdf":
                chunks = process_pdf(filepath)
            elif path.suffix.lower() in {".jpg", ".jpeg", ".png", ".heic"}:
                txt_path = path.with_suffix(".txt")
                if txt_path.exists():
                    ocr_text = txt_path.read_text(encoding="utf-8")
                else:
                    ocr_text = ""

                if not ocr_text.strip():
                    return UploadResponse(
                        status="error",
                        filename=name,
                        total_chunks=0,
                        error="Sem texto extraído (OCR necessário)",
                    )
                chunks = process_image_text(ocr_text, name)
            else:
                return UploadResponse(
                    status="error",
                    filename=name,
                    total_chunks=0,
                    error=f"Formato não suportado: {path.suffix}",
                )

            if not chunks:
                return UploadResponse(
                    status="warning",
                    filename=name,
                    total_chunks=0,
                    error="Nenhum texto extraído (documento pode ser um scan)",
                )

            try:
                doc_type = self.llm.classify(chunks[0].text)
                for valid in ["contrato", "fatura", "recibo", "carta", "relatorio", "identificacao", "outro"]:
                    if valid in doc_type:
                        doc_type = valid
                        break
                else:
                    doc_type = "outro"
            except Exception:
                doc_type = "outro"

            for chunk in chunks:
                chunk.source = name

            self.vector_store.add_chunks(chunks)
            self.hybrid_search.add_chunks(chunks)
            self._all_chunks.extend(chunks)

            self.documents = [d for d in self.documents if d.filename != name]

            self.documents.append(
                DocumentInfo(
                    filename=name,
                    total_chunks=len(chunks),
                    document_type=doc_type,
                    date_added=datetime.now(),
                    file_path=filepath,
                )
            )

            self._last_sync = datetime.now()

            return UploadResponse(
                status="success",
                filename=name,
                total_chunks=len(chunks),
                document_type=doc_type,
            )

        except Exception as e:
            return UploadResponse(
                status="error",
                filename=name,
                total_chunks=0,
                error=str(e),
            )

    def ask(self, question: str) -> AskResponse:
        """Responde a uma pergunta usando busca por texto + RAG híbrido."""
        start = time.time()

        # 1. Busca directa por texto (prioriza palavras raras como nomes)
        text_chunks = self._text_search(question, n_results=5)

        # 2. Pesquisa semântica no ChromaDB
        semantic_results = self.vector_store.search(question, n_results=15)

        # 3. Pesquisa híbrida (BM25 + semântica)
        hybrid_chunks = self.hybrid_search.search(
            query=question,
            n_results=10,
            semantic_results=semantic_results,
        )

        # 4. Combinar: text search primeiro (mais preciso para nomes)
        combined = []
        seen_keys = set()

        for chunk in text_chunks:
            key = f"{chunk.source}_p{chunk.page_number}_c{chunk.chunk_index}"
            if key not in seen_keys:
                seen_keys.add(key)
                combined.append(chunk)

        for chunk in hybrid_chunks:
            key = f"{chunk.source}_p{chunk.page_number}_c{chunk.chunk_index}"
            if key not in seen_keys:
                seen_keys.add(key)
                combined.append(chunk)

        combined = combined[:4]

        if not combined:
            return AskResponse(
                question=question,
                answer="Não encontrei informação relevante nos documentos indexados.",
                sources=[],
                processing_time_ms=int((time.time() - start) * 1000),
            )

        # 5. Montar contexto
        context = "\n\n".join(
            f"[{c.source}, p.{c.page_number}]: {c.text}" for c in combined
        )

        # 6. Gerar resposta com LLM
        answer = self.llm.ask(question, context)

        # 7. Construir sources (sem duplicados)
        seen = set()
        sources = []
        for c in combined:
            key = f"{c.source}_p{c.page_number}_c{c.chunk_index}"
            if key not in seen:
                seen.add(key)
                sources.append(
                    Source(
                        filename=c.source,
                        page_number=c.page_number,
                        excerpt=c.text[:150] + "..." if len(c.text) > 150 else c.text,
                        relevance_score=0.0,
                    )
                )

        elapsed_ms = int((time.time() - start) * 1000)

        return AskResponse(
            question=question,
            answer=answer,
            sources=sources,
            processing_time_ms=elapsed_ms,
        )

    def process_inbox(self) -> List[str]:
        """Processa todos os ficheiros na Inbox."""
        ICLOUD_INBOX.mkdir(parents=True, exist_ok=True)
        processed = []

        for f in sorted(ICLOUD_INBOX.iterdir()):
            if f.suffix.lower() in {".pdf", ".jpg", ".jpeg", ".png", ".heic"}:
                result = self.ingest_file(str(f), original_name=f.name)
                if result.status == "success":
                    processed.append(result.filename)

        return processed

    def list_documents(self) -> List[dict]:
        """Lista todos os documentos indexados."""
        return [doc.model_dump() for doc in self.documents]

    def get_sync_status(self) -> SyncStatus:
        """Estado de sincronização para o iPhone consultar."""
        ICLOUD_INBOX.mkdir(parents=True, exist_ok=True)
        inbox_files = [
            f
            for f in ICLOUD_INBOX.iterdir()
            if f.suffix.lower() in {".pdf", ".jpg", ".jpeg", ".png", ".heic"}
        ]
        return SyncStatus(
            inbox_count=len(inbox_files),
            processed_count=self.vector_store.count,
            last_sync=self._last_sync,
        )