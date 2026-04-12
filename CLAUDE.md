# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

PaperMind is a privacy-first, offline RAG (Retrieval-Augmented Generation) document management system. It has a Python FastAPI backend, a macOS SwiftUI frontend, and an iOS SwiftUI companion app. All computation is local — no cloud dependencies except iCloud Drive as a file transport layer between iPhone and Mac.

**Language:** UI, logs, prompts, and document classification are in Portuguese.

## Architecture

```
iPhone (iOS App)
  → VNDocumentCamera captures → OCR → saves to iCloud Inbox/
      ↓ (iCloud Drive sync)
Mac Backend (Python FastAPI on port 8000)
  → InboxWatcher polls Inbox/ → PDF/OCR processing → chunking (200 words, 80 overlap)
  → SentenceTransformers embeddings → ChromaDB + BM25 index
  → Auto-classifies into categories (médico, financeiro, legal, pessoal, outro)
  → Moves files to Processed/<category>/
      ↓
Mac Frontend (SwiftUI, 3-panel layout)
  → Sidebar (doc list) | PDF viewer (deep-linked) | Chat (SSE streaming from Ollama)
```

**Key integration point:** The macOS app auto-launches the Python backend via `BackendManager.swift`, which discovers `.venv/bin/python` and runs uvicorn. The backend and frontend communicate via REST/SSE on localhost:8000.

**Search pipeline:** Hybrid search combines BM25 keyword scores (0.4 weight) and semantic cosine similarity (0.6 weight). Small corpora (≤50 chunks) bypass search and send all context. Context is capped at 40KB before sending to LLM.

**OCR strategy (pdf_processor.py):** 3-layer fallback — digital text extraction (PyMuPDF) → Apple Vision CLI (`ocr_tool`) → Tesseract. Quality scored 0.0–1.0.

**LLM:** Ollama running locally (default model: Gemma4-nothink). Response validation rejects empty/degenerate answers. Supports thinking block extraction.

## Common Commands

```bash
# Backend
source .venv/bin/activate
uvicorn backend.api:app --reload --port 8000

# Tests
pytest tests/ -v

# Regenerate Xcode project from project.yml
xcodegen generate

# Build macOS app (or open in Xcode: PaperMindMac target)
open PaperMind.xcodeproj
```

## Data Paths

All data lives under `data/` (hardcoded to `~/Developer/PaperMind/data/`):
- `data/Database/` — ChromaDB persistent vector store
- `data/Inbox/` — iCloud inbox (iPhone deposits scans here)
- `data/Processed/<category>/` — Organized documents post-ingestion
- `data/status.json` — Sync status read by the iOS app
- `data/categories.json` — Custom user-defined categories

## Backend ↔ Frontend Contract

Swift models in `Shared/Models/AppModels.swift` must stay in sync with Pydantic models in `backend/models.py`. Key shared types: `AskResponse`, `UploadResponse`, `DocumentInfo`, `Source`, `SyncStatus`, `CategoryInfo`.

SSE streaming endpoint is `GET /ask/stream` — the Swift client (`APIClient.swift`) parses `data:` lines and renders word-by-word. Sources are injected as a final JSON payload.

## Key Conventions

- Embedding model is `paraphrase-multilingual-MiniLM-L12-v2` (multilingual, supports Portuguese + English)
- Categories are dynamic: 5 built-in (médico, financeiro, legal, pessoal, outro) + custom via `categories.py`/`categories.json`
- Source deduplication is by filename + page_number
- Backend process lifecycle: SIGTERM with 5s grace period → SIGKILL
- iCloud container ID: `iCloud.com.frederico.papermind`
- macOS app sandbox: network client enabled, read-only user file access
