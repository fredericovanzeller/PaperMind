"""
PaperMind — RAG Engine (orquestrador).

v3.2:
  - Upload copia ficheiro para data/Processed/[tipo]/ — PaperMind tem sempre a sua cópia
  - file_path aponta para dentro do PaperMind (nunca path externo)
  - delete_document() remove chunks + ficheiro
  - Sources dedup por ficheiro+página
  - Contexto com limite de tamanho
"""

import json
import logging
import re
import shutil
import time
from pathlib import Path
from datetime import datetime
from typing import List, Optional

logger = logging.getLogger("papermind.rag_engine")

from .models import (
    AskResponse,
    DocumentChunk,
    DocumentInfo,
    Source,
    SyncStatus,
    UploadResponse,
)
from .pdf_processor import process_pdf, process_image_text, process_docx, process_txt
from .embeddings import VectorStore
from .hybrid_search import HybridSearch
from .llm import LocalLLM
from .categories import CategoryManager


ICLOUD_BASE = Path.home() / "Developer" / "PaperMind" / "data"
ICLOUD_INBOX = ICLOUD_BASE / "Inbox"
ICLOUD_PROCESSED = ICLOUD_BASE / "Processed"
CHROMA_DIR = str(ICLOUD_BASE / "Database")

MAX_CONTEXT_CHARS = 40000


def clean_query(query: str) -> str:
    return re.sub(r'[^\w\s]', '', query)


