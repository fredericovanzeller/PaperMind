"""
PaperMind — Category Manager.

Gere categorias built-in e custom para classificação de documentos.
Custom categories são persistidas em categories.json.
"""

import json
import logging
from pathlib import Path
from typing import List, Optional

logger = logging.getLogger("papermind.categories")


# Built-in categories — always available, cannot be deleted
BUILTIN_CATEGORIES = [
    {
        "name": "medico",
        "display_name": "Médico / Saúde",
        "description": "relatórios médicos, análises clínicas, receitas, formulários de saúde, exames, diagnósticos, CBCL, consultas, vacinação",
        "icon": "cross.case.fill",
        "color": "red",
        "is_built_in": True,
    },
    {
        "name": "financeiro",
        "display_name": "Financeiro / Fiscal",
        "description": "faturas, recibos, impostos, extratos bancários, declarações fiscais, orçamentos, pagamentos, IRS, IRC",
        "icon": "eurosign.circle.fill",
        "color": "green",
        "is_built_in": True,
    },
    {
        "name": "legal",
        "display_name": "Legal / Contratos",
        "description": "contratos, acordos, procurações, notificações legais, termos e condições, escrituras, regulamentos",
        "icon": "doc.text.fill",
        "color": "blue",
        "is_built_in": True,
    },
    {
        "name": "pessoal",
        "display_name": "Pessoal / ID",
        "description": "documentos de identificação, certidões, seguros, registos pessoais, passaportes, cartas de condução, CVs",
        "icon": "person.text.rectangle.fill",
        "color": "orange",
        "is_built_in": True,
    },
    {
        "name": "outro",
        "display_name": "Outro",
        "description": "documentos que não encaixam nas categorias anteriores",
        "icon": "doc.fill",
        "color": "gray",
        "is_built_in": True,
    },
]


class CategoryManager:
    def __init__(self, data_dir: Path):
        self.data_dir = data_dir
        self.categories_file = data_dir / "categories.json"
        self._custom_categories: List[dict] = []
        self._load()

    def _load(self):
        """Carrega custom categories do ficheiro JSON."""
        if self.categories_file.exists():
            try:
                data = json.loads(self.categories_file.read_text(encoding="utf-8"))
                self._custom_categories = data.get("custom_categories", [])
                logger.info("Categorias custom carregadas: %d", len(self._custom_categories))
            except Exception as e:
                logger.error("Erro ao carregar categories.json: %s", e)
                self._custom_categories = []
        else:
            self._custom_categories = []

    def _save(self):
        """Persiste custom categories no ficheiro JSON."""
        try:
            self.data_dir.mkdir(parents=True, exist_ok=True)
            data = {"custom_categories": self._custom_categories}
            self.categories_file.write_text(
                json.dumps(data, indent=2, ensure_ascii=False), encoding="utf-8"
            )
            logger.info("Categorias guardadas: %d custom", len(self._custom_categories))
        except Exception as e:
            logger.error("Erro ao guardar categories.json: %s", e)

    def get_all(self) -> List[dict]:
        """Retorna todas as categorias (built-in + custom)."""
        return BUILTIN_CATEGORIES + self._custom_categories

    def get_custom(self) -> List[dict]:
        """Retorna apenas custom categories."""
        return list(self._custom_categories)

    def get_all_names(self) -> List[str]:
        """Retorna todos os nomes de categorias válidos."""
        return [c["name"] for c in self.get_all()]

    def get_by_name(self, name: str) -> Optional[dict]:
        """Encontra uma categoria pelo nome."""
        for cat in self.get_all():
            if cat["name"] == name:
                return cat
        return None

    def is_valid(self, name: str) -> bool:
        """Verifica se um nome de categoria é válido."""
        return name in self.get_all_names()

    def add_custom(self, name: str, display_name: str, description: str = "",
                   icon: str = "tag.fill", color: str = "purple") -> dict:
        """Adiciona uma nova custom category."""
        # Sanitizar nome: lowercase, sem espaços, sem acentos
        import unicodedata
        clean_name = name.lower().strip()
        clean_name = unicodedata.normalize("NFD", clean_name)
        clean_name = "".join(c for c in clean_name if unicodedata.category(c) != "Mn")
        clean_name = clean_name.replace(" ", "_")
        clean_name = "".join(c for c in clean_name if c.isalnum() or c == "_")

        # Verificar se já existe
        if self.get_by_name(clean_name):
            return {"error": f"Categoria '{clean_name}' já existe"}

        new_cat = {
            "name": clean_name,
            "display_name": display_name,
            "description": description,
            "icon": icon,
            "color": color,
            "is_built_in": False,
        }
        self._custom_categories.append(new_cat)
        self._save()

        logger.info("Nova categoria: %s (%s)", clean_name, display_name)
        return new_cat

    def delete_custom(self, name: str) -> dict:
        """Remove uma custom category. Não permite apagar built-ins."""
        # Check built-in
        for cat in BUILTIN_CATEGORIES:
            if cat["name"] == name:
                return {"error": "Não é possível apagar categorias built-in"}

        before = len(self._custom_categories)
        self._custom_categories = [c for c in self._custom_categories if c["name"] != name]

        if len(self._custom_categories) == before:
            return {"error": f"Categoria '{name}' não encontrada"}

        self._save()
        logger.info("Categoria removida: %s", name)
        return {"status": "deleted", "name": name}

    def get_classify_prompt_categories(self) -> str:
        """
        Gera a lista de categorias formatada para o prompt de classificação do LLM.
        Exclui 'outro' que é tratado como fallback.
        """
        lines = []
        for cat in self.get_all():
            if cat["name"] == "outro":
                continue
            lines.append(f"{cat['name']} — {cat['description']}")
        return "\n".join(lines)
