# Specification — CPU-only embedding benchmark

## Objective

Measure the CPU performance of `BAAI/bge-m3` across local, baseline-cloud, and
confidential-computing environments using identical, versioned inputs and
auditable run metadata.

## Inputs

- `data/corpus.jsonl`: deterministic measured corpus.
- `data/corpus.sha256`: measured corpus integrity manifest.
- `data/warmup.jsonl`: deterministic, size-stratified warm-up corpus.
- `data/warmup.sha256`: warm-up corpus integrity manifest.
- `uv.lock`: dependency lockfile used by every environment.
- `scripts/benchmark_profile.sh`: canonical model revision and matrix parameters.

Warm-up data must use the same model, tokenizer, maximum length, batch size, and
thread configuration as the measured corpus. Warm-up data is not included in
embeddings or measured metrics.

## Method

1. Verify both dataset hashes.
2. Load the model on CPU and apply the configured thread limits.
3. Encode the separate warm-up corpus.
4. Measure the complete versioned corpus.
5. Repeat every matrix combination at least three times.
6. Retain raw run artifacts and aggregate results with 95% confidence intervals.
7. Validate expected artifact counts before marking the matrix complete.

## Run metrics

- `n_docs_total` and `n_docs_measured`
- `total_seconds_measured`
- `docs_per_sec`
- amortized per-document `p50_ms` and `p95_ms`
- dimensionless `tail_amplification`, calculated as `p95_ms / p50_ms`
- measured-window `cpu_user_s` and `cpu_system_s`
- process-wide `rss_peak_mb`

## Traceability

Every run records:

- corpus, warm-up corpus, embeddings, and uv lock hashes;
- model identifier and runtime parameters;
- Python version, Git commit, and dirty state;
- environment metadata covering CPU, memory, storage, kernel, NUMA, affinity,
  frequency policy, microcode, and confidential-computing signals.
- a matrix manifest, pre-run environment snapshot, execution log, and completion
  marker produced by the canonical runner.

The benchmark remains provider-agnostic. The executor may assign a descriptive
`MATRIX_RUN_ID` to organize scenarios, while `env.json` remains the auditable
source of observed platform characteristics.

## Statistical reporting

Machine comparisons must use repeated runs from `summary.csv`. Report means and
95% confidence intervals, plus the repetition count. Small differences with
overlapping intervals must not be presented as conclusive performance gains.

Rows may be joined only when model revision, Git commit, uv lock, corpus hashes,
maximum length, batch, thread configuration, and warm-up parameters match. Independent
per-environment selection of the best batch is not an identical-parameter
comparison.

## Current workload interpretation

The versioned corpus intentionally preserves the reported experiment: target
sizes are approximate characters, every run processes all size classes, and
`max_length` is a tokenizer token limit. Latency percentiles and tail
amplification describe this fixed heterogeneous workload. Token-stratified
corpora and homogeneous batch composition are reserved for a future methodology
revision so that current results are not silently redefined.