class RAGEngine:
    def __init__(self, chroma_dir: Optional[str] = None):
        self.vector_store = VectorStore(persist_dir=chroma_dir or CHROMA_DIR)
        self.hybrid_search = HybridSearch(semantic_weight=0.6)
        self.llm = LocalLLM()
        self.category_manager = CategoryManager(ICLOUD_BASE)
        self.documents: List[DocumentInfo] = []
        self._last_sync: Optional[datetime] = None
        self._all_chunks: List[DocumentChunk] = []

        # Garantir que as pastas existem
        ICLOUD_INBOX.mkdir(parents=True, exist_ok=True)
        ICLOUD_PROCESSED.mkdir(parents=True, exist_ok=True)

        existing_chunks = self.vector_store.get_all_chunks()
        if existing_chunks:
            self._all_chunks = existing_chunks
            self.hybrid_search.build_index(existing_chunks)
            self._rebuild_document_list(existing_chunks)
            logger.info("Índice reconstruído: %d chunks, %d documentos", len(existing_chunks), len(self.documents))

    def _rebuild_document_list(self, chunks: List[DocumentChunk]):
        """Reconstrói a lista de documentos com tipos e paths persistidos."""
        doc_types = self.vector_store.get_doc_types()
        doc_paths = self.vector_store.get_doc_paths()

        doc_map: dict = {}
        for chunk in chunks:
            if chunk.source not in doc_map:
                doc_map[chunk.source] = 0
            doc_map[chunk.source] += 1

        self.documents = []
        for name, count in doc_map.items():
            doc_type = doc_types.get(name, "documento")
            stored_path = doc_paths.get(name, "")

            # Verificar se o ficheiro ainda existe no path guardado
            if stored_path and not Path(stored_path).exists():
                # Tentar encontrar na pasta Processed
                found_path = self._find_file(name)
                stored_path = found_path or ""

            self.documents.append(
                DocumentInfo(
                    filename=name,
                    total_chunks=count,
                    document_type=doc_type,
                    date_added=datetime.now(),
                    file_path=stored_path,
                )
            )

    def _find_file(self, filename: str) -> Optional[str]:
        """Procura um ficheiro nas pastas do PaperMind."""
        search_dirs = [ICLOUD_PROCESSED, ICLOUD_INBOX, ICLOUD_BASE]

        for base_dir in search_dirs:
            if not base_dir.exists():
                continue
            for path in base_dir.rglob("*"):
                if path.name == filename and path.is_file():
                    return str(path)

        return None

    def _write_status_json(self):
        """
        Escreve status.json na pasta iCloud para o iOS ler.
        Formato compatível com MacStatus (iCloudSync.swift).
        """
        sync = self.get_sync_status()
        last_doc = self.documents[-1].filename if self.documents else ""
        status = {
            "last_processed": self._last_sync.isoformat() if self._last_sync else "",
            "total_documents": sync.processed_count,
            "last_filename": last_doc,
            "pending_count": sync.inbox_count,
        }
        status_path = ICLOUD_BASE / "status.json"
        try:
            status_path.write_text(json.dumps(status, indent=2), encoding="utf-8")
            logger.info("status.json atualizado: %s", status_path)
        except Exception as e:
            logger.error("Erro ao escrever status.json: %s", e)

    def _copy_to_processed(self, filepath: str, filename: str, doc_type: str) -> str:
        """
        Copia o ficheiro para data/Processed/[tipo]/.
        Retorna o novo path dentro do PaperMind.
        """
        type_dir = ICLOUD_PROCESSED / doc_type.capitalize()
        type_dir.mkdir(parents=True, exist_ok=True)

        dest = type_dir / filename

        # Se já existe com o mesmo nome, adicionar sufixo
        if dest.exists():
            stem = dest.stem
            suffix = dest.suffix
            counter = 1
            while dest.exists():
                dest = type_dir / f"{stem}_{counter}{suffix}"
                counter += 1

        try:
            shutil.copy2(filepath, dest)
            logger.info("Ficheiro copiado: %s", dest)
            return str(dest)
        except Exception as e:
            logger.error("Erro ao copiar ficheiro: %s", e)
            return filepath  # fallback: usar path original

    def _text_search(self, query: str, n_results: int = 5) -> List[DocumentChunk]:
        """Busca directa por texto — prioriza chunks com a palavra mais rara."""
        cleaned = clean_query(query)
        query_words = [w.lower() for w in cleaned.split() if len(w) > 2]
        if not query_words or not self._all_chunks:
            return []

        total = len(self._all_chunks)
        word_freq = {}
        for w in query_words:
            word_freq[w] = sum(1 for c in self._all_chunks if w in c.text.lower())

        rare_words = sorted(query_words, key=lambda w: word_freq.get(w, total))
        rarest = rare_words[0]
        priority_chunks = [c for c in self._all_chunks if rarest in c.text.lower()]

        if priority_chunks:
            scored = []
            for chunk in priority_chunks:
                chunk_lower = chunk.text.lower()
                matches = sum(1 for w in query_words if w in chunk_lower)
                scored.append((matches, chunk))
            scored.sort(key=lambda x: x[0], reverse=True)
            return [chunk for _, chunk in scored[:n_results]]

        scored = []
        for chunk in self._all_chunks:
            chunk_lower = chunk.text.lower()
            matches = sum(1 for w in query_words if w in chunk_lower)
            if matches > 0:
                scored.append((matches, chunk))

        scored.sort(key=lambda x: x[0], reverse=True)
        return [chunk for _, chunk in scored[:n_results]]

    def ingest_file(
        self, filepath: str, original_name: Optional[str] = None, skip_copy: bool = False
    ) -> UploadResponse:
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
            elif path.suffix.lower() == ".docx":
                chunks = process_docx(filepath)
            elif path.suffix.lower() in {".txt", ".md"}:
                chunks = process_txt(filepath)
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

            # Classificar tipo — enviar mais texto para melhor classificação
            try:
                classify_text = " ".join(c.text for c in chunks[:3])  # primeiros 3 chunks
                cat_prompt = self.category_manager.get_classify_prompt_categories()
                cat_names = self.category_manager.get_all_names()
                doc_type = self.llm.classify(classify_text, categories_prompt=cat_prompt, valid_names=cat_names, filename=name)
                logger.info("Auto-classificação: %s → %s", name, doc_type)
            except Exception as e:
                logger.warning("Erro na auto-classificação de %s: %s", name, e)
                doc_type = "outro"

            # Copiar ficheiro para dentro do PaperMind (skip em reindex)
            if skip_copy:
                stored_path = filepath
            else:
                stored_path = self._copy_to_processed(filepath, name, doc_type)

            for chunk in chunks:
                chunk.source = name

            # Guardar com tipo e path no metadata
            self.vector_store.add_chunks(chunks, doc_type=doc_type, file_path=stored_path)
            self.hybrid_search.add_chunks(chunks)
            self._all_chunks.extend(chunks)

            self.documents = [d for d in self.documents if d.filename != name]

            self.documents.append(
                DocumentInfo(
                    filename=name,
                    total_chunks=len(chunks),
                    document_type=doc_type,
                    date_added=datetime.now(),
                    file_path=stored_path,
                )
            )

            self._last_sync = datetime.now()
            self._write_status_json()

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

    def update_category(self, filename: str, new_category: str) -> dict:
        """Atualiza a categoria de um documento."""
        doc = next((d for d in self.documents if d.filename == filename), None)
        if not doc:
            return {"status": "error", "error": "Document not found"}

        # Atualizar no ChromaDB
        self.vector_store.update_doc_type(filename, new_category)

        # Atualizar na lista em memória
        idx = next(i for i, d in enumerate(self.documents) if d.filename == filename)
        old_type = self.documents[idx].document_type
        self.documents[idx] = DocumentInfo(
            filename=doc.filename,
            total_chunks=doc.total_chunks,
            document_type=new_category,
            date_added=doc.date_added,
            file_path=doc.file_path,
        )

        logger.info("Categoria atualizada: %s → %s → %s", filename, old_type, new_category)
        return {"status": "updated", "filename": filename, "old_category": old_type, "new_category": new_category}

    def delete_document(self, filename: str) -> dict:
        """Remove um documento: chunks do ChromaDB, índice BM25, e ficheiro."""
        # 1. Encontrar o path antes de apagar
        doc = next((d for d in self.documents if d.filename == filename), None)
        file_path = doc.file_path if doc else None

        # 2. Remover do ChromaDB
        self.vector_store.delete_document(filename)

        # 3. Remover da lista de documentos
        self.documents = [d for d in self.documents if d.filename != filename]

        # 4. Remover chunks da memória e reconstruir BM25
        self._all_chunks = [c for c in self._all_chunks if c.source != filename]
        self.hybrid_search.build_index(self._all_chunks)

        # 5. Apagar ficheiro físico (se está dentro do PaperMind)
        file_deleted = False
        if file_path and Path(file_path).exists():
            papermind_data = str(ICLOUD_BASE)
            if file_path.startswith(papermind_data):
                try:
                    Path(file_path).unlink()
                    file_deleted = True
                    logger.info("Ficheiro apagado: %s", file_path)
                except Exception as e:
                    logger.error("Erro ao apagar ficheiro: %s", e)

        logger.info("Documento removido: %s (ficheiro apagado: %s)", filename, file_deleted)
        return {
            "status": "deleted",
            "filename": filename,
            "file_deleted": file_deleted,
        }

    def ask(self, question: str) -> AskResponse:
        start = time.time()
        total_chunks = len(self._all_chunks)

        # ── Small corpus optimization ──
        # If we have ≤ 50 chunks total, send EVERYTHING to the LLM.
        # No point being selective with a 4-page document.
        if total_chunks <= 50 and total_chunks > 0:
            # Sort by source then page/chunk for coherent reading order
            combined = sorted(
                self._all_chunks,
                key=lambda c: (c.source, c.page_number, c.chunk_index),
            )
            logger.info(
                "[RAG] Small corpus mode — sending ALL %d chunks to LLM",
                len(combined),
            )
        else:
            # ── Normal search mode for larger corpora ──
            text_chunks = self._text_search(question, n_results=6)
            semantic_results = self.vector_store.search(question, n_results=25)
            hybrid_chunks = self.hybrid_search.search(
                query=question,
                n_results=20,
                semantic_results=semantic_results,
            )

            # Also extract pure semantic chunks (high confidence)
            semantic_chunks = [chunk for chunk, score in semantic_results if score > 0.3]

            # Combine: hybrid first, then semantic, then text search supplements
            combined = []
            seen_keys = set()

            for chunk in hybrid_chunks:
                key = f"{chunk.source}_p{chunk.page_number}_c{chunk.chunk_index}"
                if key not in seen_keys:
                    seen_keys.add(key)
                    combined.append(chunk)

            for chunk in semantic_chunks:
                key = f"{chunk.source}_p{chunk.page_number}_c{chunk.chunk_index}"
                if key not in seen_keys:
                    seen_keys.add(key)
                    combined.append(chunk)

            for chunk in text_chunks:
                key = f"{chunk.source}_p{chunk.page_number}_c{chunk.chunk_index}"
                if key not in seen_keys:
                    seen_keys.add(key)
                    combined.append(chunk)

            # Limit per document — generous cap
            MAX_CHUNKS_PER_DOC = 15
            doc_counts: dict = {}
            balanced = []
            for chunk in combined:
                count = doc_counts.get(chunk.source, 0)
                if count < MAX_CHUNKS_PER_DOC:
                    balanced.append(chunk)
                    doc_counts[chunk.source] = count + 1

            combined = balanced[:25]

            logger.info(
                "[RAG] Search results — hybrid: %d, semantic: %d, text: %d → combined: %d",
                len(hybrid_chunks), len(semantic_chunks), len(text_chunks), len(combined),
            )

        if not combined:
            return AskResponse(
                question=question,
                answer="Não encontrei informação relevante nos documentos indexados.",
                sources=[],
                processing_time_ms=int((time.time() - start) * 1000),
            )

        # Contexto com limite de tamanho
        context_parts = []
        total_chars = 0
        for c in combined:
            part = f"[{c.source}, p.{c.page_number}]: {c.text}"
            if total_chars + len(part) > MAX_CONTEXT_CHARS:
                remaining = MAX_CONTEXT_CHARS - total_chars
                if remaining > 100:
                    context_parts.append(part[:remaining] + "...")
                break
            context_parts.append(part)
            total_chars += len(part)

        context = "\n\n".join(context_parts)

        logger.info("[RAG] Pergunta: '%s' | Chunks: %d | Contexto: %d chars", question[:60], len(combined), len(context))

        answer = self.llm.ask(question, context)

        # Sources dedup por ficheiro+página
        seen_sources = set()
        sources = []
        for c in combined:
            source_key = f"{c.source}_p{c.page_number}"
            if source_key not in seen_sources:
                seen_sources.add(source_key)
                sources.append(
                    Source(
                        filename=c.source,
                        page_number=c.page_number,
                        excerpt=c.text[:150] + "..." if len(c.text) > 150 else c.text,
                        relevance_score=0.0,
                    )
                )

        elapsed_ms = int((time.time() - start) * 1000)
        logger.info("[RAG] Resposta em %dms | Sources: %d", elapsed_ms, len(sources))

        return AskResponse(
            question=question,
            answer=answer,
            sources=sources,
            processing_time_ms=elapsed_ms,
        )

    def process_inbox(self) -> List[str]:
        ICLOUD_INBOX.mkdir(parents=True, exist_ok=True)
        processed = []
        for f in sorted(ICLOUD_INBOX.iterdir()):
            if f.suffix.lower() in {".pdf", ".jpg", ".jpeg", ".png", ".heic", ".docx", ".txt", ".md"}:
                result = self.ingest_file(str(f), original_name=f.name)
                if result.status == "success":
                    processed.append(result.filename)
                    # Limpar ficheiro da Inbox após processamento bem-sucedido
                    try:
                        f.unlink()
                        # Também remover .txt de OCR se existir
                        txt_sidecar = f.with_suffix(".txt")
                        if txt_sidecar.exists():
                            txt_sidecar.unlink()
                        logger.info("Inbox cleanup: %s removido", f.name)
                    except Exception as e:
                        logger.warning("Não consegui apagar %s da Inbox: %s", f.name, e)

        # Atualizar status.json para o iOS
        if processed:
            self._write_status_json()

        return processed

    def reindex_all(self) -> dict:
        """Re-indexa todos os documentos com os novos embeddings e chunk size."""
        docs_to_reindex = []
        for doc in self.documents:
            if doc.file_path and Path(doc.file_path).exists():
                docs_to_reindex.append((doc.filename, doc.file_path))

        if not docs_to_reindex:
            return {"status": "nothing_to_reindex", "count": 0}

        logger.info("Reindexing %d documentos...", len(docs_to_reindex))

        # Clear everything
        self.vector_store.delete_all()
        self._all_chunks = []
        old_docs = list(self.documents)
        self.documents = []

        reindexed = []
        errors = []
        for name, path in docs_to_reindex:
            try:
                result = self.ingest_file(path, original_name=name, skip_copy=True)
                if result.status == "success":
                    reindexed.append(name)
                else:
                    errors.append(f"{name}: {result.error}")
            except Exception as e:
                errors.append(f"{name}: {str(e)}")

        # Rebuild BM25
        self.hybrid_search.build_index(self._all_chunks)

        logger.info(
            "Reindex completo: %d ok, %d erros", len(reindexed), len(errors)
        )

        return {
            "status": "reindexed",
            "reindexed": len(reindexed),
            "errors": errors,
            "total_chunks": len(self._all_chunks),
        }

    def reclassify_all(self) -> dict:
        """Re-classifica todos os documentos usando o LLM com as categorias atuais."""
        if not self.documents:
            return {"status": "nothing_to_reclassify", "count": 0}

        cat_prompt = self.category_manager.get_classify_prompt_categories()
        cat_names = self.category_manager.get_all_names()

        results = []
        for doc in self.documents:
            # Get chunks for this document
            doc_chunks = [c for c in self._all_chunks if c.source == doc.filename]
            if not doc_chunks:
                continue

            classify_text = " ".join(c.text for c in doc_chunks[:3])

            try:
                new_type = self.llm.classify(classify_text, categories_prompt=cat_prompt, valid_names=cat_names, filename=doc.filename)
            except Exception:
                new_type = "outro"

            old_type = doc.document_type
            if new_type != old_type:
                self.update_category(doc.filename, new_type)
                results.append({"filename": doc.filename, "old": old_type, "new": new_type})
                logger.info("Reclassificado: %s: %s → %s", doc.filename, old_type, new_type)
            else:
                results.append({"filename": doc.filename, "old": old_type, "new": new_type, "unchanged": True})

        changed = [r for r in results if not r.get("unchanged")]
        logger.info("Reclassificação: %d documentos, %d alterados", len(results), len(changed))

        return {
            "status": "reclassified",
            "total": len(results),
            "changed": len(changed),
            "details": results,
        }

    def list_documents(self) -> List[dict]:
        return [doc.model_dump() for doc in self.documents]

    def get_sync_status(self) -> SyncStatus:
        ICLOUD_INBOX.mkdir(parents=True, exist_ok=True)
        inbox_files = [
            f for f in ICLOUD_INBOX.iterdir()
            if f.suffix.lower() in {".pdf", ".jpg", ".jpeg", ".png", ".heic", ".docx", ".txt", ".md"}
        ]
        return SyncStatus(
            inbox_count=len(inbox_files),
            processed_count=self.vector_store.count,
            last_sync=self._last_sync,
        )
