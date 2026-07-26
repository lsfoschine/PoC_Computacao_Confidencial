# Confidential Computing Benchmark PoC

[English](README.md) | [Português](README.pt-BR.md)

A reproducible CPU-only benchmark for comparing embedding workloads across
conventional and confidential-computing Linux environments. The benchmark uses
`BAAI/bge-m3`, versioned input datasets, content hashes, isolated warm-up data,
per-run environment metadata, and repeated measurements with 95% confidence
intervals.

## Requirements

- [uv](https://docs.astral.sh/uv/)

The Python version is pinned in `.python-version`; uv downloads it and creates the
virtual environment.

## Reproducible benchmark checkout

Use the `benchmark-v1` tag on every machine so that code, benchmark profile, and
dependency lock are identical:

```bash
git clone https://github.com/lsfoschine/PoC_Computacao_Confidencial.git
cd PoC_Computacao_Confidencial
git checkout benchmark-v1
./scripts/run_all.sh
```

The detached `HEAD` created by checking out the tag is expected for a benchmark
execution. `run_all.sh` installs the pinned Python version with uv, synchronizes
the locked dependencies, validates the versioned datasets, captures the
environment, and runs the complete canonical matrix. If Hugging Face
authentication is required, prepare `.env` as described below before the final
command.

## Environment setup

```bash
uv python install
uv sync --frozen
```

For environments where user-level cache directories are restricted:

```bash
UV_CACHE_DIR=.uv-cache UV_PYTHON_INSTALL_DIR=.uv-python uv python install
UV_CACHE_DIR=.uv-cache UV_PYTHON_INSTALL_DIR=.uv-python uv sync --frozen
```

For authenticated Hugging Face downloads:

```bash
cp .env.example .env
```

Set `HUGGINGFACE_HUB_TOKEN` in `.env`. The file is ignored by Git.

## Versioned datasets

The repository contains two deterministic datasets:

- `data/corpus.jsonl`: 144 measured documents, with 24 documents for each target
  size: 256, 512, 1024, 2048, 4096, and 8192 approximate characters.
- `data/warmup.jsonl`: 32 deterministic, size-stratified documents used only to
  stabilize the same tokenization and encoding pipeline before measurement.

The `size_target` values describe approximate characters, while `max_length`
configures the tokenizer's token limit. Every run measures the complete fixed
corpus containing all six size classes. P50, P95, and tail amplification
therefore describe the latency distribution of this heterogeneous workload, not
isolated scheduler jitter for a single document length.

Validate both datasets before running:

```bash
./scripts/verify_corpus.sh
```

`run_all.sh` preserves and validates existing versioned datasets. It does not
regenerate them by default. To intentionally replace both datasets and hashes:

```bash
./scripts/run_all.sh --regenerate-corpus
```

## Single benchmark run

```bash
uv run python src/bench_embed.py \
  --corpus data/corpus.jsonl \
  --warmup-corpus data/warmup.jsonl \
  --model-revision 5617a9f61b028005a4858fdac845db406aefb181 \
  --batch 16 \
  --max-length 512 \
  --threads 4 \
  --warmup-docs 32
```

Measured throughput is calculated as:

```text
docs_per_sec = n_docs_measured / total_seconds_measured
```

Warm-up documents are never included in measured latency, throughput, CPU time,
or embeddings. The recorded p50/p95 values are amortized per-document latency
derived from each batch duration. Tail amplification is recorded as the
dimensionless ratio `p95_ms / p50_ms`.

## Repeated benchmark matrix

```bash
./scripts/run_matrix.sh
```

The default matrix runs three repetitions for every `max_length × batch`
combination using the versioned profile in `scripts/benchmark_profile.sh`.
Override it with:

```bash
REPETITIONS=5 MAX_LENGTHS="256 512 1024" BATCHES="4 8" ./scripts/run_matrix.sh
```

The benchmark is provider-agnostic. Executors can use `MATRIX_RUN_ID` as an
operational label without changing the measurement:

```bash
MATRIX_RUN_ID=amd-sev-snp-01 ./scripts/run_matrix.sh
```

This label organizes artifacts; the observed platform evidence remains in each
run's `env.json`.

Outputs:

- `runs.csv`: one row per individual execution.
- `summary.csv`: means, standard deviation, and 95% confidence intervals grouped
  by model, maximum length, batch, threads, and dataset hashes, including tail
  amplification.

Use the confidence intervals when comparing machines. Small differences with
overlapping intervals should not be reported as conclusive gains.

## Complete runner

```bash
./scripts/run_all.sh --help
./scripts/run_all.sh
```

The complete runner installs the pinned Python version, synchronizes the uv
environment without modifying the lockfile, validates the datasets, enforces the
canonical profile, captures pre-run environment metadata, logs execution, and
executes the repeated matrix. It can be invoked from any working directory.

Useful options:

```text
--repetitions N
--threads N
--model-revision SHA
--matrix-run-id ID
--allow-dirty
--regenerate-corpus
--skip-python
--skip-sync
--skip-dataset
--skip-env
--skip-matrix
```

## Run artifacts

Each benchmark run writes:

- `results/<run_id>/embeddings.npy`
- `results/<run_id>/embeddings.sha256`
- `results/<run_id>/run.jsonl`
- `results/<run_id>/env.json`

Matrix executions write nested runs under `results/<matrix_run_id>/`, plus
`runs.csv` and `summary.csv`. A complete `run_all.sh` execution also writes:

- `manifest.json`: resolved profile, hashes, provenance, expected and actual counts.
- `env.before.json`: environment evidence captured before the matrix.
- `run.log`: runner stdout and stderr.
- `COMPLETED`: present only after artifact-count validation succeeds.

The environment metadata is captured best-effort and includes CPU topology,
microcode, frequency policy, NUMA, affinity, memory, storage and mount details,
kernel and boot parameters, and confidential-computing evidence. Missing or
permission-restricted signals are represented explicitly in the JSON.

## Reproducing a comparison

For every machine:

1. Check out the same clean Git commit.
2. Run `./scripts/run_all.sh` without overrides.
3. Retain the complete `results/<matrix_run_id>/` directory.
4. Verify `manifest.json` reports `completed`, 36 runs, and 12 summary rows.
5. Declare whether the analysis uses matched parameters or the best-observed
   configuration used by the reported experiment.
6. For a matched-parameter analysis, join rows only when model revision, Git
   commit, uv lock, corpus hashes, `max_length`, batch, thread configuration,
   and warm-up configuration are identical.
7. For a best-observed analysis, apply the same documented batch-selection rule
   in every environment and retain the selected batch together with the full matrix.
8. Report the selected analysis mode and retain every run directory as an audit artifact.

Both modes use the same complete benchmark matrix. Best-observed analysis
characterizes each environment after batch selection, while matched-parameter
analysis isolates a fixed batch. Neither changes benchmark execution. A future
benchmark revision may use token-stratified corpora and homogeneous batch
composition; the current profile is intentionally preserved for compatibility
with the reported experiment.

Do not commit `.env`, `results/`, or `reports/`.
