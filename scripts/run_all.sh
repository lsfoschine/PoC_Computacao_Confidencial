#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

source "${SCRIPT_DIR}/benchmark_profile.sh"

export UV_CACHE_DIR="${UV_CACHE_DIR:-.uv-cache}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-.uv-python}"

ORIGINAL_ARGS=("$@")

usage() {
  cat <<'USAGE'
Uso: ./scripts/run_all.sh [opcoes]

Perfil canonico padrao:
  modelo             BAAI/bge-m3
  revisao do modelo  5617a9f61b028005a4858fdac845db406aefb181
  max lengths        256 512 1024 2048
  batches            4 8 16
  threads            4
  warm-up docs       32
  repeticoes         3

Opcoes:
  --help                  Mostra esta ajuda e sai
  --seed N                Seed do corpus (default: 13)
  --sizes LISTA           Tamanhos alvo em chars (default: 256..8192)
  --n-per-size N          Documentos por tamanho (default: 24)
  --language LANG         Idioma do corpus (default: pt-br)
  --min-words N           Minimo de palavras por documento
  --model ID              Identificador do modelo
  --model-revision SHA    Revisao imutavel do modelo
  --max-lengths LISTA     Max lengths separados por espaco
  --batches LISTA         Batch sizes separados por espaco
  --threads N             Numero de threads CPU (default: 4)
  --warmup-docs N         Documentos de warm-up (default: 32)
  --repetitions N         Repeticoes por combinacao (default: 3)
  --matrix-run-id ID      Identificador operacional da matriz
  --allow-dirty           Permite benchmark com arvore Git modificada
  --regenerate-corpus     Regenera corpus e warm-up versionados
  --skip-sync             Nao executa uv sync --frozen
  --skip-python           Nao executa uv python install
  --skip-dataset          Nao gera nem valida o corpus nesta etapa
  --skip-env              Nao coleta env.before.json; env por run permanece
  --skip-matrix           Nao roda a matriz de benchmark

Variaveis de ambiente:
  MATRIX_RUN_ID, UV_CACHE_DIR, UV_PYTHON_INSTALL_DIR
USAGE
}

SEED="$DEFAULT_SEED"
SIZES="$DEFAULT_SIZES"
N_PER_SIZE="$DEFAULT_N_PER_SIZE"
LANGUAGE="$DEFAULT_LANGUAGE"
MIN_WORDS=""
MODEL="$DEFAULT_MODEL"
MODEL_REVISION="$DEFAULT_MODEL_REVISION"
MAX_LENGTHS="$DEFAULT_MAX_LENGTHS"
BATCHES="$DEFAULT_BATCHES"
THREADS="$DEFAULT_THREADS"
WARMUP_DOCS="$DEFAULT_WARMUP_DOCS"
REPETITIONS="$DEFAULT_REPETITIONS"
MATRIX_RUN_ID="${MATRIX_RUN_ID:-}"
ALLOW_DIRTY="0"
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
    --seed)
      SEED="$2"
      shift 2
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
    --model)
      MODEL="$2"
      shift 2
      ;;
    --model-revision)
      MODEL_REVISION="$2"
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
    --matrix-run-id)
      MATRIX_RUN_ID="$2"
      shift 2
      ;;
    --allow-dirty)
      ALLOW_DIRTY="1"
      shift
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
      echo "Opcao desconhecida: $1" >&2
      usage
      exit 1
      ;;
  esac
done

for numeric_value in "$SEED" "$N_PER_SIZE" "$THREADS" "$WARMUP_DOCS" "$REPETITIONS"; do
  if ! [[ "$numeric_value" =~ ^[0-9]+$ ]]; then
    echo "Parametros numericos devem conter apenas inteiros." >&2
    exit 1
  fi
done

if [[ "$N_PER_SIZE" -eq 0 || "$THREADS" -eq 0 || "$REPETITIONS" -eq 0 ]]; then
  echo "n-per-size, threads e repetitions devem ser maiores que zero." >&2
  exit 1
fi

if [[ -z "$MODEL_REVISION" ]]; then
  echo "--model-revision nao pode ser vazio no runner canonico." >&2
  exit 1
fi

