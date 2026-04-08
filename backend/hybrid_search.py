"""
PaperMind — Hybrid Search (BM25 + semântica).
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
        self.corpus = list(chunks)  # cópia para evitar referência partilhada
        tokenized = [chunk.text.lower().split() for chunk in self.corpus]
        if tokenized:
            self.bm25 = BM25Okapi(tokenized)
        else:
            self.bm25 = None

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
        if not self.bm25 or not self.corpus:
            return []

        query_tokens = query.lower().split()
        bm25_scores = self.bm25.get_scores(query_tokens)

        # Garantir que os tamanhos são iguais
        corpus_len = len(self.corpus)
        scores_len = len(bm25_scores)

        if scores_len != corpus_len:
            # Reconstruir índice se desalinhado
            self.build_index(self.corpus)
            bm25_scores = self.bm25.get_scores(query_tokens)
            scores_len = len(bm25_scores)

        max_bm25 = max(bm25_scores) if max(bm25_scores) > 0 else 1
        bm25_normalized = [s / max_bm25 for s in bm25_scores]

        if semantic_results:
            semantic_map = {text: score for text, score in semantic_results}
            final_scores = []
            for i in range(min(scores_len, corpus_len)):
                bm25_score = bm25_normalized[i] if i < scores_len else 0.0
                sem_score = semantic_map.get(self.corpus[i].text, 0.0)
                final_scores.append(
                    self.keyword_weight * bm25_score
                    + self.semantic_weight * sem_score
                )
        else:
            final_scores = list(bm25_normalized[:corpus_len])

        ranked = sorted(
            enumerate(final_scores), key=lambda x: x[1], reverse=True
        )[:n_results]

        return [self.corpus[i] for i, _ in ranked if i < corpus_len]
