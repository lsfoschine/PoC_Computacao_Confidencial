# PoC Computacao Confidencial - Benchmark de Embeddings

Benchmark CPU-only do modelo BAAI/bge-m3 usando corpus sintetico em PT-BR com rastreabilidade por hashes.

## Requisitos
- uv

## Setup
O uv gerencia a versao do Python via `.python-version` e prepara o venv automaticamente.
```bash
uv python install
uv sync
```

Se o ambiente bloquear caches fora do projeto:
```bash
UV_CACHE_DIR=.uv-cache UV_PYTHON_INSTALL_DIR=.uv-python uv python install
UV_CACHE_DIR=.uv-cache UV_PYTHON_INSTALL_DIR=.uv-python uv sync
```

Configure o token do Hugging Face:
```bash
cp .env.example .env
```
Edite `.env` com seu `HUGGINGFACE_HUB_TOKEN`.

## Fluxo recomendado

### 1) Gerar corpus fixo (apenas uma vez)
```bash
uv run python src/dataset_gen.py --out data/corpus.jsonl --seed 13 --sizes 256,512,1024,2048,4096,8192 --n-per-size 24 --language pt-br
./scripts/hash_corpus.sh
```

### 2) Validar corpus (em cada maquina)
```bash
./scripts/verify_corpus.sh
```

### 3) Rodar benchmark (em cada maquina)
```bash
uv run python src/bench_embed.py \
  --corpus data/corpus.jsonl \
  --batch 16 \
  --max-length 512 \
  --threads 8 \
  --warmup-docs 32
```

Os resultados sao gravados em `results/<run_id>/` com `embeddings.npy`, `embeddings.sha256`, `run.jsonl` e `env.json`.

### 4) Rodar matriz
```bash
./scripts/run_matrix.sh
```

A matriz cria `results/<matrix_run_id>/` e grava `summary.csv` com o consolidado.

## Runner completo (dataset + hash + env + matriz)
```bash
./scripts/run_all.sh --help
```

Por padrao o run_all executa `uv sync` para preparar o venv. Para pular:
```bash
./scripts/run_all.sh --skip-sync
```

## Saidas
- `data/corpus.jsonl`: corpus deterministico (versionado).
- `data/corpus.sha256`: hash do corpus (versionado).
- `results/<run_id>/`: saidas do benchmark.
- `results/<matrix_run_id>/summary.csv`: consolidado da matriz.
