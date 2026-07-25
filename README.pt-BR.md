# PoC de Benchmark para Computacao Confidencial

[English](README.md) | [Português](README.pt-BR.md)

Benchmark reproduzivel e CPU-only para comparar workloads de embeddings entre
ambientes Linux convencionais e com computacao confidencial. O benchmark usa
`BAAI/bge-m3`, datasets versionados, hashes de conteudo, dados de warm-up
isolados, metadados de ambiente por execucao e medicoes repetidas com intervalos
de confianca de 95%.

## Requisitos

- [uv](https://docs.astral.sh/uv/)

A versao do Python esta fixada em `.python-version`; o uv faz o download e cria
o ambiente virtual.

## Preparacao do ambiente

```bash
uv python install
uv sync --frozen
```

Para ambientes que restringem diretorios de cache do usuario:

```bash
UV_CACHE_DIR=.uv-cache UV_PYTHON_INSTALL_DIR=.uv-python uv python install
UV_CACHE_DIR=.uv-cache UV_PYTHON_INSTALL_DIR=.uv-python uv sync --frozen
```

Para downloads autenticados no Hugging Face:

```bash
cp .env.example .env
```

Configure `HUGGINGFACE_HUB_TOKEN` no `.env`. Esse arquivo e ignorado pelo Git.

## Datasets versionados

O repositorio contem dois datasets deterministicos:

- `data/corpus.jsonl`: 144 documentos medidos, com 24 documentos para cada
  tamanho aproximado: 256, 512, 1024, 2048, 4096 e 8192 caracteres.
- `data/warmup.jsonl`: 32 documentos deterministicos e estratificados por
  tamanho, usados apenas para estabilizar o mesmo pipeline de tokenizacao e
  encoding antes da medicao.

Os valores de `size_target` descrevem caracteres aproximados, enquanto
`max_length` configura o limite de tokens do tokenizer. Cada run mede o corpus
fixo completo com as seis classes de tamanho. P50, P95 e amplificacao de cauda
descrevem, portanto, a distribuicao de latencia desse workload heterogeneo, e nao
apenas jitter de escalonamento para um unico tamanho de documento.

Valide ambos antes da execucao:

```bash
./scripts/verify_corpus.sh
```

O `run_all.sh` preserva e valida os datasets versionados existentes. Ele nao os
regenera por padrao. Para substituir intencionalmente os datasets e hashes:

```bash
./scripts/run_all.sh --regenerate-corpus
```

## Execucao individual

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

O throughput medido e calculado como:

```text
docs_per_sec = n_docs_measured / total_seconds_measured
```

Os documentos de warm-up nao participam da latencia, throughput, tempo de CPU
ou embeddings medidos. Os valores p50/p95 representam latencia amortizada por
documento, derivada da duracao de cada batch. A amplificacao de cauda e registrada
como a razao adimensional `p95_ms / p50_ms`.

## Matriz com repeticoes

```bash
./scripts/run_matrix.sh
```

Por padrao, a matriz executa tres repeticoes para cada combinacao de
`max_length × batch`, usando o perfil versionado em
`scripts/benchmark_profile.sh`. Para alterar:

```bash
REPETITIONS=5 MAX_LENGTHS="256 512 1024" BATCHES="4 8" ./scripts/run_matrix.sh
```

O benchmark e agnostico ao provedor. O executor pode usar `MATRIX_RUN_ID` como
rotulo operacional sem alterar a medicao:

```bash
MATRIX_RUN_ID=amd-sev-snp-01 ./scripts/run_matrix.sh
```

Esse rotulo organiza os artefatos; as evidencias observadas da plataforma
permanecem no `env.json` de cada execucao.

Saidas:

- `runs.csv`: uma linha para cada execucao individual.
- `summary.csv`: medias, desvio padrao e intervalos de confianca de 95%,
  agrupados por modelo, tamanho maximo, batch, threads e hashes dos datasets,
  incluindo amplificacao de cauda.

Use os intervalos de confianca para comparar maquinas. Diferencas pequenas com
intervalos sobrepostos nao devem ser apresentadas como ganhos conclusivos.

## Runner completo

```bash
./scripts/run_all.sh --help
./scripts/run_all.sh
```

O runner completo instala a versao fixada do Python, sincroniza o ambiente uv,
sem modificar o lockfile, valida os datasets, aplica o perfil canonico, coleta
metadados antes da matriz, registra o log e executa a matriz com repeticoes. Ele
pode ser chamado a partir de qualquer diretorio.

Opcoes uteis:

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

## Artefatos da execucao

Cada execucao grava:

- `results/<run_id>/embeddings.npy`
- `results/<run_id>/embeddings.sha256`
- `results/<run_id>/run.jsonl`
- `results/<run_id>/env.json`

Execucoes da matriz gravam runs aninhados em `results/<matrix_run_id>/`, alem de
`runs.csv` e `summary.csv`. Uma execucao completa de `run_all.sh` tambem grava:

- `manifest.json`: perfil resolvido, hashes, proveniencia e contagens esperadas/reais.
- `env.before.json`: evidencias do ambiente coletadas antes da matriz.
- `run.log`: stdout e stderr do runner.
- `COMPLETED`: criado somente apos validar todas as contagens de artefatos.

Os metadados de ambiente sao coletados em modo best-effort e incluem topologia
de CPU, microcode, politica de frequencia, NUMA, afinidade, memoria,
armazenamento e mounts, kernel e parametros de boot, alem de evidencias de
computacao confidencial. Sinais ausentes ou restritos por permissao sao
representados explicitamente no JSON.

## Reproduzindo uma comparacao

Em cada maquina:

1. Obtenha o mesmo commit Git sem alteracoes locais.
2. Execute `./scripts/run_all.sh` sem sobrescrever parametros.
3. Preserve o diretorio completo `results/<matrix_run_id>/`.
4. Confirme que `manifest.json` registra `completed`, 36 runs e 12 linhas no resumo.
5. Junte somente resultados com revisao do modelo, commit Git, uv lock, hashes dos
   corpus, `max_length`, batch, configuracao de threads e warm-up identicos.
6. Compare linhas correspondentes e preserve cada run como artefato de auditoria.

Selecionar o melhor batch independentemente em cada ambiente nao representa uma
comparacao com parametros identicos. Uma revisao futura podera usar corpus
estratificado por tokens e composicao homogenea de batches; o perfil atual e
preservado para manter compatibilidade com o experimento reportado.

Nao versione `.env`, `results/` ou `reports/`.
