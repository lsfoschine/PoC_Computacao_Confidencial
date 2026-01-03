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
  --docs-per-size N     Quantidade de docs por tamanho (default: 24)
  --seq-lens LISTA      Seq lens separados por espaco (ex: "256 512 1024")
  --batch-sizes LISTA   Batch sizes separados por espaco (ex: "4 8 16")
  --limit N             Limita numero de docs no benchmark
  --skip-dataset         Nao gera o corpus
  --skip-env             Nao coleta ambiente
  --skip-matrix          Nao roda matriz de benchmark

Variaveis de ambiente:
  UV_CACHE_DIR, UV_PYTHON_INSTALL_DIR
USAGE
}

SIZES=""
DOCS_PER_SIZE="24"
SEQ_LENS=""
BATCH_SIZES=""
LIMIT=""
SKIP_DATASET="0"
SKIP_ENV="0"
SKIP_MATRIX="0"

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
    --docs-per-size)
      DOCS_PER_SIZE="$2"
      shift 2
      ;;
    --seq-lens)
      SEQ_LENS="$2"
      shift 2
      ;;
    --batch-sizes)
      BATCH_SIZES="$2"
      shift 2
      ;;
    --limit)
      LIMIT="$2"
      shift 2
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

if [[ "$SKIP_DATASET" == "0" ]]; then
  DATASET_ARGS=()
  if [[ -n "$SIZES" ]]; then
    DATASET_ARGS+=(--sizes "$SIZES")
  fi
  if [[ -n "$DOCS_PER_SIZE" ]]; then
    DATASET_ARGS+=(--docs-per-size "$DOCS_PER_SIZE")
  fi
  uv run python src/dataset_gen.py "${DATASET_ARGS[@]}"
fi

if [[ "$SKIP_ENV" == "0" ]]; then
  ./scripts/collect_env.sh > reports/env.txt
fi

if [[ "$SKIP_MATRIX" == "0" ]]; then
  export SEQ_LENS BATCH_SIZES LIMIT
  ./scripts/run_matrix.sh
fi
