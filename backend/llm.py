"""
PaperMind — Local LLM via MLX with auto-off.

Carrega o modelo em RAM apenas quando necessário.
Descarrega automaticamente após X minutos de inatividade.
"""

import threading
from mlx_lm import load, generate


def trim_repetition(text: str) -> str:
    """Remove texto repetido da resposta do LLM."""
    sentences = text.split(". ")
    if len(sentences) <= 2:
        return text

    seen = set()
    unique = []
    for s in sentences:
        # Normalizar para comparação
        normalized = s.strip().lower()
        if normalized and normalized not in seen:
            seen.add(normalized)
            unique.append(s)

    return ". ".join(unique)


class LocalLLM:
    def __init__(
        self,
        model_name: str = "mlx-community/Llama-3.2-3B-Instruct-4bit",
        auto_off_minutes: int = 5,
    ):
        self.model_name = model_name
        self.model = None
        self.tokenizer = None
        self.is_loaded = False
        self.auto_off_minutes = auto_off_minutes
        self._timer = None
        self.load()

    def load(self):
        """Carrega modelo e tokenizer em RAM."""
        if not self.is_loaded:
            print(f"A carregar {self.model_name}...")
            self.model, self.tokenizer = load(self.model_name)
            self.is_loaded = True
            self._reset_timer()

    def unload(self):
        """Liberta RAM descarregando o modelo."""
        if self.is_loaded:
            del self.model
            del self.tokenizer
            self.model = None
            self.tokenizer = None
            self.is_loaded = False
            if self._timer:
                self._timer.cancel()
            print("Modelo descarregado. RAM libertada.")

    def _reset_timer(self):
        """Reinicia o temporizador de auto-off."""
        if self._timer:
            self._timer.cancel()
        self._timer = threading.Timer(
            self.auto_off_minutes * 60, self.unload
        )
        self._timer.daemon = True
        self._timer.start()

    def ask(self, prompt: str, context: str = "") -> str:
        """Responde a uma pergunta com base no contexto dos documentos."""
        if not self.is_loaded:
            self.load()
        self._reset_timer()

        full_prompt = f"""<|begin_of_text|><|start_header_id|>system<|end_header_id|>
És um assistente que responde APENAS com base nos documentos fornecidos.
Se a resposta não estiver nos documentos, diz "Não encontrei essa informação nos documentos."
Responde em português. Sê conciso: máximo 3 frases.
Não repitas frases.<|eot_id|><|start_header_id|>user<|end_header_id|>
Documentos:
{context}

Pergunta: {prompt}<|eot_id|><|start_header_id|>assistant<|end_header_id|>
"""

        raw = generate(
            self.model, self.tokenizer, prompt=full_prompt, max_tokens=200
        )
        return trim_repetition(raw)

    def classify(self, text: str) -> str:
        """Classifica o tipo de documento."""
        if not self.is_loaded:
            self.load()

        prompt = f"""<|begin_of_text|><|start_header_id|>system<|end_header_id|>
Classifica o documento. Responde APENAS com uma palavra.<|eot_id|><|start_header_id|>user<|end_header_id|>
Opções: contrato | fatura | recibo | carta | relatorio | identificacao | outro

Texto: {text[:300]}

Tipo:<|eot_id|><|start_header_id|>assistant<|end_header_id|>
"""

        result = generate(
            self.model, self.tokenizer, prompt=prompt, max_tokens=10
        )
        return result.strip().lower()

    def suggest_filename(self, text: str, doc_type: str) -> str:
        """v3.0 — Sugere nome inteligente para o ficheiro."""
        if not self.is_loaded:
            self.load()

        prompt = f"""<|begin_of_text|><|start_header_id|>system<|end_header_id|>
Sugere um nome de ficheiro. Formato: Tipo_Entidade_Data (ex: Fatura_EDP_Marco2026)
Sem espaços, sem acentos, sem extensão. Responde APENAS com o nome.<|eot_id|><|start_header_id|>user<|end_header_id|>
Tipo: {doc_type}
Texto: {text[:200]}

Nome:<|eot_id|><|start_header_id|>assistant<|end_header_id|>
"""

        result = generate(
            self.model, self.tokenizer, prompt=prompt, max_tokens=20
        )
        return result.strip()