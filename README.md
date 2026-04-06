# PaperMind

**Fotografa qualquer documento com o iPhone. Quando abrires o Mac, já está indexado. Faz perguntas sobre ele. Tudo no teu dispositivo. Nada na cloud de ninguém.**

## O que é

PaperMind é uma app macOS + iOS de RAG (Retrieval-Augmented Generation) para documentos pessoais. Funciona 100% offline — o processamento acontece no teu Mac com modelos locais via MLX.

## Como funciona

```
📱 iPhone (campo)          ☁️ iCloud Drive          💻 Mac (base)
│                          │                         │
│ Fotografa documentos     │                         │
│ OCR em tempo real        │                         │
│ Guarda em Inbox/ ────────►                         │
│                          │ FSEvents detecta ───────►
│                          │                         │ RAG Engine
│                          │                         │ Chunking + Embeddings
│                          │                         │ ChromaDB
│                          │◄──── status.json ───────│
│◄─────────────────────────│                         │
│ "Fatura EDP indexada ✓"  │                         │
```

## Stack

| Componente | Tecnologia | Onde corre |
|---|---|---|
| UI Mac | SwiftUI | Mac |
| UI iOS | SwiftUI | iPhone |
| PDF Viewer | PDFKit + deep linking | Mac |
| Scanner | VNDocumentCamera | iPhone |
| OCR | Apple Vision | Ambos |
| LLM | MLX + Llama 3.2 | Mac |
| Embeddings | Ollama nomic-embed-text | Mac |
| Vector Search | ChromaDB | Mac |
| Keyword Search | BM25 (rank-bm25) | Mac |
| API | FastAPI + SSE | Mac |
| Sincronização | iCloud Drive | Cloud privada Apple |

## Requisitos

- macOS 14+ (Sonoma)
- iOS 17+
- Python 3.11+
- Ollama
- ~8 GB RAM livres (para o modelo LLM)

## Setup

```bash
# 1. Clonar
git clone https://github.com/SEU_USERNAME/PaperMind.git
cd PaperMind

# 2. Ambiente Python
python3.11 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt

# 3. Modelo LLM
python3 -m mlx_lm.generate \
  --model mlx-community/Llama-3.2-3B-Instruct-4bit \
  --prompt "Olá"

# 4. Embeddings
ollama serve &
ollama pull nomic-embed-text

# 5. Iniciar backend
uvicorn backend.api:app --reload --port 8000

# 6. Abrir Xcode
open PaperMind.xcodeproj
```

## Testar

```bash
# Upload
curl -X POST "http://localhost:8000/upload" \
  -F "file=@~/Documents/contrato.pdf"

# Perguntar
curl -X POST "http://localhost:8000/ask" \
  -H "Content-Type: application/json" \
  -d '{"question": "Qual é o valor mensal do contrato?"}'

# Sync status
curl "http://localhost:8000/sync/status"
```

## Privacidade

- Zero dados enviados para servidores externos
- LLM corre localmente via MLX (Apple Silicon)
- Embeddings locais via Ollama
- iCloud Drive usado apenas como transporte iPhone → Mac (encriptado pela Apple)
- Sem telemetria, sem analytics, sem tracking

## Licença

MIT

---

*PaperMind v3.0 — Frederico Van Zeller — JHU Applied Generative AI — Abril 2026*
