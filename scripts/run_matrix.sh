#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." && pwd)"
cd "$REPO_ROOT"

source "${SCRIPT_DIR}/benchmark_profile.sh"

export UV_CACHE_DIR="${UV_CACHE_DIR:-.uv-cache}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-.uv-python}"

MAX_LENGTHS_VALUE="${MAX_LENGTHS:-$DEFAULT_MAX_LENGTHS}"
BATCHES_VALUE="${BATCHES:-$DEFAULT_BATCHES}"
THREADS="${THREADS:-$DEFAULT_THREADS}"
WARMUP_DOCS="${WARMUP_DOCS:-$DEFAULT_WARMUP_DOCS}"
REPETITIONS="${REPETITIONS:-$DEFAULT_REPETITIONS}"
MODEL="${MODEL:-$DEFAULT_MODEL}"
MODEL_REVISION="${MODEL_REVISION:-$DEFAULT_MODEL_REVISION}"
CORPUS_PATH="${CORPUS_PATH:-data/corpus.jsonl}"
WARMUP_CORPUS_PATH="${WARMUP_CORPUS_PATH:-data/warmup.jsonl}"

read -r -a MAX_LENGTHS_ARR <<< "$MAX_LENGTHS_VALUE"
read -r -a BATCHES_ARR <<< "$BATCHES_VALUE"

if [[ "${#MAX_LENGTHS_ARR[@]}" -eq 0 || "${#BATCHES_ARR[@]}" -eq 0 ]]; then
  echo "MAX_LENGTHS e BATCHES nao podem ser vazios." >&2
  exit 1
fi

for numeric_value in "${MAX_LENGTHS_ARR[@]}" "${BATCHES_ARR[@]}"; do
  if ! [[ "$numeric_value" =~ ^[1-9][0-9]*$ ]]; then
    echo "MAX_LENGTHS e BATCHES devem conter inteiros positivos." >&2
    exit 1
  fi
done

for numeric_value in "$THREADS" "$WARMUP_DOCS" "$REPETITIONS"; do
  if ! [[ "$numeric_value" =~ ^[0-9]+$ ]]; then
    echo "THREADS, WARMUP_DOCS e REPETITIONS devem ser inteiros." >&2
    exit 1
  fi
done

if [[ "$THREADS" -eq 0 || "$REPETITIONS" -eq 0 ]]; then
  echo "THREADS e REPETITIONS devem ser maiores que zero." >&2
  exit 1
fi

if ! [[ "$MODEL_REVISION" =~ ^[0-9a-fA-F]{40}$ ]]; then
  echo "MODEL_REVISION deve ser um commit SHA completo de 40 caracteres." >&2
  exit 1
fi

if [[ "$MODEL" != "$DEFAULT_MODEL" && "$MODEL_REVISION" == "$DEFAULT_MODEL_REVISION" ]]; then
  echo "Ao alterar MODEL, informe tambem MODEL_REVISION." >&2
  exit 1
fi

./scripts/verify_corpus.sh

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
host="$(hostname)"
gitsha="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
MATRIX_RUN_ID="${MATRIX_RUN_ID:-matrix-${timestamp}-${host}-${gitsha}}"
if ! [[ "$MATRIX_RUN_ID" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "MATRIX_RUN_ID contem caracteres invalidos." >&2
  exit 1
fi
export MATRIX_RUN_ID
RUN_ROOT="results/${MATRIX_RUN_ID}"

mkdir -p "$RUN_ROOT"
if [[ -e "${RUN_ROOT}/runs.csv" || -e "${RUN_ROOT}/summary.csv" ]] ||
  compgen -G "${RUN_ROOT}/max*_b*_rep*" >/dev/null; then
  echo "${RUN_ROOT} ja contem artefatos de benchmark." >&2
  exit 1
fi

for max_length in "${MAX_LENGTHS_ARR[@]}"; do
  for batch in "${BATCHES_ARR[@]}"; do
    for repetition in $(seq 1 "$REPETITIONS"); do
      export MATRIX_REPETITION="$repetition"
      run_dir="${RUN_ROOT}/max${max_length}_b${batch}_rep${repetition}"
      printf "\n== max_length=%s batch=%s repetition=%s/%s ==\n" \
        "$max_length" "$batch" "$repetition" "$REPETITIONS"
      uv run python src/bench_embed.py \
        --corpus "$CORPUS_PATH" \
        --warmup-corpus "$WARMUP_CORPUS_PATH" \
        --outdir "$run_dir" \
        --model "$MODEL" \
        --model-revision "$MODEL_REVISION" \
        --max-length "$max_length" \
        --batch "$batch" \
        --threads "$THREADS" \
        --warmup-docs "$WARMUP_DOCS"
    done
  done
done

expected_groups=$(("${#MAX_LENGTHS_ARR[@]}" * "${#BATCHES_ARR[@]}"))
expected_runs=$((expected_groups * REPETITIONS))
uv run python src/summarize_results.py \
  --run-root "$RUN_ROOT" \
  --expected-runs "$expected_runs" \
  --expected-groups "$expected_groups" \
  --expected-repetitions "$REPETITIONS"

echo "Matrix results: ${RUN_ROOT}"
