# SPEC - Benchmark embeddings CPU-only (bge-m3)

## Objetivo
Medir o desempenho de geracao de embeddings com o modelo BAAI/bge-m3 em CPU, usando um corpus sintetico em PT-BR com tamanhos alvo conhecidos.

## Metodologia
- Gerar um corpus deterministico (seed fixa) com textos em PT-BR e tamanhos-alvo aproximados.
- Rodar o encoder em CPU com max_seq_length configuravel.
- Variar seq_len e batch size para observar impacto em throughput e latencia.
- Registrar metricas por execucao em results/run.jsonl e consolidar em results/summary.csv.

## Metricas
- p50 e p95 de latencia por documento (ms).
- Throughput em documentos por segundo.
- Tempo total da execucao.
- Configuracao de execucao (seq_len, batch_size, num_docs).
