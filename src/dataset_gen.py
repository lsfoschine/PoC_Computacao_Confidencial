import argparse
import json
import random
from pathlib import Path

WORDS = [
    "acao",
    "acesso",
    "agora",
    "ainda",
    "algoritmo",
    "amostra",
    "analise",
    "apoio",
    "arquivo",
    "atencao",
    "banco",
    "caminho",
    "capaz",
    "caso",
    "cidade",
    "ciclo",
    "ciencia",
    "codigo",
    "coleta",
    "comando",
    "contexto",
    "controle",
    "dados",
    "decisao",
    "desempenho",
    "detalhe",
    "dia",
    "documento",
    "efeito",
    "ensaio",
    "entrega",
    "equipo",
    "escala",
    "escolha",
    "estado",
    "estimativa",
    "evento",
    "exemplo",
    "experimento",
    "fato",
    "falha",
    "familia",
    "fase",
    "filtro",
    "forma",
    "geracao",
    "gestao",
    "grupo",
    "historia",
    "ideia",
    "impacto",
    "indice",
    "informacao",
    "inicio",
    "instante",
    "lote",
    "maior",
    "matriz",
    "media",
    "memoria",
    "metodo",
    "modelo",
    "motor",
    "nivel",
    "novo",
    "objetivo",
    "opcao",
    "ordem",
    "parte",
    "passo",
    "perda",
    "perfil",
    "periodo",
    "peso",
    "plano",
    "ponto",
    "processo",
    "produto",
    "qualidade",
    "quantidade",
    "queda",
    "rede",
    "registro",
    "relacao",
    "relato",
    "resumo",
    "resultado",
    "risco",
    "rotina",
    "saida",
    "semente",
    "sentenca",
    "serie",
    "sinal",
    "sistema",
    "tabela",
    "tarefa",
    "tempo",
    "texto",
    "tolerancia",
    "valor",
    "variacao",
    "vetor",
    "visao",
    "volume",
    "zona",
]

SIZES_DEFAULT = [256, 512, 1024, 2048, 4096, 8192]


def build_text(target_chars: int, rng: random.Random, min_words: int | None) -> str:
    sentences = []
    while True:
        length = rng.randint(6, 14)
        sentence_words = [rng.choice(WORDS) for _ in range(length)]
        sentence = " ".join(sentence_words).capitalize() + "."
        sentences.append(sentence)
        text = " ".join(sentences)
        if len(text) < target_chars:
            continue
        if min_words is not None and len(text.split()) < min_words:
            continue
        return text


def parse_sizes(raw: str) -> list[int]:
    return [int(part.strip()) for part in raw.split(",") if part.strip()]


def main() -> None:
    parser = argparse.ArgumentParser(description="Gera corpus deterministico em PT-BR.")
    parser.add_argument("--out", default="data/corpus.jsonl", help="Caminho do JSONL")
    parser.add_argument("--seed", type=int, default=13, help="Seed fixa")
    parser.add_argument(
        "--sizes",
        default=",".join(str(s) for s in SIZES_DEFAULT),
        help="Lista de tamanhos alvo (chars)",
    )
    parser.add_argument(
        "--n-per-size",
        type=int,
        default=24,
        help="Quantidade de documentos por tamanho",
    )
    parser.add_argument("--language", default="pt-br", help="Idioma (apenas pt-br)")
    parser.add_argument(
        "--min-words",
        type=int,
        default=None,
        help="Minimo de palavras por documento",
    )
    args = parser.parse_args()

    if args.language.lower() != "pt-br":
        raise SystemExit("Apenas language=pt-br esta disponivel.")

    rng = random.Random(args.seed)
    sizes = parse_sizes(args.sizes)
    out_path = Path(args.out)
    out_path.parent.mkdir(parents=True, exist_ok=True)

    records = []
    doc_id = 0
    for target in sizes:
        for _ in range(args.n_per_size):
            text = build_text(target, rng, args.min_words)
            record = {
                "id": doc_id,
                "size_target": target,
                "text": text,
            }
            records.append(record)
            doc_id += 1

    with out_path.open("w", encoding="utf-8") as handle:
        for record in records:
            handle.write(json.dumps(record, ensure_ascii=True) + "\n")

    print(f"Wrote {len(records)} docs to {out_path}")


if __name__ == "__main__":
    main()
