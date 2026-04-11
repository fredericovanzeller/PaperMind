"""
Quick classification test — runs real LLM calls against known documents.
Usage: python -m tests.test_classify
"""

import sys
from pathlib import Path

# Add project root to path
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from backend.llm import LocalLLM
from backend.pdf_processor import process_pdf

TEST_CASES = [
    {
        "filename": "App Funding & Marketing Plan (1).pdf",
        "path": "data/Processed/Contrato/App Funding & Marketing Plan (1).pdf",
        "expected_not": "medico",
    },
    {
        "filename": "Orcamento_Eyewear_Campaign_FVZ.pdf",
        "path": "data/Processed/Medico/Orcamento_Eyewear_Campaign_FVZ.pdf",
        "expected_not": "medico",
    },
    {
        "filename": "boltJCD3913_23421711_4.pdf",
        "path": "data/Processed/Contrato/boltJCD3913_23421711_4.pdf",
        "expected": "medico",
    },
    {
        "filename": "CBCL.pdf",
        "path": "data/Processed/Outro/CBCL.pdf",
        "expected": "medico",
    },
    {
        "filename": "Attention Is All You Need.pdf",
        "path": "data/Processed/Contrato/Attention Is All You Need.pdf",
        "expected": "outro",
    },
]

PROJECT_ROOT = Path(__file__).resolve().parent.parent


def main():
    llm = LocalLLM()
    print(f"Modelo: {llm.model_name}\n")
    print(f"{'Ficheiro':<50} {'Categoria':<15} {'OK?'}")
    print("-" * 75)

    for case in TEST_CASES:
        pdf_path = PROJECT_ROOT / case["path"]
        if not pdf_path.exists():
            print(f"{case['filename']:<50} {'FILE NOT FOUND':<15}")
            continue

        # Extract text from PDF
        chunks = process_pdf(str(pdf_path))
        if not chunks:
            print(f"{case['filename']:<50} {'NO TEXT':<15}")
            continue

        classify_text = " ".join(c.text for c in chunks[:3])

        category = llm.classify(
            classify_text,
            filename=case["filename"],
        )

        # Check result
        if "expected" in case:
            ok = category == case["expected"]
        else:
            ok = category != case["expected_not"]

        status = "OK" if ok else "FAIL"
        print(f"{case['filename']:<50} {category:<15} {status}")

    print()


if __name__ == "__main__":
    main()
