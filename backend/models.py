"""PaperMind — Pydantic data models."""

from pydantic import BaseModel
from typing import List, Optional
from datetime import datetime


class DocumentChunk(BaseModel):
    text: str
    source: str
    page_number: int
    chunk_index: int


class UploadResponse(BaseModel):
    status: str
    filename: str
    total_chunks: int
    document_type: Optional[str] = None
    error: Optional[str] = None


class Source(BaseModel):
    filename: str
    page_number: int  # para deep linking no PDFKit
    excerpt: str
    relevance_score: float


class AskResponse(BaseModel):
    question: str
    answer: str
    sources: List[Source]
    processing_time_ms: int


class DocumentInfo(BaseModel):
    filename: str
    total_chunks: int
    document_type: str
    date_added: datetime
    file_path: str


class SyncStatus(BaseModel):
    """v3.0 — estado de sincronização iPhone ↔ Mac."""
    inbox_count: int        # ficheiros aguardam processamento
    processed_count: int    # total indexados
    last_sync: Optional[datetime] = None
