# PoC Computacao Confidencial - Benchmark de Embeddings

Base de projeto para benchmark CPU-only do modelo BAAI/bge-m3.

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
