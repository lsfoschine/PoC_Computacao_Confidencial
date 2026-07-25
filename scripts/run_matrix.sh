#!/usr/bin/env bash
set -euo pipefail

export UV_CACHE_DIR="${UV_CACHE_DIR:-.uv-cache}"
export UV_PYTHON_INSTALL_DIR="${UV_PYTHON_INSTALL_DIR:-.uv-python}"

DEFAULT_MAX_LENGTHS=(256 512 1024 2048)
DEFAULT_BATCHES=(4 8 16)

if [[ -n "${MAX_LENGTHS:-}" ]]; then
  read -r -a MAX_LENGTHS_ARR <<< "${MAX_LENGTHS}"
else
  MAX_LENGTHS_ARR=("${DEFAULT_MAX_LENGTHS[@]}")
fi

if [[ -n "${BATCHES:-}" ]]; then
  read -r -a BATCHES_ARR <<< "${BATCHES}"
else
  BATCHES_ARR=("${DEFAULT_BATCHES[@]}")
fi

THREADS_ARG=()
if [[ -n "${THREADS:-}" ]]; then
  THREADS_ARG=(--threads "${THREADS}")
fi

WARMUP_ARG=()
if [[ -n "${WARMUP_DOCS:-}" ]]; then
  WARMUP_ARG=(--warmup-docs "${WARMUP_DOCS}")
fi

CORPUS_PATH="${CORPUS_PATH:-data/corpus.jsonl}"
REPETITIONS="${REPETITIONS:-3}"

if ! [[ "$REPETITIONS" =~ ^[1-9][0-9]*$ ]]; then
  echo "REPETITIONS deve ser um inteiro positivo" >&2
  exit 1
fi

./scripts/verify_corpus.sh

timestamp="$(date -u +%Y%m%dT%H%M%SZ)"
host="$(hostname)"
gitsha="$(git rev-parse --short HEAD 2>/dev/null || echo nogit)"
MATRIX_RUN_ID="${MATRIX_RUN_ID:-matrix-${timestamp}-${host}-${gitsha}}"
export MATRIX_RUN_ID
RUN_ROOT="results/${MATRIX_RUN_ID}"

mkdir -p "${RUN_ROOT}"

for max_length in "${MAX_LENGTHS_ARR[@]}"; do
  for batch in "${BATCHES_ARR[@]}"; do
    for repetition in $(seq 1 "$REPETITIONS"); do
      export MATRIX_REPETITION="$repetition"
      run_dir="${RUN_ROOT}/max${max_length}_b${batch}_rep${repetition}"
      printf "\n== max_length=%s batch=%s repetition=%s/%s ==\n" \
        "$max_length" "$batch" "$repetition" "$REPETITIONS"
      uv run python src/bench_embed.py \
        --corpus "${CORPUS_PATH}" \
        --outdir "${run_dir}" \
        --max-length "${max_length}" \
        --batch "${batch}" \
        "${THREADS_ARG[@]}" \
        "${WARMUP_ARG[@]}"
    done
  done
done

uv run python src/summarize_results.py --run-root "${RUN_ROOT}"
