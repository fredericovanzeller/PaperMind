"""PaperMind — ChromaDB vector store com embeddings multilingue."""

import logging
import chromadb
from chromadb.utils import embedding_functions
from typing import List, Tuple, Optional
from pathlib import Path
from .models import DocumentChunk

logger = logging.getLogger("papermind.embeddings")

# Modelo multilingue — suporta português, inglês, etc.
EMBEDDING_MODEL = "paraphrase-multilingual-MiniLM-L12-v2"


class VectorStore:
    def __init__(self, persist_dir: str = "./chroma_db"):
        self.persist_dir = persist_dir
        Path(persist_dir).mkdir(parents=True, exist_ok=True)

        self.embedding_fn = embedding_functions.SentenceTransformerEmbeddingFunction(
            model_name=EMBEDDING_MODEL
        )

        self.client = chromadb.PersistentClient(path=persist_dir)
        self.collection = self.client.get_or_create_collection(
            name="papermind_v2",
            metadata={"hnsw:space": "cosine"},
            embedding_function=self.embedding_fn,
        )

        # Migrate: if old collection exists and new one is empty, log it
        try:
            old = self.client.get_collection("papermind")
            if old.count() > 0 and self.collection.count() == 0:
                logger.warning(
                    "Coleção antiga 'papermind' tem %d chunks. "
                    "Usa /reindex para migrar para embeddings multilingue.",
                    old.count(),
                )
        except Exception:
            pass

    def add_chunks(self, chunks: List[DocumentChunk], doc_type: str = "documento", file_path: str = ""):
        """Adiciona chunks ao ChromaDB com metadata incluindo tipo e path."""
        if not chunks:
            return

        ids = [f"{c.source}_{c.chunk_index}" for c in chunks]
        documents = [c.text for c in chunks]
        metadatas = [
            {
                "source": c.source,
                "page_number": c.page_number,
                "chunk_index": c.chunk_index,
                "doc_type": doc_type,
                "file_path": file_path,
            }
            for c in chunks
        ]

        self.collection.upsert(
            ids=ids,
            documents=documents,
            metadatas=metadatas,
        )

    def search(self, query: str, n_results: int = 5) -> List[Tuple[DocumentChunk, float]]:
        """Pesquisa semântica no ChromaDB. Retorna (chunk, score) pairs."""
        count = self.collection.count()
        if count == 0:
            return []

        results = self.collection.query(
            query_texts=[query],
            n_results=min(n_results, count),
            include=["documents", "distances", "metadatas"],
        )

        pairs: List[Tuple[DocumentChunk, float]] = []
        if results["documents"] and results["distances"] and results["metadatas"]:
            for doc, dist, meta in zip(
                results["documents"][0],
                results["distances"][0],
                results["metadatas"][0],
            ):
                score = 1.0 - (dist / 2.0)
                chunk = DocumentChunk(
                    text=doc,
                    source=meta["source"],
                    page_number=meta["page_number"],
                    chunk_index=meta["chunk_index"],
                )
                pairs.append((chunk, score))

        return pairs

    def get_all_chunks(self) -> List[DocumentChunk]:
        """Recupera todos os chunks armazenados."""
        if self.collection.count() == 0:
            return []

        results = self.collection.get(include=["documents", "metadatas"])
        chunks = []
        for doc, meta in zip(
            results["documents"] or [], results["metadatas"] or []
        ):
            chunks.append(
                DocumentChunk(
                    text=doc,
                    source=meta["source"],
                    page_number=meta["page_number"],
                    chunk_index=meta["chunk_index"],
                )
            )
        return chunks

    def get_doc_types(self) -> dict:
        """Recupera o tipo de cada documento armazenado."""
        if self.collection.count() == 0:
            return {}

        results = self.collection.get(include=["metadatas"])
        doc_types = {}
        for meta in results["metadatas"] or []:
            source = meta["source"]
            doc_type = meta.get("doc_type", "documento")
            if source not in doc_types:
                doc_types[source] = doc_type

        return doc_types

    def get_doc_paths(self) -> dict:
        """Recupera o file_path de cada documento armazenado."""
        if self.collection.count() == 0:
            return {}

        results = self.collection.get(include=["metadatas"])
        doc_paths = {}
        for meta in results["metadatas"] or []:
            source = meta["source"]
            file_path = meta.get("file_path", "")
            if source not in doc_paths and file_path:
                doc_paths[source] = file_path

        return doc_paths

    def update_doc_type(self, filename: str, new_type: str):
        """Atualiza o doc_type de todos os chunks de um documento."""
        results = self.collection.get(
            where={"source": filename},
            include=["metadatas"],
        )
        if not results["ids"]:
            return

        updated_metadatas = []
        for meta in results["metadatas"]:
            meta["doc_type"] = new_type
            updated_metadatas.append(meta)

        self.collection.update(
            ids=results["ids"],
            metadatas=updated_metadatas,
        )
        logger.info("doc_type atualizado para '%s': %s (%d chunks)", filename, new_type, len(results["ids"]))

    def delete_document(self, filename: str):
        """Remove todos os chunks de um documento."""
        results = self.collection.get(
            where={"source": filename},
            include=["metadatas"],
        )
        if results["ids"]:
            self.collection.delete(ids=results["ids"])

    def delete_all(self):
        """Remove todos os chunks — usado no reindex."""
        ids = self.collection.get(include=[])["ids"]
        if ids:
            self.collection.delete(ids=ids)

    @property
    def count(self) -> int:
        return self.collection.count()
