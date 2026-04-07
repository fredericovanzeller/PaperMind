"""
PaperMind — Local LLM via Ollama with auto-off.

Usa Ollama para correr o modelo localmente.
"""

import requests
import threading


def trim_repetition(text: str) -> str:
    """Remove texto repetido da resposta do LLM."""
    sentences = text.split(". ")
    if len(sentences) <= 2:
        return text

    seen = set()
    unique = []
    for s in sentences:
        normalized = s.strip().lower()
        if normalized and normalized not in seen:
            seen.add(normalized)
            unique.append(s)

    return ". ".join(unique)


class LocalLLM:
    def __init__(
        self,
        model_name: str = "gemma4:e4b",
        ollama_url: str = "http://localhost:11434",
        auto_off_minutes: int = 10,
    ):
        self.model_name = model_name
        self.ollama_url = ollama_url
        self.is_loaded = True  # Ollama gere o modelo
        self.auto_off_minutes = auto_off_minutes
        self._timer = None
        print(f"LLM configurado: {self.model_name} via Ollama")

    def load(self):
        """Pré-carrega o modelo no Ollama."""
        try:
            requests.post(
                f"{self.ollama_url}/api/generate",
                json={"model": self.model_name, "prompt": "ok", "stream": False},
                timeout=120,
            )
            self.is_loaded = True
            print(f"Modelo {self.model_name} carregado.")
        except Exception as e:
            print(f"Erro ao carregar modelo: {e}")

    def unload(self):
        """Descarrega o modelo do Ollama."""
        try:
            requests.post(
                f"{self.ollama_url}/api/generate",
                json={"model": self.model_name, "keep_alive": 0},
                timeout=10,
            )
            self.is_loaded = False
            print("Modelo descarregado. RAM libertada.")
        except Exception:
            pass

    def _call_ollama(self, prompt: str, system: str = "", max_tokens: int = 500) -> str:
        """Chama o Ollama API."""
        try:
            response = requests.post(
                f"{self.ollama_url}/api/generate",
                json={
                    "model": self.model_name,
                    "prompt": prompt,
                    "system": system,
                    "stream": False,
                    "options": {
                        "num_predict": max_tokens,
                    },
                },
                timeout=300,
            )
            result = response.json()
            return result.get("response", "").strip()
        except Exception as e:
            print(f"Erro Ollama: {e}")
            return "Erro ao gerar resposta. Verifica que o Ollama está a correr."

    def ask(self, prompt: str, context: str = "") -> str:
        """Responde a uma pergunta com base no contexto dos documentos."""
        system = """És um assistente documental especializado. Responde APENAS com base nos documentos fornecidos.
Extrai informação exacta dos documentos: nomes, datas, valores, números, moradas, cláusulas.
Cita o texto relevante quando possível.
Se a resposta não estiver nos documentos, diz "Não encontrei essa informação nos documentos."
Responde em português. Sê completo mas não repitas informação."""

        user_prompt = f"""Documentos:
{context}

Pergunta: {prompt}"""

        raw = self._call_ollama(user_prompt, system=system, max_tokens=500)
        return trim_repetition(raw)

    def classify(self, text: str) -> str:
        """Classifica o tipo de documento."""
        system = "Classifica o documento. Responde APENAS com uma palavra."
        prompt = f"""Opções: contrato | fatura | recibo | carta | relatorio | identificacao | outro

Texto: {text[:300]}

Tipo:"""

        result = self._call_ollama(prompt, system=system, max_tokens=10)
        return result.strip().lower()

    def suggest_filename(self, text: str, doc_type: str) -> str:
        """v3.0 — Sugere nome inteligente para o ficheiro."""
        system = "Sugere um nome de ficheiro. Formato: Tipo_Entidade_Data (ex: Fatura_EDP_Marco2026). Sem espaços, sem acentos, sem extensão. Responde APENAS com o nome."
        prompt = f"""Tipo: {doc_type}
Texto: {text[:200]}

Nome:"""

        result = self._call_ollama(prompt, system=system, max_tokens=20)
        return result.strip()