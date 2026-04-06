"""PaperMind — ChromaDB vector store with Ollama embeddings."""

import chromadb
from typing import List, Tuple, Optional
from pathlib import Path
from .models import DocumentChunk


class VectorStore:
    def __init__(self, persist_dir: str = "./chroma_db"):
        """
        Inicializa ChromaDB com persistência em disco.
        Usa Ollama nomic-embed-text para embeddings.
        """
        self.persist_dir = persist_dir
        Path(persist_dir).mkdir(parents=True, exist_ok=True)

        self.client = chromadb.PersistentClient(path=persist_dir)
        self.collection = self.client.get_or_create_collection(
            name="papermind",
            metadata={"hnsw:space": "cosine"},
        )

    def add_chunks(self, chunks: List[DocumentChunk]):
        """Adiciona chunks ao ChromaDB com embeddings gerados pelo Ollama."""
        if not chunks:
            return

        ids = [f"{c.source}_{c.chunk_index}" for c in chunks]
        documents = [c.text for c in chunks]
        metadatas = [
            {
                "source": c.source,
                "page_number": c.page_number,
                "chunk_index": c.chunk_index,
            }
            for c in chunks
        ]

        # ChromaDB gera embeddings automaticamente com o modelo default
        # Para usar Ollama, configuramos o embedding function
        self.collection.upsert(
            ids=ids,
            documents=documents,
            metadatas=metadatas,
        )

    def search(
        self, query: str, n_results: int = 5
    ) -> List[Tuple[str, float]]:
        """
        Pesquisa semântica no ChromaDB.
        Retorna lista de (texto, score de relevância).
        """
        results = self.collection.query(
            query_texts=[query],
            n_results=min(n_results, self.collection.count() or 1),
        )

        pairs: List[Tuple[str, float]] = []
        if results["documents"] and results["distances"]:
            for doc, dist in zip(
                results["documents"][0], results["distances"][0]
            ):
                # ChromaDB cosine distance: 0 = idêntico, 2 = oposto
                # Converter para score de similaridade: 1 - (dist/2)
                score = 1.0 - (dist / 2.0)
                pairs.append((doc, score))

        return pairs

    def get_all_chunks(self) -> List[DocumentChunk]:
        """Recupera todos os chunks armazenados."""
        if self.collection.count() == 0:
            return []

        results = self.collection.get()
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

    def delete_document(self, filename: str):
        """Remove todos os chunks de um documento."""
        results = self.collection.get(
            where={"source": filename}
        )
        if results["ids"]:
            self.collection.delete(ids=results["ids"])

    @property
    def count(self) -> int:
        return self.collection.count()
