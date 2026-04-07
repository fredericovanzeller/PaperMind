"""
PaperMind — Local LLM via Ollama.
"""

import re
import requests


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


def clean_thinking(text: str) -> str:
    """Remove blocos de thinking e tags da resposta."""
    text = re.sub(r'<think>.*?</think>', '', text, flags=re.DOTALL)
    text = re.sub(r'^Thinking\.\.\..*?\.\.\.done thinking\.?\s*', '', text, flags=re.DOTALL | re.IGNORECASE)
    text = re.sub(r'<[^>]+>', '', text)
    return text.strip()


VALID_TYPES = ["contrato", "fatura", "recibo", "carta", "relatorio", "identificacao", "outro"]


class LocalLLM:
    def __init__(
        self,
        model_name: str = "gemma4-nothink",
        ollama_url: str = "http://localhost:11434",
        auto_off_minutes: int = 10,
    ):
        self.model_name = model_name
        self.ollama_url = ollama_url
        self.is_loaded = True
        self.auto_off_minutes = auto_off_minutes
        print(f"LLM configurado: {self.model_name} via Ollama")

    def load(self):
        try:
            requests.post(
                f"{self.ollama_url}/api/generate",
                json={"model": self.model_name, "prompt": "ok", "stream": False},
                timeout=120,
            )
            self.is_loaded = True
        except Exception as e:
            print(f"Erro ao carregar modelo: {e}")

    def unload(self):
        try:
            requests.post(
                f"{self.ollama_url}/api/generate",
                json={"model": self.model_name, "keep_alive": 0},
                timeout=10,
            )
            self.is_loaded = False
            print("Modelo descarregado.")
        except Exception:
            pass

    def _call_ollama(self, prompt: str, system: str = "", max_tokens: int = 500) -> str:
        """Chama o Ollama API. Retorna content, ou extrai do thinking se vazio."""
        try:
            response = requests.post(
                f"{self.ollama_url}/api/chat",
                json={
                    "model": self.model_name,
                    "messages": [
                        {"role": "system", "content": system},
                        {"role": "user", "content": prompt},
                    ],
                    "stream": False,
                    "options": {
                        "num_predict": max_tokens,
                    },
                },
                timeout=300,
            )
            result = response.json()
            content = result.get("message", {}).get("content", "").strip()
            content = clean_thinking(content)

            # Se content vazio, tentar extrair do thinking
            if not content:
                thinking = result.get("message", {}).get("thinking", "")
                content = self._extract_from_thinking(thinking)

            return content
        except Exception as e:
            print(f"Erro Ollama: {e}")
            return ""

    def _extract_from_thinking(self, thinking: str) -> str:
        """Tenta extrair a resposta final do bloco de thinking."""
        if not thinking:
            return ""

        # Procurar padrões comuns de resposta final no thinking
        # "Selected: carta" ou "*Selected: carta*"
        match = re.search(r'[Ss]elected?:?\s*(\w+)', thinking)
        if match:
            return match.group(1).strip()

        # Procurar a última linha que tenha uma palavra válida
        lines = thinking.strip().split('\n')
        for line in reversed(lines):
            line = line.strip().strip('*').strip()
            for valid in VALID_TYPES:
                if valid in line.lower():
                    return valid

        return ""

    def ask(self, prompt: str, context: str = "") -> str:
        system = """Responde directamente, sem pensar passo a passo, sem usar tags.

És um assistente documental para pessoas comuns. As tuas regras:

1. INTERPRETA a pergunta de forma ampla. Se o utilizador diz "DODO", procura qualquer entidade que contenha "DODO" no nome. O mesmo para abreviaturas, nomes parciais, ou referências informais.

2. EXTRAI informação exacta dos documentos: nomes completos, datas, valores, números, moradas, NIFs, cláusulas.

3. Se encontras a informação, responde de forma clara e directa. Cita os dados exactos.

4. Se NÃO encontras a informação nos documentos fornecidos, diz "Não encontrei essa informação nos documentos."

5. Responde SEMPRE em português. Sê completo mas conciso. Não repitas informação.

6. Nunca inventes informação. Usa APENAS o que está nos documentos."""

        user_prompt = f"""Documentos:
{context}

Pergunta: {prompt}"""

        raw = self._call_ollama(user_prompt, system=system, max_tokens=500)
        return trim_repetition(raw)

    def classify(self, text: str) -> str:
        """Classifica o tipo de documento."""
        system = "Responde com UMA única palavra. Sem explicações."
        prompt = f"""Classifica este documento. Escolhe UMA palavra da lista:
contrato, fatura, recibo, carta, relatorio, identificacao, outro

Texto do documento: {text[:300]}

Resposta (uma palavra):"""

        result = self._call_ollama(prompt, system=system, max_tokens=100)
        result = result.strip().lower()

        # Extrair tipo válido da resposta
        for valid in VALID_TYPES:
            if valid in result:
                return valid

        return "outro"

    def suggest_filename(self, text: str, doc_type: str) -> str:
        system = "Responde apenas com o nome do ficheiro. Sem explicações."
        prompt = f"""Sugere um nome de ficheiro.
Formato: Tipo_Entidade_Data (ex: Fatura_EDP_Marco2026)
Sem espaços, sem acentos, sem extensão.

Tipo: {doc_type}
Texto: {text[:200]}

Nome:"""

        result = self._call_ollama(prompt, system=system, max_tokens=50)
        return result.strip()