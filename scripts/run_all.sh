#!/usr/bin/env bash
set -euo pipefail

export UV_CACHE_DIR="${UV_CACHE_DIR:-.uv-cache}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-.uv-python}"

usage() {
  cat <<'USAGE'
Uso: ./scripts/run_all.sh [opcoes]

Opcoes:
  --help                Mostra esta ajuda e sai
  --sizes LISTA         Tamanhos alvo em chars (ex: "256,512,1024")
  --n-per-size N        Quantidade de docs por tamanho (default: 24)
  --language LANG       Idioma do corpus (default: pt-br)
  --min-words N         Minimo de palavras por documento
  --max-lengths LISTA   Max lengths separados por espaco (ex: "256 512 1024")
  --batches LISTA       Batch sizes separados por espaco (ex: "4 8 16")
  --threads N           Numero de threads CPU
  --warmup-docs N       Quantidade de docs para warm-up
  --repetitions N       Repeticoes por combinacao (default: 3)
  --regenerate-corpus   Regenera corpus e warm-up versionados
  --skip-sync            Nao executa uv sync
  --skip-python          Nao executa uv python install
  --skip-dataset         Nao gera o corpus
  --skip-env             Nao coleta ambiente
  --skip-matrix          Nao roda matriz de benchmark

Variaveis de ambiente:
  UV_CACHE_DIR, UV_PYTHON_INSTALL_DIR
USAGE
}

SIZES=""
N_PER_SIZE="24"
LANGUAGE="pt-br"
MIN_WORDS=""
MAX_LENGTHS=""
BATCHES=""
THREADS=""
WARMUP_DOCS=""
REPETITIONS="3"
REGENERATE_CORPUS="0"
SKIP_DATASET="0"
SKIP_ENV="0"
SKIP_MATRIX="0"
SKIP_SYNC="0"
SKIP_PYTHON="0"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --help)
      usage
      exit 0
      ;;
    --sizes)
      SIZES="$2"
      shift 2
      ;;
    --n-per-size)
      N_PER_SIZE="$2"
      shift 2
      ;;
    --language)
      LANGUAGE="$2"
      shift 2
      ;;
    --min-words)
      MIN_WORDS="$2"
      shift 2
      ;;
    --max-lengths)
      MAX_LENGTHS="$2"
      shift 2
      ;;
    --batches)
      BATCHES="$2"
      shift 2
      ;;
    --threads)
      THREADS="$2"
      shift 2
      ;;
    --warmup-docs)
      WARMUP_DOCS="$2"
      shift 2
      ;;
    --repetitions)
      REPETITIONS="$2"
      shift 2
      ;;
    --regenerate-corpus)
      REGENERATE_CORPUS="1"
      shift
      ;;
    --skip-sync)
      SKIP_SYNC="1"
      shift
      ;;
    --skip-python)
      SKIP_PYTHON="1"
      shift
      ;;
    --skip-dataset)
      SKIP_DATASET="1"
      shift
      ;;
    --skip-env)
      SKIP_ENV="1"
      shift
      ;;
    --skip-matrix)
      SKIP_MATRIX="1"
      shift
      ;;
    *)
      echo "Opcao desconhecida: $1"
      usage
      exit 1
      ;;
  esac
done

if [[ "$SKIP_PYTHON" == "0" ]]; then
  uv python install
fi

if [[ "$SKIP_SYNC" == "0" ]]; then
  uv sync
fi

generate_corpora() {
  DATASET_ARGS=()
  if [[ -n "$SIZES" ]]; then
    DATASET_ARGS+=(--sizes "$SIZES")
  fi
  if [[ -n "$N_PER_SIZE" ]]; then
    DATASET_ARGS+=(--n-per-size "$N_PER_SIZE")
  fi
  if [[ -n "$LANGUAGE" ]]; then
    DATASET_ARGS+=(--language "$LANGUAGE")
  fi
  if [[ -n "$MIN_WORDS" ]]; then
    DATASET_ARGS+=(--min-words "$MIN_WORDS")
  fi
  if [[ -n "$WARMUP_DOCS" ]]; then
    DATASET_ARGS+=(--warmup-docs "$WARMUP_DOCS")
  fi
  uv run python src/dataset_gen.py "${DATASET_ARGS[@]}"
  ./scripts/hash_corpus.sh
}

if [[ "$SKIP_DATASET" == "0" ]]; then
  if [[ "$REGENERATE_CORPUS" == "1" ]]; then
    echo "WARNING: regenerating versioned corpus and warm-up files."
    generate_corpora
  elif [[ -f data/corpus.jsonl ]]; then
    if [[ ! -f data/corpus.sha256 || ! -f data/warmup.jsonl || ! -f data/warmup.sha256 ]]; then
      echo "Corpus artifacts are incomplete. Use --regenerate-corpus to rebuild them." >&2
      exit 1
    fi
    echo "Using the existing versioned corpus. Use --regenerate-corpus to replace it."
    ./scripts/verify_corpus.sh
  else
    echo "No versioned corpus found; generating the canonical corpus and warm-up set."
    generate_corpora
  fi
fi

if [[ "$SKIP_ENV" == "0" ]]; then
  mkdir -p reports
  ./scripts/collect_env.sh > reports/env.json
fi

if [[ "$SKIP_MATRIX" == "0" ]]; then
  export MAX_LENGTHS BATCHES THREADS WARMUP_DOCS REPETITIONS
  ./scripts/run_matrix.sh
fi
