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
import unicodedata
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


def normalize_text(text: str) -> str:
    """Remove acentos e normaliza texto para comparação (médico → medico)."""
    nfkd = unicodedata.normalize("NFD", text)
    return "".join(c for c in nfkd if unicodedata.category(c) != "Mn").lower().strip()


DEFAULT_CATEGORY_NAMES = ["medico", "financeiro", "legal", "pessoal", "outro"]


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

    def _call_ollama(self, prompt: str, system: str = "", max_tokens: int = 500, valid_names: list = None) -> str:
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
                content = self._extract_from_thinking(thinking, valid_names=valid_names)

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

    def _extract_from_thinking(self, thinking: str, valid_names: list = None) -> str:
        """Tenta extrair a resposta final do bloco de thinking."""
        if not thinking:
            return ""

        names = valid_names or []

        # Procurar padrão "Selected: X" ou "Categoria: X"
        match = re.search(r'(?:[Ss]elected?|[Cc]ategoria):?\s*(\w+)', thinking)
        if match:
            candidate = normalize_text(match.group(1))
            for valid in names:
                if candidate == valid:
                    return valid

        # Procurar nas últimas 3 linhas do thinking — apenas match exacto de palavras
        if names:
            lines = thinking.strip().split('\n')
            for line in reversed(lines[-3:]):
                words = re.findall(r'\w+', normalize_text(line))
                for valid in names:
                    if valid in words:
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

7. Se a informação estiver implícita ou podes inferir com alta confiança a partir do contexto, responde com essa inferência e indica que é baseada no documento.

8. O texto dos documentos pode vir de OCR (reconhecimento óptico) e conter erros, espaços estranhos, ou formatação estranha. Ignora esses artefactos e foca-te no conteúdo e significado. Em formulários, os números 0, 1, 2 junto a frases representam pontuações/respostas.

9. LEIA todo o contexto com atenção antes de responder. A informação pode estar em qualquer parte do texto fornecido, não apenas no início."""

        user_prompt = f"""Documentos:
{context}

Pergunta: {prompt}"""

        raw = self._call_ollama(user_prompt, system=system, max_tokens=1500)

        # Validar resposta — se degenerada, devolver mensagem clara
        if not self._is_valid_answer(raw, prompt):
            logger.warning("Resposta inválida para '%s': '%s'", prompt[:50], raw[:100])
            if not raw:
                return "Não consegui gerar uma resposta. O modelo pode estar sobrecarregado — tenta novamente."
            else:
                return "Não encontrei essa informação nos documentos indexados."

        return trim_repetition(raw)

    def classify(self, text: str, categories_prompt: str = "", valid_names: list = None, filename: str = "") -> str:
        """Classifica o tipo de documento usando categorias dinâmicas (built-in + custom)."""
        if valid_names is None:
            valid_names = DEFAULT_CATEGORY_NAMES

        # Use dynamic categories prompt if provided, otherwise use defaults
        if not categories_prompt:
            categories_prompt = (
                "medico — relatórios médicos, análises clínicas, receitas, formulários de saúde, exames, diagnósticos, CBCL, consultas\n"
                "financeiro — faturas, recibos, impostos, extratos bancários, declarações fiscais, orçamentos, propostas comerciais, day rates, budgets, estimativas de custo, pagamentos\n"
                "legal — contratos, acordos, procurações, notificações legais, termos e condições, escrituras\n"
                "pessoal — documentos de identificação, certidões, seguros, registos pessoais, passaportes, cartas de condução"
            )

        names_list = ", ".join(n for n in valid_names if n != "outro")

        filename_line = f"Nome do ficheiro: {filename}\n" if filename else ""

        system = "Responde com UMA única palavra. Sem explicações, sem pontuação."
        prompt = f"""Classifica este documento numa das seguintes categorias. Responde com UMA ÚNICA palavra da lista: {names_list}, outro

{categories_prompt}

IMPORTANTE: Papers académicos, artigos de IA, textos técnicos genéricos → outro

Se não encaixar em nenhuma das categorias acima, responde: outro

{filename_line}Texto do documento (primeiros 1500 caracteres):
{text[:1500]}

Categoria (uma palavra):"""

        raw_result = self._call_ollama(prompt, system=system, max_tokens=100, valid_names=valid_names)
        logger.info("LLM classify raw response: '%s'", raw_result[:100])

        # Extrair primeira palavra, normalizar acentos e pontuação
        result = raw_result.strip().split()[0] if raw_result.strip() else ""
        result = re.sub(r'[^\w]', '', result)
        result = normalize_text(result)

        logger.info("LLM classify normalized: '%s' (valid: %s)", result, valid_names)

        # Match exacto — não substring
        for valid in valid_names:
            if result == valid:
                return valid

        # Fallback: tentar match em todas as palavras da resposta (para respostas multi-palavra)
        if raw_result.strip():
            all_words = [normalize_text(re.sub(r'[^\w]', '', w)) for w in raw_result.strip().split()]
            for valid in valid_names:
                if valid in all_words:
                    logger.info("LLM classify fallback match: '%s' found in words", valid)
                    return valid

        logger.warning("LLM classify: nenhum match para '%s', usando 'outro'", raw_result[:80])
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
