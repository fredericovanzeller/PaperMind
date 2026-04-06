"""
PaperMind — Hybrid Search (BM25 + semântica).

Porquê híbrido?
- "fatura EDP março 2024" → BM25 encontra termos exactos
- "quanto paguei de electricidade?" → semântica percebe contexto
Juntos cobrem ambos os casos.
"""

from rank_bm25 import BM25Okapi
from typing import List, Tuple, Optional
from .models import DocumentChunk


class HybridSearch:
    def __init__(self, semantic_weight: float = 0.6):
        self.semantic_weight = semantic_weight
        self.keyword_weight = 1.0 - semantic_weight
        self.bm25: Optional[BM25Okapi] = None
        self.corpus: List[DocumentChunk] = []

    def build_index(self, chunks: List[DocumentChunk]):
        """Reconstrói o índice BM25 a partir de todos os chunks."""
        self.corpus = chunks
        tokenized = [chunk.text.lower().split() for chunk in chunks]
        if tokenized:
            self.bm25 = BM25Okapi(tokenized)

    def add_chunks(self, new_chunks: List[DocumentChunk]):
        """Adiciona novos chunks e reconstrói o índice."""
        self.corpus.extend(new_chunks)
        self.build_index(self.corpus)

    def search(
        self,
        query: str,
        n_results: int = 5,
        semantic_results: Optional[List[Tuple[str, float]]] = None,
    ) -> List[DocumentChunk]:
        """
        Pesquisa híbrida: combina scores BM25 com scores semânticos.

        Args:
            query: pergunta do utilizador
            n_results: número de resultados a devolver
            semantic_results: lista de (texto, score) do ChromaDB
        """
        if not self.bm25 or not self.corpus:
            return []

        # BM25 scores
        query_tokens = query.lower().split()
        bm25_scores = self.bm25.get_scores(query_tokens)
        max_bm25 = max(bm25_scores) if max(bm25_scores) > 0 else 1
        bm25_normalized = [s / max_bm25 for s in bm25_scores]

        # Combinar com semântica se disponível
        if semantic_results:
            semantic_map = {text: score for text, score in semantic_results}
            final_scores = [
                self.keyword_weight * bm25_normalized[i]
                + self.semantic_weight * semantic_map.get(chunk.text, 0.0)
                for i, chunk in enumerate(self.corpus)
            ]
        else:
            final_scores = bm25_normalized

        # Ordenar por score e devolver top N
        ranked = sorted(
            enumerate(final_scores), key=lambda x: x[1], reverse=True
        )[:n_results]

        return [self.corpus[i] for i, _ in ranked]
