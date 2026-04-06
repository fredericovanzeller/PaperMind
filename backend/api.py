"""
PaperMind — FastAPI server v3.0.

Endpoints:
  POST /upload         — upload manual (drag & drop no Mac)
  POST /ask            — pergunta com resposta completa
  GET  /ask/stream     — pergunta com SSE streaming (palavra a palavra)
  GET  /sync/status    — estado de sincronização (iPhone consulta)
  POST /sync/process-inbox — processar Inbox manualmente
  POST /model/unload   — libertar RAM
  POST /model/load     — recarregar modelo
  GET  /health         — health check
  GET  /documents      — listar documentos indexados
"""

from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import shutil
import tempfile
import json
import asyncio

from .rag_engine import RAGEngine
from .models import SyncStatus

app = FastAPI(title="PaperMind API", version="3.0")
engine = RAGEngine()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ── Upload manual (drag & drop no Mac) ──────────────────────


@app.post("/upload")
async def upload(file: UploadFile = File(...)):
    with tempfile.NamedTemporaryFile(
        delete=False, suffix=file.filename[-4:]
    ) as tmp:
        shutil.copyfileobj(file.file, tmp)
        result = engine.ingest_file(tmp.name, original_name=file.filename)
    return result


# ── Pergunta com resposta completa ──────────────────────────


class QuestionRequest(BaseModel):
    question: str


@app.post("/ask")
async def ask(data: QuestionRequest):
    return engine.ask(data.question)


# ── Pergunta com SSE streaming (palavra a palavra) ──────────


@app.get("/ask/stream")
async def ask_stream(question: str):
    async def generate():
        result = engine.ask(question)
        for word in result.answer.split():
            yield f"data: {json.dumps({'type': 'token', 'content': word + ' '})}\n\n"
            await asyncio.sleep(0.02)

        sources_payload = {
            "type": "sources",
            "sources": [s.model_dump() for s in result.sources],
        }
        yield f"data: {json.dumps(sources_payload)}\n\n"
        yield "data: [DONE]\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")


# ── Sync status (iPhone consulta isto) ──────────────────────


@app.get("/sync/status", response_model=SyncStatus)
async def sync_status():
    return engine.get_sync_status()


# ── Processar Inbox manualmente (trigger do Mac) ────────────


@app.post("/sync/process-inbox")
async def process_inbox():
    results = engine.process_inbox()
    return {"processed": len(results), "files": results}


# ── Gestão do modelo ────────────────────────────────────────


@app.post("/model/unload")
async def unload_model():
    engine.llm.unload()
    return {"status": "unloaded"}


@app.post("/model/load")
async def load_model():
    engine.llm.load()
    return {"status": "loaded"}


# ── Health & Info ────────────────────────────────────────────


@app.get("/health")
async def health():
    return {"status": "ok", "model_loaded": engine.llm.is_loaded}


@app.get("/documents")
async def documents():
    return {"documents": engine.list_documents()}