if ! [[ "$MODEL_REVISION" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "--model-revision deve ser um commit SHA completo de 40 caracteres." >&2
  exit 1
fi

if [[ "$MODEL" != "$DEFAULT_MODEL" && "$MODEL_REVISION" == "$DEFAULT_MODEL_REVISION" ]]; then
  echo "Ao alterar --model, informe tambem --model-revision." >&2
  exit 1
fi

ensure_clean_git() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    if [[ "$ALLOW_DIRTY" == "0" ]]; then
      echo "O runner canonico requer um checkout Git ou --allow-dirty." >&2
      exit 1
    fi
    return
  fi
  if [[ "$ALLOW_DIRTY" == "0" ]] &&
    [[ -n "$(git status --porcelain 2>/dev/null || true)" ]]; then
    echo "Git working tree is dirty. Commit changes or use --allow-dirty." >&2
    exit 1
  fi
}

if [[ "$SKIP_MATRIX" == "0" ]]; then
  ensure_clean_git
  if [[ -z "$MATRIX_RUN_ID" ]]; then
    timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
    host="$(hostname)"
    gitsha="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
    MATRIX_RUN_ID="matrix-${timestamp}-${host}-${gitsha}"
  fi
  if ! [[ "$MATRIX_RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "matrix-run-id deve conter apenas letras, numeros, ponto, underscore ou hifen." >&2
    exit 1
  fi
  RUN_ROOT="results/${MATRIX_RUN_ID}"
  if [[ -e "$RUN_ROOT" ]]; then
    echo "${RUN_ROOT} ja existe; use outro matrix-run-id." >&2
    exit 1
  fi
  mkdir -p "$RUN_ROOT"
  exec > >(tee -a "${RUN_ROOT}/run.log") 2>&1
  printf -v RUN_COMMAND '%q ' "$0" "${ORIGINAL_ARGS[@]}"
  RUN_COMMAND="${RUN_COMMAND% }"
  echo "Matrix run ID: ${MATRIX_RUN_ID}"
  echo "Profile: model=${MODEL}@${MODEL_REVISION} max_lengths=${MAX_LENGTHS} batches=${BATCHES} threads=${THREADS} warmup_docs=${WARMUP_DOCS} repetitions=${REPETITIONS}"
fi

if [[ "$SKIP_PYTHON" == "0" ]]; then
  uv python install
fi

if [[ "$SKIP_SYNC" == "0" ]]; then
  uv sync --frozen
fi

generate_corpora() {
  local dataset_args=(
    --seed "$SEED"
    --sizes "$SIZES"
    --n-per-size "$N_PER_SIZE"
    --language "$LANGUAGE"
    --warmup-docs "$WARMUP_DOCS"
  )
  if [[ -n "$MIN_WORDS" ]]; then
    dataset_args+=(--min-words "$MIN_WORDS")
  fi
  uv run python src/dataset_gen.py "${dataset_args[@]}"
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

if [[ "$SKIP_MATRIX" == "0" ]]; then
  ensure_clean_git
  export MATRIX_RUN_ID MODEL MODEL_REVISION MAX_LENGTHS BATCHES THREADS
  export WARMUP_DOCS REPETITIONS
  uv run python src/matrix_manifest.py \
    --run-root "$RUN_ROOT" \
    --status start \
    --command "$RUN_COMMAND" \
    --model "$MODEL" \
    --model-revision "$MODEL_REVISION" \
    --max-lengths "$MAX_LENGTHS" \
    --batches "$BATCHES" \
    --threads "$THREADS" \
    --warmup-docs "$WARMUP_DOCS" \
    --repetitions "$REPETITIONS"
fi

if [[ "$SKIP_ENV" == "0" ]]; then
  if [[ "$SKIP_MATRIX" == "0" ]]; then
    ./scripts/collect_env.sh --out "${RUN_ROOT}/env.before.json"
  else
    mkdir -p reports
    ./scripts/collect_env.sh --out reports/env.json
  fi
fi

if [[ "$SKIP_MATRIX" == "0" ]]; then
  ./scripts/run_matrix.sh
  uv run python src/matrix_manifest.py --run-root "$RUN_ROOT" --status complete
  touch "${RUN_ROOT}/COMPLETED"
  echo "Completed matrix: ${RUN_ROOT}"
fi
