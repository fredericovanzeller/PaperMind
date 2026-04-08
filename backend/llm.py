"""
PaperMind — Local LLM via Ollama.

Alterações v3.3:
  - response_language configurável (auto/pt/en)
  - model_name alterável em runtime
v3.1:
  - Validação de respostas vazias/degeneradas no ask()
  - Logging estruturado para debug
  - Timeout com mensagens claras
  - suggest_filename() com sanitização
"""

import logging
import re
import requests

logger = logging.getLogger("papermind.llm")


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
        response_language: str = "auto",
    ):
        self.model_name = model_name
        self.ollama_url = ollama_url
        self.is_loaded = True
        self.auto_off_minutes = auto_off_minutes
        self.response_language = response_language
        logger.info("LLM configurado: %s via Ollama", self.model_name)

    def load(self):
        try:
            requests.post(
                f"{self.ollama_url}/api/generate",
                json={"model": self.model_name, "prompt": "ok", "stream": False},
                timeout=120,
            )
            self.is_loaded = True
        except Exception as e:
            logger.error("Erro ao carregar modelo: %s", e)

    def unload(self):
        try:
            requests.post(
                f"{self.ollama_url}/api/generate",
                json={"model": self.model_name, "keep_alive": 0},
                timeout=10,
            )
            self.is_loaded = False
            logger.info("Modelo descarregado.")
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

            if response.status_code != 200:
                logger.warning("Ollama HTTP %d: %s", response.status_code, response.text[:200])
                return ""

            result = response.json()
            content = result.get("message", {}).get("content", "").strip()
            content = clean_thinking(content)

            # Se content vazio, tentar extrair do thinking
            if not content:
                thinking = result.get("message", {}).get("thinking", "")
                content = self._extract_from_thinking(thinking)

            return content
        except requests.exceptions.Timeout:
            logger.error("Erro Ollama: timeout (300s)")
            return ""
        except requests.exceptions.ConnectionError:
            logger.error("Erro Ollama: servidor não acessível. Verifica se 'ollama serve' está a correr.")
            return ""
        except Exception as e:
            logger.error("Erro Ollama: %s", e)
            return ""

    def _extract_from_thinking(self, thinking: str) -> str:
        """Tenta extrair a resposta final do bloco de thinking."""
        if not thinking:
            return ""

        match = re.search(r'[Ss]elected?:?\s*(\w+)', thinking)
        if match:
            return match.group(1).strip()

        lines = thinking.strip().split('\n')
        for line in reversed(lines):
            line = line.strip().strip('*').strip()
            for valid in VALID_TYPES:
                if valid in line.lower():
                    return valid

        return ""

    def _is_valid_answer(self, answer: str, question: str) -> bool:
        """
        Verifica se a resposta do LLM é válida e não degenerada.
        Respostas inválidas: vazia, só uma palavra de classificação, ou eco da pergunta.
        """
        if not answer or len(answer.strip()) < 15:
            return False

        answer_lower = answer.strip().lower()

        # Resposta é apenas a pergunta repetida
        if answer_lower == question.strip().lower():
            return False

        return True

    def _language_instruction(self) -> str:
        """Retorna instrução de idioma com base na configuração."""
        if self.response_language == "pt":
            return "Responde SEMPRE em português."
        elif self.response_language == "en":
            return "Always respond in English."
        else:
            return "Responde no mesmo idioma da pergunta."

    def ask(self, prompt: str, context: str = "") -> str:
        lang = self._language_instruction()
        system = f"""Responde directamente, sem pensar passo a passo, sem usar tags.

És um assistente documental para pessoas comuns. As tuas regras:

1. INTERPRETA a pergunta de forma ampla. Se o utilizador diz "DODO", procura qualquer entidade que contenha "DODO" no nome. O mesmo para abreviaturas, nomes parciais, ou referências informais.

2. EXTRAI informação exacta dos documentos: nomes completos, datas, valores, números, moradas, NIFs, cláusulas.

3. Se encontras a informação, responde de forma clara e directa. Cita os dados exactos.

4. Se NÃO encontras a informação nos documentos fornecidos, diz "Não encontrei essa informação nos documentos."

5. {lang} Sê completo mas conciso. Não repitas informação.

6. Nunca inventes informação. Usa APENAS o que está nos documentos.

7. Se a informação estiver implícita ou podes inferir com alta confiança a partir do contexto, responde com essa inferência e indica que é baseada no documento."""

        user_prompt = f"""Documentos:
{context}

Pergunta: {prompt}"""

        raw = self._call_ollama(user_prompt, system=system, max_tokens=800)

        # Validar resposta — se degenerada, devolver mensagem clara
        if not self._is_valid_answer(raw, prompt):
            logger.warning("Resposta inválida para '%s': '%s'", prompt[:50], raw[:100])
            if not raw:
                return "Não consegui gerar uma resposta. O modelo pode estar sobrecarregado — tenta novamente."
            else:
                return "Não encontrei essa informação nos documentos indexados."

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
        name = result.strip()

        # Sanitizar: remover caracteres problemáticos
        name = re.sub(r'[^\w\-]', '_', name)
        name = re.sub(r'_+', '_', name).strip('_')

        return name if name else f"{doc_type.capitalize()}_Documento"
