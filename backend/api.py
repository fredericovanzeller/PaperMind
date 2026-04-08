"""
PaperMind — FastAPI server v3.3.

v3.3:
  - Settings API: modelo, idioma, iCloud path configuráveis
  - status.json exportado para iCloud após cada ingestão
  - Inbox cleanup após processamento
  - Logging estruturado
v3.2:
  - DELETE /documents/{filename} — apagar documentos
  - SSE com error handling robusto
"""

import logging
from fastapi import FastAPI, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
import shutil
import tempfile
import json
import asyncio
import traceback
from urllib.parse import unquote

from .rag_engine import RAGEngine
from .models import SyncStatus

logger = logging.getLogger("papermind.api")

app = FastAPI(title="PaperMind API", version="3.3")
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
    try:
        return engine.ask(data.question)
    except Exception as e:
        logger.error("Erro em /ask: %s", e)
        traceback.print_exc()
        return {
            "question": data.question,
            "answer": "Ocorreu um erro ao processar a pergunta. Tenta novamente.",
            "sources": [],
            "processing_time_ms": 0,
        }


# ── Pergunta com SSE streaming (palavra a palavra) ──────────


@app.get("/ask/stream")
async def ask_stream(question: str):
    async def generate():
        try:
            result = engine.ask(question)
            answer_text = result.answer or "Não consegui gerar uma resposta. Tenta novamente."

            for word in answer_text.split():
                yield f"data: {json.dumps({'type': 'token', 'content': word + ' '})}\n\n"
                await asyncio.sleep(0.02)

            sources_payload = {
                "type": "sources",
                "sources": [s.model_dump() for s in result.sources],
            }
            yield f"data: {json.dumps(sources_payload)}\n\n"
            yield "data: [DONE]\n\n"

        except Exception as e:
            logger.error("Erro em /ask/stream: %s", e)
            traceback.print_exc()
            error_msg = "Ocorreu um erro ao processar a pergunta. Tenta novamente."
            yield f"data: {json.dumps({'type': 'token', 'content': error_msg})}\n\n"
            yield f"data: {json.dumps({'type': 'sources', 'sources': []})}\n\n"
            yield "data: [DONE]\n\n"

    return StreamingResponse(generate(), media_type="text/event-stream")


# ── Apagar documento ────────────────────────────────────────


@app.delete("/documents/{filename:path}")
async def delete_document(filename: str):
    """Remove um documento do índice e apaga a cópia local."""
    decoded = unquote(filename)
    result = engine.delete_document(decoded)
    return result


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


# ── Settings (recebidos do SwiftUI SettingsView) ──────────────


class SettingsRequest(BaseModel):
    model_name: str | None = None
    response_language: str | None = None
    auto_off_minutes: int | None = None


@app.get("/settings")
async def get_settings():
    """Retorna configuração atual do backend."""
    return {
        "model_name": engine.llm.model_name,
        "response_language": getattr(engine.llm, "response_language", "auto"),
        "auto_off_minutes": engine.llm.auto_off_minutes,
    }


@app.put("/settings")
async def update_settings(data: SettingsRequest):
    """Atualiza configuração em runtime (chamado pelo SettingsView)."""
    changed = []

    if data.model_name and data.model_name != engine.llm.model_name:
        old = engine.llm.model_name
        engine.llm.model_name = data.model_name
        changed.append(f"model: {old} → {data.model_name}")
        logger.info("Modelo alterado: %s → %s", old, data.model_name)

    if data.response_language is not None:
        engine.llm.response_language = data.response_language
        changed.append(f"language: {data.response_language}")

    if data.auto_off_minutes is not None:
        engine.llm.auto_off_minutes = data.auto_off_minutes
        changed.append(f"auto_off: {data.auto_off_minutes}min")

    return {"status": "updated", "changes": changed}


# ── Health & Info ────────────────────────────────────────────


@app.get("/health")
async def health():
    return {"status": "ok", "model_loaded": engine.llm.is_loaded}


@app.get("/documents")
async def documents():
    return {"documents": engine.list_documents()}
