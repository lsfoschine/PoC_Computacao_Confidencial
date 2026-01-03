# PoC Computacao Confidencial - Benchmark de Embeddings

Benchmark CPU-only do modelo BAAI/bge-m3 usando corpus sintetico em PT-BR.

## Requisitos
- Python >= 3.10 e < 3.13 (recomendado 3.12)
- uv

## Setup
```bash
uv sync
```

Se o ambiente bloquear caches fora do projeto:
```bash
UV_CACHE_DIR=.uv-cache UV_PYTHON_INSTALL_DIR=.uv-python uv sync
```

Configure o token do Hugging Face:
```bash
cp .env.example .env
```
Edite `.env` com seu `HUGGINGFACE_HUB_TOKEN`.

## Gerar corpus
```bash
uv run python src/dataset_gen.py
```

## Rodar um benchmark
```bash
uv run python src/bench_embed.py --seq-len 512 --batch-size 16
```

## Rodar matriz de benchmarks
```bash
./scripts/run_matrix.sh
```

## Rodar tudo (setup rapido)
```bash
./scripts/run_all.sh
```

## Coletar ambiente
```bash
./scripts/collect_env.sh > reports/env.txt
```

## Saidas
- `data/corpus.jsonl`: corpus deterministico.
- `results/run.jsonl`: metricas por execucao (JSONL).
- `results/summary.csv`: consolidado de execucoes.
- `results/embeddings.npy`: embeddings da ultima execucao.
